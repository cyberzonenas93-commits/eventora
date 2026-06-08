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
  sha1Hex,
  placeOtpHash,
  normalizeOtpInput,
  maskPhone,
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

describe("place verification helpers (claim + OTP)", () => {
  test("sha1Hex is deterministic and dedups one venue to one id", () => {
    const a = sha1Hex("ChIJxxxGooglePlaceId");
    const b = sha1Hex("ChIJxxxGooglePlaceId");
    const c = sha1Hex("ChIJyyyOtherPlace");
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    expect(`gpl_${a}`).toMatch(/^gpl_[0-9a-f]{40}$/);
  });

  test("normalizeOtpInput strips non-digits and caps at 6", () => {
    expect(normalizeOtpInput(" 12-34 56 ")).toBe("123456");
    expect(normalizeOtpInput("1234567")).toBe("123456");
    expect(normalizeOtpInput("ab12")).toBe("12");
    expect(normalizeOtpInput(null)).toBe("");
  });

  test("maskPhone reveals only the last 3 digits", () => {
    expect(maskPhone("+233241234567")).toBe("**********567");
    expect(maskPhone("12")).toBe("***");
  });

  test("placeOtpHash binds code to placeId+salt (constant-time-compare friendly)", () => {
    const salt = "abcdef0123456789";
    const good = placeOtpHash("gpl_abc", "123456", salt);
    // Same inputs -> same hash (verification works)
    expect(placeOtpHash("gpl_abc", "123456", salt)).toBe(good);
    // Wrong code -> different hash
    expect(placeOtpHash("gpl_abc", "654321", salt)).not.toBe(good);
    // Same code, DIFFERENT place -> different hash (can't replay across places)
    expect(placeOtpHash("gpl_other", "123456", salt)).not.toBe(good);
    // Same code+place, different salt -> different hash
    expect(placeOtpHash("gpl_abc", "123456", "differentsalt")).not.toBe(good);
  });
});
