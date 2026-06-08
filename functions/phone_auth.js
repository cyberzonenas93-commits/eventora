"use strict";

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");
const logger = require("./logger");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const OTP_COLLECTION = "phone_login_otps";
const OTP_TTL_SECONDS = 10 * 60;
const OTP_MAX_ATTEMPTS = 5;

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
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

function isValidGhanaMobileNumber(phone) {
  return /^(\+233|233)(2[03456789]|5[03456789])\d{7}$/.test(phone);
}

function hubtelResponseLooksSuccessful(body) {
  const code = safeString(body && (body.ResponseCode || body.responseCode || body.code));
  if (code && ["0000", "0", "200", "201"].includes(code)) {
    return true;
  }
  const status = safeString(body && (body.Status || body.status)).toLowerCase();
  return ["success", "successful", "accepted", "submitted", "sent"].includes(status);
}

function loadLocalHubtelConfig() {
  try {
    return require("./hubtel_sms_config");
  } catch (error) {
    logger.warn("Hubtel SMS config file missing for phone auth.");
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

  if (config.clientId && config.clientSecret) {
    return config;
  }

  try {
    const snap = await db.collection("app_config").doc("hubtel").get();
    const data = snap.data() || {};
    config.clientId = safeString(config.clientId || data.smsClientId || data.clientId);
    config.clientSecret = safeString(
      config.clientSecret || data.smsClientSecret || data.clientSecret,
    );
    config.senderId = safeString(config.senderId || data.smsSenderId, "Vennuzo");
  } catch (error) {
    logger.error("Failed to load Hubtel SMS config for phone auth", error);
  }

  if (!config.clientId || !config.clientSecret) {
    throw new HttpsError(
      "failed-precondition",
      "Vennuzo SMS is not configured yet. Please try another sign-in method.",
    );
  }
  return config;
}

async function sendHubtelSms({ to, message, reference }) {
  const normalizedPhone = normalizePhoneNumber(to);
  if (!normalizedPhone || !isValidGhanaMobileNumber(normalizedPhone)) {
    throw new HttpsError(
      "invalid-argument",
      "Enter a valid Ghana mobile number for phone sign-in.",
    );
  }

  const config = await getHubtelSmsConfig();
  const payload = {
    From: String(config.senderId || "Vennuzo").substring(0, 11),
    To: normalizedPhone,
    Content: String(message || "").trim().slice(0, 459),
    ClientReference: safeString(reference, `auth_${Date.now()}`),
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
  const body = await parseResponseBody(response);
  if (response.ok && hubtelResponseLooksSuccessful(body)) {
    return normalizedPhone;
  }

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
  const fallbackBody = await parseResponseBody(fallbackResponse);
  if (!fallbackResponse.ok || !hubtelResponseLooksSuccessful(fallbackBody)) {
    logger.error("Phone login OTP SMS failed", {
      status: fallbackResponse.status,
      reference: payload.ClientReference,
    });
    throw new HttpsError(
      "unavailable",
      "We could not send the Vennuzo code. Please try again.",
    );
  }

  return normalizedPhone;
}

async function parseResponseBody(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch (error) {
    return { raw: text };
  }
}

function codeHash(phone, code, salt) {
  return crypto
    .createHash("sha256")
    .update(`${phone}:${code}:${salt}`)
    .digest("hex");
}

function newOtpCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, "0");
}

function verificationCode(input) {
  return safeString(input).replace(/\D/g, "").slice(0, 6);
}

function callerKey(request) {
  return safeString(
    request.rawRequest &&
      (request.rawRequest.ip ||
        request.rawRequest.headers["x-forwarded-for"] ||
        request.rawRequest.headers["fastly-client-ip"]),
    "unknown",
  ).split(",")[0].trim();
}

async function getOrCreatePhoneUser(phone) {
  try {
    return await admin.auth().getUserByPhoneNumber(phone);
  } catch (error) {
    if (error && error.code !== "auth/user-not-found") {
      throw error;
    }
  }
  return admin.auth().createUser({
    phoneNumber: phone,
    displayName: "Vennuzo user",
  });
}

