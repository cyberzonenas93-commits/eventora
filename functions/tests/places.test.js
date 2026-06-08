"use strict";

/**
 * Unit tests for Places platform helpers (places_platform.js).
 * Imports the REAL helpers via the NODE_ENV==="test" export hook so tests track
 * shipped code. Firebase SDKs are stubbed so the module imports without real I/O.
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

jest.mock("firebase-admin", () => {
  const firestore = Object.assign(() => ({ collection: () => ({}) }), {
    FieldValue: { serverTimestamp: () => ({}), increment: (n) => ({ _inc: n }) },
    Timestamp: { fromDate: () => ({}), fromMillis: () => ({}) },
    GeoPoint: class GeoPoint {},
  });
  return {
    app: () => ({}),
    initializeApp: () => {},
    firestore,
    messaging: () => ({}),
  };
});

jest.mock("../rate_limiter", () => ({ checkRateLimit: jest.fn().mockResolvedValue(undefined) }));

const {
  isAllowedMediaUrl,
  sanitizeMediaUrl,
  sanitizeMediaUrlArray,
} = require("../places_platform");

describe("isAllowedMediaUrl (media URL allow-list / anti-SSRF)", () => {
  test("accepts Firebase/GCS storage hosts over https", () => {
    expect(isAllowedMediaUrl("https://firebasestorage.googleapis.com/v0/b/x/o/y.jpg")).toBe(true);
    expect(isAllowedMediaUrl("https://storage.googleapis.com/eventora-10063.appspot.com/p.jpg")).toBe(true);
    expect(isAllowedMediaUrl("https://eventora-10063.firebasestorage.app/p.png")).toBe(true);
    // First-party G+ import bucket (existing data) is also a *.firebasestorage.app host.
    expect(isAllowedMediaUrl("https://gplus-admin.firebasestorage.app/drive_import_1.jpg")).toBe(true);
  });

  test("rejects arbitrary third-party hosts", () => {
    expect(isAllowedMediaUrl("https://evil.example.com/x.jpg")).toBe(false);
    expect(isAllowedMediaUrl("https://attacker.firebasestorage.app.evil.com/x.jpg")).toBe(false);
  });

  test("rejects non-https and malformed URLs", () => {
    expect(isAllowedMediaUrl("http://storage.googleapis.com/x.jpg")).toBe(false);
    expect(isAllowedMediaUrl("ftp://storage.googleapis.com/x.jpg")).toBe(false);
    expect(isAllowedMediaUrl("javascript:alert(1)")).toBe(false);
    expect(isAllowedMediaUrl("not a url")).toBe(false);
  });

  test("rejects empty/null", () => {
    expect(isAllowedMediaUrl("")).toBe(false);
    expect(isAllowedMediaUrl(null)).toBe(false);
    expect(isAllowedMediaUrl(undefined)).toBe(false);
  });
});

describe("sanitizeMediaUrl", () => {
  test("returns null for empty (no media set)", () => {
    expect(sanitizeMediaUrl("", "Cover image")).toBeNull();
    expect(sanitizeMediaUrl(null, "Cover image")).toBeNull();
  });

  test("returns the URL when allowed", () => {
    const url = "https://firebasestorage.googleapis.com/v0/b/x/o/cover.jpg";
    expect(sanitizeMediaUrl(url, "Cover image")).toBe(url);
  });

  test("throws on an off-allow-list URL (no SSRF/hot-link)", () => {
    expect(() => sanitizeMediaUrl("https://evil.example.com/x.jpg", "Cover image")).toThrow(
      /Vennuzo storage/,
    );
  });
});

describe("sanitizeMediaUrlArray", () => {
  test("keeps only allowed URLs and caps length", () => {
    const input = [
      "https://storage.googleapis.com/b/a.jpg",
      "https://evil.example.com/b.jpg",
      "https://eventora-10063.firebasestorage.app/c.png",
      "not a url",
    ];
    expect(sanitizeMediaUrlArray(input, 40)).toEqual([
      "https://storage.googleapis.com/b/a.jpg",
      "https://eventora-10063.firebasestorage.app/c.png",
    ]);
  });

  test("returns [] for non-array", () => {
    expect(sanitizeMediaUrlArray(undefined, 40)).toEqual([]);
    expect(sanitizeMediaUrlArray("nope", 40)).toEqual([]);
  });
});
