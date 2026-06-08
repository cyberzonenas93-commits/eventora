"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  canRolePerform,
  effectiveAdminRole,
  isAllowedSuperAdminEmail,
  isKnownAdminRole,
  normalizeAdminRole,
} = require("./admin_permissions");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const DEFAULT_FEATURED_PLACEMENT_PRICE_GHS = 150;
const DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS = 300;
function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function nonNegativeNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

async function resolveAdminEmail(uid, adminData) {
  const docEmail = safeString(adminData && adminData.email).toLowerCase();
  if (docEmail) {
    return docEmail;
  }
  try {
    const authUser = await admin.auth().getUser(uid);
    return safeString(authUser.email).toLowerCase();
  } catch (error) {
    return "";
  }
}

async function assertAdminCan(uid, action) {
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const adminData = adminSnap.data() || {};
  const email = await resolveAdminEmail(uid, adminData);
  const role = normalizeAdminRole(adminData.role);
  const status = safeString(adminData.status, "active").toLowerCase();
  if (!isKnownAdminRole(role) || status === "disabled") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  if (effectiveAdminRole(role) === "superadmin" && !isAllowedSuperAdminEmail(email)) {
    throw new HttpsError("permission-denied", "Owner access required.");
  }
  if (!canRolePerform(role, action)) {
    throw new HttpsError("permission-denied", "This admin role cannot perform that action.");
  }
  return { uid, role, email };
}

exports.getAdminPricingConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertAdminCan(request.auth.uid, "read_pricing");
    const snap = await db.collection("app_config").doc("pricing").get();
    const data = snap.exists ? snap.data() || {} : {};
    return {
      defaultSmsRateGhs: Number(data.defaultSmsRateGhs) || 0.04,
      smsMarginMultiplier: Number(data.smsMarginMultiplier) || 1.5,
      platformPushUnitPriceGhs: Number(data.platformPushUnitPriceGhs) || 0.02,
      featuredPlacementPriceGhs: nonNegativeNumber(
        data.featuredPlacementPriceGhs,
        DEFAULT_FEATURED_PLACEMENT_PRICE_GHS,
      ),
      announcementPlacementPriceGhs: nonNegativeNumber(
        data.announcementPlacementPriceGhs,
        DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS,
      ),
      // Launch pricing: 5% for first 6 months; transitions to 8% standard rate.
      platformServiceFeePercent: Number(data.platformServiceFeePercent) || 0.05,
    };
  },
);

exports.setAdminPricingConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertAdminCan(request.auth.uid, "manage_pricing");
    const defaultSmsRateGhs = Number(request.data && request.data.defaultSmsRateGhs);
    const smsMarginMultiplier = Number(request.data && request.data.smsMarginMultiplier);
    const platformPushUnitPriceGhs = Number(request.data && request.data.platformPushUnitPriceGhs);
    const featuredPlacementPriceGhs = Number(request.data && request.data.featuredPlacementPriceGhs);
    const announcementPlacementPriceGhs = Number(request.data && request.data.announcementPlacementPriceGhs);
    const platformServiceFeePercent = Number(request.data && request.data.platformServiceFeePercent);
    if (!Number.isFinite(defaultSmsRateGhs) || defaultSmsRateGhs < 0) {
      throw new HttpsError("invalid-argument", "defaultSmsRateGhs must be a non-negative number.");
    }
    if (!Number.isFinite(smsMarginMultiplier) || smsMarginMultiplier < 1) {
      throw new HttpsError("invalid-argument", "smsMarginMultiplier must be >= 1.");
    }
    if (Number.isFinite(platformPushUnitPriceGhs) && platformPushUnitPriceGhs < 0) {
      throw new HttpsError("invalid-argument", "platformPushUnitPriceGhs must be a non-negative number.");
    }
    if (Number.isFinite(featuredPlacementPriceGhs) && featuredPlacementPriceGhs < 0) {
      throw new HttpsError("invalid-argument", "featuredPlacementPriceGhs must be a non-negative number.");
    }
    if (Number.isFinite(announcementPlacementPriceGhs) && announcementPlacementPriceGhs < 0) {
      throw new HttpsError("invalid-argument", "announcementPlacementPriceGhs must be a non-negative number.");
    }
    if (Number.isFinite(platformServiceFeePercent) && (platformServiceFeePercent < 0 || platformServiceFeePercent > 1)) {
      throw new HttpsError("invalid-argument", "platformServiceFeePercent must be between 0 and 1.");
    }
    await db.collection("app_config").doc("pricing").set(
      {
        defaultSmsRateGhs,
        smsMarginMultiplier,
        platformPushUnitPriceGhs: Number.isFinite(platformPushUnitPriceGhs) ? platformPushUnitPriceGhs : 0.02,
        featuredPlacementPriceGhs: Number.isFinite(featuredPlacementPriceGhs) ?
          featuredPlacementPriceGhs :
          DEFAULT_FEATURED_PLACEMENT_PRICE_GHS,
        announcementPlacementPriceGhs: Number.isFinite(announcementPlacementPriceGhs) ?
          announcementPlacementPriceGhs :
          DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS,
        // Launch pricing: 5% for first 6 months; transitions to 8% standard rate.
        platformServiceFeePercent: Number.isFinite(platformServiceFeePercent) ? platformServiceFeePercent : 0.05,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: request.auth.uid,
      },
      { merge: true },
    );
    return { success: true };
  },
);

