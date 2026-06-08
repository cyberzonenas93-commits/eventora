"use strict";

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const GPLUS_ORGANIZATION_ID = "org_gplus";
const GPLUS_CREATOR_ID = "gplus";
const GPLUS_PROFILE_ID = "gplus";
const GPLUS_DISPLAY_NAME = "G+";
const GPLUS_PLACE_ID = "gplus_nightclub";
const GPLUS_PLACE_TITLE = "G+Nightclub";
const GPLUS_PLACE_ADDRESS = "UPSA Road, Madina, Accra, Ghana";
const GPLUS_PLACE_MAPS_URL = "https://maps.google.com/?q=G%2B%20Nightclub%20UPSA%20Road%20Madina%20Accra%20Ghana";
const GPLUS_PLACE_DEFAULT_COVER = "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0005.jpg";
const GPLUS_PLACE_DEFAULT_GALLERY = [
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0005.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0008.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0013.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0014.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0018.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0019.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0025.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0026.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0029.jpg",
  "https://storage.googleapis.com/gplus-admin.firebasestorage.app/moments/photos/drive_import_1780065860214/MG_0036.jpg",
];
const DEFAULT_TIMEZONE = "Africa/Accra";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function cleanText(value, fallback = "", max = 2000) {
  return safeString(value, fallback).slice(0, max);
}

function stableHash(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 20);
}

function safeIdPart(value, fallback = "item") {
  const normalized = safeString(value, fallback)
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return (normalized || fallback).slice(0, 80);
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value : null;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value.toDate === "function") {
    try {
      return value.toDate();
    } catch (error) {
      return null;
    }
  }
  if (typeof value.seconds === "number") {
    return new Date(value.seconds * 1000);
  }
  if (typeof value === "number") {
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }
  return null;
}

function toTimestamp(value, fallbackDate) {
  const date = toDate(value) || fallbackDate;
  return Timestamp.fromDate(date);
}

function asStringArray(value, max = 12) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => safeString(item))
    .filter(Boolean)
    .slice(0, max);
}

function isRemoteMediaUrl(value) {
  return /^https?:\/\//i.test(safeString(value));
}

function asRemoteMediaArray(value, max = 12) {
  return asStringArray(value, max).filter(isRemoteMediaUrl);
}

function firstString(data, keys, fallback = "") {
  for (const key of keys) {
    const value = safeString(data && data[key]);
    if (value) return value;
  }
  return fallback;
}

function firstNumber(data, keys) {
  for (const key of keys) {
    const value = Number(data && data[key]);
    if (Number.isFinite(value)) return value;
  }
  return null;
}

function normalizeEmail(value) {
  return safeString(value).toLowerCase();
}

