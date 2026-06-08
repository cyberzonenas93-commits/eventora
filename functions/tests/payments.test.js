"use strict";

/**
 * Unit tests for payment business logic in event_payments.js.
 * These import the REAL helpers (via the NODE_ENV==="test" export hook) so the
 * tests track the shipped code instead of a copy. No real Firebase calls happen —
 * the SDKs are stubbed below.
 */

// ── Minimal stubs so the module can be imported without real Firebase ────────
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

jest.mock("firebase-admin", () => ({
  app: () => { throw new Error("no app"); },
  initializeApp: () => {},
  firestore: Object.assign(() => ({}), {
    FieldValue: { serverTimestamp: () => ({}), increment: (n) => ({ _inc: n }) },
    Timestamp: { fromDate: () => ({}), fromMillis: () => ({}) },
  }),
}));

jest.mock("../rate_limiter", () => ({ checkRateLimit: async () => {} }));
jest.mock("../logger", () => ({
  info: () => {}, warn: () => {}, error: () => {}, debug: () => {}, critical: () => {},
}));
jest.mock("../event_notifications", () => ({ notifySuperAdmins: async () => {} }));

const crypto = require("crypto");
const { HttpsError } = require("firebase-functions/v2/https");

// Import the REAL helpers from the shipped module (test-only exports).
const {
  buildOrderSelections,
  safeString,
  isWithdrawableTicketOrder,
  verifyHubtelSignature,
  confirmHubtelStatusFromProvider,
  escapeHtml,
} = require("../event_payments");

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("buildOrderSelections", () => {
  test("returns empty selections for empty input", () => {
    const result = buildOrderSelections([]);
    expect(result.selectedTiers).toHaveLength(0);
    expect(result.totalAmount).toBe(0);
  });

  test("skips tiers with quantity <= 0", () => {
    const result = buildOrderSelections([
      { tierId: "t1", quantity: 0, price: 50 },
      { tierId: "t2", quantity: -1, price: 50 },
    ]);
    expect(result.selectedTiers).toHaveLength(0);
  });

  test("skips tiers missing tierId", () => {
    const result = buildOrderSelections([{ quantity: 2, price: 50 }]);
    expect(result.selectedTiers).toHaveLength(0);
  });

  test("computes total correctly for valid selections", () => {
    const result = buildOrderSelections([
      { tierId: "vip", quantity: 2, price: 100 },
      { tierId: "gen", quantity: 5, price: 50 },
    ]);
    expect(result.totalAmount).toBe(450);
    expect(result.selectedTiers).toHaveLength(2);
  });

  test("throws when quantity exceeds MAX_QUANTITY_PER_TIER", () => {
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 51, price: 10 }])
    ).toThrow(HttpsError);
    try {
      buildOrderSelections([{ tierId: "t1", quantity: 51, price: 10 }]);
    } catch (e) {
      expect(e.code).toBe("invalid-argument");
    }
  });

  test("throws when quantity is not an integer", () => {
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 1.5, price: 10 }])
    ).toThrow(HttpsError);
  });

  test("throws when price exceeds MAX_PRICE_PER_TIER_GHS", () => {
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 1, price: 10_001 }])
    ).toThrow(HttpsError);
  });

  test("throws when price is negative", () => {
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 1, price: -5 }])
    ).toThrow(HttpsError);
  });

  test("throws when order total exceeds MAX_ORDER_TOTAL_GHS", () => {
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 50, price: 10_000 }])
    ).toThrow(HttpsError);
  });

  test("accepts free tickets (price = 0)", () => {
    const result = buildOrderSelections([{ tierId: "free", quantity: 3, price: 0 }]);
    expect(result.totalAmount).toBe(0);
    expect(result.selectedTiers[0].price).toBe(0);
  });

  test("uses 'General' as default name when name is missing", () => {
    const result = buildOrderSelections([{ tierId: "t1", quantity: 1, price: 10 }]);
    expect(result.selectedTiers[0].name).toBe("General");
  });
});

describe("safeString", () => {
  test("trims whitespace", () => expect(safeString("  hello  ")).toBe("hello"));
  test("returns fallback for empty string", () => expect(safeString("", "default")).toBe("default"));
  test("returns fallback for null/undefined", () => {
    expect(safeString(null, "fb")).toBe("fb");
    expect(safeString(undefined, "fb")).toBe("fb");
  });
  test("converts numbers to string", () => expect(safeString(42)).toBe("42"));
});

