"use strict";

/**
 * Shared Hubtel SMS sender. NOT a Cloud Functions module — it exports plain
 * helpers and is intentionally never spread into index.js exports. Used by the
 * place-verification callables (and available to any other server-side caller)
 * to send transactional SMS without duplicating Hubtel plumbing.
 */

const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const logger = require("./logger");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
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

function isValidGhanaMobileNumber(phone) {
  return /^(\+233|233)(2[03456789]|5[03456789])\d{7}$/.test(phone);
}

function hubtelResponseLooksSuccessful(body) {
  if (!body || typeof body !== "object") return false;
  // Hubtel's v1 SMS API returns numeric status 0 ("request submitted
  // successfully") on success — guard this BEFORE safeString, since safeString(0)
  // is "" (0 is falsy) and would otherwise misread success as failure.
  if (body.status === 0 || body.status === "0" || body.Status === 0) return true;
  if (
    safeString(body.messageId) &&
    safeString(body.statusDescription).toLowerCase().includes("submitted")
  ) {
    return true;
  }
  const code = safeString(body.ResponseCode || body.responseCode || body.code);
  if (code && ["0000", "0", "200", "201"].includes(code)) return true;
  const status = safeString(body.Status || body.status).toLowerCase();
  return ["success", "successful", "accepted", "submitted", "sent"].includes(status);
}

function loadLocalHubtelConfig() {
  try {
    return require("./hubtel_sms_config");
  } catch (error) {
    return {};
  }
}

async function getHubtelSmsConfig() {
  const local = loadLocalHubtelConfig();
  const config = {
    clientId: safeString(local.clientId || process.env.HUBTEL_SMS_CLIENT_ID),
    clientSecret: safeString(local.clientSecret || process.env.HUBTEL_SMS_CLIENT_SECRET),
    senderId: safeString(local.senderId || process.env.HUBTEL_SMS_SENDER_ID, "Vennuzo"),
  };
  if (config.clientId && config.clientSecret) return config;

  try {
    const snap = await db.collection("app_config").doc("hubtel").get();
    const data = snap.data() || {};
    config.clientId = safeString(config.clientId || data.smsClientId || data.clientId);
    config.clientSecret = safeString(config.clientSecret || data.smsClientSecret || data.clientSecret);
    config.senderId = safeString(config.senderId || data.smsSenderId, "Vennuzo");
  } catch (error) {
    logger.error("Failed to load Hubtel SMS config", error);
  }

  if (!config.clientId || !config.clientSecret) {
    throw new HttpsError(
      "failed-precondition",
      "Vennuzo SMS is not configured yet. Please try another verification method.",
    );
  }
  return config;
}

async function parseResponseBody(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch (error) {
    return { raw: text };
  }
}

async function sendHubtelSms({ to, message, reference }) {
  const normalizedPhone = normalizePhoneNumber(to);
  if (!normalizedPhone || !isValidGhanaMobileNumber(normalizedPhone)) {
    throw new HttpsError("invalid-argument", "A valid Ghana mobile number is required.");
  }

  const config = await getHubtelSmsConfig();
  const payload = {
    From: String(config.senderId || "Vennuzo").substring(0, 11),
    To: normalizedPhone,
    Content: String(message || "").trim().slice(0, 459),
    ClientReference: safeString(reference, `vennuzo_${normalizedPhone}`),
  };
  const basicAuth = Buffer.from(`${config.clientId}:${config.clientSecret}`).toString("base64");

  // Try the endpoint our SMS credentials authenticate against first
  // (sms.hubtel.com). smsc.hubtel.com is kept as a fallback — it returns
  // "invalid api key credentials" for these creds, so leading with it just
  // wasted a request on every send. The full payload (incl. ClientReference)
  // goes to both for delivery tracking.
  const endpoints = [
    "https://sms.hubtel.com/v1/messages/send",
    "https://smsc.hubtel.com/v1/messages/send",
  ];
  let lastStatus = 0;
  for (const url of endpoints) {
    const response = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Basic ${basicAuth}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const body = await parseResponseBody(response);
    if (response.ok && hubtelResponseLooksSuccessful(body)) {
      return normalizedPhone;
    }
    lastStatus = response.status;
  }
  logger.error("Hubtel SMS send failed", { status: lastStatus, reference: payload.ClientReference });
  throw new HttpsError("unavailable", "We could not send the SMS. Please try again.");
}

module.exports = {
  sendHubtelSms,
  normalizePhoneNumber,
  isValidGhanaMobileNumber,
  getHubtelSmsConfig,
  hubtelResponseLooksSuccessful,
};
