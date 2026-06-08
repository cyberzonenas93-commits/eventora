"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;
const REGION = "us-central1";
const DEFAULT_GPLUS_BRIDGE_URL =
  "https://us-central1-gplus-admin.cloudfunctions.net/issueVennuzoTicketOrder";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function moneyAmount(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : 0;
}

function asTimestampIso(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string") return value;
  return null;
}

function isGPlusEvent(eventId, eventData = {}, orderData = {}) {
  const source = safeString(eventData.source || orderData.source).toLowerCase();
  const integrationSource = safeString(
    eventData.integration && eventData.integration.source,
  ).toLowerCase();
  return (
    source === "gplus" ||
    integrationSource === "gplus" ||
    safeString(eventId).startsWith("gplus_")
  );
}

async function getBridgeConfig() {
  const envSecret = safeString(process.env.GPLUS_TICKET_BRIDGE_SECRET);
  const envUrl = safeString(process.env.GPLUS_TICKET_BRIDGE_URL);
  if (envSecret) {
    return {
      secret: envSecret,
      url: envUrl || DEFAULT_GPLUS_BRIDGE_URL,
    };
  }

  const snap = await db.collection("app_config").doc("gplus").get();
  const data = snap.exists ? snap.data() || {} : {};
  return {
    secret: safeString(data.ticketBridgeSecret || data.vennuzoTicketBridgeSecret),
    url: safeString(data.ticketBridgeUrl, envUrl || DEFAULT_GPLUS_BRIDGE_URL),
  };
}

function buildBridgeTicketPayload(orderId, orderData, tickets = {}) {
  return Object.entries(tickets)
    .map(([ticketId, ticket]) => ({
      ticketId: safeString(ticket.ticketId, ticketId),
      qrToken: safeString(ticket.qrToken),
      tierId: safeString(ticket.tierId),
      tierName: safeString(ticket.tierName, "General"),
      attendeeName: safeString(ticket.attendeeName, orderData.buyerName),
      status: safeString(ticket.status, "issued"),
      price: moneyAmount(ticket.price),
      issuedAtIso: safeString(ticket.issuedAtIso) || asTimestampIso(ticket.issuedAt),
    }))
    .filter((ticket) => ticket.ticketId && ticket.qrToken);
}

function buildBridgePayload(orderId, orderData, eventData, tickets) {
  return {
    vennuzoOrderId: orderId,
    vennuzoEventId: safeString(orderData.eventId),
    gplusEventId: safeString(
      eventData.sourceEventId ||
        orderData.sourceEventId ||
        (eventData.integration && eventData.integration.sourceEventId),
    ),
    eventTitle: safeString(orderData.eventTitle || eventData.title, "G+Nightclub Event"),
    eventSnapshot: {
      title: safeString(eventData.title || orderData.eventTitle, "G+Nightclub Event"),
      startAtIso: asTimestampIso(eventData.startAt || eventData.date),
      endAtIso: asTimestampIso(eventData.endAt || eventData.endDate),
      venue: safeString(eventData.venue, "G+Nightclub"),
      city: safeString(eventData.city, "Accra"),
      sourceEventId: safeString(eventData.sourceEventId || orderData.sourceEventId),
    },
    buyer: {
      id: safeString(orderData.buyerId),
      name: safeString(orderData.buyerName, "Vennuzo attendee"),
      phone: safeString(orderData.buyerPhone),
      email: safeString(orderData.buyerEmail),
    },
    selectedTiers: Array.isArray(orderData.selectedTiers) ? orderData.selectedTiers : [],
    totalAmount: moneyAmount(orderData.totalAmount),
    currency: safeString(orderData.currency, "GHS"),
    payment: {
      provider: safeString(orderData.paymentProvider, "vennuzo"),
      status: safeString(orderData.paymentStatus || orderData.status, "paid"),
      paidAtIso: asTimestampIso(orderData.paidAt),
      details: orderData.paymentDetails || {},
    },
    tickets: buildBridgeTicketPayload(orderId, orderData, tickets),
    source: "vennuzo",
  };
}

