"use strict";

// Mock firebase-functions before requiring rate_limiter
jest.mock("firebase-functions/v2/https", () => ({
  HttpsError: class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  },
}));

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    increment: (n) => ({ _increment: n }),
    serverTimestamp: () => ({ _serverTimestamp: true }),
  },
}));

const { HttpsError } = require("firebase-functions/v2/https");
const { checkRateLimit } = require("../rate_limiter");

function makeDb({ existingCount = null, transactionError = null } = {}) {
  return {
    collection: () => ({
      doc: () => ({
        // used by runTransaction via txn.get()
      }),
    }),
    runTransaction: jest.fn(async (fn) => {
      if (transactionError) throw transactionError;
      const snap = existingCount !== null
        ? { exists: true, data: () => ({ count: existingCount }) }
        : { exists: false };
      const writes = [];
      const txn = {
        get: async () => snap,
        update: (...args) => writes.push({ op: "update", args }),
        set: (...args) => writes.push({ op: "set", args }),
      };
      return fn(txn);
    }),
  };
}

describe("checkRateLimit", () => {
  test("allows first call (no existing doc)", async () => {
    const db = makeDb({ existingCount: null });
    await expect(
      checkRateLimit(db, "user1", "testOp", { maxCalls: 5, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });

  test("allows call when under the limit", async () => {
    const db = makeDb({ existingCount: 3 });
    await expect(
      checkRateLimit(db, "user1", "testOp", { maxCalls: 5, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });

  test("throws resource-exhausted when at the limit", async () => {
    const db = makeDb({ existingCount: 5 });
    await expect(
      checkRateLimit(db, "user1", "testOp", { maxCalls: 5, windowSeconds: 60 }),
    ).rejects.toThrow(HttpsError);

    try {
      await checkRateLimit(db, "user1", "testOp", { maxCalls: 5, windowSeconds: 60 });
    } catch (err) {
      expect(err.code).toBe("resource-exhausted");
      expect(err.message).toMatch(/too many requests/i);
    }
  });

  test("allows the request if Firestore throws a transient error", async () => {
    const db = makeDb({ transactionError: new Error("Firestore unavailable") });
    // Should NOT throw — fail open to avoid blocking legitimate users
    await expect(
      checkRateLimit(db, "user1", "testOp", { maxCalls: 5, windowSeconds: 60 }),
    ).resolves.toBeUndefined();
  });
});
