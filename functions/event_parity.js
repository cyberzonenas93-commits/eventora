"use strict";

const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");
const { queuePushNotification } = require("./event_notifications");
const { syncOrderToGPlusTicketing } = require("./gplus_ticket_bridge");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

/** Constant-time verification of a Hubtel HMAC-SHA256 callback signature. */
function verifyHubtelSignature(secret, payload, headerSignature) {
  const incoming = safeString(headerSignature);
  if (!incoming) return false;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(JSON.stringify(payload))
    .digest("hex");
  const incomingBuf = Buffer.from(incoming);
  const expectedBuf = Buffer.from(expected);
  if (incomingBuf.length !== expectedBuf.length) return false;
  return crypto.timingSafeEqual(incomingBuf, expectedBuf);
}

function maskContactPhone(value) {
  const digits = String(value || "").replace(/\D/g, "");
  if (!digits) return "";
  return digits.length <= 3 ? "***" : `***${digits.slice(-3)}`;
}

function maskContactEmail(value) {
  const email = String(value || "").trim();
  const at = email.indexOf("@");
  if (at <= 0) return email ? "***" : "";
  const name = email.slice(0, at);
  const domain = email.slice(at + 1);
  const shownName = name.length <= 1 ? name : `${name[0]}***`;
  return `${shownName}@${domain}`;
}

const REGION = "us-central1";
const TIME_ZONE = "Africa/Accra";
const MAX_PUBLIC_ROWS = 500;
let publicBaseUrlCache = null;
const EVENT_TEAM_PERMISSIONS = new Set([
  "scanTickets",
  "manualVerifyTickets",
  "admitTickets",
  "collectCash",
  "issueTickets",
  "viewOrders",
  "viewAnalytics",
]);

const PROMO_MECHANIC_TYPES = new Set([
  "raffle",
  "leaderboard",
  "referral_campaign",
  "challenge",
  "flash_offer",
  "birthday_club",
  "check_in_challenge",
  "promo_code",
]);

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

async function eventManagerPushTargets(eventData) {
  const createdBy = safeString(eventData && eventData.createdBy);
  if (!createdBy) return [];
  const userSnap = await db.collection("users").doc(createdBy).get();
  if (!userSnap.exists) return [];
  const user = userSnap.data() || {};
  const prefs = user.notificationPrefs || {};
  if (prefs.pushEnabled === false || !safeString(user.fcmToken)) return [];
  return [createdBy];
}

async function notifyEventManagerPush(eventData, { kind, title, body, eventId, route }) {
  if (typeof queuePushNotification !== "function") return null;
  const targets = await eventManagerPushTargets(eventData);
  if (targets.length === 0) return null;
  return queuePushNotification({
    kind,
    targets,
    payload: {
      title,
      body,
      eventId,
      route: route || `/studio/tables?eventId=${eventId}`,
    },
    eventId,
  });
}

function normalizeEmail(value) {
  return safeString(value).toLowerCase();
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) return "";
  if (digits.startsWith("+233")) return digits;
  if (digits.startsWith("233") && digits.length === 12) return `+${digits}`;
  if (digits.startsWith("0") && digits.length === 10) return `+233${digits.slice(1)}`;
  if (digits.length === 9) return `+233${digits}`;
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function hashValue(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 32);
}

function randomQrToken() {
  return crypto.randomBytes(16).toString("hex");
}

function buildTicketId(orderId, tierId, index) {
  return `tkt_${hashValue(`${orderId}:${tierId}:${index}:${Date.now()}`)}`;
}

function projectId() {
  return safeString(process.env.GCLOUD_PROJECT || admin.app().options.projectId);
}

function functionsBaseUrl() {
  const pid = projectId();
  if (!pid) {
    throw new Error("GCLOUD_PROJECT is not available.");
  }
  return `https://${REGION}-${pid}.cloudfunctions.net`;
}

async function getPublicBaseUrl() {
  if (publicBaseUrlCache) return publicBaseUrlCache;

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
    const snap = await db.collection("app_config").doc("site").get();
    const data = snap.exists ? snap.data() || {} : {};
    const configured = safeString(
      data.publicUrl || data.publicBaseUrl || data.vennuzoPublicUrl || data.webUrl,
    );
    publicBaseUrlCache = (configured || "https://vennuzo.com").replace(/\/+$/, "");
  } catch (error) {
    publicBaseUrlCache = "https://vennuzo.com";
  }
  return publicBaseUrlCache;
}

async function buildEventUrl(eventId, params = {}) {
  const base = await getPublicBaseUrl();
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    const normalized = safeString(value);
    if (normalized) search.set(key, normalized);
  }
  const suffix = search.toString() ? `?${search.toString()}` : "";
  return `${base}/events/${encodeURIComponent(eventId)}${suffix}`;
}

async function buildTicketUrl(orderId) {
  const base = await getPublicBaseUrl();
  return `${base}/tickets/${encodeURIComponent(orderId)}`;
}

async function buildOrganizerFeedUrl(shareId) {
  const base = await getPublicBaseUrl();
  return `${base}/organizer-feed/${encodeURIComponent(shareId)}`;
}

function publicTimestamp(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return "";
}

function moneyAmount(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : 0;
}

function sanitizeMap(data, allowedKeys) {
  const result = {};
  for (const key of allowedKeys) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      result[key] = data[key];
    }
  }
  return result;
}

function publicEventSnapshot(eventId, eventData) {
  const ticketing = eventData.ticketing || {};
  const distribution = eventData.distribution || {};
  return {
    eventId,
    organizationId: safeString(eventData.organizationId),
    createdBy: safeString(eventData.createdBy),
    title: safeString(eventData.title, "Event"),
    venue: safeString(eventData.venue),
    city: safeString(eventData.city),
    startAt: eventData.startAt || null,
    endAt: eventData.endAt || null,
    timezone: safeString(eventData.timezone, TIME_ZONE),
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
  };
}

async function hasAdminAccess(uid) {
  if (!uid) return false;
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  if (safeString(data.status, "active").toLowerCase() === "disabled") return false;
  // Read-only admins must NOT gain event-management/write access through this
  // gate (admit, comp, recover, partner mgmt, pending-change review, etc.).
  // They view data via the admin console, which enforces its own per-collection RBAC.
  return safeString(data.role).toLowerCase().replace(/[\s-]+/g, "_") !== "read_only";
}

async function assertOrganizationManager(uid, organizationId) {
  const orgId = safeString(organizationId);
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!orgId) throw new HttpsError("invalid-argument", "organizationId is required.");
  if (await hasAdminAccess(uid)) return;
  if (orgId === `org_${uid}`) return;

  const [orgSnap, memberSnap, applicationSnap] = await Promise.all([
    db.collection("organizations").doc(orgId).get(),
    db.collection("organization_members").doc(`${orgId}_${uid}`).get(),
    db.collection("organizer_applications").doc(uid).get(),
  ]);
  const org = orgSnap.exists ? orgSnap.data() || {} : {};
  if (safeString(org.ownerId) === uid) return;

  const member = memberSnap.exists ? memberSnap.data() || {} : {};
  if (
    safeString(member.organizationId) === orgId &&
    safeString(member.userId) === uid &&
    safeString(member.status, "active").toLowerCase() !== "disabled"
  ) {
    return;
  }

  const application = applicationSnap.exists ? applicationSnap.data() || {} : {};
  if (safeString(application.organizationId) === orgId && safeString(application.userId) === uid) {
    return;
  }

  throw new HttpsError("permission-denied", "You cannot manage this organizer workspace.");
}

async function assertEventManager(uid, eventId) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");

  const eventData = eventSnap.data() || {};
  if (await hasAdminAccess(uid)) {
    return { eventRef: eventSnap.ref, eventData };
  }
  if (safeString(eventData.createdBy) === uid) {
    return { eventRef: eventSnap.ref, eventData };
  }
  await assertOrganizationManager(uid, safeString(eventData.organizationId));
  return { eventRef: eventSnap.ref, eventData };
}