function normalizePhoneForLookup(value) {
  const digits = String(value || "").replace(/[^\d+]/g, "");
  if (!digits) return "";
  if (digits.startsWith("+233")) return digits;
  if (digits.startsWith("233") && digits.length === 12) return `+${digits}`;
  if (digits.startsWith("0") && digits.length === 10) return `+233${digits.slice(1)}`;
  if (digits.length === 9) return `+233${digits}`;
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function uniqueStrings(values) {
  return Array.from(new Set(values.map((value) => safeString(value)).filter(Boolean)));
}

function gplusEventVennuzoId(gplusEventId) {
  return `gplus_${safeIdPart(gplusEventId, stableHash(gplusEventId))}`.slice(0, 140);
}

function normalizeVisibility(value) {
  return safeString(value).toLowerCase() === "private" ? "private" : "public";
}

function normalizeStatus(data) {
  const status = safeString(data.status || data.state).toLowerCase();
  if (["cancelled", "canceled"].includes(status)) return "cancelled";
  if (["draft", "pending", "review"].includes(status)) return "draft";
  return "published";
}

function normalizeGPlusProfile(profileId, source = {}) {
  const avatarUrl = firstString(source, ["avatarUrl", "photoUrl", "profileImageUrl", "profileImage"]);
  const coverUrl = firstString(source, ["coverUrl", "bannerUrl", "coverImageUrl"]);
  const city = firstString(source, ["city", "locationCity"], "Accra");
  const bio = firstString(
    source,
    ["bio", "description", "about"],
    "G+ events, nightlife, culture, and community moments synced into Vennuzo.",
  );

  return {
    id: profileId || GPLUS_PROFILE_ID,
    displayName: GPLUS_DISPLAY_NAME,
    bio: cleanText(bio, "", 1000),
    city,
    avatarUrl,
    coverUrl,
    followerCount: Math.max(0, Number(source.followersCount || source.followerCount || 0) || 0),
    eventCount: Math.max(0, Number(source.eventCount || 0) || 0),
    photoCount: Math.max(0, Number(source.photoCount || source.postsCount || 0) || 0),
    sourceProfileId: safeString(source.uid || source.userId || profileId),
  };
}

function eventEndDate(data = {}) {
  return toDate(data.endAt) || toDate(data.endDate) || toDate(data.endsAt) || toDate(data.startAt) || toDate(data.date);
}

function isExpiredEvent(data = {}) {
  const endDate = eventEndDate(data);
  return !!endDate && endDate.getTime() <= Date.now();
}

function normalizeTicketing(source = {}) {
  const ticketing = source.ticketing && typeof source.ticketing === "object" ? source.ticketing : {};
  const tiers = Array.isArray(ticketing.tiers)
    ? ticketing.tiers
    : Array.isArray(source.ticketTiers)
      ? source.ticketTiers
      : [];
  const normalizedTiers = tiers.map((tier, index) => ({
    tierId: safeString(tier.tierId || tier.id, `gplus_tier_${index + 1}`),
    name: cleanText(tier.name || tier.title, "General", 120),
    price: Math.max(0, Number(tier.price || tier.amount || 0) || 0),
    maxQuantity: Math.max(0, Number(tier.maxQuantity || tier.quantity || tier.capacity || 0) || 0),
    sold: Math.max(0, Number(tier.sold || tier.soldCount || 0) || 0),
    description: cleanText(tier.description, "", 300),
  }));

  return {
    enabled: ticketing.enabled === true || normalizedTiers.length > 0,
    requireTicket: ticketing.requireTicket === true || source.requireTicket === true,
    currency: safeString(ticketing.currency || source.currency, "GHS"),
    tiers: normalizedTiers,
  };
}

function normalizeGPlusEvent(gplusEventId, source = {}, profile = {}) {
  const title = firstString(source, ["title", "name", "eventTitle"], "G+ Event");
  const description = firstString(source, ["description", "details", "copy"], "");
  const startDate =
    toDate(source.startAt) ||
    toDate(source.date) ||
    toDate(source.eventDate) ||
    toDate(source.startsAt) ||
    new Date(Date.now() + 24 * 60 * 60 * 1000);
  const endDate =
    toDate(source.endAt) ||
    toDate(source.endDate) ||
    toDate(source.endsAt) ||
    new Date(startDate.getTime() + 7.5 * 60 * 60 * 1000);
  const flyerUrl = firstString(source, [
    "coverImageUrl",
    "imageUrl",
    "flyerUrl",
    "photoUrl",
    "posterUrl",
    "thumbnailUrl",
  ]);
  const venue = firstString(source, ["venue", "location", "addressText"], GPLUS_PLACE_TITLE);
  const city = firstString(source, ["city", "locationCity"], profile.city || "Accra");
  const tags = Array.from(
    new Set([
      "gplus",
      "G+",
      ...asStringArray(source.tags),
      ...asStringArray(source.hashtags).map((tag) => tag.replace(/^#/, "")),
    ].filter(Boolean)),
  ).slice(0, 16);
  const latitude = firstNumber(source, ["latitude", "lat"]);
  const longitude = firstNumber(source, ["longitude", "lng", "lon"]);
  const addressText = firstString(source, ["addressText", "address"], GPLUS_PLACE_ADDRESS);
  const categoryId = safeString(source.categoryId || source.category || source.type, "nightlife");
  const sourceEventId = safeString(source.sourceEventId || source.gplusEventId || gplusEventId);
  const eventId = gplusEventVennuzoId(sourceEventId);
  const expired = endDate.getTime() <= Date.now();
  const placeId = firstString(source, ["placeId", "venueId", "locationId"], GPLUS_PLACE_ID);

  return {
    eventId,
    sourceEventId,
    event: {
      title: cleanText(title, "G+ Event", 220),
      description: cleanText(description, "", 4000),
      venue: cleanText(venue, "G+", 300),
      city: cleanText(city, "Accra", 120),
      visibility: expired ? "private" : normalizeVisibility(source.visibility),
      status: expired ? "cancelled" : normalizeStatus(source),
      timezone: safeString(source.timezone, DEFAULT_TIMEZONE),
      startAt: Timestamp.fromDate(startDate),
      endAt: Timestamp.fromDate(endDate),
      date: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate),
      organizationId: safeString(source.organizationId, GPLUS_ORGANIZATION_ID),
      createdBy: safeString(source.createdBy || source.organizerId, GPLUS_CREATOR_ID),
      createdAt: toTimestamp(source.createdAt, new Date()),
      updatedAt: FieldValue.serverTimestamp(),
      coverImageUrl: flyerUrl,
      imageUrl: flyerUrl,
      flyerUrl,
      flyerAsset: flyerUrl,
      animatedFlyerUrl: safeString(source.animatedFlyerUrl),
      categoryId,
      mood: safeString(source.mood, "night"),
      tags,
      lineup: {
        djs: cleanText(source.djs, "", 500),
        mcs: cleanText(source.mcs || source.mc, "", 500),
        performers: cleanText(source.performers, "", 800),
      },
      distribution: {
        allowSharing: source.allowSharing !== false,
        sendPushNotification: source.sendPushNotification !== false,
        sendSmsNotification: source.sendSmsNotification !== false,
      },
      ticketing: normalizeTicketing(source),
      metrics: {
        likesCount: Math.max(0, Number(source.likesCount || source.likeCount || 0) || 0),
        rsvpCount: Math.max(0, Number(source.rsvpCount || 0) || 0),
        ticketCount: Math.max(0, Number(source.ticketCount || 0) || 0),
        grossRevenue: Math.max(0, Number(source.grossRevenue || 0) || 0),
      },
      addressText,
      placeId,
      location:
        latitude == null || longitude == null
          ? null
          : {
              address: addressText,
              latitude,
              longitude,
              placeId,
            },
      source: "gplus",
      sourceEventId,
      sync: {
        source: "gplus",
        sourceEventId,
        importedBy: "gplus_sync",
        promotedAcrossVennuzo: true,
        featured: true,
        syncedAt: FieldValue.serverTimestamp(),
      },
    },
  };
}

async function hasAdminAccess(uid) {
  if (!uid) return false;
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  return safeString(data.status, "active") !== "disabled";
}

async function assertAdmin(uid) {
  if (!(await hasAdminAccess(uid))) {
    throw new HttpsError("permission-denied", "Admin access is required.");
  }
}

async function ensureGPlusProfile(profile = {}) {
  const normalized = normalizeGPlusProfile(GPLUS_PROFILE_ID, profile);
  const profileRef = db.collection("creator_profiles").doc(GPLUS_PROFILE_ID);
  const organizationRef = db.collection("organizations").doc(GPLUS_ORGANIZATION_ID);
  const userRef = db.collection("users").doc(GPLUS_CREATOR_ID);

  await db.runTransaction(async (tx) => {
    tx.set(
      profileRef,
      {
        creatorId: GPLUS_PROFILE_ID,
        displayName: normalized.displayName,
        bio: normalized.bio,
        city: normalized.city,
        avatarUrl: normalized.avatarUrl || null,
        coverUrl: normalized.coverUrl || null,
        followerCount: normalized.followerCount,
        eventCount: normalized.eventCount,
        photoCount: normalized.photoCount,
        source: "gplus",
        sourceProfileId: normalized.sourceProfileId || GPLUS_PROFILE_ID,
        syncedFromGPlus: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      organizationRef,
      {
        organizationId: GPLUS_ORGANIZATION_ID,
        ownerId: GPLUS_CREATOR_ID,
        displayName: normalized.displayName,
        name: normalized.displayName,
        bio: normalized.bio,
        city: normalized.city,
        logoUrl: normalized.avatarUrl || null,
        coverUrl: normalized.coverUrl || null,
        status: "active",
        source: "gplus",
        syncedFromGPlus: true,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      userRef,
      {
        displayName: normalized.displayName,
        username: "gplus",
        usernameLower: "gplus",
        bio: normalized.bio,
        city: normalized.city,
        photoUrl: normalized.avatarUrl || null,
        profileImageUrl: normalized.avatarUrl || null,
        defaultOrganizationId: GPLUS_ORGANIZATION_ID,
        organizerApproved: true,
        organizerApplicationStatus: "active",
        source: "gplus",
        syncedFromGPlus: true,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  await upsertGPlusPlace(profile);
  return normalized;
}

function campaignMessageForEvent(event) {
  const location = [safeString(event.venue), safeString(event.city)].filter(Boolean).join(", ");
  return `${safeString(event.title, "G+ Event")} is now live on Vennuzo${location ? ` at ${location}` : ""}. Save it, share it, or get your tickets before the room fills.`;
}

async function upsertFeaturedCampaign(eventId, event) {
  const campaignId = `gplus_featured_${safeIdPart(eventId, stableHash(eventId))}`;
  const campaignRef = db.collection("promotion_campaigns").doc(campaignId);
  const expired = isExpiredEvent(event);
  await campaignRef.set(
    {
      eventId,
      occurrenceId: `${eventId}_primary`,
      organizationId: safeString(event.organizationId, GPLUS_ORGANIZATION_ID),
      eventTitle: safeString(event.title, "G+ Event"),
      targetType: "event",
      targetId: eventId,
      targetTitle: safeString(event.title, "G+ Event"),
      name: `${safeString(event.title, "G+ Event")} G+ featured sync`,
      status: expired ? "cancelled" : event.status === "published" && event.visibility === "public" ? "live" : "scheduled",
      channels: ["featured", "announcement", "shareLink"],
      audienceSources: ["gplus_sync"],
      audienceSourceName: "G+ automatic sync",
      scheduledAt: event.startAt || FieldValue.serverTimestamp(),
      shareLinkEnabled: true,
      placementBudget: 0,
      budget: 0,
      walletReservationAmount: 0,
      pushBudget: 0,
      smsBudget: 0,
      pushAudience: 0,
      smsAudience: 0,
      uploadedAudience: 0,
      objective: "gplus_import",
      audienceStrategy: "automatic_gplus_sync",
      optimizationGoal: "awareness",
      bidStrategy: "owned_inventory",
      creativeMode: "event_flyer",
      message: campaignMessageForEvent(event),
      source: "gplus_sync",
      createdBy: GPLUS_CREATOR_ID,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return campaignId;
}

async function upsertFeaturedPlaceCampaign() {
  const campaignId = `place_featured_${GPLUS_PLACE_ID}`;
  await db.collection("promotion_campaigns").doc(campaignId).set(
    {
      eventId: "",
      occurrenceId: "",
      organizationId: GPLUS_ORGANIZATION_ID,
      eventTitle: "",
      targetType: "place",
      targetId: GPLUS_PLACE_ID,
      targetTitle: GPLUS_PLACE_TITLE,
      name: `${GPLUS_PLACE_TITLE} featured place`,
      status: "live",
      channels: ["featured", "announcement", "shareLink"],
      audienceSources: ["places_discovery", "gplus_sync"],
      audienceSourceName: "Featured place promotion",
      scheduledAt: FieldValue.serverTimestamp(),
      shareLinkEnabled: true,
      placementBudget: 0,
      budget: 0,
      walletReservationAmount: 0,
      pushBudget: 0,
      smsBudget: 0,
      pushAudience: 0,
      smsAudience: 0,
      uploadedAudience: 0,
      objective: "place_awareness",
      audienceStrategy: "places_discovery",
      optimizationGoal: "awareness",
      bidStrategy: "owned_inventory",
      creativeMode: "place_profile",
      message: `${GPLUS_PLACE_TITLE} is featured on Vennuzo. Explore the venue, photos, reviews, and upcoming events from the place profile.`,
      source: "gplus_sync",
      createdBy: GPLUS_CREATOR_ID,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return campaignId;
}

async function upsertGPlusPlace(profile = {}) {
  const placeRef = db.collection("places").doc(GPLUS_PLACE_ID);
  const placeSnap = await placeRef.get();
  const existingPlace = placeSnap.exists ? placeSnap.data() || {} : {};
  const profileGallery = asRemoteMediaArray(profile.galleryUrls || profile.photos, 40);
  const existingGallery = asRemoteMediaArray(existingPlace.galleryUrls, 40);
  const galleryUrls = profileGallery.length
    ? profileGallery
    : existingGallery.length
      ? existingGallery
      : GPLUS_PLACE_DEFAULT_GALLERY;
  const profileCoverUrl = safeString(profile.coverUrl || profile.imageUrl);
  const existingCoverUrl = safeString(existingPlace.coverUrl);
  const coverUrl = (isRemoteMediaUrl(profileCoverUrl) ? profileCoverUrl : "") ||
    (isRemoteMediaUrl(existingCoverUrl) ? existingCoverUrl : "") ||
    GPLUS_PLACE_DEFAULT_COVER;

  await placeRef.set(
    {
      organizationId: GPLUS_ORGANIZATION_ID,
      ownerId: GPLUS_CREATOR_ID,
      name: GPLUS_PLACE_TITLE,
      description: cleanText(
        profile.placeDescription || profile.bio,
        "Nightclub and entertainment venue on UPSA Road with DJs, bottle service, VIP tables, and late-night events.",
        1000,
      ),
      city: "Accra",
      address: GPLUS_PLACE_ADDRESS,
      formattedAddress: GPLUS_PLACE_ADDRESS,
      googlePlaceId: safeString(profile.googlePlaceId) || null,
      mapsUrl: safeString(profile.mapsUrl || profile.googleMapsUrl, GPLUS_PLACE_MAPS_URL),
      phone: safeString(profile.phone) || null,
      website: safeString(profile.website, "https://gplusnightclub.com/"),
      logoUrl: safeString(profile.avatarUrl || profile.photoUrl) || null,
      coverUrl,
      galleryUrls,
      categories: ["Nightlife", "Club", "VIP tables", "Live music"],
      amenities: ["Bottle service", "VIP lounge", "DJ booth", "Table reservations", "Media gallery"],
      openingHours: asStringArray(profile.openingHours || profile.hours, 14),
      featured: true,
      status: "active",
      metrics: {
        rating: Number(profile.rating) || 4.7,
        reviewCount: Number(profile.reviewCount) || 186,
        subscriberCount: Number(profile.subscriberCount) || 2400,
      },
      source: "gplus_sync",
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: existingPlace.createdAt || FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const menuStatusSnap = await db.collection("gplus_sync_status").doc("menu_and_events").get();
  const menuStatus = menuStatusSnap.exists ? menuStatusSnap.data() || {} : {};
  const hasFullMenuSync =
    menuStatus.status === "synced" && Number(menuStatus.menuItemCount || 0) > 0;
  const sectionRef = db.collection("place_menu_sections").doc("gplus_bottles");
  if (hasFullMenuSync) {
    await sectionRef.set(
      {
        visible: false,
        status: "hidden",
        supersededBy: "gplus_menu_sync",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } else {
    await sectionRef.set(
      {
        placeId: GPLUS_PLACE_ID,
        name: "Bottles",
        description: "Bottle service and VIP table packages.",
        sortOrder: 1,
        visible: true,
        source: "gplus_sync",
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  return GPLUS_PLACE_ID;
}

async function upsertEventSocialPost(eventId, event) {
  const postId = `gplus_event_${safeIdPart(eventId, stableHash(eventId))}`;
  await db.collection("event_posts").doc(postId).set(
    {
      eventId,
      userId: GPLUS_CREATOR_ID,
      displayName: "G+",
      userPhotoUrl: null,
      photoUrl: safeString(event.imageUrl || event.coverImageUrl || event.flyerUrl) || null,
      caption: campaignMessageForEvent(event),
      likeCount: 0,
      commentCount: 0,
      timestamp: FieldValue.serverTimestamp(),
      source: "gplus_sync",
      sourceEventId: safeString(event.sourceEventId),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return postId;
}

async function upsertCreatorPhoto(eventId, event) {
  const imageUrl = safeString(event.imageUrl || event.coverImageUrl || event.flyerUrl);
  if (!imageUrl) return null;
  const photoId = `gplus_${safeIdPart(eventId, stableHash(eventId))}`;
  await db.collection("creator_event_photos").doc(photoId).set(
    {
      creatorId: GPLUS_PROFILE_ID,
      eventId,
      eventTitle: safeString(event.title, "G+ Event"),
      imageUrl,
      caption: campaignMessageForEvent(event),
      source: "gplus_sync",
      createdAt: event.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return photoId;
}

function gplusMediaPhotoId(mediaId) {
  return `gplus_media_${safeIdPart(mediaId, stableHash(mediaId))}`;
}

function gplusMediaSyncId(mediaId) {
  return `media_${safeIdPart(mediaId, stableHash(mediaId))}`;
}

async function upsertGPlusMediaGalleryItem(mediaId, source = {}) {
  if (source.isActive === false || source.status === "hidden" || source.deleted === true) {
    await db.collection("gplus_sync_status").doc(gplusMediaSyncId(mediaId)).set(
      {
        type: "media",
        source: "gplus",
        sourceMediaId: safeString(mediaId),
        status: "skipped_inactive",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { imageUrl: null, status: "skipped_inactive" };
  }

  const imageUrl = firstString(source, [
    "imageUrl",
    "processedPhotoUrl",
    "photoUrl",
    "mediaUrl",
    "downloadUrl",
    "url",
    "thumbnailUrl",
  ]);
  if (!imageUrl) {
    await db.collection("gplus_sync_status").doc(gplusMediaSyncId(mediaId)).set(
      {
        type: "media",
        source: "gplus",
        sourceMediaId: safeString(mediaId),
        status: "skipped_no_image",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { imageUrl: null, status: "skipped_no_image" };
  }

  const sourceEventId = firstString(source, ["eventId", "gplusEventId", "sourceEventId"]);
  const eventId = sourceEventId ? gplusEventVennuzoId(sourceEventId) : "";
  const placeId = firstString(source, ["placeId", "venueId", "locationId"], GPLUS_PLACE_ID);
  const caption = cleanText(source.caption || source.description || source.altText, "", 1000);
  const createdAt = source.createdAt || source.timestamp || FieldValue.serverTimestamp();
  const primary = source.primary === true || source.isPrimary === true || source.kind === "cover";
  const batch = db.batch();

  if (eventId) {
    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await eventRef.get();
    const event = eventSnap.exists ? eventSnap.data() || {} : {};
    const shouldSetCover =
      primary ||
      !safeString(event.coverImageUrl || event.imageUrl || event.flyerUrl || event.flyerAsset);
    if (shouldSetCover) {
      batch.set(
        eventRef,
        {
          coverImageUrl: imageUrl,
          imageUrl,
          flyerUrl: imageUrl,
          flyerAsset: imageUrl,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    batch.set(
      db.collection("creator_event_photos").doc(gplusMediaPhotoId(mediaId)),
      {
        creatorId: GPLUS_PROFILE_ID,
        eventId,
        eventTitle: cleanText(source.eventTitle || event.title, "G+ Event", 220),
        imageUrl,
        caption,
        source: "gplus_media_gallery",
        sourceMediaId: safeString(mediaId),
        createdAt,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    batch.set(
      db.collection("gelo_website_features").doc(`gplus_event_${safeIdPart(eventId, stableHash(eventId))}`),
      {
        imageUrl,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  if (placeId) {
    const placeUpdate = {
      galleryUrls: FieldValue.arrayUnion(imageUrl),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (primary) placeUpdate.coverUrl = imageUrl;
    batch.set(
      db.collection("places").doc(placeId),
      placeUpdate,
      { merge: true },
    );
  }

  const profileUpdate = {
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (source.profilePhoto === true) profileUpdate.avatarUrl = imageUrl;
  if (primary) profileUpdate.coverUrl = imageUrl;
  batch.set(
    db.collection("creator_profiles").doc(GPLUS_PROFILE_ID),
    profileUpdate,
    { merge: true },
  );

  batch.set(
    db.collection("gplus_sync_status").doc(gplusMediaSyncId(mediaId)),
    {
      type: "media",
      source: "gplus",
      sourceMediaId: safeString(mediaId),
      sourceEventId: sourceEventId || null,
      vennuzoEventId: eventId || null,
      placeId: placeId || null,
      creatorPhotoId: eventId ? gplusMediaPhotoId(mediaId) : null,
      imageUrl,
      status: "synced",
      syncMode: "realtime_firestore_trigger",
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return { imageUrl, eventId, placeId, status: "synced" };
}

async function markGPlusMediaDeleted(mediaId) {
  await Promise.all([
    db.collection("creator_event_photos").doc(gplusMediaPhotoId(mediaId)).delete().catch(() => null),
    db.collection("gplus_sync_status").doc(gplusMediaSyncId(mediaId)).set(
      {
        type: "media",
        source: "gplus",
        sourceMediaId: safeString(mediaId),
        status: "deleted_at_source",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
  ]);
}

async function upsertGeloEventRecords(eventId, event) {
  const queueId = `gplus_event_${safeIdPart(eventId, stableHash(eventId))}`;
  const draftId = `gplus_launch_${safeIdPart(eventId, stableHash(eventId))}`;
  const featureId = `gplus_event_${safeIdPart(eventId, stableHash(eventId))}`;
  const imageUrl = safeString(event.imageUrl || event.coverImageUrl || event.flyerUrl);
  const caption = campaignMessageForEvent(event);
  const base = {
    source: "vennuzo_gplus_sync",
    sourceApp: "vennuzo",
    sourceEventId: safeString(event.sourceEventId),
    eventId,
    eventTitle: safeString(event.title, "G+ Event"),
    organizationId: safeString(event.organizationId, GPLUS_ORGANIZATION_ID),
    imageUrl: imageUrl || null,
    caption,
    status: "ready",
    channels: ["app_feed", "website", "seo", "featured"],
    updatedAt: FieldValue.serverTimestamp(),
  };
  const batch = db.batch();
  batch.set(
    db.collection("gelo_content_queue").doc(queueId),
    {
      ...base,
      type: "event_promo",
      title: safeString(event.title, "G+ Event"),
      body: caption,
      route: `/events/${eventId}`,
      scheduledAt: event.startAt || FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    db.collection("gelo_event_launch_drafts").doc(draftId),
    {
      ...base,
      title: safeString(event.title, "G+ Event"),
      venue: safeString(event.venue),
      city: safeString(event.city),
      startAt: event.startAt || null,
      endAt: event.endAt || null,
      route: `/events/${eventId}`,
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    db.collection("gelo_website_features").doc(featureId),
    {
      ...base,
      featureType: "featured_event",
      title: safeString(event.title, "G+ Event"),
      description: cleanText(event.description, caption, 300),
      urlPath: `/events/${eventId}`,
      seoKeywords: ["G+", "Vennuzo", safeString(event.city, "Accra"), "events"].filter(Boolean),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return { queueId, draftId, featureId };
}

async function syncGPlusEventDocument(gplusEventId, source = {}, options = {}) {
  const profile = await ensureGPlusProfile(options.profile || source.profile || {});
  const normalized = normalizeGPlusEvent(gplusEventId, source, profile);
  const { eventId, event } = normalized;
  const eventRef = db.collection("events").doc(eventId);
  const syncRef = db.collection("gplus_sync_status").doc(`event_${safeIdPart(gplusEventId, stableHash(gplusEventId))}`);

  await eventRef.set(event, { merge: true });
  const [campaignId, placeId, placeCampaignId, postId, photoId, gelo] = await Promise.all([
    upsertFeaturedCampaign(eventId, event),
    upsertGPlusPlace(profile),
    upsertFeaturedPlaceCampaign(),
    upsertEventSocialPost(eventId, event),
    upsertCreatorPhoto(eventId, event),
    upsertGeloEventRecords(eventId, event),
  ]);
  await syncRef.set(
    {
      type: "event",
      source: "gplus",
      sourceEventId: safeString(gplusEventId),
      vennuzoEventId: eventId,
      promotionCampaignId: campaignId,
      placeId,
      placePromotionCampaignId: placeCampaignId,
      eventPostId: postId,
      creatorPhotoId: photoId,
      gelo,
      status: "synced",
      syncMode: "realtime_firestore_trigger",
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { eventId, campaignId, placeId, placeCampaignId, postId, photoId, gelo };
}

async function markGPlusEventDeleted(gplusEventId) {
  const eventId = gplusEventVennuzoId(gplusEventId);
  await Promise.all([
    db.collection("events").doc(eventId).set(
      {
        status: "cancelled",
        visibility: "private",
        sync: {
          deletedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
    db.collection("promotion_campaigns").doc(`gplus_featured_${safeIdPart(eventId, stableHash(eventId))}`).set(
      {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
    db.collection("gplus_sync_status").doc(`event_${safeIdPart(gplusEventId, stableHash(gplusEventId))}`).set(
      {
        type: "event",
        source: "gplus",
        sourceEventId: safeString(gplusEventId),
        vennuzoEventId: eventId,
        status: "deleted_at_source",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
  ]);
}

function normalizePostForGelo(postId, post = {}) {
  const caption = cleanText(post.caption || post.text || post.body, "", 2000);
  const eventId = safeString(post.eventId);
  const title = caption ? caption.slice(0, 120) : `Vennuzo post ${postId}`;
  return {
    source: "vennuzo_event_posts",
    sourceApp: "vennuzo",
    sourcePostId: postId,
    eventId,
    userId: safeString(post.userId),
    displayName: safeString(post.displayName, "Vennuzo"),
    title,
    body: caption,
    caption,
    imageUrl: safeString(post.photoUrl || post.imageUrl) || null,
    route: eventId ? `/events/${eventId}` : "/",
    status: "ready",
    type: "event_social_post",
    channels: ["app_feed", "social", "seo"],
    likeCount: Math.max(0, Number(post.likeCount || 0) || 0),
    commentCount: Math.max(0, Number(post.commentCount || 0) || 0),
    createdAt: post.timestamp || post.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function upsertVennuzoPostToGelo(postId, post = {}) {
  const queueId = `vennuzo_post_${safeIdPart(postId, stableHash(postId))}`;
  const payload = normalizePostForGelo(postId, post);
  await db.collection("gelo_content_queue").doc(queueId).set(payload, { merge: true });
  return queueId;
}

async function authIdentityForUid(uid, token = {}) {
  const authUser = await admin.auth().getUser(uid).catch(() => null);
  const providerEmails = authUser
    ? (authUser.providerData || []).map((provider) => normalizeEmail(provider.email))
    : [];
  const providerPhones = authUser
    ? (authUser.providerData || []).map((provider) => normalizePhoneForLookup(provider.phoneNumber))
    : [];
  return {
    uid,
    emails: uniqueStrings([
      normalizeEmail(token.email),
      normalizeEmail(authUser && authUser.email),
      ...providerEmails,
    ]),
    phones: uniqueStrings([
      normalizePhoneForLookup(token.phone_number),
      normalizePhoneForLookup(authUser && authUser.phoneNumber),
      ...providerPhones,
    ]),
  };
}

async function firstProfileFromQuery(field, value) {
  if (!value) return null;
  const snap = await db.collection("gplus_profiles").where(field, "==", value).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { id: doc.id, data: doc.data() || {}, matchField: field };
}

async function findGPlusProfileForIdentity(identity) {
  const directDocIds = uniqueStrings([identity.uid, `user_${identity.uid}`, `profile_${identity.uid}`]);
  for (const docId of directDocIds) {
    const snap = await db.collection("gplus_profiles").doc(docId).get();
    if (snap.exists) return { id: snap.id, data: snap.data() || {}, matchField: "__name__" };
  }

  for (const field of ["uid", "userId", "authUid", "sourceUserId"]) {
    const match = await firstProfileFromQuery(field, identity.uid);
    if (match) return match;
  }

  for (const email of identity.emails) {
    for (const field of ["emailLower", "email", "private.email", "auth.email"]) {
      const match = await firstProfileFromQuery(field, email);
      if (match) return match;
    }
  }

  for (const phone of identity.phones) {
    for (const field of ["phone", "phoneNumber", "private.phone", "auth.phoneNumber"]) {
      const match = await firstProfileFromQuery(field, phone);
      if (match) return match;
    }
  }

  return null;
}

function fullNameFromProfile(profile = {}) {
  const direct = firstString(profile, ["displayName", "name", "fullName", "username"]);
  if (direct) return direct;
  return [safeString(profile.firstName), safeString(profile.lastName)].filter(Boolean).join(" ");
}

function birthdayFromProfile(profile = {}) {
  const date = toDate(profile.dateOfBirth) || toDate(profile.birthDate) || toDate(profile.dob);
  return date ? Timestamp.fromDate(new Date(date.getFullYear(), date.getMonth(), date.getDate())) : null;
}

function gplusProfileImportPayload({ profileId, profile, identity, matchField }) {
  const displayName = fullNameFromProfile(profile);
  const email = identity.emails[0] || normalizeEmail(profile.email);
  const phone = identity.phones[0] || normalizePhoneForLookup(profile.phone || profile.phoneNumber);
  const photoUrl = firstString(profile, ["photoUrl", "avatarUrl", "profileImageUrl", "profileImage"]);
  const username = safeString(profile.username || profile.handle).replace(/^@/, "");
  const city = firstString(profile, ["city", "locationCity"]);
  const bio = firstString(profile, ["bio", "about", "description"]);
  const dateOfBirth = birthdayFromProfile(profile);
  const payload = {
    roles: FieldValue.arrayUnion("attendee"),
    organizerApplicationStatus: "notStarted",
    notificationPrefs: {
      pushEnabled: true,
      smsEnabled: true,
      marketingOptIn: false,
      promotionalPushEnabled: true,
      promotionalEventTypes: [],
      promotionalCities: [],
    },
    gplusProfile: {
      imported: true,
      profileId,
      sourceUserId: safeString(profile.uid || profile.userId || profile.authUid || profileId),
      matchField,
      username: username || null,
      importedAt: FieldValue.serverTimestamp(),
    },
    sourceAccounts: FieldValue.arrayUnion("gplus"),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  };

  if (displayName) payload.displayName = cleanText(displayName, "", 180);
  if (email) {
    payload.email = email;
    payload.emailLower = email;
  }
  if (phone) payload.phone = phone;
  if (photoUrl) {
    payload.photoUrl = photoUrl;
    payload.profileImageUrl = photoUrl;
  }
  if (username) {
    payload.username = username;
    payload.usernameLower = username.toLowerCase();
  }
  if (city) payload.city = cleanText(city, "", 120);
  if (bio) payload.bio = cleanText(bio, "", 1000);
  if (dateOfBirth) payload.dateOfBirth = dateOfBirth;
  return payload;
}

exports.importSignedInGPlusProfile = onCall({ region: REGION }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const uid = request.auth.uid;
  await checkRateLimit(db, uid, "importSignedInGPlusProfile", { maxCalls: 20, windowSeconds: 3600 });

  const identity = await authIdentityForUid(uid, request.auth.token || {});
  const match = await findGPlusProfileForIdentity(identity);
  const statusRef = db.collection("gplus_sync_status").doc(`user_profile_${safeIdPart(uid, stableHash(uid))}`);

  if (!match) {
    await statusRef.set(
      {
        type: "user_profile_import",
        source: "gplus",
        userId: uid,
        status: "no_match",
        checkedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { ok: true, imported: false };
  }

  const userRef = db.collection("users").doc(uid);
  const existingUserSnap = await userRef.get();
  const existingUser = existingUserSnap.data() || {};
  const payload = gplusProfileImportPayload({
    profileId: match.id,
    profile: match.data,
    identity,
    matchField: match.matchField,
  });
  if (existingUserSnap.exists) {
    delete payload.createdAt;
    if (existingUser.notificationPrefs && typeof existingUser.notificationPrefs === "object") {
      delete payload.notificationPrefs;
    }
    if (safeString(existingUser.organizerApplicationStatus)) {
      delete payload.organizerApplicationStatus;
    }
  }
  await userRef.set(payload, { merge: true });
  await statusRef.set(
    {
      type: "user_profile_import",
      source: "gplus",
      userId: uid,
      sourceProfileId: match.id,
      matchField: match.matchField,
      status: "synced",
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    imported: true,
    profileId: match.id,
    displayName: payload.displayName || null,
    username: payload.username || null,
  };
});

exports.syncGPlusProfileToVennuzo = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  await checkRateLimit(db, request.auth.uid, "syncGPlusProfileToVennuzo", { maxCalls: 20, windowSeconds: 3600 });
  await assertAdmin(request.auth.uid);
  const profile = await ensureGPlusProfile(request.data && request.data.profile);
  const placeCampaignId = await upsertFeaturedPlaceCampaign();
  await db.collection("gplus_sync_status").doc("profile_gplus").set(
    {
      type: "profile",
      source: "gplus",
      profileId: GPLUS_PROFILE_ID,
      placePromotionCampaignId: placeCampaignId,
      status: "synced",
      syncMode: "realtime_firestore_trigger",
      syncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true, profileId: profile.id, placeCampaignId };
});

exports.syncGPlusEventToVennuzo = onCall({ region: REGION, timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  await checkRateLimit(db, request.auth.uid, "syncGPlusEventToVennuzo", { maxCalls: 60, windowSeconds: 3600 });
  await assertAdmin(request.auth.uid);
  const data = request.data || {};
  const gplusEventId = safeString(data.gplusEventId || data.eventId || (data.event && data.event.id));
  if (!gplusEventId) {
    throw new HttpsError("invalid-argument", "gplusEventId is required.");
  }
  const event = data.event && typeof data.event === "object" ? data.event : data;
  const result = await syncGPlusEventDocument(gplusEventId, event, {
    profile: data.profile && typeof data.profile === "object" ? data.profile : {},
  });
  return { ok: true, ...result };
});

exports.onGPlusProfileMirrorWritten = onDocumentWritten(
  { region: REGION, document: "gplus_profiles/{profileId}" },
  async (event) => {
    if (!event.data || !event.data.after.exists) return;
    const profile = event.data.after.data() || {};
    await ensureGPlusProfile(profile);
    const placeCampaignId = await upsertFeaturedPlaceCampaign();
    await db.collection("gplus_sync_status").doc("profile_gplus").set(
      {
        type: "profile",
        source: "gplus",
        sourceProfileId: event.params.profileId,
        profileId: GPLUS_PROFILE_ID,
        placePromotionCampaignId: placeCampaignId,
        status: "synced",
        syncedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  },
);

exports.onGPlusEventMirrorWritten = onDocumentWritten(
  { region: REGION, document: "gplus_events/{gplusEventId}", timeoutSeconds: 120 },
  async (event) => {
    if (!event.data) return;
    if (!event.data.after.exists) {
      await markGPlusEventDeleted(event.params.gplusEventId);
      return;
    }
    const source = event.data.after.data() || {};
    await syncGPlusEventDocument(event.params.gplusEventId, source);
  },
);

exports.onGPlusMediaGalleryWritten = onDocumentWritten(
  { region: REGION, document: "gplus_media_gallery/{mediaId}", timeoutSeconds: 120 },
  async (event) => {
    if (!event.data) return;
    if (!event.data.after.exists) {
      await markGPlusMediaDeleted(event.params.mediaId);
      return;
    }
    await upsertGPlusMediaGalleryItem(event.params.mediaId, event.data.after.data() || {});
  },
);

exports.onVennuzoEventPostWrittenToGelo = onDocumentWritten(
  { region: REGION, document: "event_posts/{postId}" },
  async (event) => {
    if (!event.data) return;
    const queueId = `vennuzo_post_${safeIdPart(event.params.postId, stableHash(event.params.postId))}`;
    if (!event.data.after.exists) {
      await db.collection("gelo_content_queue").doc(queueId).set(
        {
          status: "archived",
          archivedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }
    await upsertVennuzoPostToGelo(event.params.postId, event.data.after.data() || {});
  },
);

if (process.env.NODE_ENV === "test") {
  module.exports.normalizeGPlusEvent = normalizeGPlusEvent;
  module.exports.normalizeGPlusProfile = normalizeGPlusProfile;
  module.exports.normalizePostForGelo = normalizePostForGelo;
  module.exports.gplusEventVennuzoId = gplusEventVennuzoId;
}
