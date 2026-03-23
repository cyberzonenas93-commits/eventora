"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

async function assertSuperAdmin(uid) {
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError("permission-denied", "Superadmin access required.");
  }
  const role = safeString(adminSnap.data() && adminSnap.data().role).toLowerCase();
  if (role !== "superadmin") {
    throw new HttpsError("permission-denied", "Superadmin access required.");
  }
}

exports.getAdminPricingConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertSuperAdmin(request.auth.uid);
    const snap = await db.collection("app_config").doc("pricing").get();
    const data = snap.exists ? snap.data() || {} : {};
    return {
      defaultSmsRateGhs: Number(data.defaultSmsRateGhs) || 0.05,
      smsMarginMultiplier: Number(data.smsMarginMultiplier) || 1.5,
    };
  },
);

exports.setAdminPricingConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    await assertSuperAdmin(request.auth.uid);
    const defaultSmsRateGhs = Number(request.data && request.data.defaultSmsRateGhs);
    const smsMarginMultiplier = Number(request.data && request.data.smsMarginMultiplier);
    if (!Number.isFinite(defaultSmsRateGhs) || defaultSmsRateGhs < 0) {
      throw new HttpsError("invalid-argument", "defaultSmsRateGhs must be a non-negative number.");
    }
    if (!Number.isFinite(smsMarginMultiplier) || smsMarginMultiplier < 1) {
      throw new HttpsError("invalid-argument", "smsMarginMultiplier must be >= 1.");
    }
    await db.collection("app_config").doc("pricing").set(
      {
        defaultSmsRateGhs,
        smsMarginMultiplier,
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
    await assertSuperAdmin(request.auth.uid);
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
        defaultSmsRateGhs: Number(d.defaultSmsRateGhs) || 0.05,
        smsMarginMultiplier: Number(d.smsMarginMultiplier) || 1.5,
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
    await assertSuperAdmin(request.auth.uid);
    const id = safeString(request.data && request.data.id);
    const name = safeString(request.data && request.data.name);
    const description = safeString(request.data && request.data.description);
    const active = request.data && request.data.active === true;
    const order = Number(request.data && request.data.order);
    const defaultSmsRateGhs = Number(request.data && request.data.defaultSmsRateGhs);
    const smsMarginMultiplier = Number(request.data && request.data.smsMarginMultiplier);
    const minSpend = request.data && request.data.minSpend != null ? Number(request.data.minSpend) : undefined;

    if (!name) throw new HttpsError("invalid-argument", "name is required.");

    const payload = {
      name,
      description: description || null,
      active: !!active,
      order: Number.isFinite(order) ? order : 0,
      defaultSmsRateGhs: Number.isFinite(defaultSmsRateGhs) ? defaultSmsRateGhs : 0.05,
      smsMarginMultiplier: Number.isFinite(smsMarginMultiplier) && smsMarginMultiplier >= 1 ? smsMarginMultiplier : 1.5,
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
    await assertSuperAdmin(request.auth.uid);
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
