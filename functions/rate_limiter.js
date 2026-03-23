"use strict";

/**
 * Per-user rate limiter for Vennuzo Cloud Functions.
 *
 * Uses a fixed-window counter backed by Firestore so limits persist
 * across function instances. Documents auto-expire via the `expiresAt`
 * field — set up a Firestore TTL policy on the `rate_limits` collection
 * using the `expiresAt` field to keep the collection clean.
 *
 * Usage:
 *   const { checkRateLimit } = require("./rate_limiter");
 *
 *   // Allow 5 calls per user per 60 seconds
 *   await checkRateLimit(db, uid, "initiatePayment", { maxCalls: 5, windowSeconds: 60 });
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const logger = require("./logger");

/**
 * Checks and increments a rate-limit counter for the given (uid, operation) pair.
 * Throws HttpsError("resource-exhausted") if the caller has exceeded the limit.
 *
 * @param {import("firebase-admin").firestore.Firestore} db
 * @param {string} uid          - Caller's Firebase UID (or IP/phone for public endpoints)
 * @param {string} operation    - Logical operation name, e.g. "initiatePayment"
 * @param {{ maxCalls: number, windowSeconds: number }} options
 */
async function checkRateLimit(db, uid, operation, { maxCalls, windowSeconds }) {
  const windowMs = windowSeconds * 1000;
  const windowKey = Math.floor(Date.now() / windowMs);
  const docId = `${uid}_${operation}_${windowKey}`;
  const ref = db.collection("rate_limits").doc(docId);

  try {
    const count = await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      if (snap.exists) {
        const current = Number(snap.data().count || 0);
        if (current >= maxCalls) {
          return current + 1; // signal over-limit without incrementing
        }
        txn.update(ref, { count: FieldValue.increment(1) });
        return current + 1;
      } else {
        const expiresAt = new Date(Date.now() + windowMs * 2);
        txn.set(ref, {
          uid,
          operation,
          count: 1,
          windowKey,
          expiresAt, // used by Firestore TTL policy — configure in Console
          createdAt: FieldValue.serverTimestamp(),
        });
        return 1;
      }
    });

    if (count > maxCalls) {
      const retryAfterSeconds = Math.ceil(
        (windowMs - (Date.now() % windowMs)) / 1000,
      );
      logger.warn("Rate limit exceeded", { uid, operation, count, maxCalls });
      throw new HttpsError(
        "resource-exhausted",
        `Too many requests. Please wait ${retryAfterSeconds}s before trying again.`,
      );
    }
  } catch (err) {
    // Re-throw HttpsErrors (our own rate-limit throws)
    if (err instanceof HttpsError) throw err;
    // Log but don't block the caller if Firestore itself has a transient error
    logger.error("Rate limiter Firestore error — allowing request", err);
  }
}

module.exports = { checkRateLimit };
