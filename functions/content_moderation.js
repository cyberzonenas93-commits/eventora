"use strict";

/**
 * App Store Guideline 1.2 — User-Generated Content moderation.
 *
 * Provides the server-authoritative callables the iOS app needs to satisfy the
 * UGC requirement: users must be able to REPORT objectionable content and BLOCK
 * abusive users. Mirrors the existing event-safety reporting pattern
 * (event_safety.js) for consistency.
 *
 *   - reportContent : files a moderation report into `content_reports` (server-only).
 *   - blockUser     : adds a uid to the caller's `user_blocks/{uid}` block list.
 *   - unblockUser   : removes a uid from the caller's block list.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const { checkRateLimit } = require("./rate_limiter");

const REGION = "us-central1";

// Content surfaces a report can target.
const ALLOWED_CONTENT_TYPES = ["post", "comment", "review", "profile"];

// Allowed report reasons. Kept in sync with the Flutter reason picker.
const ALLOWED_REASONS = [
  "spam",
  "harassment",
  "hate",
  "nudity_sexual",
  "violence",
  "false_info",
  "other",
];

function safeString(value, fallback = "") {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
}

function requireBoundedString(value, field, { min = 1, max }) {
  const text = safeString(value);
  if (text.length < min || text.length > max) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be between ${min} and ${max} characters.`,
    );
  }
  return text;
}

function requireAuthUid(request) {
  const uid = request.auth?.uid || null;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to perform this action.",
    );
  }
  return uid;
}

// ---------------------------------------------------------------------------
// reportContent — file a moderation report. Server-only target collection.
// ---------------------------------------------------------------------------
exports.reportContent = onCall(
  { region: REGION, cors: true },
  async (request) => {
    const db = admin.firestore();
    const reporterId = requireAuthUid(request);

    await checkRateLimit(db, reporterId, "reportContent", {
      maxCalls: 20,
      windowSeconds: 60,
    });

    const data = request.data || {};

    const contentType = safeString(data.contentType);
    if (!ALLOWED_CONTENT_TYPES.includes(contentType)) {
      throw new HttpsError(
        "invalid-argument",
        `contentType must be one of: ${ALLOWED_CONTENT_TYPES.join(", ")}.`,
      );
    }

    const reason = safeString(data.reason);
    if (!ALLOWED_REASONS.includes(reason)) {
      throw new HttpsError(
        "invalid-argument",
        `reason must be one of: ${ALLOWED_REASONS.join(", ")}.`,
      );
    }

    const contentId = requireBoundedString(data.contentId, "contentId", {
      min: 1,
      max: 200,
    });

    // authorId is the uid of whoever created the reported content. Optional for
    // profile reports where the contentId already IS the author uid, but we
    // still record it when supplied so moderators can act on the account.
    const authorId = safeString(data.authorId) || null;
    if (authorId && authorId.length > 200) {
      throw new HttpsError("invalid-argument", "authorId is too long.");
    }
    if (authorId && authorId === reporterId) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot report your own content.",
      );
    }

    // Details are optional context (free text). Cap the length defensively.
    const rawDetails = safeString(data.details);
    if (rawDetails.length > 4000) {
      throw new HttpsError(
        "invalid-argument",
        "details must be 4000 characters or fewer.",
      );
    }
    const details = rawDetails || null;

    const reporterEmail = safeString(request.auth?.token?.email) || null;

    const reportRef = await db.collection("content_reports").add({
      contentType,
      contentId,
      authorId,
      reason,
      details,
      reporterId,
      reporterEmail,
      status: "pending",
      source: "ios_app",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { reportId: reportRef.id };
  },
);

// ---------------------------------------------------------------------------
// blockUser — add a uid to the caller's block list (user_blocks/{auth.uid}).
// ---------------------------------------------------------------------------
exports.blockUser = onCall(
  { region: REGION, cors: true },
  async (request) => {
    const db = admin.firestore();
    const uid = requireAuthUid(request);

    await checkRateLimit(db, uid, "blockUser", {
      maxCalls: 60,
      windowSeconds: 60,
    });

    const blockedUserId = requireBoundedString(
      request.data?.blockedUserId,
      "blockedUserId",
      { min: 1, max: 200 },
    );

    if (blockedUserId === uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot block yourself.",
      );
    }

    const ref = db.collection("user_blocks").doc(uid);
    await ref.set(
      {
        ownerId: uid,
        blockedUserIds: admin.firestore.FieldValue.arrayUnion(blockedUserId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { blocked: true, blockedUserId };
  },
);

// ---------------------------------------------------------------------------
// unblockUser — remove a uid from the caller's block list.
// ---------------------------------------------------------------------------
exports.unblockUser = onCall(
  { region: REGION, cors: true },
  async (request) => {
    const db = admin.firestore();
    const uid = requireAuthUid(request);

    await checkRateLimit(db, uid, "unblockUser", {
      maxCalls: 60,
      windowSeconds: 60,
    });

    const blockedUserId = requireBoundedString(
      request.data?.blockedUserId,
      "blockedUserId",
      { min: 1, max: 200 },
    );

    const ref = db.collection("user_blocks").doc(uid);
    await ref.set(
      {
        ownerId: uid,
        blockedUserIds: admin.firestore.FieldValue.arrayRemove(blockedUserId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { blocked: false, blockedUserId };
  },
);

// Test hook: expose pure helpers + constants for jest without real Firebase I/O.
if (process.env.NODE_ENV === "test") {
  module.exports._test = {
    ALLOWED_CONTENT_TYPES,
    ALLOWED_REASONS,
    safeString,
    requireBoundedString,
  };
}
