"use strict";

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const shareLinks = require("./share_link");
const { checkRateLimit } = require("./rate_limiter");
const logger = require("./logger");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const TIME_ZONE = "Africa/Accra";
const MAX_REMINDER_BATCH = 30;
const MAX_JOB_BATCH = 25;
const MAX_SMS_RECIPIENTS_PER_JOB = 200;
const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

let hubtelSmsConfigCache = null;

async function getHubtelSmsConfig() {
  if (hubtelSmsConfigCache) {
    return hubtelSmsConfigCache;
  }

  try {
    const fileCfg = require("./hubtel_sms_config.js");
    const clientId = String(fileCfg.clientId || "").trim();
    const clientSecret = String(fileCfg.clientSecret || "").trim();
    if (clientId && clientSecret) {
      hubtelSmsConfigCache = {
        clientId,
        clientSecret,
        senderId: String(fileCfg.senderId || "Vennuzo").substring(0, 11),
      };
      return hubtelSmsConfigCache;
    }
  } catch (error) {
    console.log("Hubtel SMS config file missing, falling back to Firestore config.");
  }

  const configSnap = await db.collection("app_config").doc("hubtel").get();
  const config = configSnap.data() || {};
  const clientId =
    config.smsClientId || config.smsClientID || config.clientId || config.smsApiKey || config.apiKey;
  const clientSecret =
    config.smsClientSecret || config.clientSecret || config.smsApiSecret || config.apiSecret;
  const senderId = String(
    config.smsSenderId || config.senderId || config.smsFrom || "Vennuzo",
  ).substring(0, 11);

  if (!clientId || !clientSecret) {
    throw new Error(
      "Hubtel SMS credentials are missing. Add functions/hubtel_sms_config.js or app_config/hubtel.",
    );
  }

  hubtelSmsConfigCache = {
    clientId: String(clientId).trim(),
    clientSecret: String(clientSecret).trim(),
    senderId,
  };
  return hubtelSmsConfigCache;
}

const DEFAULT_SMS_RATE_GHS = 0.05;
const DEFAULT_SMS_MARGIN_MULTIPLIER = 1.5;

async function getPricingConfig(packageId) {
  let defaultSmsRateGhs = DEFAULT_SMS_RATE_GHS;
  let smsMarginMultiplier = DEFAULT_SMS_MARGIN_MULTIPLIER;

  if (packageId) {
    const pkgSnap = await db.collection("promo_packages").doc(packageId).get();
    if (pkgSnap.exists) {
      const pkg = pkgSnap.data() || {};
      if (Number(pkg.defaultSmsRateGhs) > 0) defaultSmsRateGhs = Number(pkg.defaultSmsRateGhs);
      if (Number(pkg.smsMarginMultiplier) > 0) smsMarginMultiplier = Number(pkg.smsMarginMultiplier);
    }
  }

  const globalSnap = await db.collection("app_config").doc("pricing").get();
  const data = globalSnap.exists ? globalSnap.data() || {} : {};
  defaultSmsRateGhs = Number(data.defaultSmsRateGhs) || defaultSmsRateGhs;
  smsMarginMultiplier = Number(data.smsMarginMultiplier) || smsMarginMultiplier;

  const platformSmsUnitPriceGhs = Math.max(0.01, Math.ceil(defaultSmsRateGhs * smsMarginMultiplier * 100) / 100);
  return {
    defaultSmsRateGhs,
    smsMarginMultiplier,
    platformSmsUnitPriceGhs,
  };
}

async function reserveCampaignBudget(organizationId, campaignId, amountGhs) {
  if (!amountGhs || amountGhs <= 0) {
    return { reserved: false };
  }
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `campaign_${campaignId}_reserve`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);

  return await db.runTransaction(async (transaction) => {
    const walletSnap = await transaction.get(walletRef);
    const walletData = walletSnap.exists ? walletSnap.data() || {} : {};
    const available = Number(walletData.availableBalance ?? 0);
    if (available < amountGhs) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient wallet balance. Need ${amountGhs.toFixed(2)} GHS; available ${available.toFixed(2)} GHS. Load your wallet in Payments & Payouts.`,
      );
    }
    const existingTxn = await transaction.get(txnRef);
    if (existingTxn.exists && existingTxn.data().status === "completed") {
      return { reserved: true, alreadyReserved: true };
    }
    transaction.update(walletRef, {
      availableBalance: FieldValue.increment(-amountGhs),
      heldBalance: FieldValue.increment(amountGhs),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "campaign_reservation",
      amount: amountGhs,
      clientReference,
      campaignId,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { reserved: true, amountGhs };
  });
}

async function chargeCampaignSms(campaignId, jobId, sentCount, unitPriceGhs) {
  const chargeAmount = Math.round(sentCount * unitPriceGhs * 100) / 100;
  if (chargeAmount <= 0) {
    return;
  }
  const campaignRef = db.collection("promotion_campaigns").doc(campaignId);
  const campaignSnap = await campaignRef.get();
  if (!campaignSnap.exists) {
    return;
  }
  const campaignData = campaignSnap.data() || {};
  const organizationId = safeString(campaignData.organizationId);
  const reservedAmount = Number(campaignData.walletReservationAmount ?? 0);
  if (reservedAmount <= 0) {
    return;
  }
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `campaign_${campaignId}_charge_${jobId}`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);

  await db.runTransaction(async (transaction) => {
    const existingTxn = await transaction.get(txnRef);
    if (existingTxn.exists && existingTxn.data().status === "completed") {
      return;
    }
    const campaignDoc = await transaction.get(campaignRef);
    const currentCharged = Number((campaignDoc.data() || {}).totalSmsCharged ?? 0);
    transaction.update(campaignRef, {
      totalSmsCharged: FieldValue.increment(chargeAmount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(walletRef, {
      heldBalance: FieldValue.increment(-chargeAmount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "campaign_charge",
      amount: chargeAmount,
      clientReference,
      campaignId,
      jobId,
      sentCount,
      unitPriceGhs,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function finalizeCampaignWallet(campaignId) {
  const campaignRef = db.collection("promotion_campaigns").doc(campaignId);
  const campaignSnap = await campaignRef.get();
  if (!campaignSnap.exists) {
    return;
  }
  const data = campaignSnap.data() || {};
  if (data.walletFinalized === true) {
    return;
  }
  const organizationId = safeString(data.organizationId);
  const reservedAmount = Number(data.walletReservationAmount ?? 0);
  const totalCharged = Number(data.totalSmsCharged ?? 0);
  if (reservedAmount <= 0) {
    await campaignRef.set({ walletFinalized: true, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return;
  }
  const releaseAmount = Math.round((reservedAmount - totalCharged) * 100) / 100;
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `campaign_${campaignId}_release`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);

  await db.runTransaction(async (transaction) => {
    const campaignDoc = await transaction.get(campaignRef);
    if (campaignDoc.data() && campaignDoc.data().walletFinalized === true) {
      return;
    }
    transaction.set(campaignRef, { walletFinalized: true, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    transaction.update(walletRef, {
      availableBalance: FieldValue.increment(releaseAmount),
      heldBalance: FieldValue.increment(-releaseAmount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "campaign_release",
      amount: releaseAmount,
      clientReference,
      campaignId,
      reservedAmount,
      totalCharged,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) {
    return null;
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

function isValidGhanaMobileNumber(phone) {
  return /^(\+233|233)(2[03456789]|5[03456789])\d{7}$/.test(phone);
}

function asDate(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function safeString(value, fallback = "") {
  const stringValue = String(value || "").trim();
  return stringValue || fallback;
}

async function buildEventLink(eventId, eventData = null) {
  try {
    const shareLink = await shareLinks.ensureEventShareLink({
      eventId,
      eventData,
      allowPrivate: false,
    });
    return shareLink.url;
  } catch (error) {
    console.warn("Falling back to static Eventora event link", eventId, error && error.message);
    return `https://vennuzo.app/e/${encodeURIComponent(eventId)}`;
  }
}

