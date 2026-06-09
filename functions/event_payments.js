"use strict";

const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { notifySuperAdmins } = require("./event_notifications");
const { checkRateLimit } = require("./rate_limiter");
const logger = require("./logger");
const { syncOrderToGPlusTicketing } = require("./gplus_ticket_bridge");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const VENNUZO_SCHEME = "vennuzoapp";
const HUBTEL_SEND_MONEY_BASE = "https://smp.hubtel.com";
const HUBTEL_SEND_MONEY_STATUS_BASE = "https://smrsc.hubtel.com";
const PAYOUT_CLIENT_REFERENCE_PREFIX = "vpo";
const PAYOUT_CHANNELS = new Set(["mtn-gh", "vodafone-gh", "tigo-gh"]);
let publicBaseUrlCache = null;

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Constant-time verification of a Hubtel HMAC-SHA256 callback signature.
 * Returns false for a missing/mismatched signature.
 */
function verifyHubtelSignature(secret, payload, headerSignature) {
  const incoming = safeString(headerSignature);
  if (!incoming) {
    return false;
  }
  const expected = crypto
    .createHmac("sha256", secret)
    .update(JSON.stringify(payload))
    .digest("hex");
  const incomingBuf = Buffer.from(incoming);
  const expectedBuf = Buffer.from(expected);
  if (incomingBuf.length !== expectedBuf.length) {
    return false;
  }
  return crypto.timingSafeEqual(incomingBuf, expectedBuf);
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) {
    return "";
  }
  if (digits.startsWith("+233")) {
    return digits;
  }
  if (digits.startsWith("233") && digits.length === 12) {
    return `+${digits}`;
  }
  if (digits.startsWith("0") && digits.length === 10) {
    return `+233${digits.slice(1)}`;
  }
  if (digits.length === 9) {
    return `+233${digits}`;
  }
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function normalizeMsisdn(raw) {
  let digits = String(raw || "").replace(/\D/g, "");
  if (digits.startsWith("0") && digits.length === 10) {
    digits = `233${digits.slice(1)}`;
  } else if (!digits.startsWith("233") && digits.length === 9) {
    digits = `233${digits}`;
  }
  return digits.length === 12 && digits.startsWith("233") ? digits : "";
}

function normalizePayoutChannel(value, msisdn = "") {
  const raw = safeString(value).toLowerCase();
  if (raw.includes("mtn")) return "mtn-gh";
  if (raw.includes("telecel") || raw.includes("vodafone")) return "vodafone-gh";
  if (raw.includes("airtel") || raw.includes("tigo")) return "tigo-gh";
  if (PAYOUT_CHANNELS.has(raw)) return raw;
  if (/^233(24|25|53|54|55|59)/.test(msisdn)) return "mtn-gh";
  if (/^233(20|50)/.test(msisdn)) return "vodafone-gh";
  if (/^233(26|27|56|57)/.test(msisdn)) return "tigo-gh";
  return "";
}

function moneyAmount(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : 0;
}

function projectId() {
  return safeString(process.env.GCLOUD_PROJECT || admin.app().options.projectId);
}

function functionsBaseUrl() {
  const pid = projectId();
  if (!pid) {
    throw new Error("GCLOUD_PROJECT is not available for Vennuzo payments.");
  }
  return `https://${REGION}-${pid}.cloudfunctions.net`;
}

async function getHubtelConfig() {
  const snap = await db.collection("app_config").doc("hubtel").get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Hubtel config not found.");
  }

  const data = snap.data() || {};
  const apiKey = safeString(data.apiKey);
  const apiSecret = safeString(data.apiSecret);
  const merchantAccount = safeString(
    data.merchantAccountNumber || data.merchantAccount,
  );
  // Source order matches the Gplus reference: HUBTEL_CALLBACK_SECRET env var
  // first, then app_config/hubtel.callbackSecret. Empty = fail-open (verification
  // off) until the secret is set here + in the Hubtel merchant dashboard.
  const callbackSecret =
    safeString(process.env.HUBTEL_CALLBACK_SECRET) || safeString(data.callbackSecret);

  if (!apiKey || !apiSecret || !merchantAccount) {
    throw new HttpsError(
      "failed-precondition",
      "Hubtel merchant credentials are not configured.",
    );
  }

  return {
    apiKey,
    apiSecret,
    merchantAccount,
    callbackSecret,
  };
}

async function getHubtelSendMoneyConfig() {
  const snap = await db.collection("app_config").doc("hubtel").get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Hubtel config not found.");
  }
  const data = snap.data() || {};
  const prepaidDepositId = safeString(
    data.sendMoneyPrepaidDepositId ||
      data.prepaidDepositId ||
      data.prepaidDepositAccount,
  );
  const apiKey = safeString(data.apiKey);
  const apiSecret = safeString(data.apiSecret);
  if (!prepaidDepositId || !apiKey || !apiSecret) {
    throw new HttpsError(
      "failed-precondition",
      "Hubtel Send Money is not configured. Add sendMoneyPrepaidDepositId to app_config/hubtel.",
    );
  }
  return { prepaidDepositId, apiKey, apiSecret };
}

function hubtelAuthHeader(config) {
  return `Basic ${Buffer.from(`${config.apiKey}:${config.apiSecret}`).toString("base64")}`;
}

/**
 * Server-to-server confirmation of a Hubtel transaction status.
 *
 * SECURITY: callback webhooks are forgeable — never fulfil a "paid" outcome
 * (issue tickets, credit wallets, mark settlementEligible) based on the
 * callback body alone. This re-queries Hubtel's authoritative transaction
 * status endpoint and is the trust anchor for all callback handlers.
 *
 * Returns { ok, status, data, reason }. `ok` is only true when Hubtel
 * positively confirmed the transaction (responseCode "0000" with data).
 * On any uncertainty (network error, IP not whitelisted, malformed body)
 * `ok` is false and callers MUST NOT treat the payment as completed.
 */
async function confirmHubtelStatusFromProvider(clientReference, config) {
  const reference = safeString(clientReference);
  if (!reference) {
    return { ok: false, status: "unknown", reason: "missing_reference" };
  }
  let resolvedConfig = config;
  if (!resolvedConfig || !resolvedConfig.merchantAccount) {
    resolvedConfig = await getHubtelConfig();
  }
  const url =
    `https://api-txnstatus.hubtel.com/transactions/${resolvedConfig.merchantAccount}` +
    `/status?clientReference=${encodeURIComponent(reference)}`;
  let response;
  try {
    response = await fetch(url, {
      method: "GET",
      headers: { Authorization: hubtelAuthHeader(resolvedConfig) },
    });
  } catch (error) {
    return {
      ok: false,
      status: "unknown",
      reason: `fetch_failed:${safeString(error && error.message, "network error")}`,
    };
  }
  if (response.status === 403) {
    return { ok: false, status: "unknown", reason: "ip_not_whitelisted" };
  }
  const result = await response.json().catch(() => ({}));
  if (result.responseCode !== "0000" || !result.data) {
    return { ok: false, status: "unknown", reason: "unconfirmed", raw: result };
  }
  return {
    ok: true,
    status: normalizeHubtelStatus(result.data.status),
    data: result.data,
  };
}

const DEFAULT_STUDIO_BASE = "https://vennuzo.com/studio";

function studioReturnBaseUrl() {
  const configured = safeString(process.env.VENNUZO_STUDIO_URL, DEFAULT_STUDIO_BASE)
    .replace(/\/+$/, "");
  return configured.endsWith("/studio") ? configured : `${configured}/studio`;
}

const STUDIO_RETURN_BASE = studioReturnBaseUrl();

