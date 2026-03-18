"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const REGION = "us-central1";
const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function safeNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function fallbackVenueName(address) {
  const firstSegment = safeString(address).split(",")[0];
  return safeString(firstSegment, "Selected venue");
}

function resolveCity(addressComponents) {
  if (!Array.isArray(addressComponents)) {
    return null;
  }

  for (const component of addressComponents) {
    const types = Array.isArray(component?.types) ? component.types : [];
    if (
      types.includes("locality") ||
      types.includes("postal_town") ||
      types.includes("administrative_area_level_2")
    ) {
      const text = safeString(
        component?.longText ||
          component?.shortText ||
          component?.long_name ||
          component?.short_name,
      );
      if (text) {
        return text;
      }
    }
  }

  return null;
}

function extractPlacesErrorMessage(payload, fallback) {
  const message = safeString(payload?.error?.message);
  return message || fallback;
}

async function callPlacesApi({
  apiKey,
  url,
  method = "GET",
  body,
  fieldMask,
  fallbackMessage,
}) {
  const response = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const responseText = await response.text();
  let payload = {};
  try {
    payload = responseText ? JSON.parse(responseText) : {};
  } catch (_) {
    payload = {};
  }

  if (!response.ok) {
    throw new HttpsError(
      "internal",
      extractPlacesErrorMessage(payload, fallbackMessage),
    );
  }

  return payload;
}

function mapAutocompleteSuggestions(payload) {
  const suggestions = Array.isArray(payload?.suggestions)
    ? payload.suggestions
    : [];

  return suggestions
    .map((entry) => {
      const prediction = entry?.placePrediction;
      const placeId = safeString(prediction?.placeId);
      if (!placeId) {
        return null;
      }

      const fullText = safeString(prediction?.text?.text);
      const title = safeString(
        prediction?.structuredFormat?.mainText?.text,
        fullText,
      );
      const subtitle = safeString(
        prediction?.structuredFormat?.secondaryText?.text,
      );
      const distanceMeters = safeNumber(prediction?.distanceMeters);

      return {
        placeId,
        title,
        subtitle,
        fullText: fullText || title,
        distanceMeters: distanceMeters == null ? null : Math.round(distanceMeters),
      };
    })
    .filter(Boolean);
}

function mapPlaceSelection(placeId, payload) {
  const latitude = safeNumber(payload?.location?.latitude);
  const longitude = safeNumber(payload?.location?.longitude);

  if (latitude == null || longitude == null) {
    throw new HttpsError(
      "failed-precondition",
      "This place does not include map coordinates.",
    );
  }

  const displayName = safeString(payload?.displayName?.text);
  const address = safeString(payload?.formattedAddress);
  const city = safeString(resolveCity(payload?.addressComponents), "Accra");

  return {
    placeId: safeString(payload?.id, placeId),
    venueName: displayName || fallbackVenueName(address),
    city,
    address: address || `${displayName || fallbackVenueName(address)}, ${city}`,
    latitude,
    longitude,
  };
}

function mapReverseGeocodeSelection(latitude, longitude, payload) {
  const results = Array.isArray(payload?.results) ? payload.results : [];
  const result = results[0];
  if (!result) {
    throw new HttpsError(
      "not-found",
      "We could not match this device location to an address.",
    );
  }

  const address = safeString(result.formatted_address);
  const city = safeString(resolveCity(result.address_components), "Accra");
  const venueName = safeString(
    result?.address_components?.[0]?.long_name,
    fallbackVenueName(address),
  );

  return {
    placeId: safeString(result.place_id),
    venueName,
    city,
    address:
      address ||
      `${venueName || "Current location pin"}, ${city || "Accra"}`,
    latitude,
    longitude,
  };
}

exports.autocompleteEventPlaces = onCall(
  {
    region: REGION,
    secrets: [GOOGLE_PLACES_API_KEY],
  },
  async (request) => {
    const query = safeString(request.data?.query);
    if (query.length < 2) {
      return { suggestions: [] };
    }

    const apiKey = safeString(GOOGLE_PLACES_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Google Places lookup is not configured on the server yet.",
      );
    }

    const body = {
      input: query,
      includedRegionCodes: ["gh"],
    };

    const originLatitude = safeNumber(request.data?.originLatitude);
    const originLongitude = safeNumber(request.data?.originLongitude);
    if (originLatitude != null && originLongitude != null) {
      body.locationBias = {
        circle: {
          center: {
            latitude: originLatitude,
            longitude: originLongitude,
          },
          radius: 50000,
        },
      };
    }

    const payload = await callPlacesApi({
      apiKey,
      url: "https://places.googleapis.com/v1/places:autocomplete",
      method: "POST",
      body,
      fieldMask: [
        "suggestions.placePrediction.placeId",
        "suggestions.placePrediction.text.text",
        "suggestions.placePrediction.structuredFormat.mainText.text",
        "suggestions.placePrediction.structuredFormat.secondaryText.text",
        "suggestions.placePrediction.distanceMeters",
      ].join(","),
      fallbackMessage: "Google Places could not return venue suggestions.",
    });

    return {
      suggestions: mapAutocompleteSuggestions(payload),
    };
  },
);

exports.getEventPlaceDetails = onCall(
  {
    region: REGION,
    secrets: [GOOGLE_PLACES_API_KEY],
  },
  async (request) => {
    const placeId = safeString(request.data?.placeId);
    if (!placeId) {
      throw new HttpsError("invalid-argument", "A place ID is required.");
    }

    const apiKey = safeString(GOOGLE_PLACES_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Google Places lookup is not configured on the server yet.",
      );
    }

    const payload = await callPlacesApi({
      apiKey,
      url: `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
      fieldMask: [
        "id",
        "displayName",
        "formattedAddress",
        "location",
        "addressComponents",
      ].join(","),
      fallbackMessage: "Google Places could not load this location.",
    });

    return mapPlaceSelection(placeId, payload);
  },
);

exports.reverseGeocodeEventCoordinates = onCall(
  {
    region: REGION,
    secrets: [GOOGLE_PLACES_API_KEY],
  },
  async (request) => {
    const latitude = safeNumber(request.data?.latitude);
    const longitude = safeNumber(request.data?.longitude);
    if (latitude == null || longitude == null) {
      throw new HttpsError(
        "invalid-argument",
        "Latitude and longitude are required.",
      );
    }

    const apiKey = safeString(GOOGLE_PLACES_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Google Places lookup is not configured on the server yet.",
      );
    }

    const params = new URLSearchParams({
      latlng: `${latitude},${longitude}`,
      key: apiKey,
      language: "en",
      result_type: "street_address|premise|establishment|route|plus_code",
    });

    const response = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`,
    );
    const responseText = await response.text();

    let payload = {};
    try {
      payload = responseText ? JSON.parse(responseText) : {};
    } catch (_) {
      payload = {};
    }

    const status = safeString(payload?.status);
    if (!response.ok || (status && status !== "OK")) {
      throw new HttpsError(
        "internal",
        extractPlacesErrorMessage(
          payload,
          "Google could not match this device location to an address.",
        ),
      );
    }

    return mapReverseGeocodeSelection(latitude, longitude, payload);
  },
);