function titleCaseTiming(timing) {
  switch (String(timing || "")) {
    case "oneDayBefore":
      return "1 day before";
    case "twoDaysBefore":
      return "2 days before";
    case "oneWeekBefore":
      return "1 week before";
    case "custom":
      return "a custom time";
    case "onDay":
    default:
      return "the day of the event";
  }
}

function formatEventDate(dateValue) {
  const date = asDate(dateValue);
  if (!date) {
    return "soon";
  }
  return date.toLocaleString("en-GH", {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: TIME_ZONE,
  });
}

function paymentStatusValue(value) {
  return String(value || "").trim();
}

function normalizedTicketPaymentState(value) {
  return paymentStatusValue(value).replace(/[_\s-]+/g, "").toLowerCase();
}

function isReservationOrder(order) {
  const paymentState = normalizedTicketPaymentState(order && order.paymentStatus);
  return paymentState === "cashatgate";
}

function orderHasIssuedTickets(order) {
  const tickets = order && order.tickets;
  if (!tickets) {
    return false;
  }
  if (Array.isArray(tickets)) {
    return tickets.length > 0;
  }
  if (typeof tickets === "object") {
    return Object.keys(tickets).length > 0;
  }
  return false;
}

function shouldSendPaidTicketConfirmation(order) {
  const paymentState = normalizedTicketPaymentState(order && order.paymentStatus);
  return paymentState === "paid" && orderHasIssuedTickets(order);
}

async function sendTicketOrderNotification({ orderId, order, reservation }) {
  const eventId = safeString(order.eventId);
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) {
    return;
  }

  const eventData = eventSnap.data() || {};
  const distribution = eventData.distribution || {};
  const buyerId = safeString(order.buyerId);
  const userSnap = buyerId ? await db.collection("users").doc(buyerId).get() : null;
  const user = userSnap && userSnap.exists ? userSnap.data() || {} : null;
  const prefs = user && user.notificationPrefs ? user.notificationPrefs : {};
  const eventTitle = safeString(order.eventTitle || eventData.title, "your event");
  const body = reservation
    ? `Your reservation for ${eventTitle} is saved. Pay at the gate to activate entry.`
    : `Your ${eventTitle} tickets are confirmed and ready for entry.`;

  if (
    distribution.sendPushNotification !== false &&
    buyerId &&
    user &&
    prefs.pushEnabled !== false &&
    user.fcmToken
  ) {
    await queuePushNotification({
      kind: reservation ? "event_ticket_reservation" : "event_ticket_confirmation",
      targets: [buyerId],
      payload: {
        title: reservation ? "Reservation created" : "Tickets confirmed",
        body,
        eventId,
        orderId,
        route: `/tickets/${orderId}`,
        link: `https://vennuzo.app/ticket/${encodeURIComponent(orderId)}`,
      },
      eventId,
    });
  }

  const phone = normalizePhoneNumber(order.buyerPhone || (user && user.phone));
  if (distribution.sendSmsNotification !== false && phone && (!user || prefs.smsEnabled !== false)) {
    const hubtelCfg = await getHubtelSmsConfig();
    await sendHubtelSms({
      to: phone,
      message:
        `${reservation ? "Reservation created" : "Tickets confirmed"}: ${body} ` +
        `https://vennuzo.app/ticket/${encodeURIComponent(orderId)}`,
      reference: `order_${orderId}`,
      hubtelCfg,
    });
  }

  await notifyOrganizersOfEventActivity({
    eventId,
    eventData,
    title: reservation ? "New reservation" : "New ticket sale",
    body: reservation
      ? `A reservation was made for ${eventTitle}.`
      : `Tickets were sold for ${eventTitle}.`,
    kind: reservation ? "organizer_reservation_alert" : "organizer_ticket_alert",
  });
}

function pickPhone(data, fieldNames) {
  for (const fieldName of fieldNames) {
    const value = fieldName
      .split(".")
      .reduce((current, part) => (current && current[part] != null ? current[part] : null), data);
    const normalized = normalizePhoneNumber(value);
    if (normalized) {
      return normalized;
    }
  }
  return null;
}