describe("isWithdrawableTicketOrder (payout-theft guard)", () => {
  const base = { paymentStatus: "paid", paymentProvider: "hubtel", totalAmount: 100 };

  test("a paid Hubtel order WITHOUT settlementEligible is NOT withdrawable (forged-order guard)", () => {
    expect(isWithdrawableTicketOrder({ ...base })).toBe(false);
    expect(isWithdrawableTicketOrder({ ...base, status: "paid" })).toBe(false);
  });

  test("only counts when the server-set settlementEligible flag is true", () => {
    expect(isWithdrawableTicketOrder({ ...base, settlementEligible: true })).toBe(true);
    expect(isWithdrawableTicketOrder({ ...base, settlementEligible: "true" })).toBe(false);
    expect(isWithdrawableTicketOrder({ ...base, settlementEligible: 1 })).toBe(false);
  });

  test("requires Hubtel provider and a positive amount even when eligible", () => {
    expect(isWithdrawableTicketOrder({ settlementEligible: true, paymentStatus: "paid", paymentProvider: "cash_at_gate", totalAmount: 100 })).toBe(false);
    expect(isWithdrawableTicketOrder({ settlementEligible: true, paymentStatus: "paid", paymentProvider: "hubtel", totalAmount: 0 })).toBe(false);
    expect(isWithdrawableTicketOrder({ settlementEligible: true, paymentStatus: "pending", paymentProvider: "hubtel", totalAmount: 100 })).toBe(false);
  });
});

describe("verifyHubtelSignature (callback authenticity)", () => {
  const secret = "shared_callback_secret";
  const payload = { Data: { ClientReference: "evt_abc", Status: "success", Amount: 50 } };
  const validSig = crypto.createHmac("sha256", secret).update(JSON.stringify(payload)).digest("hex");

  test("accepts a correctly-signed payload", () => {
    expect(verifyHubtelSignature(secret, payload, validSig)).toBe(true);
  });

  test("rejects a wrong signature", () => {
    expect(verifyHubtelSignature(secret, payload, "deadbeef")).toBe(false);
  });

  test("rejects a missing/empty signature", () => {
    expect(verifyHubtelSignature(secret, payload, "")).toBe(false);
    expect(verifyHubtelSignature(secret, payload, undefined)).toBe(false);
  });

  test("rejects a valid signature over a TAMPERED body (amount changed)", () => {
    const tampered = { Data: { ClientReference: "evt_abc", Status: "success", Amount: 999999 } };
    expect(verifyHubtelSignature(secret, tampered, validSig)).toBe(false);
  });
});

describe("escapeHtml (return-page XSS guard)", () => {
  test("escapes HTML metacharacters", () => {
    expect(escapeHtml("<img src=x onerror=alert(1)>")).toBe("&lt;img src=x onerror=alert(1)&gt;");
    expect(escapeHtml("\"&'<>")).toBe("&quot;&amp;&#39;&lt;&gt;");
  });
  test("handles null/undefined", () => {
    expect(escapeHtml(null)).toBe("");
    expect(escapeHtml(undefined)).toBe("");
  });
});

describe("confirmHubtelStatusFromProvider (forged-callback defense)", () => {
  const config = { apiKey: "k", apiSecret: "s", merchantAccount: "M123" };
  const realFetch = global.fetch;
  afterEach(() => { global.fetch = realFetch; });

  test("returns ok:false when reference is missing (never trusts empty ref)", async () => {
    const result = await confirmHubtelStatusFromProvider("", config);
    expect(result.ok).toBe(false);
    expect(result.status).toBe("unknown");
  });

  test("confirms paid only when Hubtel returns responseCode 0000 + paid data", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      status: 200,
      json: async () => ({ responseCode: "0000", data: { status: "Paid" } }),
    });
    const result = await confirmHubtelStatusFromProvider("evt_abc", config);
    expect(result.ok).toBe(true);
    expect(result.status).toBe("paid");
  });

  test("does NOT confirm when Hubtel responseCode is not 0000 (forged callback)", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      status: 200,
      json: async () => ({ responseCode: "2001", data: null }),
    });
    const result = await confirmHubtelStatusFromProvider("evt_forged", config);
    expect(result.ok).toBe(false);
  });

  test("fails closed (ok:false) when the provider call throws", async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error("network down"));
    const result = await confirmHubtelStatusFromProvider("evt_abc", config);
    expect(result.ok).toBe(false);
    expect(result.reason).toContain("fetch_failed");
  });

  test("fails closed when server IP is not whitelisted (403)", async () => {
    global.fetch = jest.fn().mockResolvedValue({ status: 403, json: async () => ({}) });
    const result = await confirmHubtelStatusFromProvider("evt_abc", config);
    expect(result.ok).toBe(false);
    expect(result.reason).toBe("ip_not_whitelisted");
  });
});