async function getPublicBaseUrl() {
  if (publicBaseUrlCache) {
    return publicBaseUrlCache;
  }

  const envUrl = safeString(
    process.env.VENNUZO_PUBLIC_URL ||
      process.env.VENNUZO_PUBLIC_BASE_URL ||
      process.env.VENNUZO_SITE_URL,
  );
  if (envUrl) {
    publicBaseUrlCache = envUrl.replace(/\/+$/, "");
    return publicBaseUrlCache;
  }

  try {
    const siteSnap = await db.collection("app_config").doc("site").get();
    const site = siteSnap.exists ? siteSnap.data() || {} : {};
    const configured = safeString(
      site.publicUrl ||
        site.publicBaseUrl ||
        site.vennuzoPublicUrl ||
        site.webUrl,
    );
    publicBaseUrlCache = (configured || "https://vennuzo.com").replace(/\/+$/, "");
  } catch (error) {
    publicBaseUrlCache = "https://vennuzo.com";
  }

  return publicBaseUrlCache;
}

function buildEventTicketReturnUrl(orderId, status) {
  const params = new URLSearchParams({
    type: "event_ticket",
    orderId,
    status,
  });
  return `${functionsBaseUrl()}/hubtelReturn?${params.toString()}`;
}

async function buildWebCheckoutConfirmationUrl(orderId, status) {
  const publicBaseUrl = await getPublicBaseUrl();
  return `${publicBaseUrl}/tickets/${encodeURIComponent(orderId)}` +
    `?status=${encodeURIComponent(status)}`;
}

async function resolvePartnerReferralForEvent(eventId, refValue) {
  const raw = safeString(refValue);
  if (!raw) {
    return {};
  }

  const directSnap = await db.collection("partner_event_links").doc(raw).get();
  let linkSnap = directSnap.exists ? directSnap : null;
  if (!linkSnap) {
    const querySnap = await db
      .collection("partner_event_links")
      .where("refCode", "==", raw)
      .limit(1)
      .get();
    linkSnap = querySnap.empty ? null : querySnap.docs[0];
  }
  if (!linkSnap || !linkSnap.exists) {
    return { partnerRefCode: raw };
  }

  const link = linkSnap.data() || {};
  if (safeString(link.eventId) !== safeString(eventId)) {
    return { partnerRefCode: raw };
  }
  return {
    partnerLinkId: linkSnap.id,
    partnerProfileId: safeString(link.partnerProfileId),
    partnerRefCode: safeString(link.refCode, raw),
  };
}

function buildWalletReturnUrl(status) {
  return `${STUDIO_RETURN_BASE}/payments?topup=${encodeURIComponent(status)}`;
}

function normalizeHubtelStatus(value) {
  const normalized = safeString(value).toLowerCase();
  if (!normalized) {
    return "pending";
  }
  if (normalized === "success" || normalized === "paid") {
    return "paid";
  }
  if (normalized === "cancelled" || normalized === "canceled") {
    return "cancelled";
  }
  if (normalized === "failed" || normalized === "declined") {
    return "failed";
  }
  return normalized;
}

function isPaidStatus(value) {
  return normalizeHubtelStatus(value) === "paid";
}

/** Maximum tickets a single user can purchase per order. */
const MAX_QUANTITY_PER_TIER = 50;
/** Maximum price (GHS) for a single ticket tier. */
const MAX_PRICE_PER_TIER_GHS = 10_000;
/** Maximum total order amount (GHS). */
const MAX_ORDER_TOTAL_GHS = 100_000;

function buildOrderSelections(selectedTiers) {
  const cleanedSelections = [];
  let totalAmount = 0;

  for (const rawSelection of Array.isArray(selectedTiers) ? selectedTiers : []) {
    const quantity = Number(rawSelection.quantity || 0);
    if (quantity <= 0) {
      continue;
    }
    if (!Number.isInteger(quantity) || quantity > MAX_QUANTITY_PER_TIER) {
      throw new HttpsError(
        "invalid-argument",
        `Quantity must be a whole number between 1 and ${MAX_QUANTITY_PER_TIER} per tier.`,
      );
    }
    const price = Number(rawSelection.price || rawSelection.amount || 0);
    if (!Number.isFinite(price) || price < 0 || price > MAX_PRICE_PER_TIER_GHS) {
      throw new HttpsError(
        "invalid-argument",
        `Ticket price must be between 0 and ${MAX_PRICE_PER_TIER_GHS} GHS.`,
      );
    }
    const tierId = safeString(rawSelection.tierId);
    if (!tierId) {
      continue;
    }
    cleanedSelections.push({
      tierId,
      name: safeString(rawSelection.name, "General"),
      price,
      quantity,
    });
    totalAmount += price * quantity;
  }

  if (totalAmount > MAX_ORDER_TOTAL_GHS) {
    throw new HttpsError(
      "invalid-argument",
      `Order total cannot exceed ${MAX_ORDER_TOTAL_GHS} GHS.`,
    );
  }

  return {
    selectedTiers: cleanedSelections,
    totalAmount,
  };
}

function paymentStatusForOrderStatus(statusValue) {
  const normalized = normalizeHubtelStatus(statusValue);
  if (normalized === "paid") {
    return "paid";
  }
  if (normalized === "cancelled") {
    return "cancelled";
  }
  if (normalized === "failed") {
    return "failed";
  }
  return normalized || "pending";
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = safeString(value);
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function buildEventSnapshotForFirestore(eventId, snapshotData, existingEventData = {}) {
  const ticketing = snapshotData.ticketing || existingEventData.ticketing || {};
  const distribution = snapshotData.distribution || existingEventData.distribution || {};
  const metrics = snapshotData.metrics || existingEventData.metrics || {};

  return {
    organizationId: safeString(
      snapshotData.organizationId,
      safeString(existingEventData.organizationId),
    ),
    createdBy: safeString(
      snapshotData.createdBy,
      safeString(existingEventData.createdBy),
    ),
    title: safeString(snapshotData.title, safeString(existingEventData.title, "Event")),
    description: safeString(
      snapshotData.description,
      safeString(existingEventData.description),
    ),
    venue: safeString(snapshotData.venue, safeString(existingEventData.venue)),
    city: safeString(snapshotData.city, safeString(existingEventData.city)),
    visibility: safeString(
      snapshotData.visibility,
      safeString(existingEventData.visibility, "public"),
    ),
    status: safeString(
      snapshotData.status,
      safeString(existingEventData.status, "published"),
    ),
    timezone: safeString(
      snapshotData.timezone,
      safeString(existingEventData.timezone, "Africa/Accra"),
    ),
    startAt: snapshotData.startAt || existingEventData.startAt || null,
    endAt: snapshotData.endAt || existingEventData.endAt || null,
    ticketing: {
      enabled: ticketing.enabled !== false,
      requireTicket: ticketing.requireTicket === true,
      currency: safeString(ticketing.currency, "GHS"),
      tiers: Array.isArray(ticketing.tiers) ? ticketing.tiers : [],
    },
    distribution: {
      allowSharing: distribution.allowSharing !== false,
      sendPushNotification: distribution.sendPushNotification !== false,
      sendSmsNotification: distribution.sendSmsNotification !== false,
    },
    lineup: snapshotData.lineup || existingEventData.lineup || {},
    mood: safeString(snapshotData.mood, safeString(existingEventData.mood)),
    tags: Array.isArray(snapshotData.tags)
      ? snapshotData.tags
      : Array.isArray(existingEventData.tags)
        ? existingEventData.tags
        : [],
    metrics: {
      likesCount: Number(metrics.likesCount || 0),
      rsvpCount: Number(metrics.rsvpCount || 0),
      ticketCount: Number(metrics.ticketCount || 0),
      grossRevenue: Number(metrics.grossRevenue || 0),
    },
    updatedAt: FieldValue.serverTimestamp(),
    eventId,
  };
}

async function initiateHubtelCheckout({
  totalAmount,
  description,
  clientReference,
  payeeName,
  payeeMobileNumber,
  payeeEmail,
  returnUrl: customReturnUrl,
  cancellationUrl: customCancellationUrl,
}) {
  const config = await getHubtelConfig();
  const defaultReturn = buildEventTicketReturnUrl(clientReference.replace(/^evt_/, ""), "success");
  const defaultCancel = buildEventTicketReturnUrl(clientReference.replace(/^evt_/, ""), "cancelled");
  const requestBody = {
    totalAmount,
    description,
    clientReference,
    callbackUrl: `${functionsBaseUrl()}/hubtelCallback`,
    returnUrl: customReturnUrl || defaultReturn,
    cancellationUrl: customCancellationUrl || defaultCancel,
    merchantAccountNumber: config.merchantAccount,
    payeeName,
    payeeMobileNumber: payeeMobileNumber || undefined,
    payeeEmail: payeeEmail || undefined,
  };

  const response = await fetch("https://payproxyapi.hubtel.com/items/initiate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: hubtelAuthHeader(config),
    },
    body: JSON.stringify(requestBody),
  });

  const result = await response.json().catch(() => ({}));
  const checkoutUrl = safeString(
    result?.data?.checkoutDirectUrl || result?.data?.checkoutUrl,
  );
  if (!response.ok || !checkoutUrl) {
    console.error("Hubtel event checkout initiate failed", response.status, result);
    throw new HttpsError(
      "internal",
      "Failed to create Hubtel checkout. Please try again.",
    );
  }

  return {
    checkoutUrl,
    checkoutId: safeString(result?.data?.checkoutId),
    checkoutDirectUrl: safeString(result?.data?.checkoutDirectUrl),
    checkoutHostedUrl: safeString(result?.data?.checkoutUrl),
  };
}