exports.requestPhoneLoginOtp = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    if (!phone || !isValidGhanaMobileNumber(phone)) {
      throw new HttpsError(
        "invalid-argument",
        "Enter a valid Ghana mobile number for phone sign-in.",
      );
    }

    await checkRateLimit(db, `phone:${phone}`, "requestPhoneLoginOtp", {
      maxCalls: 3,
      windowSeconds: 600,
    });
    await checkRateLimit(db, `ip:${callerKey(request)}`, "requestPhoneLoginOtp", {
      maxCalls: 20,
      windowSeconds: 600,
    });

    const code = newOtpCode();
    const salt = crypto.randomBytes(16).toString("hex");
    const expiresAt = Timestamp.fromMillis(Date.now() + OTP_TTL_SECONDS * 1000);
    const ref = db.collection(OTP_COLLECTION).doc(phone);

    await ref.set(
      {
        phone,
        codeHash: codeHash(phone, code, salt),
        salt,
        attempts: 0,
        expiresAt,
        consumedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await sendHubtelSms({
      to: phone,
      message: `Your Vennuzo sign-in code is ${code}. It expires in 10 minutes.`,
      reference: `phone_auth_${Date.now()}`,
    });

    return {
      success: true,
      phone,
      expiresInSeconds: OTP_TTL_SECONDS,
      senderId: "Vennuzo",
    };
  },
);

exports.verifyPhoneLoginOtp = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request) => {
    const phone = normalizePhoneNumber(request.data && request.data.phone);
    const code = verificationCode(request.data && request.data.code);
    if (!phone || !isValidGhanaMobileNumber(phone) || code.length !== 6) {
      throw new HttpsError("invalid-argument", "Enter the 6-digit Vennuzo code.");
    }

    await checkRateLimit(db, `phone:${phone}`, "verifyPhoneLoginOtp", {
      maxCalls: 10,
      windowSeconds: 600,
    });

    const ref = db.collection(OTP_COLLECTION).doc(phone);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Request a new Vennuzo code first.");
    }

    const data = snap.data() || {};
    const expiresAt = data.expiresAt && data.expiresAt.toMillis
      ? data.expiresAt.toMillis()
      : 0;
    if (data.consumedAt || expiresAt <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "That Vennuzo code has expired.");
    }
    const attempts = Number(data.attempts || 0);
    if (attempts >= OTP_MAX_ATTEMPTS) {
      throw new HttpsError("resource-exhausted", "Request a new Vennuzo code.");
    }

    const expected = safeString(data.codeHash);
    const actual = codeHash(phone, code, safeString(data.salt));
    const expectedBuffer = Buffer.from(expected);
    const actualBuffer = Buffer.from(actual);
    if (
      expectedBuffer.length !== actualBuffer.length ||
      !crypto.timingSafeEqual(expectedBuffer, actualBuffer)
    ) {
      await ref.set(
        {
          attempts: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw new HttpsError("permission-denied", "That Vennuzo code did not match.");
    }

    const user = await getOrCreatePhoneUser(phone);
    const userDocRef = db.collection("users").doc(user.uid);
    const existingUserSnap = await userDocRef.get();

    // Fields safe to refresh on every login.
    const userPatch = {
      displayName: user.displayName || "Vennuzo user",
      phone,
      updatedAt: FieldValue.serverTimestamp(),
    };

    // SECURITY/CORRECTNESS: only seed defaults for brand-new users. Writing
    // roles/organizerApplicationStatus/notificationPrefs unconditionally would
    // demote existing organizers/admins back to "attendee" and reset their
    // application status + notification preferences on every phone login.
    if (!existingUserSnap.exists) {
      userPatch.roles = ["attendee"];
      userPatch.organizerApplicationStatus = "notStarted";
      userPatch.notificationPrefs = {
        pushEnabled: true,
        smsEnabled: true,
        marketingOptIn: false,
        promotionalPushEnabled: true,
        promotionalEventTypes: [],
        promotionalCities: [],
      };
      userPatch.createdAt = FieldValue.serverTimestamp();
    }

    await userDocRef.set(userPatch, { merge: true });
    await ref.set(
      {
        consumedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const customToken = await admin.auth().createCustomToken(user.uid, {
      phone,
      signInProvider: "vennuzo_sms",
    });
    return {
      success: true,
      customToken,
      phone,
      isNewUser: user.metadata.creationTime === user.metadata.lastSignInTime,
    };
  },
);