async function sendHubtelSms({ to, message, reference, hubtelCfg }) {
  const normalizedPhone = normalizePhoneNumber(to);
  if (!normalizedPhone || !isValidGhanaMobileNumber(normalizedPhone)) {
    throw new Error(`Invalid Ghana mobile number: ${to}`);
  }

  const config = hubtelCfg || await getHubtelSmsConfig();
  const payload = {
    From: String(config.senderId || "Vennuzo").substring(0, 11),
    To: normalizedPhone,
    Content: String(message || "").trim().slice(0, 459),
    ClientReference: safeString(reference, `evt_${Date.now()}`),
  };

  const basicAuth = Buffer.from(`${config.clientId}:${config.clientSecret}`).toString("base64");
  const response = await fetch("https://smsc.hubtel.com/v1/messages/send", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basicAuth}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch (error) {
    body = { raw: text };
  }

  if (response.ok && hubtelResponseLooksSuccessful(body)) {
    return {
      success: true,
      normalizedPhone,
      providerResponse: body,
    };
  }

  const fallbackUrl =
    "https://sms.hubtel.com/v1/messages/send?" +
    new URLSearchParams({
      clientid: config.clientId,
      clientsecret: config.clientSecret,
      from: payload.From,
      to: normalizedPhone,
      content: payload.Content,
    }).toString();

  const fallbackResponse = await fetch(fallbackUrl, { method: "GET" });
  const fallbackText = await fallbackResponse.text();
  let fallbackBody;
  try {
    fallbackBody = JSON.parse(fallbackText);
  } catch (error) {
    fallbackBody = { raw: fallbackText };
  }

  if (!fallbackResponse.ok || !hubtelResponseLooksSuccessful(fallbackBody)) {
    throw new Error(`Hubtel SMS failed: ${JSON.stringify(fallbackBody || body)}`);
  }

  return {
    success: true,
    normalizedPhone,
    providerResponse: fallbackBody,
  };
}

function hubtelResponseLooksSuccessful(body) {
  if (!body) {
    return false;
  }

  if (body.status === 0 || body.Status === 0) {
    return true;
  }

  if (body.messageId || body.MessageId || body.messageid) {
    return true;
  }

  const statusText = safeString(
    body.status || body.Status || body.message || body.Message || body.ResponseCode,
  ).toLowerCase();
  return statusText.includes("success") || statusText === "0";
}