function hasAdminAccess(adminData) {
  if (!adminData || Object.keys(adminData).length === 0) return false;
  // Read-only admins do not get management/write access via this gate.
  return safeString(adminData.role).toLowerCase().replace(/[\s-]+/g, "_") !== "read_only";
}

async function notifyPaymentWebhookAlert(body) {
  try {
    await notifySuperAdmins({
      title: "Payment webhook alert",
      body,
      route: "/admin/settings",
      kind: "superadmin_payment_webhook_alert",
    });
  } catch (err) {
    console.error("notifyPaymentWebhookAlert failed", err);
  }
}

async function assertOrganizerCanRequestPayout(uid, organizationId) {
  if (!organizationId) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  if (organizationId === `org_${uid}`) {
    return;
  }
  const memberSnap = await db.collection("organization_members").doc(`${organizationId}_${uid}`).get();
  const member = memberSnap.exists ? memberSnap.data() || {} : {};
  if (memberSnap.exists && safeString(member.status).toLowerCase() === "active") {
    return;
  }
  throw new HttpsError("permission-denied", "You cannot request a payout for this organization.");
}

function isWithdrawableTicketOrder(order) {
  const status = safeString(order.paymentStatus || order.status).toLowerCase();
  const provider = safeString(order.paymentProvider).toLowerCase();
  // `settlementEligible` is a server-only flag set exclusively by the Hubtel
  // ticket callback / server-to-server status confirmation. Firestore rules
  // forbid clients from writing it, so forged "paid" order documents can never
  // count toward an organizer's withdrawable balance.
  return (
    order.settlementEligible === true &&
    status === "paid" &&
    provider === "hubtel" &&
    moneyAmount(order.totalAmount) > 0
  );
}

function isReservedPayoutStatus(status) {
  return ["pending", "processing", "success", "paid", "completed"].includes(
    safeString(status).toLowerCase(),
  );
}

async function calculateOrganizerPayoutSummary(organizationId, transaction = null) {
  const orderQuery = db
    .collection("event_ticket_orders")
    .where("organizationId", "==", organizationId);
  const payoutQuery = db
    .collection("payout_requests")
    .where("organizationId", "==", organizationId);
  const [ordersSnap, payoutsSnap] = transaction
    ? await Promise.all([transaction.get(orderQuery), transaction.get(payoutQuery)])
    : await Promise.all([orderQuery.get(), payoutQuery.get()]);

  const grossTicketSalesGhs = ordersSnap.docs.reduce((sum, docSnap) => {
    const order = docSnap.data() || {};
    return isWithdrawableTicketOrder(order) ? sum + moneyAmount(order.totalAmount) : sum;
  }, 0);
  const reservedPayoutsGhs = payoutsSnap.docs.reduce((sum, docSnap) => {
    const payout = docSnap.data() || {};
    return isReservedPayoutStatus(payout.status) ? sum + moneyAmount(payout.amountGhs) : sum;
  }, 0);
  const availableGhs = Math.max(
    0,
    moneyAmount(grossTicketSalesGhs - reservedPayoutsGhs),
  );
  const recentRequests = payoutsSnap.docs
    .map((docSnap) => {
      const data = docSnap.data() || {};
      const createdAt = data.createdAt && typeof data.createdAt.toDate === "function"
        ? data.createdAt.toDate().toISOString()
        : safeString(data.createdAt);
      const completedAt = data.completedAt && typeof data.completedAt.toDate === "function"
        ? data.completedAt.toDate().toISOString()
        : safeString(data.completedAt);
      return {
        id: docSnap.id,
        amountGhs: moneyAmount(data.amountGhs),
        status: safeString(data.status, "pending"),
        recipientName: safeString(data.recipientName),
        recipientMsisdn: safeString(data.recipientMsisdn),
        channel: safeString(data.channel),
        clientReference: safeString(data.clientReference),
        errorDescription: safeString(data.errorDescription),
        createdAt,
        completedAt,
      };
    })
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, 20);

  return {
    grossTicketSalesGhs: moneyAmount(grossTicketSalesGhs),
    reservedPayoutsGhs: moneyAmount(reservedPayoutsGhs),
    availableGhs,
    currency: "GHS",
    recentRequests,
  };
}

function isSuccessfulHubtelSendMoneyResponse(payload) {
  const responseCode = safeString(payload.ResponseCode || payload.responseCode).toLowerCase();
  const data = payload.Data || payload.data || {};
  const status = safeString(
    data.TransactionStatus ||
      data.transactionStatus ||
      data.Status ||
      data.status,
  ).toLowerCase();
  return responseCode === "0000" || status === "success" || status === "paid";
}

function isFailedHubtelSendMoneyStatus(value) {
  return ["failed", "reversed", "cancelled", "canceled", "declined"].includes(
    safeString(value).toLowerCase(),
  );
}

async function finalizeOrganizerPayout({ payoutDoc, success, payload, source }) {
  const data = payload.Data || payload.data || {};
  const patch = success
    ? {
        status: "success",
        completedAt: FieldValue.serverTimestamp(),
        hubtelTransactionId: safeString(data.TransactionId || data.transactionId),
        externalTransactionId: safeString(data.ExternalTransactionId || data.externalTransactionId || data.networkTransactionId),
        providerPayload: payload,
        updatedAt: FieldValue.serverTimestamp(),
      }
    : {
        status: "failed",
        completedAt: FieldValue.serverTimestamp(),
        errorCode: safeString(payload.ResponseCode || payload.responseCode || data.TransactionStatus || data.transactionStatus),
        errorDescription: safeString(data.Description || data.description || payload.Description || payload.message, "Hubtel Send Money failed."),
        providerPayload: payload,
        updatedAt: FieldValue.serverTimestamp(),
      };

  await payoutDoc.ref.set(patch, { merge: true });
  const payout = payoutDoc.data() || {};
  await notifySuperAdmins({
    title: success ? "Payout sent" : "Payout failed",
    body: success
      ? `Organizer payout of GHS ${moneyAmount(payout.amountGhs).toFixed(2)} was sent to ${safeString(payout.recipientMsisdn)}.`
      : `Organizer payout of GHS ${moneyAmount(payout.amountGhs).toFixed(2)} failed via ${source}.`,
    route: "/admin/settings",
    kind: success ? "superadmin_payout_sent" : "superadmin_payout_failed",
  }).catch(() => {});
}

