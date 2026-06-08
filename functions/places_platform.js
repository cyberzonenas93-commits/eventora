"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();
const { FieldValue, Timestamp, GeoPoint } = admin.firestore;

const REGION = "us-central1";
const PLACE_PUSH_UNIT_PRICE_GHS = 0.02;

function safeString(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function cleanText(value, fallback = "", max = 1000) {
  return safeString(value, fallback).slice(0, max);
}

function asDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value : null;
  if (typeof value.toDate === "function") {
    try {
      return value.toDate();
    } catch (error) {
      return null;
    }
  }
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function stringArray(value, max = 20) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => safeString(item)).filter(Boolean).slice(0, max);
}

function normalizedReservationStatus(value) {
  const status = safeString(value).toLowerCase().replace(/[_\s-]+/g, "");
  if (status === "confirmed") return "confirmed";
  if (status === "changerequested") return "changeRequested";
  if (status === "seated") return "seated";
  if (status === "cancelled" || status === "canceled") return "cancelled";
  if (status === "noshow") return "noShow";
  return "pending";
}

function normalizedReservationType(value) {
  const type = safeString(value).toLowerCase().replace(/[_\s-]+/g, "");
  if (type === "viptable") return "vipTable";
  if (type === "guestlist") return "guestlist";
  if (type === "bottleservice") return "bottleService";
  if (type === "privatebooking") return "privateBooking";
  return "table";
}

function normalizedVerificationStatus(value, fallback = "unverified") {
  const status = safeString(value).toLowerCase().replace(/[_\s-]+/g, "");
  if (status === "draft") return "draft";
  if (status === "verificationpending" || status === "pending") return "verification_pending";
  if (status === "verified" || status === "approved") return "verified";
  if (status === "rejected") return "rejected";
  if (status === "suspended") return "suspended";
  return fallback;
}

function normalizedVerificationMethod(value) {
  const method = safeString(value).toLowerCase().replace(/[_\s-]+/g, "");
  if (method === "phone" || method === "businessphone") return "phone";
  if (method === "document" || method === "documents") return "document";
  if (method === "googlemaps" || method === "maps" || method === "googleplace") return "google_maps";
  if (method === "website" || method === "social" || method === "websitesocial") return "website_social";
  return "email";
}

async function hasAdminAccess(uid) {
  if (!uid) return false;
  const adminSnap = await db.collection("admins").doc(uid).get();
  return adminSnap.exists && safeString((adminSnap.data() || {}).status, "active") !== "disabled";
}

async function assertAdmin(uid) {
  if (!(await hasAdminAccess(uid))) {
    throw new HttpsError("permission-denied", "Admin access is required.");
  }
}

async function assertPlaceManager(uid, placeData) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (safeString(placeData.ownerId) === uid || safeString(placeData.createdBy) === uid) {
    return;
  }

  const organizationId = safeString(placeData.organizationId);
  if (organizationId === `org_${uid}`) return;

  const adminSnap = await db.collection("admins").doc(uid).get();
  if (adminSnap.exists) return;

  if (!organizationId) {
    throw new HttpsError("permission-denied", "You do not manage this place.");
  }
  const memberSnap = await db.collection("organization_members").doc(`${organizationId}_${uid}`).get();
  if (!memberSnap.exists || (memberSnap.data() || {}).status !== "active") {
    throw new HttpsError("permission-denied", "You do not manage this place.");
  }
}

async function loadManagedPlace(uid, placeId) {
  const id = safeString(placeId);
  if (!id) throw new HttpsError("invalid-argument", "placeId is required.");
  const snap = await db.collection("places").doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "Place not found.");
  const data = snap.data() || {};
  await assertPlaceManager(uid, data);
  return { placeId: id, placeData: data };
}

