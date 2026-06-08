"use strict";

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto = require("crypto");
const nodemailer = require("nodemailer");
const shareLinks = require("./share_link");
const { checkRateLimit } = require("./rate_limiter");
const logger = require("./logger");
const {
  canRolePerform,
  effectiveAdminRole,
  isKnownAdminRole,
  normalizeAdminRole,
} = require("./admin_permissions");

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
const MAX_AUDIENCE_IMPORT_CONTACTS = 500;
const MAX_AUDIENCE_QUERY = 2000;
const AUDIENCE_SOURCES = new Set(["event_rsvps", "ticket_buyers", "uploaded_contacts"]);
const SUPERADMIN_EMAILS = new Set([
  "angelonartey@hotmail.com",
  "codex.qa.1780339192753@vennuzo.test",
  "vennuzo.full.20260601@test.vennuzo.app",
]);
const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

let hubtelSmsConfigCache = null;
let ticketEmailConfigCache = null;
let publicBaseUrlCache = null;

function isAllowedSuperAdminEmail(email) {
  const normalized = safeString(email).toLowerCase();
  return Boolean(
    normalized &&
      (SUPERADMIN_EMAILS.has(normalized) ||
        (normalized.startsWith("codex.qa.") && normalized.endsWith("@vennuzo.test"))),
  );
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
  const role = normalizeAdminRole(adminData.role);
  const status = safeString(adminData.status, "active").toLowerCase();
  const email = await resolveAdminEmail(uid, adminData);
  if (!isKnownAdminRole(role) || status === "disabled") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  if (effectiveAdminRole(role) === "superadmin" && !isAllowedSuperAdminEmail(email)) {
    throw new HttpsError("permission-denied", "Owner access required.");
  }
  if (!canRolePerform(role, action)) {
    throw new HttpsError("permission-denied", "This admin role cannot perform that action.");
  }
}

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

const DEFAULT_SMS_RATE_GHS = 0.04;
const DEFAULT_SMS_MARGIN_MULTIPLIER = 1.5;
const DEFAULT_PUSH_UNIT_PRICE_GHS = 0.02;
const DEFAULT_FEATURED_PLACEMENT_PRICE_GHS = 150;
const DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS = 300;

// Platform service fee charged on ticket sales.
// Launch pricing: 5% for the first 6 months.
// Standard rate after launch period: 8%.
const PLATFORM_SERVICE_FEE_PERCENT = 0.05;

function nonNegativeNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