/**
 * Confirms a payout's real outcome directly with Hubtel (server-to-server) and
 * finalises it. Used by both the status-check callable and the callback webhook
 * so neither relies on a (forgeable) callback body.
 * Returns "success" | "failed" | "processing".
 */
async function reconcilePayoutStatusFromProvider(payoutDoc) {
  const payout = payoutDoc.data() || {};
  const clientReference = safeString(payout.clientReference);
  if (!clientReference) {
    return safeString(payout.status, "processing");
  }
  const config = await getHubtelSendMoneyConfig();
  const resp = await fetch(
    `${HUBTEL_SEND_MONEY_STATUS_BASE}/api/merchants/${config.prepaidDepositId}` +
      `/transactions/status?clientReference=${encodeURIComponent(clientReference)}`,
    {
      method: "GET",
      headers: {
        Accept: "application/json",
        Authorization: hubtelAuthHeader(config),
      },
    },
  );
  const result = await resp.json().catch(() => ({}));
  const data = result.Data || result.data || {};
  const transactionStatus = safeString(
    data.TransactionStatus || data.transactionStatus || data.Status || data.status,
  ).toLowerCase();
  if (transactionStatus === "success" || transactionStatus === "paid") {
    await finalizeOrganizerPayout({ payoutDoc, success: true, payload: result, source: "provider_verified" });
    return "success";
  }
  if (isFailedHubtelSendMoneyStatus(transactionStatus)) {
    await finalizeOrganizerPayout({ payoutDoc, success: false, payload: result, source: "provider_verified" });
    return "failed";
  }
  return "processing";
}

async function authorizeOrderAccess(orderData, uid, action) {
  const buyerId = safeString(orderData.buyerId);
  if (!buyerId || buyerId === uid) {
    return;
  }

  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!hasAdminAccess(adminSnap.data())) {
    throw new HttpsError("permission-denied", `Not authorized to ${action} this order.`);
  }
}

function buildPlaceholderTicketId(orderId, tierId, sequence) {
  return `${orderId}_${tierId}_${sequence}`;
}

function randomQrToken() {
  return crypto.randomBytes(16).toString("hex");
}