async function markBridgeStatus(orderRef, patch) {
  await orderRef.set(
    {
      gplusTicketBridge: {
        ...patch,
        updatedAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function postToGPlusBridge(payload) {
  const config = await getBridgeConfig();
  if (!config.secret) {
    throw new Error(
      "G+ ticket bridge secret is not configured. Set GPLUS_TICKET_BRIDGE_SECRET or app_config/gplus.ticketBridgeSecret.",
    );
  }
  const response = await fetch(config.url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Vennuzo-Ticket-Bridge-Secret": config.secret,
    },
    body: JSON.stringify(payload),
  });
  const body = await response.json().catch(async () => ({
    error: await response.text().catch(() => ""),
  }));
  if (!response.ok || body.success === false) {
    throw new Error(
      `G+ ticket bridge failed (${response.status}): ${safeString(body.error || body.message, "unknown error")}`,
    );
  }
  return body;
}

async function syncOrderToGPlusTicketing(orderId, options = {}) {
  const orderRef = db.collection("event_ticket_orders").doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new HttpsError("not-found", "Ticket order not found.");
  }
  const orderData = orderSnap.data() || {};
  const eventId = safeString(orderData.eventId);
  if (!eventId) {
    throw new HttpsError("failed-precondition", "Order is missing eventId.");
  }

  const eventSnap = await db.collection("events").doc(eventId).get();
  const eventData = eventSnap.exists ? eventSnap.data() || {} : orderData.eventSnapshot || {};
  if (!isGPlusEvent(eventId, eventData, orderData)) {
    return { skipped: true, reason: "not_gplus_event" };
  }

  const tickets = orderData.tickets || {};
  const ticketEntries = Object.keys(tickets);
  if (ticketEntries.length === 0) {
    throw new HttpsError("failed-precondition", "Order has no issued tickets to sync.");
  }

  const existing = orderData.gplusTicketBridge || {};
  if (
    !options.force &&
    safeString(existing.status).toLowerCase() === "synced" &&
    safeString(existing.gplusOrderId)
  ) {
    return {
      skipped: true,
      reason: "already_synced",
      gplusOrderId: safeString(existing.gplusOrderId),
    };
  }

  const payload = buildBridgePayload(orderSnap.id, orderData, eventData, tickets);
  if (payload.tickets.length === 0) {
    throw new HttpsError("failed-precondition", "Order has no tickets with QR tokens.");
  }

  await markBridgeStatus(orderRef, {
    status: "syncing",
    source: safeString(options.source, "backend"),
    attemptCount: Number(existing.attemptCount || 0) + 1,
  });

  try {
    const result = await postToGPlusBridge(payload);
    await markBridgeStatus(orderRef, {
      status: "synced",
      source: safeString(options.source, "backend"),
      gplusOrderId: safeString(result.gplusOrderId),
      gplusEventId: safeString(result.gplusEventId),
      ticketCount: Number(result.ticketCount || payload.tickets.length),
      lastError: FieldValue.delete(),
      syncedAt: FieldValue.serverTimestamp(),
      attemptCount: Number(existing.attemptCount || 0) + 1,
    });
    return result;
  } catch (error) {
    await markBridgeStatus(orderRef, {
      status: "failed",
      source: safeString(options.source, "backend"),
      lastError: safeString(error && error.message, "G+ bridge sync failed").slice(0, 1000),
      failedAt: FieldValue.serverTimestamp(),
      attemptCount: Number(existing.attemptCount || 0) + 1,
    });
    throw error;
  }
}

exports.syncGPlusTicketOrder = onCall(
  { region: REGION, timeoutSeconds: 180 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const adminSnap = await db.collection("admins").doc(uid).get();
    if (!adminSnap.exists) {
      throw new HttpsError("permission-denied", "Only admins can retry G+ ticket sync.");
    }
    const orderId = safeString(request.data && request.data.orderId);
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }
    return syncOrderToGPlusTicketing(orderId, {
      force: request.data && request.data.force === true,
      source: "manual_retry",
    });
  },
);

exports.retryGPlusTicketBridgeFailures = onSchedule(
  {
    region: REGION,
    schedule: "every 15 minutes",
    timeoutSeconds: 300,
  },
  async () => {
    const failedSnap = await db
      .collection("event_ticket_orders")
      .where("gplusTicketBridge.status", "==", "failed")
      .limit(25)
      .get();

    let retried = 0;
    for (const doc of failedSnap.docs) {
      try {
        await syncOrderToGPlusTicketing(doc.id, {
          force: true,
          source: "scheduled_retry",
        });
        retried += 1;
      } catch (error) {
        console.error(`G+ ticket bridge retry failed for ${doc.id}`, error);
      }
    }
    return { retried };
  },
);

module.exports.syncOrderToGPlusTicketing = syncOrderToGPlusTicketing;
module.exports.isGPlusEvent = isGPlusEvent;
