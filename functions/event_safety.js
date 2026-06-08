"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const { checkRateLimit } = require("./rate_limiter");

const REGION = "us-central1";

function cleanString(value, fallback = "") {
  return String(value ?? fallback).trim();
}

function requireBoundedString(value, field, { min = 1, max }) {
  const text = cleanString(value);
  if (text.length < min || text.length > max) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be between ${min} and ${max} characters.`,
    );
  }
  return text;
}

exports.submitEventReport = onCall(
  { region: REGION, cors: true },
  async (request) => {
    const db = admin.firestore();
    const authUid = request.auth?.uid || null;
    const rateKey =
      authUid ||
      request.rawRequest?.ip ||
      request.rawRequest?.headers?.["x-forwarded-for"] ||
      "anonymous";

    await checkRateLimit(db, String(rateKey), "submitEventReport", {
      maxCalls: 8,
      windowSeconds: 60,
    });

    const data = request.data || {};
    const eventId = requireBoundedString(data.eventId, "eventId", {
      min: 1,
      max: 200,
    });
    const eventTitle = requireBoundedString(data.eventTitle, "eventTitle", {
      min: 1,
      max: 500,
    });
    const reason = requireBoundedString(data.reason, "reason", {
      min: 3,
      max: 500,
    });
    const details = requireBoundedString(data.details, "details", {
      min: 10,
      max: 4000,
    });
    const reporterEmail = cleanString(data.reporterEmail || request.auth?.token?.email);

    const reportRef = await db.collection("event_reports").add({
      eventId,
      eventTitle,
      reason,
      details,
      reporterUid: authUid,
      reporterEmail: reporterEmail || null,
      status: "new",
      source: "ios_app",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { reportId: reportRef.id };
  },
);