function browserRedirectHtml({ orderId, status, deepLink }) {
  const statusLabel = status === "success" ? "Payment complete" : "Payment cancelled";
  const heading = status === "success"
    ? "Your Vennuzo payment is processing"
    : "Your Vennuzo payment was cancelled";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${statusLabel}</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(160deg, #111827 0%, #0f172a 55%, #f97316 140%);
      color: #fff7ed;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 24px;
    }
    .card {
      width: min(440px, 100%);
      background: rgba(15, 23, 42, 0.86);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 28px;
      padding: 28px;
      box-shadow: 0 24px 60px rgba(15, 23, 42, 0.45);
    }
    h1 {
      font-size: 28px;
      margin: 0 0 12px;
    }
    p {
      color: rgba(255, 247, 237, 0.84);
      line-height: 1.55;
      margin: 0 0 12px;
    }
    .button {
      display: inline-block;
      margin-top: 12px;
      background: #f97316;
      color: white;
      text-decoration: none;
      padding: 14px 18px;
      border-radius: 16px;
      font-weight: 700;
    }
    .meta {
      margin-top: 18px;
      padding: 12px 14px;
      border-radius: 16px;
      background: rgba(255, 255, 255, 0.08);
      color: rgba(255, 247, 237, 0.72);
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>${heading}</h1>
    <p>${status === "success"
      ? "Open Vennuzo to watch your ticket status. Tickets will appear automatically once Hubtel confirms the payment callback."
      : "Reopen Vennuzo to review the order or try the payment again."}</p>
    <a class="button" href="${escapeHtml(deepLink)}">Open Vennuzo</a>
    <div class="meta">Order ID: ${escapeHtml(orderId)}</div>
  </div>
  <script>
    setTimeout(function() { window.location = ${JSON.stringify(deepLink)}; }, 300);
  </script>
</body>
</html>`;
}

function buildBuyerPatch(orderData, callbackData) {
  const patch = {};
  const buyerPhone = firstNonEmpty(
    orderData.buyerPhone,
    normalizePhoneNumber(callbackData.CustomerPhoneNumber),
    normalizePhoneNumber(callbackData?.PaymentDetails?.MobileMoneyNumber),
  );
  const buyerName = firstNonEmpty(
    orderData.buyerName,
    callbackData.CustomerName,
    buyerPhone,
  );
  const buyerEmail = firstNonEmpty(
    orderData.buyerEmail,
    callbackData.CustomerEmail,
  );

  if (buyerPhone) {
    patch.buyerPhone = buyerPhone;
  }
  if (buyerName) {
    patch.buyerName = buyerName;
  }
  if (buyerEmail) {
    patch.buyerEmail = buyerEmail;
  }
  return patch;
}

async function handleEventTicketCallback(clientReference, data, response, config) {
  const orderId = safeString(clientReference).replace(/^evt_/, "");
  if (!orderId) {
    return response.status(400).json({ error: "Invalid client reference." });
  }

  const orderRef = db.collection("event_ticket_orders").doc(orderId);
  let orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    const fallbackSnap = await db
      .collection("event_ticket_orders")
      .where("paymentReference.clientReference", "==", clientReference)
      .limit(1)
      .get();
    if (!fallbackSnap.empty) {
      orderSnap = fallbackSnap.docs[0];
    }
  }

  if (!orderSnap.exists) {
    await notifyPaymentWebhookAlert(
      `Hubtel ticket callback: order not found for reference ${clientReference} (parsed orderId: ${orderId || "n/a"}).`,
    );
    return response.status(404).json({ error: "Order not found.", orderId });
  }

  const orderData = orderSnap.data() || {};
  let normalizedStatus = normalizeHubtelStatus(data.Status);

  // SECURITY: the callback body is forgeable. Before honouring any "paid"
  // outcome, re-confirm the transaction server-to-server with Hubtel. If we
  // cannot positively confirm payment, downgrade the status so the order is
  // NOT fulfilled and is NOT marked settlement-eligible.
  if (isPaidStatus(normalizedStatus)) {
    const confirmation = await confirmHubtelStatusFromProvider(clientReference, config);
    if (!confirmation.ok || !isPaidStatus(confirmation.status)) {
      await notifyPaymentWebhookAlert(
        `Hubtel ticket callback claimed paid but server-side confirmation failed ` +
          `for ${clientReference} (reason: ${safeString(confirmation.reason, "n/a")}, ` +
          `confirmedStatus: ${safeString(confirmation.status, "unknown")}).`,
      );
      normalizedStatus = confirmation.ok ? confirmation.status : "pending";
    }
  }

  const paymentStatus = paymentStatusForOrderStatus(normalizedStatus);
  const buyerPatch = buildBuyerPatch(orderData, data);

  if (!isPaidStatus(normalizedStatus)) {
    await orderSnap.ref.set(
      {
        ...buyerPatch,
        status: normalizedStatus === "cancelled" ? "cancelled" : "pending",
        paymentStatus,
        paymentProvider: "hubtel",
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || orderData.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return response.status(200).json({
      success: false,
      orderId: orderSnap.id,
      status: normalizedStatus,
    });
  }

  if (
    safeString(orderData.status).toLowerCase() === "paid" &&
    orderData.tickets &&
    Object.keys(orderData.tickets).length > 0
  ) {
    await orderSnap.ref.set(
      {
        ...buyerPatch,
        paymentStatus: "paid",
        paymentProvider: "hubtel",
        settlementEligible: true,
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || orderData.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    try {
      await syncOrderToGPlusTicketing(orderSnap.id, { source: "hubtel_callback_duplicate" });
    } catch (error) {
      logger.warn(
        `[gplus-ticket-bridge] Duplicate callback sync failed for order ${orderSnap.id}: ${safeString(error && error.message, "unknown error")}`,
      );
    }

    return response.status(200).json({
      success: true,
      orderId: orderSnap.id,
      status: "paid",
      alreadyProcessed: true,
    });
  }

  await db.runTransaction(async (transaction) => {
    const freshOrderSnap = await transaction.get(orderSnap.ref);
    const freshOrder = freshOrderSnap.data() || {};
    const eventId = safeString(freshOrder.eventId);
    if (!eventId) {
      throw new HttpsError("failed-precondition", "Order is missing eventId.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await transaction.get(eventRef);
    const eventData = eventSnap.exists
      ? eventSnap.data() || {}
      : (freshOrder.eventSnapshot || {});
    if (Object.keys(eventData).length === 0) {
      throw new HttpsError("not-found", "Event snapshot not found for ticket order.");
    }
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? [...ticketing.tiers] : [];
    const tierIndex = new Map();
    tiers.forEach((tier, index) => {
      tierIndex.set(safeString(tier.tierId), index);
    });

    const selections = Array.isArray(freshOrder.selectedTiers)
      ? freshOrder.selectedTiers
      : [];
    const now = FieldValue.serverTimestamp();
    const issuedAtIso = new Date().toISOString();
    const buyerName = firstNonEmpty(
      buyerPatch.buyerName,
      freshOrder.buyerName,
      "Vennuzo attendee",
    );
    const issuedTickets = {};
    const lookupWrites = [];
    let ticketCount = 0;

    for (const selection of selections) {
      const tierId = safeString(selection.tierId);
      const quantity = Number(selection.quantity || 0);
      if (!tierId || quantity <= 0) {
        continue;
      }

      const tierPosition = tierIndex.get(tierId);
      if (tierPosition == null) {
        throw new HttpsError("failed-precondition", `Ticket tier ${tierId} no longer exists.`);
      }

      const tier = { ...tiers[tierPosition] };
      const sold = Number(tier.sold || 0);
      const maxQuantity = Number(tier.maxQuantity || 0);
      if (maxQuantity > 0 && sold + quantity > maxQuantity) {
        throw new HttpsError(
          "failed-precondition",
          `${safeString(tier.name, "Ticket")} no longer has enough inventory.`,
        );
      }
      tier.sold = sold + quantity;
      tiers[tierPosition] = tier;

      for (let index = 0; index < quantity; index += 1) {
        ticketCount += 1;
        const ticketId = buildPlaceholderTicketId(orderSnap.id, tierId, ticketCount);
        const qrToken = randomQrToken();
        issuedTickets[ticketId] = {
          ticketId,
          orderId: orderSnap.id,
          eventId,
          occurrenceId: safeString(freshOrder.occurrenceId, `${eventId}_primary`),
          tierId,
          tierName: safeString(selection.name, safeString(tier.name, "General")),
          qrToken,
          status: "issued",
          attendeeName: buyerName,
          price: Number(selection.price || 0),
          issuedAt: now,
          issuedAtIso,
          updatedAt: now,
        };
        lookupWrites.push({
          qrToken,
          payload: {
            qrToken,
            orderId: orderSnap.id,
            ticketId,
            eventId,
            occurrenceId: safeString(freshOrder.occurrenceId, `${eventId}_primary`),
            organizationId: safeString(
              freshOrder.organizationId,
              eventData.organizationId,
            ),
            buyerId: safeString(freshOrder.buyerId),
            attendeeName: buyerName,
            tierId,
            tierName: safeString(selection.name, safeString(tier.name, "General")),
            ticketStatus: "issued",
            paymentStatus: "paid",
            createdAt: now,
            updatedAt: now,
          },
        });
      }
    }

    transaction.set(
      orderSnap.ref,
      {
        ...buyerPatch,
        status: "paid",
        paymentStatus: "paid",
        paymentProvider: "hubtel",
        settlementEligible: true,
        ticketCount,
        tickets: issuedTickets,
        paidAt: now,
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || freshOrder.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: now,
        },
        updatedAt: now,
      },
      { merge: true },
    );

    transaction.set(
      eventRef,
      {
        ...buildEventSnapshotForFirestore(
          eventId,
          freshOrder.eventSnapshot || eventData,
          eventData,
        ),
        ticketing: {
          ...ticketing,
          tiers,
        },
        metrics: {
          ...(eventData.metrics || {}),
          ticketCount: FieldValue.increment(ticketCount),
          grossRevenue: FieldValue.increment(Number(freshOrder.totalAmount || 0)),
        },
        updatedAt: now,
      },
      { merge: true },
    );

    for (const lookup of lookupWrites) {
      transaction.set(
        db.collection("event_ticket_lookups").doc(lookup.qrToken),
        lookup.payload,
        { merge: true },
      );
    }
  });

  try {
    await syncOrderToGPlusTicketing(orderSnap.id, { source: "hubtel_callback" });
  } catch (error) {
    logger.warn(
      `[gplus-ticket-bridge] Sync failed for order ${orderSnap.id}: ${safeString(error && error.message, "unknown error")}`,
    );
  }

  return response.status(200).json({
    success: true,
    orderId: orderSnap.id,
    status: "paid",
  });
}

exports.createEventTicketPaymentForOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const orderId = safeString(request.data && request.data.orderId);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in before paying for tickets.");
    }
    // Rate limit: max 10 payment initiations per user per 5 minutes
    await checkRateLimit(db, uid, "createEventTicketPayment", { maxCalls: 10, windowSeconds: 300 });
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }

    const orderRef = db.collection("event_ticket_orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Event ticket order not found.");
    }

    const orderData = orderSnap.data() || {};
    await authorizeOrderAccess(orderData, uid, "pay for");

    const eventId = safeString(orderData.eventId);
    if (!eventId) {
      throw new HttpsError("failed-precondition", "Order is missing eventId.");
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    const eventData = eventSnap.exists
      ? eventSnap.data() || {}
      : (orderData.eventSnapshot || {});
    if (Object.keys(eventData).length === 0) {
      throw new HttpsError("not-found", "Event snapshot not found for this order.");
    }
    const { selectedTiers, totalAmount } = buildOrderSelections(
      orderData.selectedTiers,
    );
    const effectiveAmount = Number(orderData.totalAmount || totalAmount);
    if (!effectiveAmount || effectiveAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Total ticket amount must be greater than zero for payment.",
      );
    }

    const buyerName = firstNonEmpty(orderData.buyerName, "Guest");
    const buyerPhone = normalizePhoneNumber(orderData.buyerPhone);
    const buyerEmail = safeString(orderData.buyerEmail);
    const eventTitle = safeString(eventData.title, safeString(orderData.eventTitle, "Event"));
    const clientReference = `evt_${orderId}`;
    const checkout = await initiateHubtelCheckout({
      totalAmount: effectiveAmount,
      description: `Tickets: ${eventTitle}`,
      clientReference,
      payeeName: buyerName,
      payeeMobileNumber: buyerPhone,
      payeeEmail: buyerEmail,
    });

    await orderRef.set(
      {
        selectedTiers,
        totalAmount: effectiveAmount,
        paymentProvider: "hubtel",
        paymentStatus: "pending",
        paymentReference: {
          checkoutId: checkout.checkoutId,
          clientReference,
          checkoutUrl: checkout.checkoutHostedUrl || checkout.checkoutUrl,
          checkoutDirectUrl: checkout.checkoutDirectUrl || null,
          initiatedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      orderId,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
      clientReference,
    };
  },
);

exports.checkHubtelTicketStatus = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const orderId = safeString(request.data && request.data.orderId);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in before checking ticket status.");
    }
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }

    const orderRef = db.collection("event_ticket_orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Event ticket order not found.");
    }

    const orderData = orderSnap.data() || {};
    await authorizeOrderAccess(orderData, uid, "check");

    const clientReference = safeString(orderData?.paymentReference?.clientReference);
    if (!clientReference) {
      throw new HttpsError(
        "failed-precondition",
        "Payment has not been initiated for this order yet.",
      );
    }

    const config = await getHubtelConfig();
    const url =
      `https://api-txnstatus.hubtel.com/transactions/${config.merchantAccount}` +
      `/status?clientReference=${encodeURIComponent(clientReference)}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: hubtelAuthHeader(config),
      },
    });

    if (response.status === 403) {
      throw new HttpsError(
        "permission-denied",
        "Server IP is not whitelisted with Hubtel.",
      );
    }

    const result = await response.json().catch(() => ({}));
    if (result.responseCode !== "0000" || !result.data) {
      return {
        success: false,
        status: "unknown",
        raw: result,
      };
    }

    const normalizedStatus = normalizeHubtelStatus(result.data.status);
    await orderRef.set(
      {
        status: normalizedStatus === "paid"
          ? "paid"
          : normalizedStatus === "cancelled"
            ? "cancelled"
            : safeString(orderData.status, "pending"),
        paymentStatus: paymentStatusForOrderStatus(normalizedStatus),
        paymentProvider: "hubtel",
        // Server-to-server Hubtel confirmation: safe to mark settlement-eligible.
        ...(normalizedStatus === "paid" ? { settlementEligible: true } : {}),
        paymentDetails: {
          transactionId: safeString(result.data.transactionId),
          externalTransactionId: safeString(result.data.externalTransactionId),
          paymentMethod: safeString(result.data.paymentMethod),
          amount: Number(result.data.amount || orderData.totalAmount || 0),
          charges: Number(result.data.charges || 0),
          amountAfterCharges: Number(result.data.amountAfterCharges || 0),
          currencyCode: safeString(result.data.currencyCode),
          statusCheckedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      status: normalizedStatus,
      isPaid: normalizedStatus === "paid",
      details: result.data,
    };
  },
);

async function ensureWallet(organizationId, ownerId) {
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const snap = await walletRef.get();
  if (snap.exists) {
    return snap.ref;
  }
  await walletRef.set({
    organizationId,
    ownerId,
    availableBalance: 0,
    heldBalance: 0,
    currency: "GHS",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return walletRef;
}

async function handleWalletTopUpCallback(clientReference, data, response, config) {
  let normalizedStatus = normalizeHubtelStatus(data.Status);
  const txnRef = db.collection("wallet_transactions").doc(clientReference);
  const txnSnap = await txnRef.get();

  if (!txnSnap.exists) {
    await notifyPaymentWebhookAlert(
      `Hubtel wallet callback: transaction not found for ${clientReference}.`,
    );
    return response.status(404).json({
      error: "Wallet transaction not found.",
      clientReference,
    });
  }

  const txnData = txnSnap.data() || {};
  if (txnData.status === "completed") {
    return response.status(200).json({
      success: true,
      walletId: txnData.walletId,
      status: "completed",
      alreadyProcessed: true,
    });
  }

  // SECURITY: re-confirm "paid" with Hubtel before crediting the wallet.
  if (isPaidStatus(normalizedStatus)) {
    const confirmation = await confirmHubtelStatusFromProvider(clientReference, config);
    if (!confirmation.ok || !isPaidStatus(confirmation.status)) {
      await notifyPaymentWebhookAlert(
        `Hubtel wallet callback claimed paid but server-side confirmation failed ` +
          `for ${clientReference} (reason: ${safeString(confirmation.reason, "n/a")}).`,
      );
      normalizedStatus = confirmation.ok ? confirmation.status : "pending";
    }
  }

  if (!isPaidStatus(normalizedStatus)) {
    // Keep unconfirmed transactions "pending" (a later confirmation can still
    // complete them); only cancelled/failed states are terminal.
    const terminalStatus =
      normalizedStatus === "cancelled"
        ? "cancelled"
        : normalizedStatus === "pending"
          ? "pending"
          : "failed";
    await txnRef.set(
      {
        status: terminalStatus,
        hubtelResponse: data,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return response.status(200).json({
      success: false,
      status: normalizedStatus,
    });
  }

  const walletId = safeString(txnData.walletId);
  const amount = Number(txnData.amount || data.Amount || 0);
  if (!walletId || amount <= 0) {
    await notifyPaymentWebhookAlert(
      `Hubtel wallet callback: invalid paid transaction data for ${clientReference} (walletId/amount).`,
    );
    return response.status(400).json({ error: "Invalid wallet transaction." });
  }

  const walletRef = db.collection("advertiser_wallets").doc(walletId);
  await db.runTransaction(async (transaction) => {
    const freshTxn = await transaction.get(txnRef);
    if (freshTxn.data() && freshTxn.data().status === "completed") {
      return;
    }
    const walletSnap = await transaction.get(walletRef);
    if (!walletSnap.exists) {
      throw new Error("Wallet not found.");
    }
    const current = walletSnap.data().availableBalance || 0;
    transaction.update(walletRef, {
      availableBalance: current + amount,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(txnRef, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      hubtelResponse: data,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return response.status(200).json({
    success: true,
    walletId,
    status: "paid",
    amount,
  });
}

exports.initiateWalletTopUp = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to fund your wallet.");
    }

    const uid = request.auth.uid;
    const organizationId = safeString(request.data && request.data.organizationId);
    const amount = Number(request.data && request.data.amount);
    const payeeName = safeString(request.data && request.data.payeeName);
    const payeeMobileNumber = normalizePhoneNumber(request.data && request.data.payeeMobileNumber);
    const payeeEmail = safeString(request.data && request.data.payeeEmail);

    const effectiveOrgId = organizationId || `org_${uid}`;
    if (effectiveOrgId !== `org_${uid}`) {
      throw new HttpsError(
        "permission-denied",
        "You can only fund the wallet for your own organization.",
      );
    }
    // Rate limit: max 5 top-up initiations per user per 10 minutes
    await checkRateLimit(db, uid, "initiateWalletTopUp", { maxCalls: 5, windowSeconds: 600 });
    if (!Number.isFinite(amount) || amount < 1) {
      throw new HttpsError("invalid-argument", "Amount must be at least 1 GHS.");
    }
    if (!payeeName || !payeeMobileNumber) {
      throw new HttpsError(
        "invalid-argument",
        "payeeName and payeeMobileNumber are required.",
      );
    }

    await ensureWallet(effectiveOrgId, uid);
    const clientReference = `wallet_${effectiveOrgId}_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    const checkout = await initiateHubtelCheckout({
      totalAmount: Math.round(amount * 100) / 100,
      description: "Vennuzo campaign wallet top-up",
      clientReference,
      payeeName,
      payeeMobileNumber: payeeMobileNumber || undefined,
      payeeEmail: payeeEmail || undefined,
      returnUrl: buildWalletReturnUrl("success"),
      cancellationUrl: buildWalletReturnUrl("cancelled"),
    });

    await db.collection("wallet_transactions").doc(clientReference).set({
      walletId: effectiveOrgId,
      type: "top_up",
      amount,
      clientReference,
      status: "pending",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
      clientReference,
      returnUrl: buildWalletReturnUrl("success"),
      cancellationUrl: buildWalletReturnUrl("cancelled"),
    };
  },
);

exports.getWalletBalance = onCall(
  {
    region: REGION,
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to view wallet.");
    }

    const uid = request.auth.uid;
    const organizationId = safeString(request.data && request.data.organizationId) || `org_${uid}`;
    if (organizationId !== `org_${uid}`) {
      throw new HttpsError(
        "permission-denied",
        "You can only view your own organization wallet.",
      );
    }

    const walletSnap = await db.collection("advertiser_wallets").doc(organizationId).get();
    if (!walletSnap.exists) {
      await ensureWallet(organizationId, uid);
      return {
        availableBalance: 0,
        heldBalance: 0,
        currency: "GHS",
      };
    }

    const data = walletSnap.data() || {};
    return {
      availableBalance: Number(data.availableBalance ?? 0),
      heldBalance: Number(data.heldBalance ?? 0),
      currency: safeString(data.currency, "GHS"),
    };
  },
);

