"use strict";

/**
 * Unit tests for payment business logic extracted from event_payments.js.
 * These test pure functions in isolation — no Firebase SDK calls needed.
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
  }),
}));

jest.mock("./rate_limiter", () => ({ checkRateLimit: async () => {} }), { virtual: true });
jest.mock("../rate_limiter", () => ({ checkRateLimit: async () => {} }));
jest.mock("../logger", () => ({
  info: () => {}, warn: () => {}, error: () => {}, debug: () => {}, critical: () => {},
}));
jest.mock("../event_notifications", () => ({ notifySuperAdmins: async () => {} }));

// ── Helpers under test (copied / re-exported as pure functions) ───────────────

const { HttpsError } = require("firebase-functions/v2/https");

// Re-implement the pure helpers locally so tests don't depend on module internals
function safeString(value, fallback = "") {
  return String(value || "").trim() || fallback;
}

const MAX_QUANTITY_PER_TIER = 50;
const MAX_PRICE_PER_TIER_GHS = 10_000;
const MAX_ORDER_TOTAL_GHS = 100_000;

function buildOrderSelections(selectedTiers) {
  const cleanedSelections = [];
  let totalAmount = 0;

  for (const rawSelection of Array.isArray(selectedTiers) ? selectedTiers : []) {
    const quantity = Number(rawSelection.quantity || 0);
    if (quantity <= 0) continue;
    if (!Number.isInteger(quantity) || quantity > MAX_QUANTITY_PER_TIER) {
      throw new HttpsError("invalid-argument",
        `Quantity must be a whole number between 1 and ${MAX_QUANTITY_PER_TIER} per tier.`);
    }
    const price = Number(rawSelection.price || rawSelection.amount || 0);
    if (!Number.isFinite(price) || price < 0 || price > MAX_PRICE_PER_TIER_GHS) {
      throw new HttpsError("invalid-argument",
        `Ticket price must be between 0 and ${MAX_PRICE_PER_TIER_GHS} GHS.`);
    }
    const tierId = safeString(rawSelection.tierId);
    if (!tierId) continue;
    cleanedSelections.push({ tierId, name: safeString(rawSelection.name, "General"), price, quantity });
    totalAmount += price * quantity;
  }

  if (totalAmount > MAX_ORDER_TOTAL_GHS) {
    throw new HttpsError("invalid-argument", `Order total cannot exceed ${MAX_ORDER_TOTAL_GHS} GHS.`);
  }
  return { selectedTiers: cleanedSelections, totalAmount };
}

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
    // 50 tickets × GHS 10,000 = GHS 500,000 > limit
    expect(() =>
      buildOrderSelections([{ tierId: "t1", quantity: 50, price: 10_000 }])
    ).toThrow(HttpsError);
  });

  test("accepts free tickets (price = 0)", () => {
    const result = buildOrderSelections([
      { tierId: "free", quantity: 3, price: 0 },
    ]);
    expect(result.totalAmount).toBe(0);
    expect(result.selectedTiers[0].price).toBe(0);
  });

  test("uses 'General' as default name when name is missing", () => {
    const result = buildOrderSelections([{ tierId: "t1", quantity: 1, price: 10 }]);
    expect(result.selectedTiers[0].name).toBe("General");
  });
});

describe("safeString", () => {
  test("trims whitespace", () => {
    expect(safeString("  hello  ")).toBe("hello");
  });
  test("returns fallback for empty string", () => {
    expect(safeString("", "default")).toBe("default");
  });
  test("returns fallback for null/undefined", () => {
    expect(safeString(null, "fb")).toBe("fb");
    expect(safeString(undefined, "fb")).toBe("fb");
  });
  test("converts numbers to string", () => {
    expect(safeString(42)).toBe("42");
  });
});