exports.listAdminPromoPackages = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertAdminCan(request.auth.uid, "read_pricing");
    const snap = await db
      .collection("promo_packages")
      .orderBy("order", "asc")
      .limit(100)
      .get();
    const packages = snap.docs.map((docSnap) => {
      const d = docSnap.data() || {};
      return {
        id: docSnap.id,
        name: safeString(d.name, "Package"),
        description: safeString(d.description),
        active: d.active === true,
        order: Number(d.order) || 0,
        defaultSmsRateGhs: Number(d.defaultSmsRateGhs) || 0.04,
        smsMarginMultiplier: Number(d.smsMarginMultiplier) || 1.5,
        platformPushUnitPriceGhs: Number(d.platformPushUnitPriceGhs) || 0.02,
        featuredPlacementPriceGhs: nonNegativeNumber(
          d.featuredPlacementPriceGhs,
          DEFAULT_FEATURED_PLACEMENT_PRICE_GHS,
        ),
        announcementPlacementPriceGhs: nonNegativeNumber(
          d.announcementPlacementPriceGhs,
          DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS,
        ),
        minSpend: d.minSpend != null ? Number(d.minSpend) : undefined,
      };
    });
    return { packages };
  },
);

exports.setAdminPromoPackage = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertAdminCan(request.auth.uid, "manage_promo_packages");
    const id = safeString(request.data && request.data.id);
    const name = safeString(request.data && request.data.name);
    const description = safeString(request.data && request.data.description);
    const active = request.data && request.data.active === true;
    const order = Number(request.data && request.data.order);
    const defaultSmsRateGhs = Number(request.data && request.data.defaultSmsRateGhs);
    const smsMarginMultiplier = Number(request.data && request.data.smsMarginMultiplier);
    const platformPushUnitPriceGhs = Number(request.data && request.data.platformPushUnitPriceGhs);
    const featuredPlacementPriceGhs = Number(request.data && request.data.featuredPlacementPriceGhs);
    const announcementPlacementPriceGhs = Number(request.data && request.data.announcementPlacementPriceGhs);
    const minSpend = request.data && request.data.minSpend != null ? Number(request.data.minSpend) : undefined;

    if (!name) throw new HttpsError("invalid-argument", "name is required.");

    const payload = {
      name,
      description: description || null,
      active: !!active,
      order: Number.isFinite(order) ? order : 0,
      defaultSmsRateGhs: Number.isFinite(defaultSmsRateGhs) ? defaultSmsRateGhs : 0.04,
      smsMarginMultiplier: Number.isFinite(smsMarginMultiplier) && smsMarginMultiplier >= 1 ? smsMarginMultiplier : 1.5,
      platformPushUnitPriceGhs: Number.isFinite(platformPushUnitPriceGhs) && platformPushUnitPriceGhs >= 0 ? platformPushUnitPriceGhs : 0.02,
      featuredPlacementPriceGhs: Number.isFinite(featuredPlacementPriceGhs) && featuredPlacementPriceGhs >= 0 ?
        featuredPlacementPriceGhs :
        DEFAULT_FEATURED_PLACEMENT_PRICE_GHS,
      announcementPlacementPriceGhs: Number.isFinite(announcementPlacementPriceGhs) && announcementPlacementPriceGhs >= 0 ?
        announcementPlacementPriceGhs :
        DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    };
    if (minSpend != null && Number.isFinite(minSpend)) payload.minSpend = minSpend;

    const ref = id
      ? db.collection("promo_packages").doc(id)
      : db.collection("promo_packages").doc();
    if (!id) payload.createdAt = FieldValue.serverTimestamp();
    await ref.set(payload, { merge: true });
    return { success: true, id: ref.id };
  },
);

exports.listAdminCampaigns = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertAdminCan(request.auth.uid, "read_campaigns");
    const limit = Math.min(Number(request.data && request.data.limit) || 50, 100);
    const statusFilter = safeString(request.data && request.data.status);
    let query = db.collection("promotion_campaigns").orderBy("createdAt", "desc").limit(limit);
    if (statusFilter) {
      query = db
        .collection("promotion_campaigns")
        .where("status", "==", statusFilter)
        .orderBy("createdAt", "desc")
        .limit(limit);
    }
    const snap = await query.get();
    const campaigns = snap.docs.map((docSnap) => {
      const d = docSnap.data() || {};
      const createdAt = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate().toISOString() : "";
      const scheduledAt = d.scheduledAt && d.scheduledAt.toDate ? d.scheduledAt.toDate().toISOString() : "";
      return {
        id: docSnap.id,
        eventId: safeString(d.eventId),
        eventTitle: safeString(d.eventTitle),
        organizationId: safeString(d.organizationId),
        status: safeString(d.status),
        channels: Array.isArray(d.channels) ? d.channels : [],
        pushAudience: Number(d.pushAudience ?? 0),
        smsAudience: Number(d.smsAudience ?? 0),
        walletReservationAmount: Number(d.walletReservationAmount ?? 0),
        totalSmsCharged: d.totalSmsCharged != null ? Number(d.totalSmsCharged) : undefined,
        createdAt,
        scheduledAt: scheduledAt || undefined,
        createdBy: safeString(d.createdBy),
      };
    });
    return { campaigns };
  },
);