exports.getOrganizerPayoutSummary = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to view payout balance.");
    }
    const uid = request.auth.uid;
    const organizationId = safeString(request.data && request.data.organizationId);
    await assertOrganizerCanRequestPayout(uid, organizationId);
    return calculateOrganizerPayoutSummary(organizationId);
  },
);

exports.submitOrganizerPayoutRequest = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to request a payout.");
    }
    const uid = request.auth.uid;
    const organizationId = safeString(request.data && request.data.organizationId);
    const amountGhs = moneyAmount(request.data && request.data.amountGhs);
    const notes = safeString(request.data && request.data.notes);
    const recipientName = safeString(request.data && request.data.recipientName, "Vennuzo organizer");
    const recipientMsisdn = normalizeMsisdn(request.data && request.data.recipientMsisdn);
    const channel = normalizePayoutChannel(request.data && request.data.channel, recipientMsisdn);
    if (!organizationId) {
      throw new HttpsError("invalid-argument", "organizationId is required.");
    }
    if (!Number.isFinite(amountGhs) || amountGhs <= 0) {
      throw new HttpsError("invalid-argument", "amountGhs must be a positive number.");
    }
    if (!recipientMsisdn) {
      throw new HttpsError("invalid-argument", "Enter a valid mobile money number.");
    }
    if (!PAYOUT_CHANNELS.has(channel)) {
      throw new HttpsError("invalid-argument", "Choose MTN, Telecel/Vodafone, or AirtelTigo Money.");
    }
    await assertOrganizerCanRequestPayout(uid, organizationId);
    // Rate limit: max 3 payout requests per user per hour
    await checkRateLimit(db, uid, "submitPayoutRequest", { maxCalls: 3, windowSeconds: 3600 });
    const config = await getHubtelSendMoneyConfig();
    const requestRef = db.collection("payout_requests").doc();
    const clientReference = `${PAYOUT_CLIENT_REFERENCE_PREFIX}_${requestRef.id}`.slice(0, 36);
    let availableBefore = 0;

    await db.runTransaction(async (transaction) => {
      const summary = await calculateOrganizerPayoutSummary(organizationId, transaction);
      availableBefore = summary.availableGhs;
      if (availableBefore < amountGhs) {
        throw new HttpsError(
          "failed-precondition",
          `Insufficient ticket-sales balance. Available ${availableBefore.toFixed(2)} GHS.`,
        );
      }
      transaction.set(requestRef, {
        organizationId,
        amountGhs,
        notes: notes.slice(0, 2000),
        requestedBy: uid,
        status: "pending",
        payoutMethod: "mobile-money",
        recipientName,
        recipientMsisdn,
        channel,
        clientReference,
        provider: "hubtel_send_money",
        availableBeforeGhs: availableBefore,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    const body = {
      RecipientName: recipientName,
      RecipientMsisdn: recipientMsisdn,
      Channel: channel,
      Amount: amountGhs,
      PrimaryCallbackURL: `${functionsBaseUrl()}/hubtelSendMoneyCallback`,
      Description: `Vennuzo payout ${clientReference}`,
      ClientReference: clientReference,
    };
    const resp = await fetch(
      `${HUBTEL_SEND_MONEY_BASE}/api/merchants/${config.prepaidDepositId}/send/mobilemoney`,
      {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          Authorization: hubtelAuthHeader(config),
        },
        body: JSON.stringify(body),
      },
    );
    const result = await resp.json().catch(() => ({}));
    const responseCode = safeString(result.ResponseCode || result.responseCode);
    if (responseCode === "0001" || responseCode === "0000") {
      const resultData = result.Data || result.data || {};
      await requestRef.set({
        status: "processing",
        hubtelTransactionId: safeString(resultData.TransactionId || resultData.transactionId) || null,
        providerPayload: result,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return {
        success: true,
        requestId: requestRef.id,
        clientReference,
        status: "processing",
        availableBeforeGhs: availableBefore,
      };
    }

    await requestRef.set({
      status: "failed",
      completedAt: FieldValue.serverTimestamp(),
      errorCode: responseCode,
      errorDescription: safeString(
        (result.Data || result.data || {}).Description ||
          result.Description ||
          result.ResponseMessage ||
          result.message,
        "Hubtel Send Money failed.",
      ),
      providerPayload: result,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    throw new HttpsError("internal", safeString(
      (result.Data || result.data || {}).Description ||
        result.Description ||
        result.ResponseMessage ||
        result.message,
      "Hubtel Send Money failed.",
    ));
  },
);

exports.checkOrganizerPayoutStatus = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to check payout status.");
    }
    const clientReference = safeString(request.data && request.data.clientReference);
    if (!clientReference.startsWith(`${PAYOUT_CLIENT_REFERENCE_PREFIX}_`)) {
      throw new HttpsError("invalid-argument", "Invalid payout reference.");
    }
    const snap = await db
      .collection("payout_requests")
      .where("clientReference", "==", clientReference)
      .limit(1)
      .get();
    if (snap.empty) throw new HttpsError("not-found", "Payout request not found.");
    const payoutDoc = snap.docs[0];
    const payout = payoutDoc.data() || {};
    await assertOrganizerCanRequestPayout(request.auth.uid, safeString(payout.organizationId));
    if (safeString(payout.status) !== "processing" && safeString(payout.status) !== "pending") {
      return {
        status: safeString(payout.status),
        requestId: payoutDoc.id,
        alreadyFinalized: true,
      };
    }

    const resolvedStatus = await reconcilePayoutStatusFromProvider(payoutDoc);
    return { status: resolvedStatus, requestId: payoutDoc.id, fromStatusCheck: true };
  },
);

exports.hubtelSendMoneyCallback = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      return response.status(405).json({ error: "Method not allowed." });
    }
    const payload = request.body || {};
    const data = payload.Data || payload.data || {};
    const clientReference = safeString(data.ClientReference || data.clientReference);
    if (!clientReference.startsWith(`${PAYOUT_CLIENT_REFERENCE_PREFIX}_`)) {
      return response.status(200).json({ success: true, ignored: true });
    }
    const snap = await db
      .collection("payout_requests")
      .where("clientReference", "==", clientReference)
      .limit(1)
      .get();
    if (snap.empty) {
      return response.status(200).json({ success: true, processed: false, reason: "payout_not_found" });
    }
    const payoutDoc = snap.docs[0];
    const payout = payoutDoc.data() || {};
    if (!["pending", "processing"].includes(safeString(payout.status))) {
      return response.status(200).json({ success: true, processed: false, reason: "already_finalized" });
    }
    // The Send Money callback is unauthenticated and its body is forgeable, so
    // we do NOT trust it. Independently confirm the real transfer outcome with a
    // server-to-server status check before finalising the payout.
    const resolvedStatus = await reconcilePayoutStatusFromProvider(payoutDoc);
    return response.status(200).json({
      success: true,
      processed: resolvedStatus !== "processing",
      status: resolvedStatus,
    });
  },
);