async function assertEventTicketPermission(uid, eventId, permission) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!EVENT_TEAM_PERMISSIONS.has(permission)) {
    throw new HttpsError("invalid-argument", "Unknown event team permission.");
  }
  try {
    const managerContext = await assertEventManager(uid, eventId);
    return {
      ...managerContext,
      actor: {
        userId: uid,
        role: "owner",
        roleLabel: "Owner",
        manager: true,
      },
    };
  } catch (error) {
    if (error instanceof HttpsError && error.code !== "permission-denied") {
      throw error;
    }
  }

  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const memberSnap = await db.collection("event_team_members").doc(`${eventId}_${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "You are not on this event team.");
  }
  const member = memberSnap.data() || {};
  const permissions = member.permissions && typeof member.permissions === "object" ? member.permissions : {};
  if (safeString(member.status, "active") !== "active" || safeString(member.eventId) !== eventId) {
    throw new HttpsError("permission-denied", "This event team access is inactive.");
  }
  if (permissions[permission] !== true) {
    throw new HttpsError("permission-denied", "Your event role cannot perform this action.");
  }
  return {
    eventRef: eventSnap.ref,
    eventData: eventSnap.data() || {},
    actor: {
      userId: uid,
      role: safeString(member.role, "scanner"),
      roleLabel: safeString(member.roleLabel, "Scanner"),
      manager: false,
      teamMemberId: memberSnap.id,
      email: normalizeEmail(member.email),
    },
  };
}

async function writeTicketScanLog({
  type,
  qrToken,
  lookup = {},
  order = {},
  actor = {},
  status = "success",
  outcome = "",
  amountCollected = 0,
}) {
  await db.collection("ticket_scan_logs").add({
    type,
    qrToken,
    eventId: safeString(lookup.eventId || order.eventId),
    orderId: safeString(lookup.orderId || order.id),
    ticketId: safeString(lookup.ticketId),
    attendeeName: safeString(lookup.attendeeName || order.buyerName),
    tierName: safeString(lookup.tierName, "General"),
    paymentStatus: safeString(lookup.paymentStatus || order.paymentStatus),
    ticketStatus: safeString(lookup.ticketStatus, "issued"),
    amountCollected: moneyAmount(amountCollected),
    performedBy: safeString(actor.userId),
    performedByEmail: safeString(actor.email),
    role: safeString(actor.role),
    roleLabel: safeString(actor.roleLabel),
    status,
    outcome,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function assertPublicEvent(eventId) {
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const eventData = eventSnap.data() || {};
  if (eventData.visibility !== "public" || eventData.status !== "published") {
    throw new HttpsError("failed-precondition", "This event is not publicly available.");
  }
  return { eventRef: eventSnap.ref, eventData };
}

function selectedTiersFromSelections({ tiers, selections, priceMode }) {
  const tierById = new Map();
  for (const tier of tiers) {
    tierById.set(safeString(tier.tierId), tier);
  }

  const selectedTiers = [];
  let totalAmount = 0;
  let ticketCount = 0;
  for (const [tierId, rawQuantity] of Object.entries(selections || {})) {
    const quantity = Math.min(Math.max(Number(rawQuantity || 0), 0), 20);
    if (!Number.isFinite(quantity) || quantity <= 0) continue;

    const tier = tierById.get(safeString(tierId));
    if (!tier) continue;
    const price = moneyAmount(tier.price);
    if (priceMode === "free" && price !== 0) continue;
    if (priceMode === "paid" && price <= 0) continue;

    selectedTiers.push({
      tierId: safeString(tier.tierId),
      name: safeString(tier.name, "General"),
      price,
      quantity,
    });
    totalAmount += price * quantity;
    ticketCount += quantity;
  }

  return {
    selectedTiers,
    ticketCount,
    totalAmount: moneyAmount(totalAmount),
  };
}

async function issueTicketsForOrder(orderRef, options = {}) {
  let issuedCount = 0;
  await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Ticket order not found.");
    }
    const order = orderSnap.data() || {};
    if (order.tickets && Object.keys(order.tickets).length > 0) {
      issuedCount = Object.keys(order.tickets).length;
      return;
    }

    const eventId = safeString(order.eventId);
    if (!eventId) throw new HttpsError("failed-precondition", "Order is missing eventId.");
    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await transaction.get(eventRef);
    const eventData = eventSnap.exists ? eventSnap.data() || {} : order.eventSnapshot || {};
    if (!eventData || Object.keys(eventData).length === 0) {
      throw new HttpsError("not-found", "Event not found for ticket order.");
    }

    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? [...ticketing.tiers] : [];
    const tierIndex = new Map();
    tiers.forEach((tier, index) => tierIndex.set(safeString(tier.tierId), index));

    const selectedTiers = Array.isArray(order.selectedTiers) ? order.selectedTiers : [];
    const now = FieldValue.serverTimestamp();
    const issuedAtIso = new Date().toISOString();
    const attendeeName = safeString(order.buyerName, "Vennuzo attendee");
    const issuedTickets = {};
    const lookupWrites = [];
    let ticketCount = 0;

    for (const selection of selectedTiers) {
      const tierId = safeString(selection.tierId);
      const quantity = Math.min(Math.max(Number(selection.quantity || 0), 0), 20);
      if (!tierId || quantity <= 0) continue;

      const position = tierIndex.get(tierId);
      if (position == null) {
        throw new HttpsError("failed-precondition", `Ticket tier ${tierId} no longer exists.`);
      }

      const tier = { ...tiers[position] };
      const sold = Number(tier.sold || 0);
      const maxQuantity = Number(tier.maxQuantity || 0);
      if (maxQuantity > 0 && sold + quantity > maxQuantity) {
        throw new HttpsError(
          "failed-precondition",
          `${safeString(tier.name, "Ticket")} no longer has enough inventory.`,
        );
      }
      tier.sold = sold + quantity;
      tiers[position] = tier;

      for (let index = 0; index < quantity; index += 1) {
        ticketCount += 1;
        const ticketId = buildTicketId(orderRef.id, tierId, ticketCount);
        const qrToken = randomQrToken();
        issuedTickets[ticketId] = {
          ticketId,
          orderId: orderRef.id,
          eventId,
          occurrenceId: safeString(order.occurrenceId, `${eventId}_primary`),
          tierId,
          tierName: safeString(selection.name, safeString(tier.name, "General")),
          qrToken,
          status: "issued",
          attendeeName,
          price: moneyAmount(selection.price),
          issuedAt: now,
          issuedAtIso,
          updatedAt: now,
        };
        lookupWrites.push({
          qrToken,
          payload: {
            qrToken,
            orderId: orderRef.id,
            ticketId,
            eventId,
            occurrenceId: safeString(order.occurrenceId, `${eventId}_primary`),
            organizationId: safeString(order.organizationId, eventData.organizationId),
            buyerId: safeString(order.buyerId),
            attendeeName,
            tierId,
            tierName: safeString(selection.name, safeString(tier.name, "General")),
            ticketStatus: "issued",
            paymentStatus: "paid",
            admitted: false,
            createdAt: now,
            updatedAt: now,
          },
        });
      }
    }

    if (ticketCount <= 0) {
      throw new HttpsError("failed-precondition", "No tickets could be issued for this order.");
    }

    transaction.set(
      orderRef,
      {
        status: "paid",
        paymentStatus: "paid",
        paymentProvider: safeString(options.paymentProvider, safeString(order.paymentProvider, "manual")),
        ticketCount,
        tickets: issuedTickets,
        paidAt: now,
        paymentDetails: {
          ...(order.paymentDetails || {}),
          ...(options.paymentDetails || {}),
          issuedByBackend: true,
          issuedAt: now,
        },
        updatedAt: now,
      },
      { merge: true },
    );

    transaction.set(
      eventRef,
      {
        ticketing: {
          ...ticketing,
          tiers,
        },
        metrics: {
          ...(eventData.metrics || {}),
          ticketCount: FieldValue.increment(ticketCount),
          grossRevenue: FieldValue.increment(moneyAmount(order.totalAmount)),
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
    issuedCount = ticketCount;
  });
  try {
    await syncOrderToGPlusTicketing(orderRef.id, {
      source: safeString(options.paymentProvider, "event_parity"),
    });
  } catch (error) {
    console.warn(
      `[gplus-ticket-bridge] Sync failed for order ${orderRef.id}: ${safeString(error && error.message, "unknown error")}`,
    );
  }
  return issuedCount;
}

async function getHubtelConfig() {
  const snap = await db.collection("app_config").doc("hubtel").get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Hubtel config not found.");
  }
  const data = snap.data() || {};
  const apiKey = safeString(data.apiKey);
  const apiSecret = safeString(data.apiSecret);
  const merchantAccount = safeString(data.merchantAccountNumber || data.merchantAccount);
  // Source order matches the Gplus reference: HUBTEL_CALLBACK_SECRET env var first,
  // then app_config/hubtel.callbackSecret (empty = fail-open until configured).
  const callbackSecret =
    safeString(process.env.HUBTEL_CALLBACK_SECRET) || safeString(data.callbackSecret);
  if (!apiKey || !apiSecret || !merchantAccount) {
    throw new HttpsError("failed-precondition", "Hubtel merchant credentials are not configured.");
  }
  return { apiKey, apiSecret, merchantAccount, callbackSecret };
}

function hubtelAuthHeader(config) {
  return `Basic ${Buffer.from(`${config.apiKey}:${config.apiSecret}`).toString("base64")}`;
}

/**
 * Server-to-server confirmation of a Hubtel transaction status.
 * SECURITY: callback bodies are forgeable; never fulfil a "paid" outcome based
 * on the callback alone. Returns { ok, status } where ok is only true when
 * Hubtel positively confirms the transaction.
 */
async function confirmHubtelStatusFromProvider(clientReference, config) {
  const reference = safeString(clientReference);
  if (!reference) return { ok: false, status: "unknown", reason: "missing_reference" };
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
    return { ok: false, status: "unknown", reason: "fetch_failed" };
  }
  if (response.status === 403) return { ok: false, status: "unknown", reason: "ip_not_whitelisted" };
  const result = await response.json().catch(() => ({}));
  if (result.responseCode !== "0000" || !result.data) {
    return { ok: false, status: "unknown", reason: "unconfirmed" };
  }
  return { ok: true, status: normalizeHubtelStatus(result.data.status) };
}

function tableReturnUrl(bookingId, status) {
  const params = new URLSearchParams({
    bookingId,
    status,
  });
  return `${functionsBaseUrl()}/tablePackageHubtelReturn?${params.toString()}`;
}

async function initiateTableHubtelCheckout({
  bookingId,
  totalAmount,
  description,
  clientReference,
  payeeName,
  payeeMobileNumber,
  payeeEmail,
}) {
  const config = await getHubtelConfig();
  const body = {
    totalAmount,
    description,
    clientReference,
    callbackUrl: `${functionsBaseUrl()}/tablePackageHubtelCallback`,
    returnUrl: tableReturnUrl(bookingId, "success"),
    cancellationUrl: tableReturnUrl(bookingId, "cancelled"),
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
    body: JSON.stringify(body),
  });
  const result = await response.json().catch(() => ({}));
  const checkoutUrl = safeString(result && result.data && (result.data.checkoutDirectUrl || result.data.checkoutUrl));
  if (!response.ok || !checkoutUrl) {
    console.error("Hubtel table package checkout initiate failed", response.status, result);
    throw new HttpsError("internal", "Failed to create Hubtel checkout. Please try again.");
  }
  return {
    checkoutUrl,
    checkoutId: safeString(result && result.data && result.data.checkoutId),
    checkoutDirectUrl: safeString(result && result.data && result.data.checkoutDirectUrl),
    checkoutHostedUrl: safeString(result && result.data && result.data.checkoutUrl),
  };
}

function normalizeHubtelStatus(value) {
  const normalized = safeString(value).toLowerCase();
  if (["paid", "success", "successful", "completed"].includes(normalized)) return "paid";
  if (["cancelled", "canceled", "failed", "expired"].includes(normalized)) return normalized;
  return normalized || "pending";
}

function isPaidHubtelStatus(value) {
  return normalizeHubtelStatus(value) === "paid";
}

async function resolvePartnerReferral(eventId, refValue) {
  const raw = safeString(refValue);
  if (!raw) return {};
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
  if (!linkSnap || !linkSnap.exists) return { partnerRefCode: raw };
  const link = linkSnap.data() || {};
  if (safeString(link.eventId) !== safeString(eventId)) return { partnerRefCode: raw };
  return {
    partnerLinkId: linkSnap.id,
    partnerProfileId: safeString(link.partnerProfileId),
    partnerRefCode: safeString(link.refCode, raw),
  };
}

exports.submitPublicEventRsvp = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const name = safeString(request.data && request.data.name);
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    const email = normalizeEmail(request.data && request.data.email);
    const guestCount = Math.min(Math.max(Number(request.data && request.data.guestCount || 1), 1), 20);
    const wantsTable = Boolean(request.data && request.data.wantsTable);
    const partnerRef = safeString(request.data && (request.data.partnerRef || request.data.ref));

    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    if (!name || (!phone && !email)) {
      throw new HttpsError("invalid-argument", "Name and either phone or email are required.");
    }

    const { eventRef, eventData } = await assertPublicEvent(eventId);
    const referral = await resolvePartnerReferral(eventId, partnerRef);
    const contactKey = email || phone || name.toLowerCase();
    const rsvpId = `rsvp_${hashValue(`${eventId}:${contactKey}`)}`;
    const rsvpRef = db.collection("event_rsvps").doc(rsvpId);
    let created = false;

    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(rsvpRef);
      created = !current.exists;
      transaction.set(
        rsvpRef,
        {
          eventId,
          organizationId: safeString(eventData.organizationId),
          eventTitle: safeString(eventData.title, "Event"),
          name,
          phone,
          email,
          guestCount,
          wantsTable,
          userId: safeString(request.auth && request.auth.uid) || null,
          source: "public_web",
          status: "confirmed",
          ...referral,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: current.exists ? current.data().createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      if (created) {
        transaction.set(
          eventRef,
          {
            metrics: {
              ...((eventData && eventData.metrics) || {}),
              rsvpCount: FieldValue.increment(1),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    });

    return {
      success: true,
      rsvpId,
      created,
      eventUrl: await buildEventUrl(eventId, referral.partnerRefCode ? { ref: referral.partnerRefCode } : {}),
    };
  },
);

exports.submitPublicEventLike = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const clientId = safeString(request.data && request.data.clientId);

    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    if (!clientId || clientId.length < 8 || clientId.length > 128) {
      throw new HttpsError("invalid-argument", "A valid clientId is required.");
    }

    const { eventRef, eventData } = await assertPublicEvent(eventId);
    const likeId = `like_${hashValue(`${eventId}:${clientId}`)}`;
    const likeRef = db.collection("event_likes").doc(likeId);
    let created = false;
    let likesCount = Number((eventData.metrics && eventData.metrics.likesCount) || 0);

    await db.runTransaction(async (transaction) => {
      const [currentLike, currentEvent] = await Promise.all([
        transaction.get(likeRef),
        transaction.get(eventRef),
      ]);
      const latestEvent = currentEvent.data() || eventData;
      likesCount = Number((latestEvent.metrics && latestEvent.metrics.likesCount) || 0);
      created = !currentLike.exists;
      if (!created) {
        return;
      }

      transaction.set(likeRef, {
        eventId,
        organizationId: safeString(latestEvent.organizationId),
        clientHash: hashValue(clientId),
        userId: safeString(request.auth && request.auth.uid) || null,
        source: "public_web",
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.set(
        eventRef,
        {
          metrics: {
            ...((latestEvent && latestEvent.metrics) || {}),
            likesCount: FieldValue.increment(1),
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      likesCount += 1;
    });

    return {
      success: true,
      likeId,
      created,
      likesCount,
    };
  },
);

exports.createFreeWebTicketOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    // Unauthenticated and immediately issues real tickets — throttle hard by
    // IP to prevent free-ticket minting / inventory exhaustion.
    const ipKey = safeString(
      String(
        (request.rawRequest && request.rawRequest.headers["x-forwarded-for"]) || "",
      ).split(",")[0] ||
        (request.rawRequest && request.rawRequest.ip) ||
        "unknown",
    );
    await checkRateLimit(db, `ip:${ipKey}`, "createFreeWebTicketOrder", {
      maxCalls: 10,
      windowSeconds: 300,
    });

    const eventId = safeString(request.data && request.data.eventId);
    const selections = request.data && request.data.selections;
    const buyerName = safeString(request.data && request.data.buyerName);
    const buyerPhone = normalizePhoneNumber(request.data && request.data.buyerPhone);
    const buyerEmail = normalizeEmail(request.data && request.data.buyerEmail);
    const partnerRef = safeString(request.data && (request.data.partnerRef || request.data.ref));

    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    if (!selections || typeof selections !== "object") {
      throw new HttpsError("invalid-argument", "selections is required.");
    }
    if (!buyerName || !buyerPhone || !buyerEmail) {
      throw new HttpsError("invalid-argument", "buyerName, buyerPhone, and buyerEmail are required.");
    }

    const { eventData } = await assertPublicEvent(eventId);
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? ticketing.tiers : [];
    if (ticketing.enabled === false || tiers.length === 0) {
      throw new HttpsError("failed-precondition", "Ticketing is not enabled for this event.");
    }

    const selected = selectedTiersFromSelections({ tiers, selections, priceMode: "free" });
    if (selected.selectedTiers.length === 0 || selected.ticketCount <= 0) {
      throw new HttpsError("failed-precondition", "Select at least one free ticket tier.");
    }

    const referral = await resolvePartnerReferral(eventId, partnerRef);
    const orderRef = db.collection("event_ticket_orders").doc();
    await orderRef.set({
      eventId,
      occurrenceId: `${eventId}_primary`,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      buyerId: safeString(request.auth && request.auth.uid) || null,
      buyerName,
      buyerPhone,
      buyerEmail,
      selectedTiers: selected.selectedTiers,
      totalAmount: 0,
      currency: safeString(ticketing.currency, "GHS"),
      status: "pending",
      paymentStatus: "initiated",
      source: "web_free",
      eventSnapshot: publicEventSnapshot(eventId, eventData),
      ...referral,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await issueTicketsForOrder(orderRef, {
      paymentProvider: "free",
      paymentDetails: {
        source: "web_free",
        amount: 0,
      },
    });

    return {
      success: true,
      orderId: orderRef.id,
      ticketUrl: await buildTicketUrl(orderRef.id),
    };
  },
);

exports.getPublicTicket = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request, response) => {
    try {
      if (request.method !== "GET") {
        return response.status(405).json({ error: "Method not allowed." });
      }
      const orderId = safeString(request.query.orderId);
      if (!orderId) return response.status(400).json({ error: "orderId is required." });
      // Rate limit by IP to prevent orderId enumeration / ticket-token harvesting.
      const ip = safeString(
        String(request.headers["x-forwarded-for"] || "").split(",")[0] || request.ip,
        "unknown",
      );
      try {
        await checkRateLimit(db, `ip_${ip}`, "getPublicTicket", { maxCalls: 30, windowSeconds: 60 });
      } catch (_rateError) {
        return response.status(429).json({ error: "Too many requests. Please slow down." });
      }
      const orderSnap = await db.collection("event_ticket_orders").doc(orderId).get();
      if (!orderSnap.exists) return response.status(404).json({ error: "Order not found." });
      const order = orderSnap.data() || {};
      const tickets = order.tickets
        ? Object.values(order.tickets).map((ticket) => ({
            ticketId: safeString(ticket.ticketId),
            eventId: safeString(ticket.eventId),
            tierName: safeString(ticket.tierName, "General"),
            attendeeName: safeString(ticket.attendeeName || order.buyerName),
            qrToken: safeString(ticket.qrToken),
            status: safeString(ticket.status, "issued"),
            price: moneyAmount(ticket.price),
          }))
        : [];
      return response.json({
        orderId,
        eventId: safeString(order.eventId),
        eventTitle: safeString(order.eventTitle, "Event"),
        buyerName: safeString(order.buyerName),
        totalAmount: moneyAmount(order.totalAmount),
        currency: safeString(order.currency, "GHS"),
        paymentStatus: safeString(order.paymentStatus),
        tickets,
      });
    } catch (error) {
      console.error("getPublicTicket error", error);
      // Do not leak internal error details to the public caller.
      return response.status(500).json({ error: "Ticket lookup failed." });
    }
  },
);

exports.validateEventTicket = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const qrToken = safeString(request.data && request.data.qrToken);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!qrToken) throw new HttpsError("invalid-argument", "qrToken is required.");

    const lookupSnap = await db.collection("event_ticket_lookups").doc(qrToken).get();
    if (!lookupSnap.exists) throw new HttpsError("not-found", "Ticket not found.");
    const lookup = lookupSnap.data() || {};
    const { eventData, actor } = await assertEventTicketPermission(uid, safeString(lookup.eventId), "scanTickets");

    const orderSnap = await db.collection("event_ticket_orders").doc(safeString(lookup.orderId)).get();
    const order = orderSnap.exists ? orderSnap.data() || {} : {};
    const paymentStatus = safeString(lookup.paymentStatus || order.paymentStatus);
    const normalizedPayment = paymentStatus.replace(/[_\s-]+/g, "").toLowerCase();
    const requiresCash = normalizedPayment === "cashatgate" || normalizedPayment === "unpaid";
    await writeTicketScanLog({
      type: "validate",
      qrToken,
      lookup,
      order,
      actor,
      outcome: lookup.admitted === true ? "already_admitted" : requiresCash ? "requires_cash" : "valid",
    });

    return {
      success: true,
      valid: true,
      eventId: safeString(lookup.eventId),
      eventTitle: safeString(order.eventTitle || eventData.title, "Event"),
      orderId: safeString(lookup.orderId),
      ticketId: safeString(lookup.ticketId),
      attendeeName: safeString(lookup.attendeeName || order.buyerName),
      tierName: safeString(lookup.tierName, "General"),
      ticketStatus: safeString(lookup.ticketStatus, "issued"),
      paymentStatus,
      admitted: Boolean(lookup.admitted),
      admittedAt: publicTimestamp(lookup.admittedAt),
      requiresCash,
      amountDue: requiresCash ? moneyAmount(order.totalAmount) : 0,
      checkedAt: new Date().toISOString(),
    };
  },
);

exports.admitEventTicket = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const qrToken = safeString(request.data && request.data.qrToken);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!qrToken) throw new HttpsError("invalid-argument", "qrToken is required.");
    const lookupRef = db.collection("event_ticket_lookups").doc(qrToken);
    const lookupSnap = await lookupRef.get();
    if (!lookupSnap.exists) throw new HttpsError("not-found", "Ticket not found.");
    const lookup = lookupSnap.data() || {};
    const { actor } = await assertEventTicketPermission(uid, safeString(lookup.eventId), "admitTickets");

    // Confirm payment and prevent silent double-admission inside a transaction.
    const orderRef = lookup.orderId
      ? db.collection("event_ticket_orders").doc(safeString(lookup.orderId))
      : null;
    const result = await db.runTransaction(async (transaction) => {
      const freshLookupSnap = await transaction.get(lookupRef);
      const freshLookup = freshLookupSnap.data() || {};
      const orderSnap = orderRef ? await transaction.get(orderRef) : null;
      const order = orderSnap && orderSnap.exists ? orderSnap.data() || {} : {};

      const payment = safeString(freshLookup.paymentStatus || order.paymentStatus)
        .replace(/[_\s-]+/g, "")
        .toLowerCase();
      const blocked = [
        "cashatgate",
        "unpaid",
        "pending",
        "initiated",
        "failed",
        "cancelled",
      ].includes(payment);
      if (blocked) {
        throw new HttpsError(
          "failed-precondition",
          "This ticket is not paid yet. Collect cash / confirm payment before admitting.",
        );
      }

      if (freshLookup.admitted === true) {
        return { alreadyAdmitted: true, admittedAt: publicTimestamp(freshLookup.admittedAt) };
      }

      transaction.set(
        lookupRef,
        {
          admitted: true,
          ticketStatus: "admitted",
          admittedAt: FieldValue.serverTimestamp(),
          admittedBy: uid,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(db.collection("ticket_admin_actions").doc(), {
        type: "admit",
        qrToken,
        eventId: safeString(freshLookup.eventId),
        orderId: safeString(freshLookup.orderId),
        ticketId: safeString(freshLookup.ticketId),
        performedBy: uid,
        actorRole: safeString(actor.role),
        createdAt: FieldValue.serverTimestamp(),
      });
      return { alreadyAdmitted: false, admittedAt: null };
    });
    await writeTicketScanLog({
      type: "admit",
      qrToken,
      lookup,
      actor,
      outcome: result.alreadyAdmitted === true ? "already_admitted" : "admitted",
    });

    return {
      success: true,
      qrToken,
      status: "admitted",
      alreadyAdmitted: result.alreadyAdmitted === true,
      admittedAt: result.admittedAt || null,
    };
  },
);

exports.confirmCashForReservationTicket = onCall(
  {
    region: REGION,
    timeoutSeconds: 90,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const qrToken = safeString(request.data && request.data.qrToken);
    const amountCollected = moneyAmount(request.data && request.data.amountCollected);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!qrToken) throw new HttpsError("invalid-argument", "qrToken is required.");

    const lookupRef = db.collection("event_ticket_lookups").doc(qrToken);
    const lookupSnap = await lookupRef.get();
    if (!lookupSnap.exists) throw new HttpsError("not-found", "Ticket not found.");
    const lookup = lookupSnap.data() || {};
    const { actor } = await assertEventTicketPermission(uid, safeString(lookup.eventId), "collectCash");

    const orderRef = db.collection("event_ticket_orders").doc(safeString(lookup.orderId));
    await db.runTransaction(async (transaction) => {
      const orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
      const order = orderSnap.data() || {};
      transaction.set(
        orderRef,
        {
          status: "paid",
          paymentStatus: "cash_at_gate_paid",
          paymentProvider: "cash_at_gate",
          paidAt: FieldValue.serverTimestamp(),
          paymentDetails: {
            ...(order.paymentDetails || {}),
            amountCollected: amountCollected || moneyAmount(order.totalAmount),
            collectedBy: uid,
            collectedAt: FieldValue.serverTimestamp(),
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(
        lookupRef,
        {
          paymentStatus: "cash_at_gate_paid",
          ticketStatus: "admitted",
          admitted: true,
          admittedAt: FieldValue.serverTimestamp(),
          admittedBy: uid,
          cashCollectedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
    await db.collection("ticket_admin_actions").add({
      type: "cash_collect_and_admit",
      qrToken,
      eventId: safeString(lookup.eventId),
      orderId: safeString(lookup.orderId),
      amountCollected,
      performedBy: uid,
      actorRole: safeString(actor.role),
      createdAt: FieldValue.serverTimestamp(),
    });
    await writeTicketScanLog({
      type: "cash_collect_and_admit",
      qrToken,
      lookup,
      actor,
      amountCollected,
      outcome: "cash_collected_and_admitted",
    });
    return { success: true, qrToken, status: "cash_at_gate_paid" };
  },
);

exports.issueComplimentaryTickets = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const selections = request.data && request.data.selections;
    const buyerName = safeString(request.data && request.data.buyerName);
    const buyerPhone = normalizePhoneNumber(request.data && request.data.buyerPhone);
    const buyerEmail = normalizeEmail(request.data && request.data.buyerEmail);

    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    if (!buyerName || !buyerPhone || !buyerEmail) {
      throw new HttpsError("invalid-argument", "buyerName, buyerPhone, and buyerEmail are required.");
    }

    const { eventData } = await assertEventTicketPermission(uid, eventId, "issueTickets");
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? ticketing.tiers : [];
    const selected = selectedTiersFromSelections({ tiers, selections, priceMode: "free" });
    const fallbackTier = tiers[0];
    if (selected.selectedTiers.length === 0 && fallbackTier) {
      const quantity = Math.min(Math.max(Number(request.data && request.data.quantity || 1), 1), 20);
      selected.selectedTiers.push({
        tierId: safeString(fallbackTier.tierId),
        name: safeString(request.data && request.data.tierName, safeString(fallbackTier.name, "Comp")),
        price: 0,
        quantity,
      });
      selected.ticketCount = quantity;
    }
    if (selected.selectedTiers.length === 0) {
      throw new HttpsError("failed-precondition", "Add at least one ticket tier before issuing comps.");
    }

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
      selectedTiers: selected.selectedTiers,
      totalAmount: 0,
      currency: safeString(ticketing.currency, "GHS"),
      status: "pending",
      paymentStatus: "initiated",
      source: "complimentary",
      issuedBy: uid,
      eventSnapshot: publicEventSnapshot(eventId, eventData),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await issueTicketsForOrder(orderRef, {
      paymentProvider: "complimentary",
      paymentDetails: {
        source: "complimentary",
        issuedBy: uid,
      },
    });
    return {
      success: true,
      orderId: orderRef.id,
      ticketUrl: await buildTicketUrl(orderRef.id),
    };
  },
);

exports.createOrganizerFeedLink = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    const { eventData } = await assertEventManager(uid, eventId);
    const shareId = `feed_${hashValue(`${eventId}:${uid}`)}`;
    await db.collection("share_links").doc(shareId).set(
      {
        type: "organizer_rsvp_feed",
        targetId: eventId,
        organizationId: safeString(eventData.organizationId),
        title: `${safeString(eventData.title, "Event")} RSVP and ticket feed`,
        status: "active",
        createdBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return {
      success: true,
      shareId,
      url: await buildOrganizerFeedUrl(shareId),
    };
  },
);

exports.getSharedOrganizerRsvpFeed = onCall(
  {
    region: REGION,
    timeoutSeconds: 90,
  },
  async (request) => {
    const shareId = safeString(request.data && request.data.shareId);
    if (!shareId) throw new HttpsError("invalid-argument", "shareId is required.");
    // Rate limit by caller (uid when signed in, else IP) to stop enumeration.
    const feedRateKey = safeString(
      request.auth && request.auth.uid,
      `ip_${safeString((request.rawRequest && request.rawRequest.ip) || "unknown")}`,
    );
    await checkRateLimit(db, feedRateKey, "getSharedOrganizerRsvpFeed", { maxCalls: 30, windowSeconds: 60 });
    const linkSnap = await db.collection("share_links").doc(shareId).get();
    if (!linkSnap.exists) throw new HttpsError("not-found", "Shared feed not found.");
    const link = linkSnap.data() || {};
    if (safeString(link.type) !== "organizer_rsvp_feed" || safeString(link.status, "active") !== "active") {
      throw new HttpsError("failed-precondition", "Shared feed is not active.");
    }
    // Honour an optional expiry so leaked links don't live forever.
    const feedExpiresAt = link.expiresAt && typeof link.expiresAt.toDate === "function"
      ? link.expiresAt.toDate()
      : null;
    if (feedExpiresAt && feedExpiresAt.getTime() < Date.now()) {
      throw new HttpsError("failed-precondition", "Shared feed has expired.");
    }
    const eventId = safeString(link.targetId);
    const [eventSnap, rsvpsSnap, ordersSnap] = await Promise.all([
      db.collection("events").doc(eventId).get(),
      db.collection("event_rsvps").where("eventId", "==", eventId).limit(MAX_PUBLIC_ROWS).get(),
      db.collection("event_ticket_orders").where("eventId", "==", eventId).limit(MAX_PUBLIC_ROWS).get(),
    ]);
    const eventData = eventSnap.exists ? eventSnap.data() || {} : {};
    // Full attendee contact details are only exposed to the event's managers;
    // anyone merely holding the share link sees masked phone/email.
    const feedViewerUid = safeString(request.auth && request.auth.uid);
    const viewerIsManager = feedViewerUid
      ? ((await hasAdminAccess(feedViewerUid)) || safeString(eventData.organizationId) === `org_${feedViewerUid}`)
      : false;
    const rsvps = rsvpsSnap.docs.map((docSnap) => {
      const d = docSnap.data() || {};
      return {
        id: docSnap.id,
        name: safeString(d.name),
        phone: viewerIsManager ? safeString(d.phone) : maskContactPhone(d.phone),
        email: viewerIsManager ? safeString(d.email) : maskContactEmail(d.email),
        guestCount: Number(d.guestCount || 1),
        status: safeString(d.status, "confirmed"),
        wantsTable: Boolean(d.wantsTable),
        createdAt: publicTimestamp(d.createdAt),
      };
    });
    const orders = ordersSnap.docs.map((docSnap) => {
      const d = docSnap.data() || {};
      return {
        id: docSnap.id,
        buyerName: safeString(d.buyerName),
        buyerPhone: viewerIsManager ? safeString(d.buyerPhone) : maskContactPhone(d.buyerPhone),
        buyerEmail: viewerIsManager ? safeString(d.buyerEmail) : maskContactEmail(d.buyerEmail),
        paymentStatus: safeString(d.paymentStatus),
        totalAmount: moneyAmount(d.totalAmount),
        ticketCount: Number(d.ticketCount || 0),
        createdAt: publicTimestamp(d.createdAt),
      };
    });
    return {
      success: true,
      event: {
        id: eventId,
        title: safeString(eventData.title, safeString(link.title, "Event")),
        startAt: publicTimestamp(eventData.startAt),
        venue: safeString(eventData.venue),
        city: safeString(eventData.city),
      },
      rsvps,
      orders,
      summary: {
        rsvpCount: rsvps.length,
        orderCount: orders.length,
        paidOrderCount: orders.filter((order) => order.paymentStatus === "paid").length,
        ticketCount: orders.reduce((sum, order) => sum + Number(order.ticketCount || 0), 0),
        revenue: moneyAmount(orders.reduce((sum, order) => sum + Number(order.totalAmount || 0), 0)),
      },
    };
  },
);

exports.createPartnerProfile = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const organizationId = safeString(request.data && request.data.organizationId);
    const name = safeString(request.data && request.data.name);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    await assertOrganizationManager(uid, organizationId);
    if (!name) throw new HttpsError("invalid-argument", "Partner name is required.");
    const ref = db.collection("partner_profiles").doc();
    await ref.set({
      organizationId,
      name,
      email: normalizeEmail(request.data && request.data.email),
      phone: normalizePhoneNumber(request.data && request.data.phone),
      type: safeString(request.data && request.data.type, "promoter"),
      commissionRate: moneyAmount(request.data && request.data.commissionRate),
      status: "active",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, partnerProfileId: ref.id };
  },
);

exports.listPartnerProfiles = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const organizationId = safeString(request.data && request.data.organizationId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    await assertOrganizationManager(uid, organizationId);
    const snap = await db
      .collection("partner_profiles")
      .where("organizationId", "==", organizationId)
      .limit(100)
      .get();
    return {
      success: true,
      partners: snap.docs.map((docSnap) => ({
        id: docSnap.id,
        ...sanitizeMap(docSnap.data() || {}, ["name", "email", "phone", "type", "commissionRate", "status"]),
      })),
    };
  },
);

exports.createPartnerEventLink = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const partnerProfileId = safeString(request.data && request.data.partnerProfileId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId || !partnerProfileId) {
      throw new HttpsError("invalid-argument", "eventId and partnerProfileId are required.");
    }
    const { eventData } = await assertEventManager(uid, eventId);
    const partnerSnap = await db.collection("partner_profiles").doc(partnerProfileId).get();
    if (!partnerSnap.exists) throw new HttpsError("not-found", "Partner not found.");
    const partner = partnerSnap.data() || {};
    if (safeString(partner.organizationId) !== safeString(eventData.organizationId)) {
      throw new HttpsError("permission-denied", "Partner does not belong to this organizer.");
    }
    const refCode = safeString(request.data && request.data.refCode).toLowerCase().replace(/[^a-z0-9-]+/g, "-") ||
      `p-${crypto.randomBytes(4).toString("hex")}`;
    const linkId = `plink_${hashValue(`${eventId}:${partnerProfileId}:${refCode}`)}`;
    const url = await buildEventUrl(eventId, { ref: refCode });
    await db.collection("partner_event_links").doc(linkId).set(
      {
        eventId,
        organizationId: safeString(eventData.organizationId),
        partnerProfileId,
        partnerName: safeString(partner.name),
        eventTitle: safeString(eventData.title, "Event"),
        refCode,
        url,
        status: "active",
        clicks: 0,
        orders: 0,
        revenue: 0,
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { success: true, linkId, refCode, url };
  },
);

exports.recordPartnerClick = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const refCode = safeString(request.data && (request.data.refCode || request.data.ref));
    if (!eventId || !refCode) return { success: false, reason: "missing_ref" };
    // Rate limit by caller/IP to stop click/commission-metric inflation.
    const clickRateKey = safeString(
      request.auth && request.auth.uid,
      `ip_${safeString((request.rawRequest && request.rawRequest.ip) || "unknown")}`,
    );
    await checkRateLimit(db, clickRateKey, "recordPartnerClick", { maxCalls: 60, windowSeconds: 60 });
    const referral = await resolvePartnerReferral(eventId, refCode);
    const linkId = safeString(referral.partnerLinkId);
    if (!linkId) return { success: false, reason: "link_not_found" };
    await Promise.all([
      db.collection("partner_event_links").doc(linkId).set(
        {
          clicks: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
      db.collection("partner_clicks").add({
        eventId,
        partnerLinkId: linkId,
        partnerProfileId: safeString(referral.partnerProfileId),
        refCode,
        userAgent: safeString(request.rawRequest && request.rawRequest.headers && request.rawRequest.headers["user-agent"]).slice(0, 300),
        createdAt: FieldValue.serverTimestamp(),
      }),
    ]);
    return { success: true, partnerLinkId: linkId };
  },
);

exports.getPartnerDashboard = onCall(
  {
    region: REGION,
    timeoutSeconds: 90,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const organizationId = safeString(request.data && request.data.organizationId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    await assertOrganizationManager(uid, organizationId);
    const [partnersSnap, linksSnap, ordersSnap] = await Promise.all([
      db.collection("partner_profiles").where("organizationId", "==", organizationId).limit(100).get(),
      db.collection("partner_event_links").where("organizationId", "==", organizationId).limit(200).get(),
      db.collection("event_ticket_orders").where("organizationId", "==", organizationId).limit(500).get(),
    ]);
    const ordersByLink = new Map();
    for (const orderDoc of ordersSnap.docs) {
      const order = orderDoc.data() || {};
      const linkId = safeString(order.partnerLinkId);
      if (!linkId) continue;
      const current = ordersByLink.get(linkId) || { orders: 0, revenue: 0 };
      current.orders += 1;
      current.revenue += moneyAmount(order.totalAmount);
      ordersByLink.set(linkId, current);
    }
    return {
      success: true,
      partners: partnersSnap.docs.map((docSnap) => ({
        id: docSnap.id,
        ...sanitizeMap(docSnap.data() || {}, ["name", "email", "phone", "type", "commissionRate", "status"]),
      })),
      links: linksSnap.docs.map((docSnap) => {
        const link = docSnap.data() || {};
        const orderMetrics = ordersByLink.get(docSnap.id) || { orders: 0, revenue: 0 };
        return {
          id: docSnap.id,
          eventId: safeString(link.eventId),
          eventTitle: safeString(link.eventTitle),
          partnerProfileId: safeString(link.partnerProfileId),
          partnerName: safeString(link.partnerName),
          refCode: safeString(link.refCode),
          url: safeString(link.url),
          clicks: Number(link.clicks || 0),
          orders: orderMetrics.orders,
          revenue: moneyAmount(orderMetrics.revenue),
          status: safeString(link.status, "active"),
        };
      }),
    };
  },
);

exports.createTablePackage = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const name = safeString(request.data && request.data.name);
    const priceGhs = moneyAmount(request.data && request.data.priceGhs);
    const capacity = Math.max(Number(request.data && request.data.capacity || 1), 1);
    const quantity = Math.max(Number(request.data && request.data.quantity || 1), 1);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId || !name) throw new HttpsError("invalid-argument", "eventId and name are required.");
    const { eventData } = await assertEventManager(uid, eventId);
    const ref = db.collection("tablePackages").doc();
    await ref.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      name,
      description: safeString(request.data && request.data.description),
      priceGhs,
      capacity,
      quantity,
      booked: 0,
      items: safeString(request.data && request.data.items),
      status: "active",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, tablePackageId: ref.id };
  },
);

exports.listTablePackages = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
    const eventData = eventSnap.data() || {};
    if (request.auth && request.auth.uid) {
      await assertEventManager(request.auth.uid, eventId).catch(async () => {
        await assertPublicEvent(eventId);
      });
    } else {
      await assertPublicEvent(eventId);
    }
    const snap = await db
      .collection("tablePackages")
      .where("eventId", "==", eventId)
      .limit(100)
      .get();
    return {
      success: true,
      event: {
        id: eventId,
        title: safeString(eventData.title, "Event"),
      },
      packages: snap.docs.map((docSnap) => {
        const d = docSnap.data() || {};
        const booked = Number(d.booked || 0);
        const quantity = Number(d.quantity || 0);
        return {
          id: docSnap.id,
          name: safeString(d.name),
          description: safeString(d.description),
          priceGhs: moneyAmount(d.priceGhs),
          capacity: Number(d.capacity || 1),
          quantity,
          booked,
          available: quantity <= 0 ? null : Math.max(quantity - booked, 0),
          items: safeString(d.items),
          status: safeString(d.status, "active"),
        };
      }),
    };
  },
);

exports.listTableBookings = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const organizationId = safeString(request.data && request.data.organizationId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    await assertOrganizationManager(uid, organizationId);
    const snap = await db
      .collection("table_package_bookings")
      .where("organizationId", "==", organizationId)
      .limit(100)
      .get();
    return {
      success: true,
      bookings: snap.docs.map((docSnap) => {
        const d = docSnap.data() || {};
        return {
          id: docSnap.id,
          eventId: safeString(d.eventId),
          eventTitle: safeString(d.eventTitle),
          packageName: safeString(d.packageName),
          buyerName: safeString(d.buyerName),
          buyerPhone: safeString(d.buyerPhone),
          buyerEmail: safeString(d.buyerEmail),
          quantity: Number(d.quantity || 1),
          totalAmount: moneyAmount(d.totalAmount),
          paymentStatus: safeString(d.paymentStatus),
          status: safeString(d.status),
          createdAt: publicTimestamp(d.createdAt),
        };
      }),
    };
  },
);

exports.createWebTablePackageBooking = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const tablePackageId = safeString(request.data && request.data.tablePackageId);
    const buyerName = safeString(request.data && request.data.buyerName);
    const buyerPhone = normalizePhoneNumber(request.data && request.data.buyerPhone);
    const buyerEmail = normalizeEmail(request.data && request.data.buyerEmail);
    const quantity = Math.min(Math.max(Number(request.data && request.data.quantity || 1), 1), 10);
    if (!eventId || !tablePackageId) {
      throw new HttpsError("invalid-argument", "eventId and tablePackageId are required.");
    }
    if (!buyerName || !buyerPhone || !buyerEmail) {
      throw new HttpsError("invalid-argument", "buyerName, buyerPhone, and buyerEmail are required.");
    }
    const { eventData } = await assertPublicEvent(eventId);
    const packageRef = db.collection("tablePackages").doc(tablePackageId);
    const packageSnap = await packageRef.get();
    if (!packageSnap.exists) throw new HttpsError("not-found", "Table package not found.");
    const tablePackage = packageSnap.data() || {};
    if (safeString(tablePackage.eventId) !== eventId || safeString(tablePackage.status, "active") !== "active") {
      throw new HttpsError("failed-precondition", "Table package is not available.");
    }
    const available = Number(tablePackage.quantity || 0) - Number(tablePackage.booked || 0);
    if (Number(tablePackage.quantity || 0) > 0 && available < quantity) {
      throw new HttpsError("failed-precondition", "Not enough tables are available.");
    }

    const totalAmount = moneyAmount(Number(tablePackage.priceGhs || 0) * quantity);
    const bookingRef = db.collection("table_package_bookings").doc();
    await bookingRef.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      tablePackageId,
      packageName: safeString(tablePackage.name),
      buyerName,
      buyerPhone,
      buyerEmail,
      quantity,
      totalAmount,
      currency: "GHS",
      status: totalAmount > 0 ? "pending_payment" : "confirmed",
      paymentStatus: totalAmount > 0 ? "initiated" : "paid",
      source: "public_web",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await db.collection("table_bookings").doc(bookingRef.id).set(
      {
        bookingId: bookingRef.id,
        eventId,
        organizationId: safeString(eventData.organizationId),
        tablePackageId,
        packageName: safeString(tablePackage.name),
        guestName: buyerName,
        guestPhone: buyerPhone,
        quantity,
        status: totalAmount > 0 ? "pending_payment" : "confirmed",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (totalAmount <= 0) {
      await packageRef.set(
        {
          booked: FieldValue.increment(quantity),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await notifyEventManagerPush(eventData, {
        kind: "table_package_booking_confirmed",
        title: "Table package booked",
        body: `${buyerName} booked ${quantity} x ${safeString(tablePackage.name, "table package")}.`,
        eventId,
      });
      return { success: true, bookingId: bookingRef.id, status: "confirmed" };
    }

    const clientReference = `tablepkg_${bookingRef.id}`;
    const checkout = await initiateTableHubtelCheckout({
      bookingId: bookingRef.id,
      totalAmount,
      description: `Table package: ${safeString(eventData.title, "Event")}`,
      clientReference,
      payeeName: buyerName,
      payeeMobileNumber: buyerPhone,
      payeeEmail: buyerEmail,
    });
    await bookingRef.set(
      {
        paymentProvider: "hubtel",
        paymentReference: {
          clientReference,
          checkoutId: checkout.checkoutId,
          checkoutUrl: checkout.checkoutHostedUrl || checkout.checkoutUrl,
          checkoutDirectUrl: checkout.checkoutDirectUrl || null,
          initiatedAt: FieldValue.serverTimestamp(),
        },
        paymentStatus: "pending",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return {
      success: true,
      bookingId: bookingRef.id,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
    };
  },
);

exports.tablePackageHubtelCallback = onRequest(
  {
    // Server-to-server webhook — CORS is unnecessary attack surface.
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request, response) => {
    try {
      if (request.method !== "POST") return response.status(405).json({ error: "Method not allowed." });
      const payload = request.body || {};
      const data = payload.Data || {};
      const clientReference = safeString(data.ClientReference);
      if (!clientReference.startsWith("tablepkg_")) {
        return response.status(400).json({ error: "Unsupported client reference." });
      }
      const config = await getHubtelConfig();
      // Optional callback signature verification (matches the Gplus reference):
      // verify constant-time when callbackSecret is configured, otherwise proceed
      // so payment fulfilment keeps working.
      if (config.callbackSecret) {
        if (!verifyHubtelSignature(config.callbackSecret, payload, request.headers["x-hubtel-signature"])) {
          return response.status(401).json({ error: "Invalid callback signature." });
        }
      }
      const bookingId = clientReference.replace(/^tablepkg_/, "");
      const bookingRef = db.collection("table_package_bookings").doc(bookingId);
      let status = normalizeHubtelStatus(data.Status);

      // SECURITY: re-confirm "paid" server-to-server before confirming the
      // booking and incrementing booked inventory.
      if (isPaidHubtelStatus(status)) {
        const confirmation = await confirmHubtelStatusFromProvider(clientReference, config);
        if (!confirmation.ok || !isPaidHubtelStatus(confirmation.status)) {
          console.warn(
            "tablePackageHubtelCallback claimed paid but provider confirmation failed",
            clientReference,
            confirmation.reason,
          );
          status = confirmation.ok ? confirmation.status : "pending";
        }
      }

      const bookingSnap = await bookingRef.get();
      if (!bookingSnap.exists) return response.status(404).json({ error: "Booking not found." });
      const booking = bookingSnap.data() || {};
      if (!isPaidHubtelStatus(status)) {
        await Promise.all([
          bookingRef.set(
            {
              status: status === "cancelled" || status === "failed" ? status : "pending_payment",
              paymentStatus: status,
              paymentDetails: {
                checkoutId: safeString(data.CheckoutId),
                salesInvoiceId: safeString(data.SalesInvoiceId),
                amount: moneyAmount(data.Amount || booking.totalAmount),
                callbackReceivedAt: FieldValue.serverTimestamp(),
              },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
          db.collection("table_bookings").doc(bookingId).set(
            {
              status: status === "cancelled" || status === "failed" ? status : "pending_payment",
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
        ]);
        return response.status(200).json({ success: false, bookingId, status });
      }

      let confirmedNow = false;
      await db.runTransaction(async (transaction) => {
        const freshBookingSnap = await transaction.get(bookingRef);
        const freshBooking = freshBookingSnap.data() || {};
        if (safeString(freshBooking.paymentStatus) === "paid") return;
        confirmedNow = true;
        transaction.set(
          bookingRef,
          {
            status: "confirmed",
            paymentStatus: "paid",
            paidAt: FieldValue.serverTimestamp(),
            paymentDetails: {
              checkoutId: safeString(data.CheckoutId),
              salesInvoiceId: safeString(data.SalesInvoiceId),
              amount: moneyAmount(data.Amount || freshBooking.totalAmount),
              callbackReceivedAt: FieldValue.serverTimestamp(),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(
          db.collection("table_bookings").doc(bookingId),
          {
            status: "confirmed",
            paymentStatus: "paid",
            paidAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(
          db.collection("tablePackages").doc(safeString(freshBooking.tablePackageId)),
          {
            booked: FieldValue.increment(Number(freshBooking.quantity || 1)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });
      if (confirmedNow) {
        const eventSnap = await db.collection("events").doc(safeString(booking.eventId)).get();
        const notifyEventData = eventSnap.exists ? eventSnap.data() || {} : {};
        await notifyEventManagerPush(notifyEventData, {
          kind: "table_package_booking_paid",
          title: "Table package paid",
          body: `${safeString(booking.buyerName, "A guest")} paid GHS ${moneyAmount(booking.totalAmount).toFixed(2)} for ${safeString(booking.packageName, "a table package")}.`,
          eventId: safeString(booking.eventId),
        });
      }
      return response.status(200).json({ success: true, bookingId, status: "paid" });
    } catch (error) {
      console.error("tablePackageHubtelCallback error", error);
      // Do not leak internal error details to the caller.
      return response.status(500).json({ error: "Callback failed." });
    }
  },
);

exports.tablePackageHubtelReturn = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request, response) => {
    const bookingId = safeString(request.query.bookingId);
    const status = safeString(request.query.status, "success");
    let eventId = "";
    try {
      const snap = await db.collection("table_package_bookings").doc(bookingId).get();
      eventId = snap.exists ? safeString((snap.data() || {}).eventId) : "";
    } catch (error) {
      eventId = "";
    }
    const base = await getPublicBaseUrl();
    const target = eventId
      ? `${base}/events/${encodeURIComponent(eventId)}?tableBooking=${encodeURIComponent(bookingId)}&status=${encodeURIComponent(status)}`
      : `${base}/events?tableBooking=${encodeURIComponent(bookingId)}&status=${encodeURIComponent(status)}`;
    return response.redirect(302, target);
  },
);

exports.createPromoMechanic = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const type = safeString(request.data && request.data.type);
    const title = safeString(request.data && request.data.title);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId || !PROMO_MECHANIC_TYPES.has(type)) {
      throw new HttpsError("invalid-argument", "eventId and a supported promo mechanic type are required.");
    }
    const { eventData } = await assertEventManager(uid, eventId);
    const ref = db.collection("promo_mechanics").doc();
    await ref.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      type,
      title: title || type.replace(/_/g, " "),
      description: safeString(request.data && request.data.description),
      code: safeString(request.data && request.data.code).toUpperCase(),
      reward: safeString(request.data && request.data.reward),
      startsAt: request.data && request.data.startsAt ? Timestamp.fromDate(new Date(request.data.startsAt)) : null,
      endsAt: request.data && request.data.endsAt ? Timestamp.fromDate(new Date(request.data.endsAt)) : null,
      status: "active",
      entries: 0,
      redemptions: 0,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, promoMechanicId: ref.id };
  },
);

exports.joinPromoMechanic = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const promoMechanicId = safeString(request.data && request.data.promoMechanicId);
    const name = safeString(request.data && request.data.name);
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    const email = normalizeEmail(request.data && request.data.email);
    const points = Math.max(Number(request.data && request.data.points || 1), 1);
    if (!promoMechanicId || !name || (!phone && !email)) {
      throw new HttpsError("invalid-argument", "promoMechanicId, name, and contact details are required.");
    }
    const mechanicRef = db.collection("promo_mechanics").doc(promoMechanicId);
    const mechanicSnap = await mechanicRef.get();
    if (!mechanicSnap.exists) throw new HttpsError("not-found", "Promo mechanic not found.");
    const mechanic = mechanicSnap.data() || {};
    if (safeString(mechanic.status, "active") !== "active") {
      throw new HttpsError("failed-precondition", "This promo is not active.");
    }
    const contactKey = email || phone;
    const entryId = `entry_${hashValue(`${promoMechanicId}:${contactKey}`)}`;
    const entryRef = db.collection("promo_entries").doc(entryId);
    let created = false;
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(entryRef);
      created = !current.exists;
      transaction.set(
        entryRef,
        {
          promoMechanicId,
          eventId: safeString(mechanic.eventId),
          organizationId: safeString(mechanic.organizationId),
          name,
          phone,
          email,
          points: FieldValue.increment(points),
          status: "active",
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: current.exists ? current.data().createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(
        mechanicRef,
        {
          entries: created ? FieldValue.increment(1) : FieldValue.increment(0),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
    return { success: true, entryId, created };
  },
);

exports.redeemPromoCode = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const code = safeString(request.data && request.data.code).toUpperCase();
    const name = safeString(request.data && request.data.name);
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    if (!eventId || !code || !name) {
      throw new HttpsError("invalid-argument", "eventId, code, and name are required.");
    }
    const snap = await db
      .collection("promo_mechanics")
      .where("eventId", "==", eventId)
      .where("code", "==", code)
      .limit(1)
      .get();
    if (snap.empty) throw new HttpsError("not-found", "Promo code not found.");
    const mechanicRef = snap.docs[0].ref;
    const mechanic = snap.docs[0].data() || {};
    const redemptionRef = db.collection("promo_redemptions").doc(`red_${hashValue(`${snap.docs[0].id}:${phone || name}`)}`);
    await redemptionRef.set(
      {
        promoMechanicId: snap.docs[0].id,
        eventId,
        organizationId: safeString(mechanic.organizationId),
        code,
        name,
        phone,
        status: "redeemed",
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await mechanicRef.set(
      {
        redemptions: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { success: true, redemptionId: redemptionRef.id };
  },
);

exports.getPromoLeaderboard = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const promoMechanicId = safeString(request.data && request.data.promoMechanicId);
    if (!promoMechanicId) throw new HttpsError("invalid-argument", "promoMechanicId is required.");
    const snap = await db
      .collection("promo_entries")
      .where("promoMechanicId", "==", promoMechanicId)
      .limit(100)
      .get();
    const entries = snap.docs
      .map((docSnap) => {
        const d = docSnap.data() || {};
        return {
          id: docSnap.id,
          name: safeString(d.name),
          points: Number(d.points || 0),
          status: safeString(d.status, "active"),
        };
      })
      .sort((a, b) => b.points - a.points);
    return { success: true, entries };
  },
);

exports.submitPendingEventChange = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const changes = request.data && request.data.changes && typeof request.data.changes === "object"
      ? request.data.changes
      : {};
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!eventId || Object.keys(changes).length === 0) {
      throw new HttpsError("invalid-argument", "eventId and changes are required.");
    }
    const { eventData } = await assertEventManager(uid, eventId);
    const allowedChanges = sanitizeMap(changes, [
      "title",
      "description",
      "venue",
      "city",
      "startAt",
      "endAt",
      "status",
      "visibility",
      "coverImageUrl",
      "tags",
      "lineup",
      "ticketing",
      "recurrence",
    ]);
    const ref = db.collection("pending_event_changes").doc();
    await ref.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      changes: allowedChanges,
      status: "pending",
      submittedBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, pendingChangeId: ref.id };
  },
);

exports.reviewPendingEventChange = onCall(
  {
    region: REGION,
    timeoutSeconds: 90,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const pendingChangeId = safeString(request.data && request.data.pendingChangeId);
    const decision = safeString(request.data && request.data.decision).toLowerCase();
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!(await hasAdminAccess(uid))) throw new HttpsError("permission-denied", "Admin access required.");
    if (!pendingChangeId || !["approved", "rejected"].includes(decision)) {
      throw new HttpsError("invalid-argument", "pendingChangeId and decision are required.");
    }
    const changeRef = db.collection("pending_event_changes").doc(pendingChangeId);
    const changeSnap = await changeRef.get();
    if (!changeSnap.exists) throw new HttpsError("not-found", "Pending change not found.");
    const change = changeSnap.data() || {};
    if (decision === "approved") {
      await db.collection("events").doc(safeString(change.eventId)).set(
        {
          ...(change.changes || {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await changeRef.set(
      {
        status: decision,
        reviewedBy: uid,
        reviewedAt: FieldValue.serverTimestamp(),
        reviewNotes: safeString(request.data && request.data.reviewNotes),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { success: true, status: decision };
  },
);

exports.recoverTicketOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const orderId = safeString(request.data && request.data.orderId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!orderId) throw new HttpsError("invalid-argument", "orderId is required.");
    const orderRef = db.collection("event_ticket_orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = orderSnap.data() || {};
    await assertEventManager(uid, safeString(order.eventId));
    const paymentStatus = safeString(order.paymentStatus).replace(/[_\s-]+/g, "").toLowerCase();
    if (!["paid", "cashatgatepaid", "complimentary"].includes(paymentStatus)) {
      throw new HttpsError("failed-precondition", "Only paid orders can be recovered.");
    }
    const issued = await issueTicketsForOrder(orderRef, {
      paymentProvider: safeString(order.paymentProvider, "recovery"),
      paymentDetails: {
        recoveredBy: uid,
      },
    });
    const jobRef = await db.collection("ticket_recovery_jobs").add({
      orderId,
      eventId: safeString(order.eventId),
      organizationId: safeString(order.organizationId),
      issued,
      performedBy: uid,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { success: true, recoveryJobId: jobRef.id, issued, ticketUrl: await buildTicketUrl(orderId) };
  },
);

function heuristicFlyerExtraction(input) {
  const text = safeString(input.text || input.caption || input.prompt);
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  return {
    title: safeString(input.title || lines[0]),
    venue: safeString(input.venue),
    city: safeString(input.city, "Accra"),
    dateText: safeString(input.dateText),
    priceText: safeString(input.priceText),
    tablePackages: Array.isArray(input.tablePackages) ? input.tablePackages : [],
    confidence: text ? 0.35 : 0.1,
  };
}

exports.extractEventDetailsFromFlyer = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const organizationId = safeString(request.data && request.data.organizationId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    await assertOrganizationManager(uid, organizationId);

    const extraction = heuristicFlyerExtraction(request.data || {});
    const ref = db.collection("event_ai_extractions").doc();
    await ref.set({
      organizationId,
      sourceImageUrl: safeString(request.data && request.data.imageUrl),
      sourceText: safeString(request.data && request.data.text).slice(0, 4000),
      extraction,
      provider: "vennuzo_gemini_ready",
      status: "needs_manual_review",
      note: "Stored for Gemini-assisted event creation when a Gemini API key is configured.",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, extractionId: ref.id, extraction };
  },
);
