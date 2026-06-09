"use strict";

/**
 * Unit tests for the UGC moderation callables (content_moderation.js).
 *
 * Firebase SDKs are stubbed so the module imports without real I/O. The onCall
 * mock returns the raw handler so we can invoke it directly and assert on the
 * validation / Firestore-write behavior required by App Store Guideline 1.2.
 */

jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_opts, fn) => fn,
  onRequest: (_opts, fn) => fn,
  HttpsError: class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  },
}));

// Capture what handlers write to Firestore. A `mock`-prefixed global is the
// only way jest's hoisted factory is allowed to reference outer scope.
global.mockWrites = { added: [], setCalls: [] };

jest.mock("firebase-admin", () => {
  const firestore = Object.assign(
    () => ({
      collection: (name) => ({
        add: (data) => {
          global.mockWrites.added.push({ collection: name, data });
          return Promise.resolve({ id: "report_123" });
        },
        doc: () => ({
          set: (data, opts) => {
            global.mockWrites.setCalls.push({ data, opts });
            return Promise.resolve();
          },
        }),
      }),
    }),
    {
      FieldValue: {
        serverTimestamp: () => "__ts__",
        arrayUnion: (v) => ({ _arrayUnion: v }),
        arrayRemove: (v) => ({ _arrayRemove: v }),
      },
    },
  );
  return { firestore };
});

const writes = global.mockWrites;

jest.mock("../rate_limiter", () => ({
  checkRateLimit: jest.fn().mockResolvedValue(undefined),
}));

process.env.NODE_ENV = "test";
const moderation = require("../content_moderation");
const { ALLOWED_CONTENT_TYPES, ALLOWED_REASONS, safeString } = moderation._test;

const authReq = (data) => ({
  auth: { uid: "user_a", token: { email: "a@example.com" } },
  data,
});

beforeEach(() => {
  writes.added = [];
  writes.setCalls = [];
});

describe("allow-lists", () => {
  test("content types and reasons match the documented set", () => {
    expect(ALLOWED_CONTENT_TYPES).toEqual([
      "post",
      "comment",
      "review",
      "profile",
    ]);
    expect(ALLOWED_REASONS).toEqual([
      "spam",
      "harassment",
      "hate",
      "nudity_sexual",
      "violence",
      "false_info",
      "other",
    ]);
  });

  test("safeString trims and falls back", () => {
    expect(safeString("  hi  ")).toBe("hi");
    expect(safeString(null, "x")).toBe("x");
    expect(safeString(undefined)).toBe("");
  });
});

describe("reportContent", () => {
  test("requires authentication", async () => {
    await expect(
      moderation.reportContent({ auth: null, data: {} }),
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("rejects an invalid contentType", async () => {
    await expect(
      moderation.reportContent(
        authReq({ contentType: "tweet", contentId: "p1", reason: "spam" }),
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects a reason outside the allow-list", async () => {
    await expect(
      moderation.reportContent(
        authReq({ contentType: "post", contentId: "p1", reason: "i_dislike" }),
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects a missing contentId", async () => {
    await expect(
      moderation.reportContent(
        authReq({ contentType: "post", contentId: "", reason: "spam" }),
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("rejects reporting your own content", async () => {
    await expect(
      moderation.reportContent(
        authReq({
          contentType: "post",
          contentId: "p1",
          reason: "spam",
          authorId: "user_a",
        }),
      ),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("writes a pending report to content_reports with reporterId", async () => {
    const res = await moderation.reportContent(
      authReq({
        contentType: "comment",
        contentId: "c9",
        reason: "harassment",
        authorId: "user_b",
        details: "  abusive language  ",
      }),
    );
    expect(res).toEqual({ reportId: "report_123" });
    expect(writes.added).toHaveLength(1);
    const { collection, data } = writes.added[0];
    expect(collection).toBe("content_reports");
    expect(data).toMatchObject({
      contentType: "comment",
      contentId: "c9",
      reason: "harassment",
      authorId: "user_b",
      reporterId: "user_a",
      reporterEmail: "a@example.com",
      status: "pending",
      details: "abusive language",
    });
  });
});

describe("blockUser", () => {
  test("requires authentication", async () => {
    await expect(
      moderation.blockUser({ auth: null, data: { blockedUserId: "x" } }),
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("refuses to block yourself", async () => {
    await expect(
      moderation.blockUser(authReq({ blockedUserId: "user_a" })),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  test("requires a blockedUserId", async () => {
    await expect(
      moderation.blockUser(authReq({ blockedUserId: "" })),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  test("arrayUnions the blocked uid onto the caller's block doc", async () => {
    const res = await moderation.blockUser(authReq({ blockedUserId: "user_b" }));
    expect(res).toEqual({ blocked: true, blockedUserId: "user_b" });
    expect(writes.setCalls).toHaveLength(1);
    const { data, opts } = writes.setCalls[0];
    expect(opts).toEqual({ merge: true });
    expect(data.ownerId).toBe("user_a");
    expect(data.blockedUserIds).toEqual({ _arrayUnion: "user_b" });
  });
});

describe("unblockUser", () => {
  test("arrayRemoves the uid from the caller's block doc", async () => {
    const res = await moderation.unblockUser(
      authReq({ blockedUserId: "user_b" }),
    );
    expect(res).toEqual({ blocked: false, blockedUserId: "user_b" });
    expect(writes.setCalls).toHaveLength(1);
    const { data, opts } = writes.setCalls[0];
    expect(opts).toEqual({ merge: true });
    expect(data.blockedUserIds).toEqual({ _arrayRemove: "user_b" });
  });

  test("requires authentication", async () => {
    await expect(
      moderation.unblockUser({ auth: null, data: { blockedUserId: "x" } }),
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });
});