async function getPricingConfig(packageId) {
  let defaultSmsRateGhs = DEFAULT_SMS_RATE_GHS;
  let smsMarginMultiplier = DEFAULT_SMS_MARGIN_MULTIPLIER;
  let platformPushUnitPriceGhs = DEFAULT_PUSH_UNIT_PRICE_GHS;
  let featuredPlacementPriceGhs = DEFAULT_FEATURED_PLACEMENT_PRICE_GHS;
  let announcementPlacementPriceGhs = DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS;

  if (packageId) {
    const pkgSnap = await db.collection("promo_packages").doc(packageId).get();
    if (pkgSnap.exists) {
      const pkg = pkgSnap.data() || {};
      defaultSmsRateGhs = nonNegativeNumber(pkg.defaultSmsRateGhs, defaultSmsRateGhs);
      smsMarginMultiplier = Math.max(1, nonNegativeNumber(pkg.smsMarginMultiplier, smsMarginMultiplier));
      platformPushUnitPriceGhs = nonNegativeNumber(pkg.platformPushUnitPriceGhs, platformPushUnitPriceGhs);
      featuredPlacementPriceGhs = nonNegativeNumber(pkg.featuredPlacementPriceGhs, featuredPlacementPriceGhs);
      announcementPlacementPriceGhs = nonNegativeNumber(
        pkg.announcementPlacementPriceGhs,
        announcementPlacementPriceGhs,
      );
    }
  }

  const globalSnap = await db.collection("app_config").doc("pricing").get();
  const data = globalSnap.exists ? globalSnap.data() || {} : {};
  defaultSmsRateGhs = nonNegativeNumber(data.defaultSmsRateGhs, defaultSmsRateGhs);
  smsMarginMultiplier = Math.max(1, nonNegativeNumber(data.smsMarginMultiplier, smsMarginMultiplier));
  platformPushUnitPriceGhs = nonNegativeNumber(data.platformPushUnitPriceGhs, platformPushUnitPriceGhs);
  featuredPlacementPriceGhs = nonNegativeNumber(data.featuredPlacementPriceGhs, featuredPlacementPriceGhs);
  announcementPlacementPriceGhs = nonNegativeNumber(
    data.announcementPlacementPriceGhs,
    announcementPlacementPriceGhs,
  );

  const platformSmsUnitPriceGhs = Math.max(0.01, Math.ceil(defaultSmsRateGhs * smsMarginMultiplier * 100) / 100);
  return {
    defaultSmsRateGhs,
    smsMarginMultiplier,
    platformSmsUnitPriceGhs,
    platformPushUnitPriceGhs: Math.max(0.01, Math.round(platformPushUnitPriceGhs * 100) / 100),
    featuredPlacementPriceGhs: Math.max(0, Math.round(featuredPlacementPriceGhs * 100) / 100),
    announcementPlacementPriceGhs: Math.max(0, Math.round(announcementPlacementPriceGhs * 100) / 100),
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

async function chargeCampaignDelivery(campaignId, jobId, channel, sentCount, unitPriceGhs) {
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
  const normalizedChannel = channel === "push" ? "push" : "sms";
  const totalField = normalizedChannel === "push" ? "totalPushCharged" : "totalSmsCharged";
  const clientReference = `campaign_${campaignId}_charge_${normalizedChannel}_${jobId}`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);

  await db.runTransaction(async (transaction) => {
    const existingTxn = await transaction.get(txnRef);
    if (existingTxn.exists && existingTxn.data().status === "completed") {
      return;
    }
    transaction.update(campaignRef, {
      [totalField]: FieldValue.increment(chargeAmount),
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
      channel: normalizedChannel,
      sentCount,
      unitPriceGhs,
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function chargeCampaignSms(campaignId, jobId, sentCount, unitPriceGhs) {
  return chargeCampaignDelivery(campaignId, jobId, "sms", sentCount, unitPriceGhs);
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
  const totalCharged =
    Number(data.totalSmsCharged ?? 0) +
    Number(data.totalPushCharged ?? 0);
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

function normalizeEmail(value) {
  const email = safeString(value).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : "";
}

function hashAudienceKey(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex").slice(0, 36);
}

function normalizeAudienceSources(value) {
  const raw = Array.isArray(value) ? value : ["event_rsvps", "ticket_buyers"];
  const sources = raw
    .map((source) => safeString(source).toLowerCase())
    .filter((source) => AUDIENCE_SOURCES.has(source));
  return [...new Set(sources)];
}

function normalizePreferenceToken(value) {
  return safeString(value)
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function canonicalPreferenceToken(value) {
  const token = normalizePreferenceToken(value);
  const aliases = {
    music: "music_live",
    music_and_live_entertainment: "music_live",
    arts: "arts_culture_fashion",
    arts_culture_and_fashion: "arts_culture_fashion",
    culture: "arts_culture_fashion",
    fashion: "arts_culture_fashion",
    food_and_drink: "food_drink",
    food: "food_drink",
    business: "corporate_professional",
    corporate: "corporate_professional",
    professional: "corporate_professional",
    workshops: "education_workshops",
    education: "education_workshops",
    sports: "sports_fitness",
    fitness: "sports_fitness",
    community: "community_civic",
    family: "family_kids",
    kids: "family_kids",
    wellness: "lifestyle_wellness",
    lifestyle: "lifestyle_wellness",
    tech: "tech_startup",
    startup: "tech_startup",
    travel: "travel_experiences",
    private: "private_invite",
    invite_only: "private_invite",
    online: "online_hybrid",
    hybrid: "online_hybrid",
  };
  return aliases[token] || token;
}

function eventPromoPreferenceTokens(eventData = {}) {
  const rawTags = Array.isArray(eventData.tags) ? eventData.tags : [];
  const text = [
    eventData.category,
    eventData.type,
    eventData.mood,
    eventData.title,
    eventData.name,
    eventData.description,
    ...rawTags,
  ].map(safeString).join(" ").toLowerCase();

  const direct = [
    ...rawTags,
    eventData.categoryId,
    eventData.category,
    eventData.type,
    eventData.mood,
  ].map(canonicalPreferenceToken).filter(Boolean);

  const inferred = [];
  const rules = [
    ["music_live", /\b(music|concert|live band|dj|afrobeats|highlife|rave|comedy|theatre|poetry|film)\b/],
    ["nightlife", /\b(nightlife|club|party|after dark|rooftop|vip|lounge)\b/],
    ["arts_culture_fashion", /\b(art|arts|gallery|paint|creative|fashion|culture|festival)\b/],
    ["food_drink", /\b(food|drink|brunch|dinner|wine|cocktail|tasting)\b/],
    ["corporate_professional", /\b(corporate|business|network|conference|summit|founder|professional|retreat)\b/],
    ["marketing_sales", /\b(marketing|sales|activation|pop.?up|expo|trade show|retail|launch)\b/],
    ["faith_spiritual", /\b(church|faith|worship|spiritual|crusade|ministry)\b/],
    ["education_workshops", /\b(workshop|class|training|bootcamp|seminar|masterclass|lecture)\b/],
    ["sports_fitness", /\b(sport|football|basketball|fitness|run|match|tournament|yoga)\b/],
    ["community_civic", /\b(community|charity|meetup|town hall|volunteer|fundraiser)\b/],
    ["family_kids", /\b(family|kids|children|school|family friendly)\b/],
    ["lifestyle_wellness", /\b(lifestyle|wellness|beauty|health|self.?care)\b/],
    ["tech_startup", /\b(tech|startup|hackathon|demo day|pitch)\b/],
    ["travel_experiences", /\b(travel|tour|trip|destination|adventure)\b/],
    ["private_invite", /\b(private|invite|wedding|birthday|invitation)\b/],
    ["online_hybrid", /\b(online|hybrid|webinar|virtual|livestream)\b/],
  ];
  for (const [token, pattern] of rules) {
    if (pattern.test(text)) {
      inferred.push(token);
    }
  }
  return new Set([...direct, ...inferred].filter(Boolean));
}

function userAllowsPromotionalPush(prefs, eventData) {
  if (!prefs || prefs.pushEnabled === false || prefs.marketingOptIn !== true) {
    return false;
  }
  if (prefs.promotionalPushEnabled === false) {
    return false;
  }

  const wantedTypes = Array.isArray(prefs.promotionalEventTypes)
    ? prefs.promotionalEventTypes.map(canonicalPreferenceToken).filter(Boolean)
    : [];
  if (wantedTypes.length > 0 && !wantedTypes.includes("all")) {
    const eventTokens = eventPromoPreferenceTokens(eventData);
    if (!wantedTypes.some((token) => eventTokens.has(token))) {
      return false;
    }
  }

  const wantedCities = Array.isArray(prefs.promotionalCities)
    ? prefs.promotionalCities.map(normalizePreferenceToken).filter(Boolean)
    : [];
  if (wantedCities.length > 0 && !wantedCities.includes("all")) {
    const city = normalizePreferenceToken(eventData.city || eventData.audienceCity);
    if (city && !wantedCities.includes(city)) {
      return false;
    }
  }
  return true;
}

function audienceHasDirectDeliveryChannel(channels) {
  return Array.isArray(channels) && (channels.includes("push") || channels.includes("sms"));
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
    console.warn("Falling back to static Vennuzo event link", eventId, error && error.message);
    const publicBaseUrl = await getPublicBaseUrl();
    return `${publicBaseUrl}/events/${encodeURIComponent(eventId)}`;
  }
}

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

async function buildTicketLink(orderId) {
  const publicBaseUrl = await getPublicBaseUrl();
  return `${publicBaseUrl}/tickets/${encodeURIComponent(orderId)}`;
}

async function getTicketEmailConfig() {
  if (ticketEmailConfigCache) {
    return ticketEmailConfigCache;
  }

  const configSnap = await db.collection("app_config").doc("email").get();
  const config = configSnap.exists ? configSnap.data() || {} : {};
  const smtpHost = safeString(process.env.SMTP_HOST || config.smtpHost, "smtp.gmail.com");
  const smtpPort = Number(process.env.SMTP_PORT || config.smtpPort || 587);
  const smtpUser = safeString(process.env.SMTP_USER || config.smtpUser);
  const smtpPass = safeString(process.env.SMTP_PASS || config.smtpPass);
  const fromEmail = safeString(
    process.env.FROM_EMAIL || config.fromEmail || config.senderEmail || smtpUser,
    "tickets@vennuzo.app",
  );
  const fromName = safeString(process.env.FROM_NAME || config.fromName, "Vennuzo");

  ticketEmailConfigCache = {
    enabled: config.enabled !== false && Boolean(smtpUser && smtpPass),
    smtpHost,
    smtpPort: Number.isFinite(smtpPort) ? smtpPort : 587,
    smtpUser,
    smtpPass,
    fromEmail,
    fromName,
  };
  return ticketEmailConfigCache;
}

function escapeHtml(value) {
  return safeString(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function ticketEntriesFromOrder(order) {
  const tickets = order && order.tickets;
  if (!tickets) {
    return [];
  }
  const entries = Array.isArray(tickets) ? tickets : Object.values(tickets);
  return entries
    .filter((ticket) => ticket && typeof ticket === "object")
    .map((ticket) => ({
      ticketId: safeString(ticket.ticketId),
      tierName: safeString(ticket.tierName, "General"),
      attendeeName: safeString(ticket.attendeeName || order.buyerName, "Vennuzo attendee"),
      qrToken: safeString(ticket.qrToken),
      price: Number(ticket.price || 0),
      status: safeString(ticket.status, "issued"),
    }))
    .sort((a, b) => `${a.tierName}:${a.ticketId}`.localeCompare(`${b.tierName}:${b.ticketId}`));
}

function formatMoney(amount, currency = "GHS") {
  const value = Number(amount || 0);
  if (!Number.isFinite(value)) {
    return `${currency} 0.00`;
  }
  return `${safeString(currency, "GHS")} ${value.toFixed(2)}`;
}

function buildTicketEmail({ orderId, order, eventData, ticketLink, tickets }) {
  const eventTitle = safeString(order.eventTitle || eventData.title, "your event");
  const buyerName = safeString(order.buyerName, "Vennuzo attendee");
  const eventDate = formatEventDate(eventData.startAt || order.eventStartAt);
  const venueParts = [
    safeString(eventData.venue || order.eventVenue),
    safeString(eventData.city || order.eventCity),
  ].filter(Boolean);
  const venue = venueParts.length ? venueParts.join(", ") : "See event details";
  const currency = safeString(order.currency, "GHS");
  const total = formatMoney(order.totalAmount, currency);
  const ticketRows = tickets
    .map((ticket, index) => {
      const qrImageUrl = ticket.qrToken
        ? `https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=${encodeURIComponent(ticket.qrToken)}&ecc=M&margin=1`
        : "";
      return `
        <tr>
          <td style="padding: 18px 0; border-top: 1px solid #e5e7eb;">
            <table role="presentation" style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="vertical-align: top; padding-right: 16px;">
                  <p style="margin: 0 0 6px; color: #111827; font-size: 16px; font-weight: 700;">
                    Ticket ${index + 1}: ${escapeHtml(ticket.tierName)}
                  </p>
                  <p style="margin: 0 0 4px; color: #4b5563; font-size: 14px;">
                    Attendee: ${escapeHtml(ticket.attendeeName)}
                  </p>
                  <p style="margin: 0 0 4px; color: #4b5563; font-size: 14px;">
                    Ticket ID: ${escapeHtml(ticket.ticketId.slice(-8).toUpperCase() || ticket.ticketId)}
                  </p>
                  <p style="margin: 0; color: #4b5563; font-size: 14px;">
                    QR token: <span style="font-family: Menlo, Consolas, monospace;">${escapeHtml(ticket.qrToken)}</span>
                  </p>
                </td>
                <td style="width: 116px; vertical-align: top; text-align: right;">
                  ${qrImageUrl ? `<img src="${qrImageUrl}" width="112" height="112" alt="Ticket QR code" style="display: inline-block; border: 1px solid #e5e7eb; border-radius: 10px;" />` : ""}
                </td>
              </tr>
            </table>
          </td>
        </tr>`;
    })
    .join("");

  const html = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Your Vennuzo Tickets</title>
  </head>
  <body style="margin: 0; padding: 0; background: #f6f7fb; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;">
    <table role="presentation" style="width: 100%; border-collapse: collapse; background: #f6f7fb;">
      <tr>
        <td align="center" style="padding: 32px 16px;">
          <table role="presentation" style="max-width: 640px; width: 100%; border-collapse: collapse; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 18px 45px rgba(15, 23, 42, 0.10);">
            <tr>
              <td style="padding: 34px 30px; background: #080b18; color: #ffffff;">
                <p style="margin: 0 0 8px; color: #8ef9ff; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase;">Vennuzo tickets</p>
                <h1 style="margin: 0; font-size: 28px; line-height: 1.15;">Your tickets are ready</h1>
                <p style="margin: 14px 0 0; color: #dbeafe; font-size: 16px; line-height: 1.5;">${escapeHtml(eventTitle)}</p>
              </td>
            </tr>
            <tr>
              <td style="padding: 30px;">
                <p style="margin: 0 0 18px; color: #111827; font-size: 16px; line-height: 1.6;">Hi ${escapeHtml(buyerName)},</p>
                <p style="margin: 0 0 22px; color: #374151; font-size: 16px; line-height: 1.6;">
                  Your purchase is confirmed. You have ${tickets.length} ticket${tickets.length === 1 ? "" : "s"} for <strong>${escapeHtml(eventTitle)}</strong>.
                </p>
                <table role="presentation" style="width: 100%; border-collapse: collapse; margin: 0 0 24px; background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 12px;">
                  <tr>
                    <td style="padding: 16px 18px; color: #4b5563; font-size: 14px;">Date</td>
                    <td style="padding: 16px 18px; color: #111827; font-size: 14px; font-weight: 700; text-align: right;">${escapeHtml(eventDate)}</td>
                  </tr>
                  <tr>
                    <td style="padding: 0 18px 16px; color: #4b5563; font-size: 14px;">Venue</td>
                    <td style="padding: 0 18px 16px; color: #111827; font-size: 14px; font-weight: 700; text-align: right;">${escapeHtml(venue)}</td>
                  </tr>
                  <tr>
                    <td style="padding: 0 18px 16px; color: #4b5563; font-size: 14px;">Order total</td>
                    <td style="padding: 0 18px 16px; color: #111827; font-size: 14px; font-weight: 700; text-align: right;">${escapeHtml(total)}</td>
                  </tr>
                </table>
                <table role="presentation" style="width: 100%; border-collapse: collapse; margin: 24px 0;">
                  <tr>
                    <td align="center">
                      <a href="${ticketLink}" style="display: inline-block; padding: 15px 26px; background: #f151c8; color: #ffffff; text-decoration: none; border-radius: 999px; font-size: 15px; font-weight: 800;">Open tickets</a>
                    </td>
                  </tr>
                </table>
                <p style="margin: 0 0 20px; color: #6b7280; font-size: 13px; line-height: 1.6;">
                  Show the QR code at the door. You can also open this link any time: <a href="${ticketLink}" style="color: #2563eb; word-break: break-all;">${ticketLink}</a>
                </p>
                <table role="presentation" style="width: 100%; border-collapse: collapse;">
                  ${ticketRows}
                </table>
                <p style="margin: 24px 0 0; color: #6b7280; font-size: 13px; line-height: 1.6;">
                  Order ref: ${escapeHtml(orderId)}
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding: 22px 30px; background: #f9fafb; color: #6b7280; font-size: 12px; line-height: 1.6;">
                This is an automated ticket confirmation from Vennuzo. Keep this email safe until after the event.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  const ticketLines = tickets
    .map((ticket, index) =>
      [
        `Ticket ${index + 1}: ${ticket.tierName}`,
        `Attendee: ${ticket.attendeeName}`,
        `Ticket ID: ${ticket.ticketId}`,
        `QR token: ${ticket.qrToken}`,
      ].join("\n"),
    )
    .join("\n\n");

  const text = [
    `Hi ${buyerName},`,
    "",
    `Your purchase is confirmed for ${eventTitle}.`,
    `Date: ${eventDate}`,
    `Venue: ${venue}`,
    `Order total: ${total}`,
    "",
    `Open your tickets: ${ticketLink}`,
    "",
    ticketLines,
    "",
    `Order ref: ${orderId}`,
    "",
    "This is an automated ticket confirmation from Vennuzo.",
  ].join("\n");

  return {
    subject: `Your tickets for ${eventTitle}`,
    html,
    text,
  };
}

async function sendTicketEmail({ to, orderId, order, eventData, ticketLink, tickets }) {
  const email = normalizeEmail(to);
  if (!email) {
    return { status: "skipped", reason: "missing_email" };
  }

  const config = await getTicketEmailConfig();
  if (!config.enabled) {
    return { status: "skipped", reason: "email_not_configured" };
  }

  const message = buildTicketEmail({ orderId, order, eventData, ticketLink, tickets });
  const transporter = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpPort === 465,
    auth: {
      user: config.smtpUser,
      pass: config.smtpPass,
    },
  });
  const info = await transporter.sendMail({
    from: `"${config.fromName}" <${config.fromEmail}>`,
    to: email,
    subject: message.subject,
    text: message.text,
    html: message.html,
  });

  return {
    status: "sent",
    messageId: safeString(info && info.messageId),
  };
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
  const ticketLink = await buildTicketLink(orderId);
  const tickets = ticketEntriesFromOrder(order);
  const delivery = order.ticketDelivery || {};
  const orderRef = db.collection("event_ticket_orders").doc(orderId);

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
        link: ticketLink,
      },
      eventId,
    });
  }

  const phone = normalizePhoneNumber(order.buyerPhone || (user && user.phone));
  const smsAlreadySent = delivery.sms && delivery.sms.status === "sent";
  const shouldSendSms =
    !smsAlreadySent &&
    phone &&
    (reservation
      ? distribution.sendSmsNotification !== false && (!user || prefs.smsEnabled !== false)
      : true);
  if (shouldSendSms) {
    try {
      const hubtelCfg = await getHubtelSmsConfig();
      const smsPrefix = reservation ? "Reservation created" : "Tickets confirmed";
      const ticketCountLabel = tickets.length > 0
        ? `${tickets.length} ticket${tickets.length === 1 ? "" : "s"}`
        : "your ticket";
      const smsMessage = reservation
        ? `${smsPrefix}: ${body}`
        : `${smsPrefix}: ${ticketCountLabel} for ${eventTitle}. Open QR tickets: ${ticketLink}`;
      const result = await sendHubtelSms({
        to: phone,
        message: smsMessage,
        reference: `order_${orderId}`,
        hubtelCfg,
      });
      await orderRef.set(
        {
          ticketDelivery: {
            sms: {
              status: "sent",
              to: result.normalizedPhone || phone,
              sentAt: FieldValue.serverTimestamp(),
              reference: `order_${orderId}`,
              link: reservation ? null : ticketLink,
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } catch (error) {
      console.error("Ticket SMS delivery failed", orderId, error);
      await orderRef.set(
        {
          ticketDelivery: {
            sms: {
              status: "failed",
              to: phone,
              error: safeString(error && error.message, "Ticket SMS delivery failed").slice(0, 500),
              attemptedAt: FieldValue.serverTimestamp(),
              reference: `order_${orderId}`,
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  } else if (!smsAlreadySent) {
    await orderRef.set(
      {
        ticketDelivery: {
          sms: {
            status: "skipped",
            reason: phone ? "sms_disabled" : "missing_phone",
            attemptedAt: FieldValue.serverTimestamp(),
          },
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  if (!reservation) {
    const emailAlreadySent = delivery.email && delivery.email.status === "sent";
    const email = normalizeEmail(order.buyerEmail || (user && user.email));
    if (!emailAlreadySent && email) {
      try {
        const result = await sendTicketEmail({
          to: email,
          orderId,
          order,
          eventData,
          ticketLink,
          tickets,
        });
        await orderRef.set(
          {
            ticketDelivery: {
              email: {
                status: result.status,
                to: email,
                reason: result.reason || null,
                messageId: result.messageId || null,
                sentAt: result.status === "sent" ? FieldValue.serverTimestamp() : null,
                attemptedAt: FieldValue.serverTimestamp(),
                link: ticketLink,
              },
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } catch (error) {
        console.error("Ticket email delivery failed", orderId, error);
        await orderRef.set(
          {
            ticketDelivery: {
              email: {
                status: "failed",
                to: email,
                error: safeString(error && error.message, "Ticket email delivery failed").slice(0, 500),
                attemptedAt: FieldValue.serverTimestamp(),
                link: ticketLink,
              },
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    } else if (!emailAlreadySent) {
      await orderRef.set(
        {
          ticketDelivery: {
            email: {
              status: "skipped",
              reason: "missing_email",
              attemptedAt: FieldValue.serverTimestamp(),
              link: ticketLink,
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
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

  // Fallback to the legacy SMS host, but keep credentials in the Authorization
  // header — never in the URL/query string, which can leak into proxy/access logs.
  const fallbackResponse = await fetch("https://sms.hubtel.com/v1/messages/send", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basicAuth}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      From: payload.From,
      To: normalizedPhone,
      Content: payload.Content,
    }),
  });
  const fallbackText = await fallbackResponse.text();
  let fallbackBody;
  try {
    fallbackBody = JSON.parse(fallbackText);
  } catch (error) {
    fallbackBody = { raw: fallbackText };
  }

  if (!fallbackResponse.ok || !hubtelResponseLooksSuccessful(fallbackBody)) {
    // Do not include the provider payload — it can contain the recipient's phone.
    console.error("Hubtel SMS send failed", {
      status: fallbackResponse.status,
      reference: payload.ClientReference,
    });
    throw new Error("Hubtel SMS failed. Please verify the SMS configuration and try again.");
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
    androidChannel: "vennuzo_urgent_alerts_v2",
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
    const uid = doc.id;
    const email = await resolveAdminEmail(uid, data);
    if (role !== "superadmin" && !isAllowedSuperAdminEmail(email)) {
      continue;
    }
    if (!isAllowedSuperAdminEmail(email)) {
      continue;
    }
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
async function notifyUserPush(uid, { title, body, route, kind, ...extraPayload }) {
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
    payload: {
      title,
      body,
      route: route || "/",
      ...Object.fromEntries(
        Object.entries(extraPayload).filter(([, value]) => value != null),
      ),
    },
  });
}

exports.notifySuperAdmins = notifySuperAdmins;
exports.notifyUserPush = notifyUserPush;
exports.queuePushNotification = queuePushNotification;

function docMillis(value) {
  if (!value) return 0;
  if (value.toMillis) return value.toMillis();
  if (value.toDate) return value.toDate().getTime();
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

async function maybeSendMonitorAlert({ key, title, body, route, severity = "warning", details = {} }) {
  const today = new Date().toISOString().slice(0, 10);
  const alertId = `${today}_${safeString(key).replace(/[^a-z0-9_-]+/gi, "_").slice(0, 140)}`;
  const alertRef = db.collection("production_monitor_alerts").doc(alertId);
  const created = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(alertRef);
    if (snap.exists) return false;
    transaction.set(alertRef, {
      key,
      title,
      body,
      route,
      severity,
      details,
      status: "open",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!created) return false;
  await notifySuperAdmins({
    title,
    body,
    route,
    kind: "production_monitor_alert",
  });
  return true;
}

async function scanCollectionForMonitor({
  collection,
  statuses,
  staleMinutes,
  route,
  title,
  label,
  statusField = "status",
  timestampFields = ["updatedAt", "createdAt"],
}) {
  const cutoff = Date.now() - staleMinutes * 60 * 1000;
  let count = 0;
  const examples = [];
  for (const status of statuses) {
    const snap = await db.collection(collection).where(statusField, "==", status).limit(25).get();
    for (const docSnap of snap.docs) {
      const data = docSnap.data() || {};
      const timestamp = timestampFields
        .map((field) => docMillis(data[field]))
        .find((millis) => millis > 0) || 0;
      if (timestamp && timestamp > cutoff) continue;
      count += 1;
      if (examples.length < 4) {
        examples.push({
          id: docSnap.id,
          status,
          eventId: safeString(data.eventId),
          organizationId: safeString(data.organizationId || data.walletId),
          ageMinutes: timestamp ? Math.round((Date.now() - timestamp) / 60000) : null,
        });
      }
    }
  }
  if (count <= 0) return 0;
  await maybeSendMonitorAlert({
    key: `${collection}_${statuses.join("_")}_${count}`,
    title,
    body: `${count} ${label} need attention.`,
    route,
    severity: statuses.includes("failed") || statuses.includes("error") ? "critical" : "warning",
    details: { collection, statusField, statuses, staleMinutes, examples },
  });
  return count;
}

exports.monitorProductionOperations = onSchedule(
  { schedule: "every 15 minutes", timeZone: TIME_ZONE, region: REGION, timeoutSeconds: 120 },
  async () => {
    const checks = [
      scanCollectionForMonitor({
        collection: "push_queue",
        statuses: ["failed", "partial"],
        staleMinutes: 10,
        route: "/admin/settings",
        title: "Push delivery needs attention",
        label: "push queue records",
        timestampFields: ["processedAt", "updatedAt", "createdAt"],
      }),
      scanCollectionForMonitor({
        collection: "push_queue",
        statuses: ["pending"],
        staleMinutes: 20,
        route: "/admin/settings",
        title: "Push queue is stuck",
        label: "pending push queue records",
      }),
      scanCollectionForMonitor({
        collection: "notification_jobs",
        statuses: ["failed"],
        staleMinutes: 10,
        route: "/admin/campaigns",
        title: "Campaign notification jobs failed",
        label: "campaign notification jobs",
      }),
      scanCollectionForMonitor({
        collection: "notification_jobs",
        statuses: ["queued", "processing"],
        staleMinutes: 45,
        route: "/admin/campaigns",
        title: "Campaign notification jobs are stuck",
        label: "campaign notification jobs",
      }),
      scanCollectionForMonitor({
        collection: "ticket_recovery_jobs",
        statuses: ["failed", "error"],
        staleMinutes: 10,
        route: "/admin/tickets",
        title: "Ticket recovery jobs failed",
        label: "ticket recovery jobs",
      }),
      scanCollectionForMonitor({
        collection: "flyer_jobs",
        statuses: ["error", "failed"],
        staleMinutes: 10,
        route: "/admin/data",
        title: "Creative generation jobs failed",
        label: "creative generation jobs",
      }),
      scanCollectionForMonitor({
        collection: "flyer_video_jobs",
        statuses: ["error", "failed"],
        staleMinutes: 10,
        route: "/admin/data",
        title: "Flyer video jobs failed",
        label: "flyer video jobs",
      }),
      scanCollectionForMonitor({
        collection: "payout_requests",
        statuses: ["failed", "error"],
        staleMinutes: 10,
        route: "/admin/payments",
        title: "Payout requests failed",
        label: "payout requests",
      }),
      scanCollectionForMonitor({
        collection: "event_ticket_orders",
        statuses: ["pending", "initiated"],
        staleMinutes: 60,
        route: "/admin/tickets",
        title: "Ticket payments may be stuck",
        label: "ticket payment orders",
        statusField: "paymentStatus",
        timestampFields: ["paymentUpdatedAt", "updatedAt", "createdAt"],
      }),
      scanCollectionForMonitor({
        collection: "table_package_bookings",
        statuses: ["pending_payment", "pending"],
        staleMinutes: 60,
        route: "/admin/tables",
        title: "Table package payments may be stuck",
        label: "table package bookings",
        statusField: "paymentStatus",
        timestampFields: ["callbackReceivedAt", "updatedAt", "createdAt"],
      }),
    ];
    const results = await Promise.all(checks);
    logger.info("[monitorProductionOperations] completed", { issueCount: results.reduce((sum, value) => sum + value, 0) });
  },
);

function chunkList(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

async function fetchUsersByField(fieldName, values) {
  const uniqueValues = [...new Set(values.filter(Boolean))].slice(0, MAX_AUDIENCE_QUERY);
  const users = new Map();
  for (const chunk of chunkList(uniqueValues, 10)) {
    const snap = await db.collection("users").where(fieldName, "in", chunk).get();
    for (const docSnap of snap.docs) {
      const data = docSnap.data() || {};
      users.set(String(data[fieldName] || "").toLowerCase(), {
        uid: docSnap.id,
        data,
      });
    }
  }
  return users;
}

async function resolveAudienceUsers(candidates) {
  const uniqueUids = [...new Set(candidates.map((candidate) => safeString(candidate.uid)).filter(Boolean))];
  const [userEntries, usersByEmail, usersByPhone] = await Promise.all([
    Promise.all(
      uniqueUids.map(async (uid) => {
        const userSnap = await db.collection("users").doc(uid).get();
        return [uid, userSnap.exists ? { uid, data: userSnap.data() || {} } : null];
      }),
    ),
    fetchUsersByField("email", candidates.map((candidate) => normalizeEmail(candidate.email)).filter(Boolean)),
    fetchUsersByField(
      "phone",
      candidates.map((candidate) => normalizePhoneNumber(candidate.phone)).filter(Boolean),
    ),
  ]);
  return {
    byUid: new Map(userEntries),
    byEmail: usersByEmail,
    byPhone: usersByPhone,
  };
}

async function getUploadedAudienceCandidates(organizationId, audienceSourceName = "") {
  if (!organizationId) {
    return [];
  }
  const requestedSourceName = safeString(audienceSourceName).toLowerCase();

  const snap = await db
    .collection("audience_contacts")
    .where("organizationId", "==", organizationId)
    .limit(MAX_AUDIENCE_QUERY)
    .get();

  return snap.docs
    .map((docSnap) => {
      const data = docSnap.data() || {};
      const sourceName = safeString(data.sourceName || data.source).toLowerCase();
      if (requestedSourceName && sourceName !== requestedSourceName) {
        return null;
      }
      if (data.marketingConsent !== true) {
        return null;
      }
      const phone = normalizePhoneNumber(data.phone);
      const email = normalizeEmail(data.email || data.emailLower);
      if (!phone && !email && !safeString(data.userId)) {
        return null;
      }
      return {
        uid: safeString(data.userId || data.uid),
        phone,
        email,
        name: safeString(data.displayName || data.name, "Imported contact"),
        source: "uploaded_contacts",
        sourceName: safeString(data.sourceName || data.source),
        smsConsent: data.smsConsent !== false,
      };
    })
    .filter(Boolean);
}

async function getEventAudience({
  eventId,
  organizationId = "",
  marketingOnly = false,
  audienceSources = ["event_rsvps", "ticket_buyers"],
  audienceSourceName = "",
}) {
  const sources = normalizeAudienceSources(audienceSources);
  let eventData = {};
  if (marketingOnly && eventId) {
    try {
      const eventSnap = await db.collection("events").doc(eventId).get();
      eventData = eventSnap.exists ? eventSnap.data() || {} : {};
    } catch (error) {
      console.warn("Could not load event for promo preference filtering", eventId, error && error.message);
    }
  }
  const queries = [];
  queries.push(
    sources.includes("event_rsvps")
      ? db.collection("event_rsvps").where("eventId", "==", eventId).limit(1000).get()
      : Promise.resolve({ docs: [] }),
  );
  queries.push(
    sources.includes("ticket_buyers")
      ? db.collection("event_ticket_orders").where("eventId", "==", eventId).limit(1000).get()
      : Promise.resolve({ docs: [] }),
  );
  queries.push(
    sources.includes("uploaded_contacts")
      ? getUploadedAudienceCandidates(organizationId, audienceSourceName)
      : Promise.resolve([]),
  );

  const [rsvpSnap, orderSnap, uploadedCandidates] = await Promise.all(queries);
  const candidates = [];

  for (const doc of rsvpSnap.docs) {
    const data = doc.data() || {};
    candidates.push({
      uid: safeString(data.userId || data.uid),
      phone: pickPhone(data, ["phone", "buyerPhone"]),
      email: normalizeEmail(data.email),
      name: safeString(data.name || data.fullName, "Vennuzo guest"),
      source: "event_rsvps",
      smsConsent: true,
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
      email: normalizeEmail(data.buyerEmail || data.customerEmail || data.payeeEmail),
      name: safeString(data.buyerName || data.customerName, "Vennuzo attendee"),
      source: "ticket_buyers",
      smsConsent: true,
    });
  }

  candidates.push(...uploadedCandidates);

  const users = await resolveAudienceUsers(candidates);
  const audienceMap = new Map();
  for (const candidate of candidates) {
    const uid = safeString(candidate.uid);
    const normalizedPhone = normalizePhoneNumber(candidate.phone);
    const email = normalizeEmail(candidate.email);
    const directUser = uid ? users.byUid.get(uid) : null;
    const matchedUser =
      directUser ||
      (email ? users.byEmail.get(email) : null) ||
      (normalizedPhone ? users.byPhone.get(normalizedPhone.toLowerCase()) : null);
    const userData = matchedUser ? matchedUser.data || {} : null;
    const resolvedUid = matchedUser ? matchedUser.uid : uid;
    const dedupeKey = resolvedUid
      ? `uid:${resolvedUid}`
      : email
        ? `email:${email}`
        : normalizedPhone
          ? `phone:${normalizedPhone}`
          : null;
    if (!dedupeKey) {
      continue;
    }

    const prefs = userData && userData.notificationPrefs ? userData.notificationPrefs : {};
    const userMarketingOptIn = prefs.marketingOptIn === true;
    const importedConsent = candidate.source === "uploaded_contacts";
    if (marketingOnly && userData && !userMarketingOptIn && !importedConsent) {
      continue;
    }
    if (marketingOnly && !userData && !importedConsent) {
      continue;
    }

    const existing = audienceMap.get(dedupeKey) || {
      uid: resolvedUid || null,
      phone: normalizedPhone,
      email,
      name: candidate.name,
      sources: [],
      allowPush: false,
      allowSms: false,
    };

    const allowPush =
      Boolean(resolvedUid) &&
      Boolean(userData && userData.fcmToken) &&
      (marketingOnly
        ? userAllowsPromotionalPush(prefs, eventData)
        : prefs.pushEnabled !== false);
    const allowSms =
      Boolean(normalizedPhone) &&
      candidate.smsConsent !== false &&
      (marketingOnly ? importedConsent || userMarketingOptIn : true) &&
      (userData ? prefs.smsEnabled !== false : importedConsent);

    audienceMap.set(dedupeKey, {
      uid: existing.uid || resolvedUid || null,
      phone: existing.phone || normalizedPhone || null,
      email: existing.email || email || null,
      name: existing.name || candidate.name,
      sources: [...new Set([...(existing.sources || []), candidate.source].filter(Boolean))],
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

async function assertOrganizationManager(uid, organizationId) {
  const orgId = safeString(organizationId);
  if (!uid || !orgId) {
    throw new HttpsError("permission-denied", "You do not have access to this organization.");
  }

  if (orgId === `org_${uid}`) {
    return;
  }

  const adminSnap = await db.collection("admins").doc(uid).get();
  if (adminSnap.exists) {
    return;
  }

  const membershipSnap = await db.collection("organization_members").doc(`${orgId}_${uid}`).get();
  if (!membershipSnap.exists) {
    throw new HttpsError("permission-denied", "You do not have access to this organization.");
  }

  const membership = membershipSnap.data() || {};
  if (membership.status !== "active") {
    throw new HttpsError("permission-denied", "Your organization access is not active.");
  }
}

function normalizeChannels(channels) {
  const values = Array.isArray(channels) ? channels : [];
  return [...new Set(values.map((channel) => safeString(channel).toLowerCase()))].filter((value) =>
    ["push", "sms", "sharelink", "featured", "announcement"].includes(value),
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
      organizationId: safeString(jobData.organizationId),
      audienceSources: jobData.audienceSources,
      audienceSourceName: safeString(jobData.audienceSourceName),
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
        try {
          const campaignSnap = await db.collection("promotion_campaigns").doc(safeString(jobData.campaignId)).get();
          const campaignData = campaignSnap.exists ? campaignSnap.data() || {} : {};
          const packageId = safeString(campaignData.packageId);
          const pricing = await getPricingConfig(packageId || undefined);
          await chargeCampaignDelivery(
            safeString(jobData.campaignId),
            queueRef.id,
            "push",
            targets.length,
            pricing.platformPushUnitPriceGhs,
          );
        } catch (err) {
          console.error("Campaign push charge failed", jobData.campaignId, queueRef.id, err);
        }
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
            const link = safeString(jobData.payload && jobData.payload.link);
            const smsMessage = `${title}: ${body}${link ? ` ${link}` : ""}`.trim();
            await sendHubtelSms({
              to: recipient.phone,
              message: smsMessage,
              reference: `${safeString(jobData.campaignId, "job")}_${Date.now()}`,
              hubtelCfg,
            });
            sentCount += 1;
          } catch (error) {
            failedCount += 1;
            console.error("Vennuzo SMS job failed for recipient", recipient.phone, error);
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
          channelId: "vennuzo_urgent_alerts_v2",
          sound: "default",
          priority: "max",
          defaultVibrateTimings: true,
          defaultSound: true,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            "interruption-level": "time-sensitive",
            "relevance-score": 1,
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
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    await assertAdminCan(request.auth.uid, "record_sms_opt_out");

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

exports.importAudienceContacts = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before importing audience contacts.");
    }

    const organizationId = safeString(
      request.data && request.data.organizationId,
      `org_${request.auth.uid}`,
    );
    await assertOrganizationManager(request.auth.uid, organizationId);

    const rawContacts = Array.isArray(request.data && request.data.contacts)
      ? request.data.contacts.slice(0, MAX_AUDIENCE_IMPORT_CONTACTS)
      : [];
    if (rawContacts.length === 0) {
      throw new HttpsError("invalid-argument", "Upload at least one contact.");
    }

    const sourceName = safeString(request.data && request.data.sourceName, "CSV import").slice(0, 80);
    const duplicateMode = ["skip", "update", "merge"].includes(safeString(request.data && request.data.duplicateMode))
      ? safeString(request.data && request.data.duplicateMode)
      : "merge";
    const normalizedContacts = [];
    let skippedCount = 0;

    for (const raw of rawContacts) {
      const email = normalizeEmail(raw && (raw.email || raw.emailAddress));
      const phone = normalizePhoneNumber(raw && (raw.phone || raw.phoneNumber || raw.mobile));
      const validPhone = phone && isValidGhanaMobileNumber(phone) ? phone : "";
      const marketingConsent = raw && raw.marketingConsent === true;
      if (!marketingConsent || (!email && !validPhone)) {
        skippedCount += 1;
        continue;
      }
      const dedupeKey = email ? `email:${email}` : `phone:${validPhone}`;
      normalizedContacts.push({
        dedupeKey,
        email,
        phone: validPhone,
        displayName: safeString(raw && (raw.displayName || raw.name || raw.fullName), email || validPhone).slice(0, 120),
        marketingConsent: true,
        smsConsent: validPhone ? raw.smsConsent !== false : false,
        tags: Array.isArray(raw && raw.tags)
          ? raw.tags.map((tag) => safeString(tag).slice(0, 40)).filter(Boolean).slice(0, 12)
          : [],
      });
    }

    const contactsByKey = new Map();
    for (const contact of normalizedContacts) {
      contactsByKey.set(contact.dedupeKey, contact);
    }
    const contacts = [...contactsByKey.values()];

    if (contacts.length === 0) {
      return {
        importedCount: 0,
        skippedCount,
        pushMatchedCount: 0,
        smsEligibleCount: 0,
      };
    }

    const [usersByEmail, usersByPhone] = await Promise.all([
      fetchUsersByField("email", contacts.map((contact) => contact.email).filter(Boolean)),
      fetchUsersByField("phone", contacts.map((contact) => contact.phone).filter(Boolean)),
    ]);

    const batch = db.batch();
    let pushMatchedCount = 0;
    let smsEligibleCount = 0;
    const contactRefs = contacts.map((contact) =>
      db.collection("audience_contacts").doc(
        `aud_${hashAudienceKey(`${organizationId}:${contact.dedupeKey}`)}`,
      ),
    );
    const existingSnaps = await db.getAll(...contactRefs);
    let importedCount = 0;

    for (const [index, contact] of contacts.entries()) {
      const contactRef = contactRefs[index];
      const existingSnap = existingSnaps[index];
      if (duplicateMode === "skip" && existingSnap.exists) {
        skippedCount += 1;
        continue;
      }
      importedCount += 1;
      const matchedUser =
        (contact.email ? usersByEmail.get(contact.email) : null) ||
        (contact.phone ? usersByPhone.get(contact.phone.toLowerCase()) : null);
      const prefs = matchedUser && matchedUser.data ? matchedUser.data.notificationPrefs || {} : {};
      if (matchedUser && matchedUser.data && matchedUser.data.fcmToken && userAllowsPromotionalPush(prefs, {})) {
        pushMatchedCount += 1;
      }
      if (contact.phone && contact.smsConsent) {
        smsEligibleCount += 1;
      }

      const existingTags = existingSnap.exists && Array.isArray(existingSnap.data().tags)
        ? existingSnap.data().tags.map((tag) => safeString(tag)).filter(Boolean)
        : [];
      const tags = duplicateMode === "merge"
        ? [...new Set([...existingTags, ...contact.tags])].slice(0, 12)
        : contact.tags;
      batch.set(
        contactRef,
        {
          organizationId,
          dedupeKey: contact.dedupeKey,
          displayName: contact.displayName,
          email: contact.email || null,
          emailLower: contact.email || null,
          phone: contact.phone || null,
          userId: matchedUser ? matchedUser.uid : null,
          source: "upload",
          sourceName,
          marketingConsent: true,
          smsConsent: contact.smsConsent,
          tags,
          importedBy: request.auth.uid,
          lastImportedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    if (importedCount > 0) {
      await batch.commit();
    }
    return {
      importedCount,
      skippedCount,
      pushMatchedCount,
      smsEligibleCount,
    };
  },
);

exports.saveCrmContact = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in before saving contacts.");
    }

    const organizationId = safeString(
      request.data && request.data.organizationId,
      `org_${request.auth.uid}`,
    );
    await assertOrganizationManager(request.auth.uid, organizationId);

    const email = normalizeEmail(request.data && request.data.email);
    const normalizedPhone = normalizePhoneNumber(request.data && request.data.phone);
    const rawPhone = safeString(request.data && request.data.phone);
    const phone = normalizedPhone || rawPhone;
    const userId = safeString(request.data && request.data.userId);
    if (!email && !phone && !userId) {
      throw new HttpsError("invalid-argument", "Save at least one contact channel.");
    }

    const dedupeKey = email
      ? `email:${email}`
      : phone
        ? `phone:${normalizePhoneNumber(phone) || phone.replace(/\D/g, "") || phone}`
        : `uid:${userId}`;
    const tags = Array.isArray(request.data && request.data.tags)
      ? request.data.tags.map((tag) => safeString(tag).slice(0, 40)).filter(Boolean).slice(0, 12)
      : [];
    const notes = safeString(request.data && request.data.notes).slice(0, 1000);
    const displayName = safeString(
      request.data && (request.data.displayName || request.data.name),
      email || phone || "CRM contact",
    ).slice(0, 120);
    const sourceName = safeString(request.data && request.data.sourceName, "CRM").slice(0, 80);

    const contactRef = db.collection("audience_contacts").doc(
      `aud_${hashAudienceKey(`${organizationId}:${dedupeKey}`)}`,
    );
    await contactRef.set(
      {
        organizationId,
        dedupeKey,
        displayName,
        email: email || null,
        emailLower: email || null,
        phone: phone || null,
        userId: userId || null,
        source: "crm",
        sourceName,
        marketingConsent: request.data && request.data.marketingConsent === true,
        smsConsent: request.data && request.data.smsConsent === true,
        tags,
        notes,
        updatedBy: request.auth.uid,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      contactId: contactRef.id,
    };
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
    const audienceSources = normalizeAudienceSources(request.data && request.data.audienceSources);
    const organizationId = safeString(eventData.organizationId, `org_${request.auth.uid}`);
    const audience = await getEventAudience({
      eventId,
      organizationId,
      marketingOnly: true,
      audienceSources,
      audienceSourceName: safeString(request.data && request.data.audienceSourceName),
    });
    const pushCount = audience.filter((e) => e.allowPush).length;
    const smsCount = audience.filter((e) => e.allowSms).length;
    const uploadedCount = audience.filter((e) => (e.sources || []).includes("uploaded_contacts")).length;
    const packageId = safeString(request.data && request.data.packageId);
    const pricing = await getPricingConfig(packageId || undefined);
    const channels = normalizeChannels(request.data && request.data.channels);
    const hasPush = channels.length === 0 || channels.includes("push");
    const hasSms = channels.length === 0 || channels.includes("sms");
    const hasFeatured = channels.includes("featured");
    const hasAnnouncement = channels.includes("announcement");
    const estimatedSmsCostGhs = hasSms ? Math.round(smsCount * pricing.platformSmsUnitPriceGhs * 100) / 100 : 0;
    const estimatedPushCostGhs = hasPush ? Math.round(pushCount * pricing.platformPushUnitPriceGhs * 100) / 100 : 0;
    const estimatedPlacementCostGhs =
      (hasFeatured ? pricing.featuredPlacementPriceGhs : 0) +
      (hasAnnouncement ? pricing.announcementPlacementPriceGhs : 0);
    return {
      pushCount,
      smsCount,
      uploadedCount,
      platformPushUnitPriceGhs: pricing.platformPushUnitPriceGhs,
      platformSmsUnitPriceGhs: pricing.platformSmsUnitPriceGhs,
      featuredPlacementPriceGhs: pricing.featuredPlacementPriceGhs,
      announcementPlacementPriceGhs: pricing.announcementPlacementPriceGhs,
      estimatedPushCostGhs,
      estimatedSmsCostGhs,
      estimatedPlacementCostGhs,
      estimatedTotalCostGhs: Math.round((estimatedPushCostGhs + estimatedSmsCostGhs + estimatedPlacementCostGhs) * 100) / 100,
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
          platformPushUnitPriceGhs: Number(d.platformPushUnitPriceGhs) || DEFAULT_PUSH_UNIT_PRICE_GHS,
          featuredPlacementPriceGhs: nonNegativeNumber(
            d.featuredPlacementPriceGhs,
            DEFAULT_FEATURED_PLACEMENT_PRICE_GHS,
          ),
          announcementPlacementPriceGhs: nonNegativeNumber(
            d.announcementPlacementPriceGhs,
            DEFAULT_ANNOUNCEMENT_PLACEMENT_PRICE_GHS,
          ),
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
    const audienceSources = normalizeAudienceSources(request.data && request.data.audienceSources);
    if (!eventId || !message || channels.length === 0) {
      throw new HttpsError("invalid-argument", "eventId, message, and channels are required.");
    }
    if (audienceHasDirectDeliveryChannel(channels) && audienceSources.length === 0) {
      throw new HttpsError("invalid-argument", "Choose at least one owned audience source for push or SMS.");
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "The selected event does not exist in Firestore yet.");
    }

    const eventData = eventSnap.data() || {};
    await assertEventManager(request.auth.uid, eventData);

    const organizationId = safeString(eventData.organizationId, `org_${request.auth.uid}`);
    const packageId = safeString(request.data && request.data.packageId);
    const audienceSourceName = safeString(request.data && request.data.audienceSourceName);
    const objective = safeString(request.data && request.data.objective, "sell_tickets");
    const audienceStrategy = safeString(request.data && request.data.audienceStrategy, "recommended");
    const optimizationGoal = safeString(request.data && request.data.optimizationGoal, "conversions");
    const bidStrategy = safeString(request.data && request.data.bidStrategy, "balanced");
    const creativeMode = safeString(request.data && request.data.creativeMode, "single");
    const targetType = safeString(request.data && request.data.targetType, "event").toLowerCase() === "place" ? "place" : "event";
    const targetId = safeString(request.data && request.data.targetId, eventId);
    const targetTitle = safeString(request.data && request.data.targetTitle, safeString(eventData.title));
    const frequencyCap = Math.max(1, Math.min(10, Number(request.data && request.data.frequencyCap) || 2));
    const budgetCapGhs = nonNegativeNumber(request.data && request.data.budgetCapGhs, 0);
    const audience = await getEventAudience({
      eventId,
      organizationId,
      marketingOnly: true,
      audienceSources,
      audienceSourceName,
    });
    const pushCount = audience.filter((e) => e.allowPush).length;
    const smsCount = audience.filter((e) => e.allowSms).length;
    const uploadedAudience = audience.filter((e) => (e.sources || []).includes("uploaded_contacts")).length;
    const pricing = await getPricingConfig(packageId || undefined);
    const hasPush = channels.includes("push");
    const hasSms = channels.includes("sms");
    const estimatedPushCostGhs =
      hasPush && pushCount > 0
        ? Math.round(pushCount * pricing.platformPushUnitPriceGhs * 100) / 100
        : 0;
    const estimatedSmsCostGhs =
      hasSms && smsCount > 0
        ? Math.round(smsCount * pricing.platformSmsUnitPriceGhs * 100) / 100
        : 0;
    const estimatedPlacementCostGhs = Math.round((
      (channels.includes("featured") ? pricing.featuredPlacementPriceGhs : 0) +
      (channels.includes("announcement") ? pricing.announcementPlacementPriceGhs : 0)
    ) * 100) / 100;
    const estimatedTotalCostGhs = Math.round((estimatedPushCostGhs + estimatedSmsCostGhs + estimatedPlacementCostGhs) * 100) / 100;

    const scheduledAt = asDate(request.data && request.data.scheduledAt) || new Date();
    const campaignId = db.collection("promotion_campaigns").doc().id;
    const campaignRef = db.collection("promotion_campaigns").doc(campaignId);

    if (estimatedTotalCostGhs > 0) {
      try {
        await reserveCampaignBudget(organizationId, campaignId, estimatedTotalCostGhs);
      } catch (err) {
        const msg = safeString(err && err.message, "Insufficient wallet balance.");
        await notifySuperAdmins({
          title: "Budget alert",
          body: `Campaign could not reserve promotion budget for "${safeString(eventData.title)}": ${msg}`,
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
    const includeShareLink = request.data && request.data.shareLinkEnabled === true;
    const isScheduled = scheduledAt.getTime() > Date.now() + 30000;
    const shareLink = includeShareLink ? await buildEventLink(eventId, eventData) : "";
    const payload = {
      title,
      body: message,
      eventId,
      eventTitle: safeString(eventData.title),
      route: `/events/${eventId}`,
    };
    if (shareLink) {
      payload.link = shareLink;
    }

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
          audienceSources,
          audienceSourceName,
          scheduledAt: Timestamp.fromDate(scheduledAt),
          payload,
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
        targetType,
        targetId,
        targetTitle,
        name: safeString(request.data && request.data.name, `${safeString(eventData.title)} campaign`),
        status: isScheduled ? "scheduled" : "live",
        channels: channels.map((channel) => (channel === "sharelink" ? "shareLink" : channel)),
        audienceSources,
        audienceSourceName: audienceSourceName || null,
        scheduledAt: Timestamp.fromDate(scheduledAt),
        pushAudience: pushCount,
        smsAudience: smsCount,
        uploadedAudience,
        shareLinkEnabled: includeShareLink,
        pushBudget: estimatedPushCostGhs,
        smsBudget: estimatedSmsCostGhs,
        placementBudget: estimatedPlacementCostGhs,
        budget: estimatedTotalCostGhs,
        walletReservationAmount: estimatedTotalCostGhs,
        platformPushUnitPriceGhs: pricing.platformPushUnitPriceGhs,
        platformSmsUnitPriceGhs: pricing.platformSmsUnitPriceGhs,
        featuredPlacementPriceGhs: pricing.featuredPlacementPriceGhs,
        announcementPlacementPriceGhs: pricing.announcementPlacementPriceGhs,
        packageId: packageId || null,
        objective,
        audienceStrategy,
        optimizationGoal,
        bidStrategy,
        creativeMode,
        frequencyCap,
        budgetCapGhs: budgetCapGhs || null,
        optimizationConfig: {
          objective,
          audienceStrategy,
          optimizationGoal,
          bidStrategy,
          creativeMode,
          frequencyCap,
          budgetCapGhs: budgetCapGhs || null,
        },
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

    if (estimatedPlacementCostGhs > 0) {
      try {
        await chargeCampaignDelivery(
          campaignId,
          "placement",
          "placement",
          1,
          estimatedPlacementCostGhs,
        );
        if (jobSpecs.length === 0) {
          await finalizeCampaignWallet(campaignId);
        }
      } catch (err) {
        console.error("Campaign placement charge failed", campaignId, err);
      }
    }

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
    await activateDueScheduledCampaigns(now);
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

async function activateDueScheduledCampaigns(now) {
  const snap = await db
    .collection("promotion_campaigns")
    .where("status", "==", "scheduled")
    .where("scheduledAt", "<=", now)
    .limit(MAX_JOB_BATCH)
    .get();

  if (snap.empty) {
    return;
  }

  const batch = db.batch();
  for (const docSnap of snap.docs) {
    batch.set(
      docSnap.ref,
      {
        status: "live",
        activatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
}

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
    const smsAdminSnap = await db.collection("admins").doc(request.auth.uid).get();
    if (!smsAdminSnap.exists
      || safeString(smsAdminSnap.data() && smsAdminSnap.data().status, "active").toLowerCase() === "disabled") {
      throw new HttpsError("permission-denied", "Admin access is required to send test messages.");
    }
    // Rate limit: max 10 test SMS per admin per hour (Hubtel credit protection).
    await checkRateLimit(db, request.auth.uid, "sendTestEventSms", { maxCalls: 10, windowSeconds: 3600 });

    const phone = safeString(request.data && request.data.phone);
    const message = safeString(
      request.data && request.data.message,
      "Vennuzo test SMS: Hubtel is connected and ready.",
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
    const pushAdminSnap = await db.collection("admins").doc(request.auth.uid).get();
    if (!pushAdminSnap.exists
      || safeString(pushAdminSnap.data() && pushAdminSnap.data().status, "active").toLowerCase() === "disabled") {
      throw new HttpsError("permission-denied", "Admin access is required to send test messages.");
    }
    // Rate limit: max 20 test pushes per admin per hour.
    await checkRateLimit(db, request.auth.uid, "sendTestEventPush", { maxCalls: 20, windowSeconds: 3600 });

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