exports.createWebEventTicketOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    // Unauthenticated public web checkout — throttle by IP to prevent
    // unbounded pending-order creation and Hubtel initiate abuse.
    const ipKey = safeString(
      (request.rawRequest &&
        (request.rawRequest.ip ||
          request.rawRequest.headers["x-forwarded-for"] ||
          request.rawRequest.headers["fastly-client-ip"])) ||
        "unknown",
    );
    await checkRateLimit(db, `ip:${ipKey}`, "createWebEventTicketOrder", {
      maxCalls: 20,
      windowSeconds: 300,
    });

    const eventId = safeString(request.data && request.data.eventId);
    const selections = request.data && request.data.selections;
    const buyerName = safeString(request.data && request.data.buyerName);
    const buyerPhone = normalizePhoneNumber(request.data && request.data.buyerPhone);
    const buyerEmail = safeString(request.data && request.data.buyerEmail);
    const partnerRef = safeString(
      request.data &&
        (request.data.partnerRef || request.data.ref || request.data.partnerReferralCode),
    );

    if (!eventId) {
      throw new HttpsError("invalid-argument", "eventId is required.");
    }
    if (!selections || typeof selections !== "object") {
      throw new HttpsError("invalid-argument", "selections is required.");
    }
    if (!buyerName || !buyerPhone || !buyerEmail) {
      throw new HttpsError(
        "invalid-argument",
        "buyerName, buyerPhone, and buyerEmail are required.",
      );
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }

    const eventData = eventSnap.data() || {};
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? ticketing.tiers : [];
    if (!ticketing.enabled || tiers.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Ticketing is not enabled for this event.",
      );
    }

    const tierById = new Map();
    for (const tier of tiers) {
      tierById.set(safeString(tier.tierId), tier);
    }

    const selectedTiers = [];
    let totalAmount = 0;
    for (const [tierId, rawQuantity] of Object.entries(selections)) {
      const quantity = Number(rawQuantity || 0);
      if (quantity <= 0) {
        continue;
      }
      if (!Number.isInteger(quantity) || quantity > MAX_QUANTITY_PER_TIER) {
        throw new HttpsError(
          "invalid-argument",
          `Quantity must be a whole number between 1 and ${MAX_QUANTITY_PER_TIER} per tier.`,
        );
      }
      const tier = tierById.get(safeString(tierId));
      if (!tier) {
        continue;
      }
      const price = Number(tier.price || 0);
      if (price <= 0) {
        continue;
      }
      selectedTiers.push({
        tierId: safeString(tier.tierId),
        name: safeString(tier.name, "General"),
        price,
        quantity,
      });
      totalAmount += price * quantity;
    }

    if (selectedTiers.length === 0 || totalAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Select at least one paid ticket tier.",
      );
    }
    if (totalAmount > MAX_ORDER_TOTAL_GHS) {
      throw new HttpsError(
        "invalid-argument",
        `Order total cannot exceed ${MAX_ORDER_TOTAL_GHS} GHS.`,
      );
    }

    const referral = await resolvePartnerReferralForEvent(eventId, partnerRef);
    const orderRef = db.collection("event_ticket_orders").doc();
    await orderRef.set({
      eventId,
      occurrenceId: `${eventId}_primary`,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      buyerId: null,
      buyerName,
      buyerPhone,
      buyerEmail,
      selectedTiers,
      totalAmount,
      currency: safeString(ticketing.currency, "GHS"),
      status: "pending",
      paymentStatus: "initiated",
      source: "web",
      eventSnapshot: buildEventSnapshotForFirestore(eventId, eventData),
      ...referral,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const checkout = await initiateHubtelCheckout({
      totalAmount,
      description: `Tickets: ${safeString(eventData.title, "Event")}`,
      clientReference: `evt_${orderRef.id}`,
      payeeName: buyerName,
      payeeMobileNumber: buyerPhone,
      payeeEmail: buyerEmail,
    });

    await orderRef.set(
      {
        paymentProvider: "hubtel",
        paymentStatus: "pending",
        paymentReference: {
          checkoutId: checkout.checkoutId,
          clientReference: `evt_${orderRef.id}`,
          checkoutUrl: checkout.checkoutHostedUrl || checkout.checkoutUrl,
          checkoutDirectUrl: checkout.checkoutDirectUrl || null,
          initiatedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      orderId: orderRef.id,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
    };
  },
);

exports.hubtelCallback = onRequest(
  {
    // Server-to-server webhook — no browser origin, so CORS is unnecessary
    // attack surface.
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request, response) => {
    try {
      if (request.method !== "POST") {
        return response.status(405).json({ error: "Method not allowed." });
      }

      const payload = request.body || {};
      const data = payload.Data || {};
      const clientReference = safeString(data.ClientReference);
      if (!clientReference) {
        return response.status(400).json({ error: "Invalid callback payload." });
      }

      const config = await getHubtelConfig();
      // Optional callback signature verification (matches the Gplus reference):
      // when app_config/hubtel.callbackSecret is set we verify constant-time and
      // reject mismatches; when it is absent we log and proceed so payment
      // fulfilment keeps working. Set callbackSecret (here + in the Hubtel
      // dashboard) to enable enforcement.
      if (config.callbackSecret) {
        if (!verifyHubtelSignature(config.callbackSecret, payload, request.headers["x-hubtel-signature"])) {
          await notifyPaymentWebhookAlert("Hubtel callback rejected: invalid or missing x-hubtel-signature.");
          return response.status(401).json({ error: "Invalid callback signature." });
        }
      } else {
        logger.warn(
          "[hubtelCallback] callbackSecret not configured — signature not verified. " +
            "Set app_config/hubtel.callbackSecret to enable verification.",
        );
      }

      if (clientReference.startsWith("evt_")) {
        return handleEventTicketCallback(clientReference, data, response, config);
      }
      if (clientReference.startsWith("wallet_")) {
        return handleWalletTopUpCallback(clientReference, data, response, config);
      }

      return response.status(400).json({
        error: "Unsupported Hubtel client reference.",
        clientReference,
      });
    } catch (error) {
      console.error("hubtelCallback error", error);
      await notifyPaymentWebhookAlert(
        `Hubtel callback error: ${safeString(error && error.message, "unknown error")}`,
      );
      // Do not leak internal error details to the caller.
      return response.status(500).json({ error: "Hubtel callback failed." });
    }
  },
);

exports.hubtelReturn = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request, response) => {
    const type = safeString(request.query.type, "event_ticket");
    const orderId = safeString(request.query.orderId);
    const status = safeString(request.query.status, "success");

    if (type !== "event_ticket" || !orderId) {
      return response.status(400).send("Invalid return payload.");
    }

    // For web orders, redirect the browser straight to the web confirmation page
    // instead of showing the app deep-link HTML.
    try {
      const orderSnap = await db.collection("event_ticket_orders").doc(orderId).get();
      if (orderSnap.exists && orderSnap.data().source === "web") {
        const webUrl = await buildWebCheckoutConfirmationUrl(orderId, status);
        return response.redirect(302, webUrl);
      }
    } catch (_err) {
      // Fall through to the default app deep-link page on any error.
    }

    const deepLink =
      `${VENNUZO_SCHEME}://payment-status?orderId=${encodeURIComponent(orderId)}` +
      `&status=${encodeURIComponent(status)}`;

    return response
      .status(200)
      .set("Content-Type", "text/html; charset=utf-8")
      .send(browserRedirectHtml({ orderId, status, deepLink }));
  },
);

// Test-only exports of pure helpers so unit tests exercise the REAL code (not a
// copy). This block is a no-op at deploy/runtime — Firebase's function discovery
// and the deployed runtime never run with NODE_ENV==="test", so no extra exports
// are registered there. jest sets NODE_ENV="test".
if (process.env.NODE_ENV === "test") {
  module.exports.buildOrderSelections = buildOrderSelections;
  module.exports.isWithdrawableTicketOrder = isWithdrawableTicketOrder;
  module.exports.verifyHubtelSignature = verifyHubtelSignature;
  module.exports.confirmHubtelStatusFromProvider = confirmHubtelStatusFromProvider;
  module.exports.escapeHtml = escapeHtml;
  module.exports.safeString = safeString;
}