async function removeInvalidFcmTokens(tokenList) {
  if (!Array.isArray(tokenList) || tokenList.length === 0) {
    return;
  }

  for (let index = 0; index < tokenList.length; index += 10) {
    const chunk = tokenList.slice(index, index + 10);
    const snap = await db.collection("users").where("fcmToken", "in", chunk).get();
    if (snap.empty) {
      continue;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        fcmToken: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

async function queuePushNotification({
  kind,
  targets,
  payload,
  campaignId,
  eventId,
}) {
  if (!Array.isArray(targets) || targets.length === 0) {
    return null;
  }

  const queueRef = db.collection("push_queue").doc();
  await queueRef.set({
    kind,
    status: "pending",
    targets: Array.from(new Set(targets)),
    payload,
    eventId: eventId || payload.eventId || null,
    campaignId: campaignId || null,
    androidChannel: "vennuzo_event_updates",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return queueRef.id;
}

/** Resolve organizer UIDs for an event who have push enabled and fcmToken (so they can receive admin alerts). */
async function getOrganizerPushTargets(eventData) {
  const createdBy = safeString(eventData.createdBy);
  if (!createdBy) {
    return [];
  }

  const userSnap = await db.collection("users").doc(createdBy).get();
  if (!userSnap.exists) {
    return [];
  }

  const user = userSnap.data() || {};
  const prefs = user.notificationPrefs || {};
  if (prefs.pushEnabled === false || !user.fcmToken) {
    return [];
  }

  return [createdBy];
}

/** Send a push to event organizers (e.g. new RSVP or ticket sale). */
async function notifyOrganizersOfEventActivity({
  eventId,
  eventData,
  title,
  body,
  kind,
}) {
  const targets = await getOrganizerPushTargets(eventData);
  if (targets.length === 0) {
    return;
  }

  await queuePushNotification({
    kind: kind || "organizer_alert",
    targets,
    payload: {
      title,
      body,
      eventId,
      route: `/events/${eventId}`,
    },
    eventId,
  });
}

/** Resolve superadmin UIDs who have push enabled and fcmToken (for admin alerts). Optionally exclude UIDs. */
async function getSuperAdminPushTargets(options = {}) {
  const excludeUids = new Set(options.excludeUids || []);
  const adminSnap = await db.collection("admins").get();
  const uids = [];
  for (const doc of adminSnap.docs) {
    const data = doc.data() || {};
    const role = safeString(data.role).toLowerCase();
    if (role !== "superadmin") {
      continue;
    }
    const uid = doc.id;
    if (excludeUids.has(uid)) {
      continue;
    }
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      continue;
    }
    const user = userSnap.data() || {};
    const prefs = user.notificationPrefs || {};
    if (prefs.pushEnabled === false || !user.fcmToken) {
      continue;
    }
    uids.push(uid);
  }
  return uids;
}

/** Send a push to all superadmins (e.g. new organizer application, admin created). */
async function notifySuperAdmins({
  title,
  body,
  route,
  kind,
  applicationId,
  eventId,
  excludeUids,
}) {
  const targets = await getSuperAdminPushTargets({ excludeUids });
  if (targets.length === 0) {
    return;
  }

  const payload = {
    title,
    body,
    route: route || "/admin/approvals",
  };
  if (applicationId) {
    payload.applicationId = applicationId;
  }
  if (eventId) {
    payload.eventId = eventId;
  }

  await queuePushNotification({
    kind: kind || "superadmin_alert",
    targets,
    payload,
  });
}

/** Notify a single user by UID (e.g. applicant when application is reviewed). */
async function notifyUserPush(uid, { title, body, route, kind }) {
  if (!uid) {
    return;
  }
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    return;
  }
  const user = userSnap.data() || {};
  const prefs = user.notificationPrefs || {};
  if (prefs.pushEnabled === false || !user.fcmToken) {
    return;
  }
  await queuePushNotification({
    kind: kind || "user_alert",
    targets: [uid],
    payload: { title, body, route: route || "/" },
  });
}

exports.notifySuperAdmins = notifySuperAdmins;
exports.notifyUserPush = notifyUserPush;

async function getEventAudience({ eventId, marketingOnly = false }) {
  const [rsvpSnap, orderSnap] = await Promise.all([
    db.collection("event_rsvps").where("eventId", "==", eventId).limit(1000).get(),
    db.collection("event_ticket_orders").where("eventId", "==", eventId).limit(1000).get(),
  ]);

  const candidates = [];
  for (const doc of rsvpSnap.docs) {
    const data = doc.data() || {};
    candidates.push({
      uid: safeString(data.userId || data.uid),
      phone: pickPhone(data, ["phone", "buyerPhone"]),
      name: safeString(data.name || data.fullName, "Eventora guest"),
    });
  }

  for (const doc of orderSnap.docs) {
    const data = doc.data() || {};
    const status = paymentStatusValue(data.paymentStatus || data.status).toLowerCase();
    if (!["paid", "cashatgate", "cashatgatepaid", "complimentary", "reserved"].includes(status.replace(/_/g, ""))) {
      continue;
    }
    candidates.push({
      uid: safeString(data.buyerId || data.userId),
      phone: pickPhone(data, [
        "buyerPhone",
        "paymentDetails.customerPhoneNumber",
        "paymentDetails.mobileMoneyNumber",
      ]),
      name: safeString(data.buyerName || data.customerName, "Eventora attendee"),
    });
  }

  const uniqueUids = [...new Set(candidates.map((candidate) => candidate.uid).filter(Boolean))];
  const userEntries = await Promise.all(
    uniqueUids.map(async (uid) => {
      const userSnap = await db.collection("users").doc(uid).get();
      return [uid, userSnap.exists ? userSnap.data() || {} : null];
    }),
  );
  const usersByUid = new Map(userEntries);

  const audienceMap = new Map();
  for (const candidate of candidates) {
    const uid = safeString(candidate.uid);
    const normalizedPhone = normalizePhoneNumber(candidate.phone);
    const dedupeKey = uid ? `uid:${uid}` : normalizedPhone ? `phone:${normalizedPhone}` : null;
    if (!dedupeKey) {
      continue;
    }

    const user = uid ? usersByUid.get(uid) : null;
    const prefs = user && user.notificationPrefs ? user.notificationPrefs : {};
    const marketingOptIn = prefs.marketingOptIn === true;
    if (marketingOnly && !marketingOptIn) {
      continue;
    }

    const existing = audienceMap.get(dedupeKey) || {
      uid: uid || null,
      phone: normalizedPhone,
      name: candidate.name,
      allowPush: false,
      allowSms: false,
    };

    const allowPush =
      Boolean(uid) &&
      Boolean(user && user.fcmToken) &&
      prefs.pushEnabled !== false;
    const allowSms =
      Boolean(normalizedPhone) &&
      (marketingOnly ? marketingOptIn : true) &&
      (user ? prefs.smsEnabled !== false : !marketingOnly);

    audienceMap.set(dedupeKey, {
      uid: existing.uid || uid || null,
      phone: existing.phone || normalizedPhone || null,
      name: existing.name || candidate.name,
      allowPush: existing.allowPush || allowPush,
      allowSms: existing.allowSms || allowSms,
    });
  }

  const audience = [...audienceMap.values()];
  const phones = [...new Set(audience.map((e) => e.phone).filter(Boolean))];
  const optedOutPhones = await getSmsOptedOutPhones(phones);
  if (optedOutPhones.size === 0) {
    return audience;
  }
  return audience.map((entry) =>
    entry.phone && optedOutPhones.has(entry.phone)
      ? { ...entry, allowSms: false }
      : entry,
  );
}

const SMS_OPT_OUT_BATCH = 30;

async function getSmsOptedOutPhones(phoneList) {
  if (!Array.isArray(phoneList) || phoneList.length === 0) {
    return new Set();
  }
  const normalized = phoneList.map((p) => normalizePhoneNumber(p)).filter(Boolean);
  const unique = [...new Set(normalized)];
  const optedOut = new Set();
  for (let i = 0; i < unique.length; i += SMS_OPT_OUT_BATCH) {
    const chunk = unique.slice(i, i + SMS_OPT_OUT_BATCH);
    const refs = chunk.map((phone) => db.collection("sms_opt_out").doc(phone));
    const snap = await db.getAll(...refs);
    for (const doc of snap) {
      if (doc.exists) {
        optedOut.add(doc.id);
      }
    }
  }
  return optedOut;
}

async function assertEventManager(uid, eventData) {
  const createdBy = safeString(eventData.createdBy);
  if (createdBy === uid) {
    return;
  }

  const organizationId = safeString(eventData.organizationId);
  if (!organizationId) {
    throw new HttpsError("permission-denied", "You do not have access to this event.");
  }

  if (organizationId === `org_${uid}`) {
    return;
  }

  const membershipSnap = await db.collection("organization_members").doc(`${organizationId}_${uid}`).get();
  if (!membershipSnap.exists) {
    throw new HttpsError("permission-denied", "You do not have access to this event.");
  }

  const membership = membershipSnap.data() || {};
  if (membership.status !== "active") {
    throw new HttpsError("permission-denied", "Your organization access is not active.");
  }
}

function normalizeChannels(channels) {
  const values = Array.isArray(channels) ? channels : [];
  return [...new Set(values.map((channel) => safeString(channel).toLowerCase()))].filter((value) =>
    ["push", "sms", "sharelink", "featured"].includes(value),
  );
}

async function dispatchNotificationJob(jobRef, jobData) {
  const queueRef = jobRef || db.collection("notification_jobs").doc(jobData.jobId);
  await queueRef.set(
    {
      status: "processing",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  try {
    const eventId = safeString(jobData.eventId);
    const audience = await getEventAudience({
      eventId,
      marketingOnly: jobData.marketingOnly === true,
    });

    const eventSnap = await db.collection("events").doc(eventId).get();
    const eventData = eventSnap.exists ? eventSnap.data() || {} : {};
    const distribution = eventData.distribution || {};

    if (jobData.type === "push") {
      const targets = audience.filter((entry) => entry.allowPush).map((entry) => entry.uid).filter(Boolean);
      if (targets.length === 0) {
        await queueRef.set(
          {
            status: "skipped",
            result: { sentCount: 0, failedCount: 0, reason: "No push-eligible audience" },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } else {
        const queueId = await queuePushNotification({
          kind: "event_campaign",
          targets,
          payload: jobData.payload || {},
          campaignId: jobData.campaignId || null,
          eventId,
        });
        await queueRef.set(
          {
            status: "sent",
            result: { sentCount: targets.length, failedCount: 0, queueId },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    } else if (jobData.type === "sms") {
      if (distribution.sendSmsNotification === false) {
        await queueRef.set(
          {
            status: "skipped",
            result: { sentCount: 0, failedCount: 0, reason: "Event SMS disabled" },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } else {
        const recipients = audience
          .filter((entry) => entry.allowSms && entry.phone)
          .slice(0, MAX_SMS_RECIPIENTS_PER_JOB);

        const hubtelCfg = await getHubtelSmsConfig();
        let sentCount = 0;
        let failedCount = 0;
        for (const recipient of recipients) {
          try {
            const title = safeString(jobData.payload && jobData.payload.title, "Event update");
            const body = safeString(jobData.payload && jobData.payload.body);
            const smsMessage = `${title}: ${body}`.trim();
            await sendHubtelSms({
              to: recipient.phone,
              message: smsMessage,
              reference: `${safeString(jobData.campaignId, "job")}_${Date.now()}`,
              hubtelCfg,
            });
            sentCount += 1;
          } catch (error) {
            failedCount += 1;
            console.error("Eventora SMS job failed for recipient", recipient.phone, error);
          }
        }

        await queueRef.set(
          {
            status: failedCount > 0 && sentCount === 0 ? "failed" : "sent",
            result: { sentCount, failedCount },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        if (sentCount > 0) {
          try {
            const campaignSnap = await db.collection("promotion_campaigns").doc(safeString(jobData.campaignId)).get();
            const campaignData = campaignSnap.exists ? campaignSnap.data() || {} : {};
            const packageId = safeString(campaignData.packageId);
            const pricing = await getPricingConfig(packageId || undefined);
            await chargeCampaignSms(
              safeString(jobData.campaignId),
              queueRef.id,
              sentCount,
              pricing.platformSmsUnitPriceGhs,
            );
          } catch (err) {
            console.error("Campaign SMS charge failed", jobData.campaignId, queueRef.id, err);
          }
        }
      }
    } else {
      await queueRef.set(
        {
          status: "skipped",
          result: { sentCount: 0, failedCount: 0, reason: "No delivery needed for this channel" },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await refreshCampaignStatus(jobData.campaignId);
  } catch (error) {
    console.error("Notification job failed", queueRef.id, error);
    await queueRef.set(
      {
        status: "failed",
        error: safeString(error && error.message, "Notification job failed"),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await refreshCampaignStatus(jobData.campaignId);
  }
}

async function refreshCampaignStatus(campaignId) {
  if (!campaignId) {
    return;
  }

  const pendingSnap = await db
    .collection("notification_jobs")
    .where("campaignId", "==", campaignId)
    .where("status", "in", ["queued", "processing"])
    .limit(10)
    .get();

  const failedSnap = await db
    .collection("notification_jobs")
    .where("campaignId", "==", campaignId)
    .where("status", "==", "failed")
    .limit(10)
    .get();

  let status = "completed";
  if (!pendingSnap.empty) {
    status = "live";
  } else if (!failedSnap.empty) {
    status = "completed";
  }

  await db.collection("promotion_campaigns").doc(campaignId).set(
    {
      status,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (status === "completed") {
    try {
      await finalizeCampaignWallet(campaignId);
    } catch (err) {
      console.error("Finalize campaign wallet failed", campaignId, err);
    }
  }
}

exports.processPushQueue = onDocumentCreated(
  {
    document: "push_queue/{queueId}",
    region: REGION,
  },
  async (event) => {
    const queueDoc = event.data;
    if (!queueDoc) {
      return;
    }

    const queueId = event.params.queueId;
    const data = queueDoc.data() || {};
    const targets = Array.isArray(data.targets) ? data.targets.filter(Boolean) : [];
    const queueRef = db.collection("push_queue").doc(queueId);

    if (targets.length === 0) {
      await queueRef.set(
        {
          status: "skipped",
          error: "No push targets were provided.",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const userSnaps = await Promise.all(
      targets.map((uid) => db.collection("users").doc(uid).get()),
    );
    const tokenMap = [];
    for (const snap of userSnaps) {
      if (!snap.exists) {
        continue;
      }
      const token = safeString(snap.data() && snap.data().fcmToken);
      if (!token) {
        continue;
      }
      tokenMap.push({
        uid: snap.id,
        token,
      });
    }

    if (tokenMap.length === 0) {
      await queueRef.set(
        {
          status: "skipped",
          error: "No valid FCM tokens were found for the requested users.",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const payload = data.payload || {};
    const response = await messaging.sendEachForMulticast({
      tokens: tokenMap.map((entry) => entry.token),
      notification: {
        title: safeString(payload.title, "Vennuzo"),
        body: safeString(payload.body, "You have a new event update."),
      },
      data: {
        ...Object.fromEntries(
          Object.entries(payload).map(([key, value]) => [key, String(value)]),
        ),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "vennuzo_event_updates",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    const invalidTokens = [];
    const results = [];
    response.responses.forEach((result, index) => {
      const entry = tokenMap[index];
      if (result.success) {
        results.push({ uid: entry.uid, success: true });
        return;
      }
      const code = safeString(result.error && result.error.code);
      results.push({
        uid: entry.uid,
        success: false,
        code,
        message: safeString(result.error && result.error.message),
      });
      if (INVALID_TOKEN_CODES.has(code)) {
        invalidTokens.push(entry.token);
      }
    });

    if (invalidTokens.length > 0) {
      await removeInvalidFcmTokens(invalidTokens);
    }

    const status =
      response.failureCount > 0
        ? response.successCount > 0
          ? "partial"
          : "failed"
        : "sent";
    await queueRef.set(
      {
        status,
        sentCount: response.successCount,
        failedCount: response.failureCount,
        processedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        results,
      },
      { merge: true },
    );

    if (
      status === "failed" ||
      (response.failureCount >= 5 && response.failureCount >= response.successCount)
    ) {
      await notifySuperAdmins({
        title: "Delivery issues",
        body: `High push failure rate: ${response.failureCount} failed, ${response.successCount} sent. Check logs.`,
        route: "/admin/settings",
        kind: "superadmin_push_delivery_alert",
      });
    }
  },
);

exports.recordSmsOptOut = onCall(
  {
    region: REGION,
    timeoutSeconds: 30,
  },
  async (request) => {
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    if (!phone || !isValidGhanaMobileNumber(phone)) {
      throw new HttpsError("invalid-argument", "A valid Ghana mobile number is required to opt out.");
    }
    const ref = db.collection("sms_opt_out").doc(phone);
    await ref.set(
      {
        phone,
        createdAt: FieldValue.serverTimestamp(),
        source: safeString(request.data && request.data.source, "user"),
      },
      { merge: true },
    );
    return { success: true, phone };
  },
);

exports.recordSmsOptOutPublic = onRequest(
  {
    region: REGION,
    timeoutSeconds: 30,
    cors: ["https://vennuzo.com", "https://www.vennuzo.com"],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }
    // Rate limit by IP: max 10 opt-out requests per IP per minute
    const ip = String(req.headers["x-forwarded-for"] || req.ip || "unknown").split(",")[0].trim();
    try {
      await checkRateLimit(db, `ip_${ip}`, "smsOptOutPublic", { maxCalls: 10, windowSeconds: 60 });
    } catch (err) {
      if (err && err.code === "resource-exhausted") {
        res.status(429).json({ error: "Too many requests. Please try again shortly." });
        return;
      }
    }
    let phone;
    try {
      const body = typeof req.body === "object" ? req.body : {};
      phone = normalizePhoneNumber(body.phone || body.Phone || req.query.phone);
    } catch (e) {
      res.status(400).json({ error: "Invalid request. Send JSON: { \"phone\": \"0XX XXX XXXX\" }" });
      return;
    }
    if (!phone || !isValidGhanaMobileNumber(phone)) {
      res.status(400).json({ error: "A valid Ghana mobile number is required to opt out." });
      return;
    }
    const ref = db.collection("sms_opt_out").doc(phone);
    await ref.set(
      {
        phone,
        createdAt: FieldValue.serverTimestamp(),
        source: "public_form",
      },
      { merge: true },
    );
    res.status(200).json({ success: true, message: "You have been unsubscribed from Vennuzo SMS." });
  },
);

exports.getEventAudienceEstimate = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to view audience estimate.");
    }
    const eventId = safeString(request.data && request.data.eventId);
    if (!eventId) {
      throw new HttpsError("invalid-argument", "eventId is required.");
    }
    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }
    const eventData = eventSnap.data() || {};
    await assertEventManager(request.auth.uid, eventData);
    const audience = await getEventAudience({ eventId, marketingOnly: true });
    const pushCount = audience.filter((e) => e.allowPush).length;
    const smsCount = audience.filter((e) => e.allowSms).length;
    const packageId = safeString(request.data && request.data.packageId);
    const pricing = await getPricingConfig(packageId || undefined);
    const estimatedSmsCostGhs = Math.round(smsCount * pricing.platformSmsUnitPriceGhs * 100) / 100;
    return {
      pushCount,
      smsCount,
      platformSmsUnitPriceGhs: pricing.platformSmsUnitPriceGhs,
      estimatedSmsCostGhs,
    };
  },
);

exports.listPromoPackages = onCall(
  {
    region: REGION,
    timeoutSeconds: 30,
  },
  async () => {
    const snap = await db
      .collection("promo_packages")
      .where("active", "==", true)
      .orderBy("order", "asc")
      .limit(20)
      .get();
    return {
      packages: snap.docs.map((docSnap) => {
        const d = docSnap.data() || {};
        return {
          id: docSnap.id,
          name: safeString(d.name, "Package"),
          description: safeString(d.description),
          defaultSmsRateGhs: Number(d.defaultSmsRateGhs) || DEFAULT_SMS_RATE_GHS,
          smsMarginMultiplier: Number(d.smsMarginMultiplier) || DEFAULT_SMS_MARGIN_MULTIPLIER,
          minSpend: d.minSpend != null ? Number(d.minSpend) : undefined,
          order: Number(d.order) || 0,
        };
      }),
    };
  },
);

exports.launchEventNotificationCampaign = onCall(
  {
    region: REGION,
    timeoutSeconds: 540,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before launching campaigns.");
    }
    // Rate limit: max 10 campaigns per organizer per hour
    await checkRateLimit(db, request.auth.uid, "launchCampaign", { maxCalls: 10, windowSeconds: 3600 });

    const eventId = safeString(request.data && request.data.eventId);
    const message = safeString(request.data && request.data.message);
    const channels = normalizeChannels(request.data && request.data.channels);
    if (!eventId || !message || channels.length === 0) {
      throw new HttpsError("invalid-argument", "eventId, message, and channels are required.");
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "The selected event does not exist in Firestore yet.");
    }

    const eventData = eventSnap.data() || {};
    await assertEventManager(request.auth.uid, eventData);

    const organizationId = safeString(eventData.organizationId, `org_${request.auth.uid}`);
    const packageId = safeString(request.data && request.data.packageId);
    const audience = await getEventAudience({ eventId, marketingOnly: true });
    const pushCount = audience.filter((e) => e.allowPush).length;
    const smsCount = audience.filter((e) => e.allowSms).length;
    const pricing = await getPricingConfig(packageId || undefined);
    const hasSms = channels.includes("sms");
    const estimatedSmsCostGhs =
      hasSms && smsCount > 0
        ? Math.round(smsCount * pricing.platformSmsUnitPriceGhs * 100) / 100
        : 0;

    const scheduledAt = asDate(request.data && request.data.scheduledAt) || new Date();
    const campaignId = db.collection("promotion_campaigns").doc().id;
    const campaignRef = db.collection("promotion_campaigns").doc(campaignId);

    if (estimatedSmsCostGhs > 0) {
      try {
        await reserveCampaignBudget(organizationId, campaignId, estimatedSmsCostGhs);
      } catch (err) {
        const msg = safeString(err && err.message, "Insufficient wallet balance.");
        await notifySuperAdmins({
          title: "Budget alert",
          body: `Campaign could not reserve SMS budget for "${safeString(eventData.title)}": ${msg}`,
          route: "/admin/campaigns",
          kind: "superadmin_budget_campaign_reserve_failed",
          eventId,
        });
        throw err;
      }
    }

    const title = safeString(
      request.data && request.data.title,
      `${safeString(eventData.title, "Vennuzo")} update`,
    );
    const isScheduled = scheduledAt.getTime() > Date.now() + 30000;
    const shareLink = await buildEventLink(eventId, eventData);

    const jobSpecs = channels
      .filter((channel) => channel === "push" || channel === "sms")
      .map((channel) => ({
        ref: db.collection("notification_jobs").doc(),
        data: {
          organizationId,
          eventId,
          campaignId,
          type: channel,
          status: "queued",
          marketingOnly: true,
          scheduledAt: Timestamp.fromDate(scheduledAt),
          payload: {
            title,
            body: message,
            eventId,
            eventTitle: safeString(eventData.title),
            route: `/events/${eventId}`,
            link: shareLink,
          },
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      }));

    const batch = db.batch();
    batch.set(
      campaignRef,
      {
        eventId,
        occurrenceId: safeString(request.data && request.data.occurrenceId, `${eventId}_primary`),
        organizationId,
        eventTitle: safeString(eventData.title),
        name: safeString(request.data && request.data.name, `${safeString(eventData.title)} campaign`),
        status: isScheduled ? "scheduled" : "live",
        channels: channels.map((channel) => (channel === "sharelink" ? "shareLink" : channel)),
        scheduledAt: Timestamp.fromDate(scheduledAt),
        pushAudience: pushCount,
        smsAudience: smsCount,
        shareLinkEnabled: request.data && request.data.shareLinkEnabled === true,
        budget: estimatedSmsCostGhs,
        walletReservationAmount: estimatedSmsCostGhs,
        packageId: packageId || null,
        message,
        createdBy: request.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    for (const job of jobSpecs) {
      batch.set(job.ref, job.data);
    }
    await batch.commit();

    if (!isScheduled) {
      for (const job of jobSpecs) {
        await dispatchNotificationJob(job.ref, job.data);
      }
    }

    await notifySuperAdmins({
      title: "Campaign launched",
      body: `A campaign was launched for ${safeString(eventData.title, "an event")}.`,
      route: "/admin/campaigns",
      kind: "superadmin_campaign_launched",
    });

    return {
      campaignId,
      jobsCreated: jobSpecs.length,
      status: isScheduled ? "scheduled" : "live",
    };
  },
);

exports.processNotificationJobs = onSchedule(
  {
    schedule: "*/5 * * * *",
    timeZone: TIME_ZONE,
    region: REGION,
  },
  async () => {
    const now = Timestamp.now();
    const snap = await db
      .collection("notification_jobs")
      .where("status", "==", "queued")
      .where("scheduledAt", "<=", now)
      .limit(MAX_JOB_BATCH)
      .get();

    for (const doc of snap.docs) {
      await dispatchNotificationJob(doc.ref, doc.data() || {});
    }
  },
);

exports.processEventReminderNotifications = onSchedule(
  {
    schedule: "*/15 * * * *",
    timeZone: TIME_ZONE,
    region: REGION,
  },
  async () => {
    const now = Timestamp.now();
    const reminderSnap = await db
      .collection("event_reminders")
      .where("status", "==", "scheduled")
      .where("scheduledAt", "<=", now)
      .limit(MAX_REMINDER_BATCH)
      .get();

    for (const doc of reminderSnap.docs) {
      const reminder = doc.data() || {};
      try {
        const eventId = safeString(reminder.eventId);
        const eventSnap = await db.collection("events").doc(eventId).get();
        if (!eventSnap.exists) {
          await doc.ref.set(
            {
              status: "cancelled",
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          continue;
        }

        const eventData = eventSnap.data() || {};
        const distribution = eventData.distribution || {};
        const userId = safeString(reminder.userId);
        const userSnap = userId ? await db.collection("users").doc(userId).get() : null;
        const user = userSnap && userSnap.exists ? userSnap.data() || {} : null;
        const prefs = user && user.notificationPrefs ? user.notificationPrefs : {};
        const eventTitle = safeString(reminder.eventTitle || eventData.title, "your event");
        const body =
          `${eventTitle} is coming up ${titleCaseTiming(reminder.timing)}. ` +
          `Starts ${formatEventDate(eventData.startAt)}.`;
        const shareLink = await buildEventLink(eventId, eventData);

        if (distribution.sendPushNotification !== false && userId && user && prefs.pushEnabled !== false && user.fcmToken) {
          await queuePushNotification({
            kind: "event_reminder",
            targets: [userId],
            payload: {
              title: `Reminder: ${eventTitle}`,
              body,
              eventId,
              route: `/events/${eventId}`,
              link: shareLink,
            },
            eventId,
          });
        }

        const reminderPhone = normalizePhoneNumber(reminder.phone || (user && user.phone));
        if (distribution.sendSmsNotification !== false && reminderPhone && prefs.smsEnabled !== false) {
          const hubtelCfg = await getHubtelSmsConfig();
          await sendHubtelSms({
            to: reminderPhone,
            message: `${eventTitle} reminder: ${body} ${shareLink}`,
            reference: `reminder_${doc.id}`,
            hubtelCfg,
          });
        }

        await doc.ref.set(
          {
            status: "sent",
            sentAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } catch (error) {
        console.error("Reminder dispatch failed", doc.id, error);
        await doc.ref.set(
          {
            status: "failed",
            error: safeString(error && error.message, "Reminder dispatch failed"),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }
  },
);

exports.onEventRsvpCreated = onDocumentCreated(
  {
    document: "event_rsvps/{rsvpId}",
    region: REGION,
  },
  async (event) => {
    const rsvpDoc = event.data;
    if (!rsvpDoc) {
      return;
    }

    const rsvp = rsvpDoc.data() || {};
    const eventId = safeString(rsvp.eventId);
    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      return;
    }

    const eventData = eventSnap.data() || {};
    const distribution = eventData.distribution || {};
    const userId = safeString(rsvp.userId);
    const userSnap = userId ? await db.collection("users").doc(userId).get() : null;
    const user = userSnap && userSnap.exists ? userSnap.data() || {} : null;
    const prefs = user && user.notificationPrefs ? user.notificationPrefs : {};
    const eventTitle = safeString(rsvp.eventTitle || eventData.title, "your event");
    const body = `Your RSVP is confirmed for ${eventTitle} on ${formatEventDate(eventData.startAt)}.`;
    const shareLink = await buildEventLink(eventId, eventData);

    if (distribution.sendPushNotification !== false && userId && user && prefs.pushEnabled !== false && user.fcmToken) {
      await queuePushNotification({
        kind: "event_rsvp_confirmation",
        targets: [userId],
        payload: {
          title: "RSVP confirmed",
          body,
          eventId,
          route: `/events/${eventId}`,
          link: shareLink,
        },
        eventId,
      });
    }

    const phone = normalizePhoneNumber(rsvp.phone || (user && user.phone));
    if (distribution.sendSmsNotification !== false && phone && (!user || prefs.smsEnabled !== false)) {
      const hubtelCfg = await getHubtelSmsConfig();
      await sendHubtelSms({
        to: phone,
        message: `RSVP confirmed: ${body} ${shareLink}`,
        reference: `rsvp_${rsvpDoc.id}`,
        hubtelCfg,
      });
    }

    await notifyOrganizersOfEventActivity({
      eventId,
      eventData,
      title: "New RSVP",
      body: `Someone just RSVP'd to ${eventTitle}.`,
      kind: "organizer_rsvp_alert",
    });
  },
);

exports.onEventTicketOrderCreated = onDocumentCreated(
  {
    document: "event_ticket_orders/{orderId}",
    region: REGION,
  },
  async (event) => {
    const orderDoc = event.data;
    if (!orderDoc) {
      return;
    }

    const order = orderDoc.data() || {};
    if (!isReservationOrder(order)) {
      return;
    }

    await sendTicketOrderNotification({
      orderId: orderDoc.id,
      order,
      reservation: true,
    });
  },
);

exports.onEventTicketOrderUpdated = onDocumentUpdated(
  {
    document: "event_ticket_orders/{orderId}",
    region: REGION,
  },
  async (event) => {
    const beforeDoc = event.data.before;
    const afterDoc = event.data.after;
    if (!beforeDoc.exists || !afterDoc.exists) {
      return;
    }

    const before = beforeDoc.data() || {};
    const after = afterDoc.data() || {};
    if (!shouldSendPaidTicketConfirmation(after) || shouldSendPaidTicketConfirmation(before)) {
      return;
    }

    await sendTicketOrderNotification({
      orderId: afterDoc.id,
      order: after,
      reservation: false,
    });
  },
);

function notifySuperAdminsOrganizerApplication(applicationId, applicationData) {
  const organizerName = safeString(
    applicationData.organizerName || applicationData.organization || "An organizer",
  );
  return notifySuperAdmins({
    title: "New organizer application",
    body: `${organizerName} submitted an application for review.`,
    route: "/admin/approvals",
    kind: "superadmin_organizer_application",
    applicationId,
  });
}

const WALLET_LOW_BALANCE_THRESHOLD_GHS = 20;

exports.onAdvertiserWalletLowBalance = onDocumentUpdated(
  {
    document: "advertiser_wallets/{walletId}",
    region: REGION,
  },
  async (event) => {
    if (!event.data.before.exists || !event.data.after.exists) {
      return;
    }
    const beforeBal = Number(event.data.before.data().availableBalance ?? 0);
    const afterBal = Number(event.data.after.data().availableBalance ?? 0);
    if (afterBal >= WALLET_LOW_BALANCE_THRESHOLD_GHS) {
      return;
    }
    if (beforeBal < WALLET_LOW_BALANCE_THRESHOLD_GHS) {
      return;
    }
    await notifySuperAdmins({
      title: "Budget alert",
      body: `Organization wallet ${event.params.walletId} fell below ${WALLET_LOW_BALANCE_THRESHOLD_GHS} GHS (${afterBal.toFixed(2)} GHS remaining).`,
      route: "/admin/settings",
      kind: "superadmin_wallet_low_balance",
    });
  },
);

exports.onEventReportCreated = onDocumentCreated(
  {
    document: "event_reports/{reportId}",
    region: REGION,
  },
  async (event) => {
    const d = event.data?.data() || {};
    const eventTitle = safeString(d.eventTitle, "An event");
    const reason = safeString(d.reason);
    const eventId = safeString(d.eventId);
    const snippet = reason.length > 100 ? `${reason.slice(0, 100)}…` : reason;
    await notifySuperAdmins({
      title: "Event reported",
      body: `"${eventTitle}" reported: ${snippet || "See admin queue."}`,
      route: "/admin/settings",
      kind: "superadmin_event_reported",
      eventId: eventId || undefined,
    });
  },
);

exports.onPayoutRequestCreated = onDocumentCreated(
  {
    document: "payout_requests/{requestId}",
    region: REGION,
  },
  async (event) => {
    const d = event.data?.data() || {};
    const org = safeString(d.organizationId);
    const amount = Number(d.amountGhs ?? d.amount ?? 0);
    const notes = safeString(d.notes || d.description);
    const noteSnippet = notes.length > 80 ? `${notes.slice(0, 80)}…` : notes;
    await notifySuperAdmins({
      title: "Payout request",
      body: `Organizer payout: ${amount.toFixed(2)} GHS for ${org || "unknown org"}.${noteSnippet ? ` ${noteSnippet}` : ""}`,
      route: "/admin/settings",
      kind: "superadmin_payout_request",
    });
  },
);

exports.onEventPublished = onDocumentUpdated(
  {
    document: "events/{eventId}",
    region: REGION,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.exists ? event.data.after.data() || {} : {};
    const afterStatus = safeString(after.status).toLowerCase();
    const beforeStatus = safeString(before.status).toLowerCase();
    if (afterStatus !== "published" || beforeStatus === "published") {
      return;
    }

    const eventTitle = safeString(after.title, "An event");
    await notifySuperAdmins({
      title: "New event live",
      body: `${eventTitle} is now live.`,
      route: "/admin/events",
      kind: "superadmin_event_published",
      eventId: event.params.eventId,
    });
  },
);

exports.onOrganizerApplicationCreated = onDocumentCreated(
  {
    document: "organizer_applications/{applicationId}",
    region: REGION,
  },
  async (event) => {
    const data = event.data?.data() || {};
    if (safeString(data.status).toLowerCase() !== "submitted") {
      return;
    }
    await notifySuperAdminsOrganizerApplication(event.params.applicationId, data);
  },
);

exports.onOrganizerApplicationSubmitted = onDocumentUpdated(
  {
    document: "organizer_applications/{applicationId}",
    region: REGION,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.exists ? event.data.after.data() || {} : {};
    const afterStatus = safeString(after.status).toLowerCase();
    const beforeStatus = safeString(before.status).toLowerCase();
    if (afterStatus !== "submitted" || beforeStatus === "submitted") {
      return;
    }
    await notifySuperAdminsOrganizerApplication(event.params.applicationId, after);
  },
);

exports.sendTestEventSms = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before sending a test SMS.");
    }

    const phone = safeString(request.data && request.data.phone);
    const message = safeString(
      request.data && request.data.message,
      "Eventora test SMS: Hubtel is connected and ready.",
    );
    if (!phone) {
      throw new HttpsError("invalid-argument", "A phone number is required.");
    }

    const result = await sendHubtelSms({
      to: phone,
      message,
      reference: `test_sms_${request.auth.uid}_${Date.now()}`,
    });
    return {
      success: true,
      to: result.normalizedPhone,
    };
  },
);

exports.sendTestEventPush = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before sending a test push.");
    }

    const targetUid = safeString(request.data && request.data.targetUid, request.auth.uid);
    const queueId = await queuePushNotification({
      kind: "event_test_push",
      targets: [targetUid],
      payload: {
        title: safeString(request.data && request.data.title, "Vennuzo test push"),
        body: safeString(
          request.data && request.data.body,
          "Push notifications are connected and ready.",
        ),
        route: "/",
      },
    });

    return {
      success: true,
      queueId,
      targetUid,
    };
  },
);