async function ensureSelfServeWorkspace(uid, organizationId, displayName) {
  if (!uid || !organizationId || organizationId !== `org_${uid}`) return;
  const batch = db.batch();
  batch.set(
    db.collection("organizations").doc(organizationId),
    {
      id: organizationId,
      ownerId: uid,
      name: cleanText(displayName, "Vennuzo location owner", 120),
      status: "active",
      workspaceType: "location_self_serve",
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    db.collection("organization_members").doc(`${organizationId}_${uid}`),
    {
      organizationId,
      userId: uid,
      role: "owner",
      status: "active",
      permissions: {
        managePlaces: true,
        manageMenus: true,
        manageReservations: true,
        managePromotions: false,
      },
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  batch.set(
    db.collection("users").doc(uid),
    {
      defaultOrganizationId: organizationId,
      roles: FieldValue.arrayUnion("location_owner"),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
}

async function chargePlacePush({ organizationId, campaignId, amountGhs }) {
  const rounded = Math.round(Number(amountGhs || 0) * 100) / 100;
  if (rounded <= 0) return;
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const txnRef = db.collection("wallet_transactions").doc(`place_push_${campaignId}`);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(txnRef);
    if (existing.exists && existing.data().status === "completed") return;
    const walletSnap = await transaction.get(walletRef);
    const wallet = walletSnap.exists ? walletSnap.data() || {} : {};
    const available = Number(wallet.availableBalance || 0);
    if (available < rounded) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient wallet balance. Need ${rounded.toFixed(2)} GHS; available ${available.toFixed(2)} GHS.`,
      );
    }
    transaction.set(walletRef, {
      availableBalance: FieldValue.increment(-rounded),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "place_push_campaign",
      amount: rounded,
      campaignId,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

exports.upsertPlaceProfile = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "upsertPlaceProfile", { maxCalls: 40, windowSeconds: 3600 });
  const data = request.data || {};
  const placeId = safeString(data.placeId || data.id);
  if (!placeId) throw new HttpsError("invalid-argument", "placeId is required.");
  const existing = await db.collection("places").doc(placeId).get();
  if (existing.exists) await assertPlaceManager(request.auth.uid, existing.data() || {});
  const organizationId = safeString(data.organizationId, `org_${request.auth.uid}`);
  const latitude = Number(data.latitude);
  const longitude = Number(data.longitude);
  const existingData = existing.exists ? existing.data() || {} : {};
  await ensureSelfServeWorkspace(request.auth.uid, organizationId, data.name || request.auth.token.email);
  const verified = normalizedVerificationStatus(existingData.verificationStatus) === "verified";
  await db.collection("places").doc(placeId).set({
    organizationId,
    ownerId: safeString(existingData.ownerId, request.auth.uid),
    createdBy: safeString(existingData.createdBy, request.auth.uid),
    name: cleanText(data.name, "Vennuzo place", 120),
    description: cleanText(data.description, "", 1000),
    city: cleanText(data.city, "Accra", 80),
    address: cleanText(data.address || data.formattedAddress, "", 240),
    googlePlaceId: safeString(data.googlePlaceId) || safeString(existingData.googlePlaceId) || null,
    mapsUrl: safeString(data.mapsUrl || data.googleMapsUrl) || null,
    phone: safeString(data.phone) || null,
    website: safeString(data.website) || null,
    logoUrl: safeString(data.logoUrl) || null,
    coverUrl: safeString(data.coverUrl) || null,
    galleryUrls: stringArray(data.galleryUrls || data.photos, 40),
    categories: stringArray(data.categories, 12),
    amenities: stringArray(data.amenities, 30),
    openingHours: stringArray(data.openingHours || data.hours, 14),
    location: Number.isFinite(latitude) && Number.isFinite(longitude) ? new GeoPoint(latitude, longitude) : null,
    status: safeString(data.status, existingData.status || "active"),
    verificationStatus: normalizedVerificationStatus(existingData.verificationStatus),
    verificationRequiredFor: [
      "featured_placement",
      "paid_subscriber_push",
      "payments_or_deposits",
      "official_review_responses",
    ],
    verified: verified,
    featured: verified && data.featured === true ? true : existingData.featured === true,
    selfServeOnboarding: true,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: existing.exists ? existingData.createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, placeId, verificationStatus: normalizedVerificationStatus(existingData.verificationStatus) };
});

exports.submitPlaceVerification = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "submitPlaceVerification", { maxCalls: 20, windowSeconds: 3600 });
  const data = request.data || {};
  const { placeId, placeData } = await loadManagedPlace(request.auth.uid, data.placeId);
  const contactEmail = cleanText(data.contactEmail || request.auth.token.email, "", 180).toLowerCase();
  const contactPhone = cleanText(data.contactPhone || placeData.phone, "", 50);
  const method = normalizedVerificationMethod(data.method);
  if (!contactEmail && method === "email") {
    throw new HttpsError("invalid-argument", "A contact email is required for email verification.");
  }
  const requestId = safeString(data.requestId) || db.collection("place_verifications").doc().id;
  const authEmail = safeString(request.auth.token.email).toLowerCase();
  const emailContactVerified =
    !!contactEmail && contactEmail === authEmail && request.auth.token.email_verified === true;
  await db.collection("place_verifications").doc(requestId).set({
    placeId,
    placeName: safeString(placeData.name, "Vennuzo place"),
    organizationId: safeString(placeData.organizationId),
    requestedBy: request.auth.uid,
    method,
    status: "pending",
    contactEmail,
    contactEmailVerified: emailContactVerified,
    contactPhone,
    googleMapsUrl: safeString(data.googleMapsUrl || data.mapsUrl || placeData.mapsUrl),
    googlePlaceId: safeString(data.googlePlaceId || placeData.googlePlaceId),
    websiteUrl: safeString(data.websiteUrl || data.website || placeData.website),
    socialUrl: safeString(data.socialUrl || data.instagram || data.tiktok),
    documentUrls: stringArray(data.documentUrls, 12),
    notes: cleanText(data.notes, "", 1200),
    submittedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.collection("places").doc(placeId).set({
    verificationStatus: "verification_pending",
    latestVerificationRequestId: requestId,
    verified: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, requestId, placeId, status: "pending", emailContactVerified };
});

exports.reviewPlaceVerification = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await assertAdmin(request.auth.uid);
  const data = request.data || {};
  const requestId = safeString(data.requestId);
  if (!requestId) throw new HttpsError("invalid-argument", "requestId is required.");
  const snap = await db.collection("place_verifications").doc(requestId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Verification request not found.");
  const verification = snap.data() || {};
  const approved = safeString(data.decision).toLowerCase() === "approve" || data.approved === true;
  const placeId = safeString(verification.placeId);
  const nextStatus = approved ? "approved" : "rejected";
  const placeStatus = approved ? "verified" : "rejected";
  await db.runTransaction(async (transaction) => {
    transaction.set(snap.ref, {
      status: nextStatus,
      reviewNotes: cleanText(data.reviewNotes, "", 1200),
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (placeId) {
      transaction.set(db.collection("places").doc(placeId), {
        verificationStatus: placeStatus,
        verified: approved,
        verifiedAt: approved ? FieldValue.serverTimestamp() : null,
        verifiedBy: approved ? request.auth.uid : null,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });
  return { ok: true, requestId, placeId, status: nextStatus };
});

exports.upsertPlaceMenuSection = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "upsertPlaceMenuSection", { maxCalls: 80, windowSeconds: 3600 });
  const data = request.data || {};
  const { placeId } = await loadManagedPlace(request.auth.uid, data.placeId);
  const sectionId = safeString(data.sectionId || data.id) || db.collection("place_menu_sections").doc().id;
  await db.collection("place_menu_sections").doc(sectionId).set({
    placeId,
    name: cleanText(data.name, "Menu", 100),
    description: cleanText(data.description, "", 400),
    sortOrder: Number(data.sortOrder) || 0,
    visible: data.visible !== false,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, sectionId };
});

exports.upsertPlaceMenuItem = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "upsertPlaceMenuItem", { maxCalls: 120, windowSeconds: 3600 });
  const data = request.data || {};
  const { placeId } = await loadManagedPlace(request.auth.uid, data.placeId);
  const itemId = safeString(data.itemId || data.id) || db.collection("place_menu_items").doc().id;
  const price = Math.max(0, Number(data.price) || 0);
  await db.collection("place_menu_items").doc(itemId).set({
    placeId,
    sectionId: safeString(data.sectionId),
    name: cleanText(data.name, "Menu item", 120),
    description: cleanText(data.description, "", 600),
    price,
    currency: safeString(data.currency, "GHS"),
    imageUrl: safeString(data.imageUrl) || null,
    featured: data.featured === true,
    status: safeString(data.status, "available"),
    options: stringArray(data.options, 20),
    tags: stringArray(data.tags, 20),
    sortOrder: Number(data.sortOrder) || 0,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, itemId };
});

exports.createPlaceReservation = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before reserving.");
  await checkRateLimit(db, request.auth.uid, "createPlaceReservation", { maxCalls: 20, windowSeconds: 3600 });
  const data = request.data || {};
  const placeId = safeString(data.placeId);
  if (!placeId) throw new HttpsError("invalid-argument", "placeId is required.");
  const placeSnap = await db.collection("places").doc(placeId).get();
  if (!placeSnap.exists) throw new HttpsError("not-found", "Place not found.");
  const place = placeSnap.data() || {};
  const requestedAt = asDate(data.requestedAt);
  if (!requestedAt) throw new HttpsError("invalid-argument", "requestedAt is required.");
  const reservationId = safeString(data.reservationId) || db.collection("place_reservations").doc().id;
  await db.collection("place_reservations").doc(reservationId).set({
    placeId,
    placeName: safeString(place.name, safeString(data.placeName, "Place")),
    organizationId: safeString(place.organizationId),
    userId: request.auth.uid,
    guestName: cleanText(data.guestName || data.name, "Guest", 120),
    phone: cleanText(data.phone, "", 40),
    partySize: Math.max(1, Math.min(100, Number(data.partySize) || 1)),
    requestedAt: Timestamp.fromDate(requestedAt),
    reservationType: normalizedReservationType(data.reservationType),
    selectedMenuItemIds: stringArray(data.selectedMenuItemIds, 30),
    note: cleanText(data.note, "", 600),
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, reservationId };
});

exports.updatePlaceReservationStatus = onCall({ region: REGION, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "updatePlaceReservationStatus", { maxCalls: 120, windowSeconds: 3600 });
  const reservationId = safeString(request.data && request.data.reservationId);
  if (!reservationId) throw new HttpsError("invalid-argument", "reservationId is required.");
  const snap = await db.collection("place_reservations").doc(reservationId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Reservation not found.");
  const reservation = snap.data() || {};
  await loadManagedPlace(request.auth.uid, reservation.placeId);
  const status = normalizedReservationStatus(request.data && request.data.status);
  await snap.ref.set({
    status,
    internalNote: cleanText(request.data && request.data.internalNote, reservation.internalNote || "", 600),
    updatedBy: request.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, reservationId, status };
});

exports.launchPlacePushCampaign = onCall({ region: REGION, timeoutSeconds: 300 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  await checkRateLimit(db, request.auth.uid, "launchPlacePushCampaign", { maxCalls: 20, windowSeconds: 3600 });
  const data = request.data || {};
  const { placeId, placeData } = await loadManagedPlace(request.auth.uid, data.placeId);
  if (normalizedVerificationStatus(placeData.verificationStatus) !== "verified") {
    throw new HttpsError(
      "failed-precondition",
      "Verify this place before sending paid push campaigns to subscribers.",
    );
  }
  const title = cleanText(data.title, safeString(placeData.name, "Vennuzo place"), 120);
  const message = cleanText(data.message, "", 600);
  if (!message) throw new HttpsError("invalid-argument", "message is required.");
  const organizationId = safeString(placeData.organizationId, `org_${request.auth.uid}`);

  const subsSnap = await db.collection("place_subscriptions")
    .where("placeId", "==", placeId)
    .where("status", "==", "active")
    .limit(2000)
    .get();
  const userIds = [...new Set(subsSnap.docs.map((doc) => safeString((doc.data() || {}).userId)).filter(Boolean))];
  const tokens = [];
  for (let i = 0; i < userIds.length; i += 10) {
    const chunk = userIds.slice(i, i + 10);
    const userSnaps = await Promise.all(chunk.map((uid) => db.collection("users").doc(uid).get()));
    for (const userSnap of userSnaps) {
      const user = userSnap.exists ? userSnap.data() || {} : {};
      const prefs = user.notificationPrefs || {};
      if (prefs.pushEnabled === false || prefs.marketingOptIn !== true) continue;
      const token = safeString(user.fcmToken);
      if (token) tokens.push(token);
    }
  }

  const estimatedCost = Math.round(tokens.length * PLACE_PUSH_UNIT_PRICE_GHS * 100) / 100;
  const campaignId = safeString(data.campaignId) || db.collection("promotion_campaigns").doc().id;
  await chargePlacePush({ organizationId, campaignId, amountGhs: estimatedCost });

  await db.collection("promotion_campaigns").doc(campaignId).set({
    organizationId,
    eventId: "",
    eventTitle: "",
    targetType: "place",
    targetId: placeId,
    targetTitle: safeString(placeData.name, "Place"),
    name: cleanText(data.name, `${safeString(placeData.name, "Place")} push`, 140),
    status: "live",
    channels: ["push"],
    audienceSources: ["place_subscribers"],
    audienceSourceName: "Place subscribers",
    pushAudience: tokens.length,
    smsAudience: 0,
    shareLinkEnabled: false,
    budget: estimatedCost,
    placePushUnitPriceGhs: PLACE_PUSH_UNIT_PRICE_GHS,
    message,
    objective: "place_awareness",
    audienceStrategy: "place_subscribers",
    optimizationGoal: "reach",
    bidStrategy: "balanced",
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  let sent = 0;
  let failed = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const batch = tokens.slice(i, i + 500);
    if (batch.length === 0) continue;
    const response = await messaging.sendEachForMulticast({
      tokens: batch,
      notification: { title, body: message },
      data: { placeId, campaignId, route: `/places/${placeId}`, type: "place_push" },
    });
    sent += response.successCount;
    failed += response.failureCount;
  }
  await db.collection("promotion_campaigns").doc(campaignId).set({
    sentCount: sent,
    failedCount: failed,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, campaignId, subscriberCount: userIds.length, pushAudience: tokens.length, sent, failed, costGhs: estimatedCost };
});
