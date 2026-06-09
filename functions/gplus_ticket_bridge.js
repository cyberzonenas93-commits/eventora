"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
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
const DEFAULT_GPLUS_RSVP_BRIDGE_URL =
  "https://us-central1-gplus-admin.cloudfunctions.net/issueVennuzoEventRsvp";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function moneyAmount(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : 0;
}

function positiveInt(value, fallback = 1) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(1, parsed);
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

async function getRsvpBridgeConfig() {
  const envSecret = safeString(
    process.env.GPLUS_RSVP_BRIDGE_SECRET || process.env.GPLUS_TICKET_BRIDGE_SECRET,
  );
  const envUrl = safeString(process.env.GPLUS_RSVP_BRIDGE_URL);
  if (envSecret) {
    return {
      secret: envSecret,
      url: envUrl || DEFAULT_GPLUS_RSVP_BRIDGE_URL,
    };
  }

  const snap = await db.collection("app_config").doc("gplus").get();
  const data = snap.exists ? snap.data() || {} : {};
  return {
    secret: safeString(
      data.rsvpBridgeSecret ||
        data.ticketBridgeSecret ||
        data.vennuzoTicketBridgeSecret,
    ),
    url: safeString(data.rsvpBridgeUrl, envUrl || DEFAULT_GPLUS_RSVP_BRIDGE_URL),
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
    eventTitle: safeString(orderData.eventTitle || eventData.title, "G+ Nightclub Event"),
    eventSnapshot: {
      title: safeString(eventData.title || orderData.eventTitle, "G+ Nightclub Event"),
      startAtIso: asTimestampIso(eventData.startAt || eventData.date),
      endAtIso: asTimestampIso(eventData.endAt || eventData.endDate),
      venue: safeString(eventData.venue, "G+ Nightclub"),
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

function resolveGPlusEventId(eventId, eventData = {}, rsvpData = {}) {
  const explicit = safeString(
    eventData.sourceEventId ||
      rsvpData.sourceEventId ||
      (eventData.integration && eventData.integration.sourceEventId),
  );
  if (explicit) return explicit;
  const normalized = safeString(eventId);
  if (normalized.startsWith("gplus_")) return normalized.replace(/^gplus_/, "");
  return normalized;
}

function buildBridgeRsvpPayload(rsvpId, rsvpData, eventData) {
  const eventId = safeString(rsvpData.eventId);
  const guestCount = positiveInt(
    rsvpData.guestCount || rsvpData.numberOfPeople || rsvpData.partySize,
    1,
  );

  return {
    vennuzoRsvpId: rsvpId,
    vennuzoEventId: eventId,
    gplusEventId: resolveGPlusEventId(eventId, eventData, rsvpData),
    eventTitle: safeString(rsvpData.eventTitle || eventData.title, "G+ Nightclub Event"),
    eventSnapshot: {
      title: safeString(eventData.title || rsvpData.eventTitle, "G+ Nightclub Event"),
      startAtIso: asTimestampIso(eventData.startAt || eventData.date),
      endAtIso: asTimestampIso(eventData.endAt || eventData.endDate),
      venue: safeString(eventData.venue, "G+ Nightclub"),
      city: safeString(eventData.city, "Accra"),
      sourceEventId: safeString(eventData.sourceEventId || rsvpData.sourceEventId),
    },
    attendee: {
      id: safeString(rsvpData.userId),
      name: safeString(rsvpData.name, "Vennuzo attendee"),
      phone: safeString(rsvpData.phone),
      guestCount,
      numberOfPeople: guestCount,
      bookTable: rsvpData.bookTable === true,
      gender: safeString(rsvpData.gender, "Unknown"),
      optedInWhatsApp: rsvpData.optedInWhatsApp === true,
    },
    status: safeString(rsvpData.status, "attending"),
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

async function markRsvpBridgeStatus(rsvpRef, patch) {
  await rsvpRef.set(
    {
      gplusRsvpBridge: {
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

async function postToGPlusRsvpBridge(payload) {
  const config = await getRsvpBridgeConfig();
  if (!config.secret) {
    throw new Error(
      "G+ RSVP bridge secret is not configured. Set GPLUS_RSVP_BRIDGE_SECRET or app_config/gplus.rsvpBridgeSecret.",
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
      `G+ RSVP bridge failed (${response.status}): ${safeString(body.error || body.message, "unknown error")}`,
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

async function syncRsvpToGPlus(rsvpId, options = {}) {
  const rsvpRef = db.collection("event_rsvps").doc(rsvpId);
  const rsvpSnap = await rsvpRef.get();
  if (!rsvpSnap.exists) {
    throw new HttpsError("not-found", "RSVP not found.");
  }
  const rsvpData = rsvpSnap.data() || {};
  const eventId = safeString(rsvpData.eventId);
  if (!eventId) {
    throw new HttpsError("failed-precondition", "RSVP is missing eventId.");
  }

  const eventSnap = await db.collection("events").doc(eventId).get();
  const eventData = eventSnap.exists ? eventSnap.data() || {} : {};
  if (!isGPlusEvent(eventId, eventData, rsvpData)) {
    return { skipped: true, reason: "not_gplus_event" };
  }

  const existing = rsvpData.gplusRsvpBridge || {};
  if (
    !options.force &&
    safeString(existing.status).toLowerCase() === "synced" &&
    safeString(existing.gplusRsvpId)
  ) {
    return {
      skipped: true,
      reason: "already_synced",
      gplusRsvpId: safeString(existing.gplusRsvpId),
    };
  }

  const payload = buildBridgeRsvpPayload(rsvpSnap.id, rsvpData, eventData);
  if (!payload.gplusEventId) {
    throw new HttpsError("failed-precondition", "RSVP is missing a G+ source event id.");
  }

  await markRsvpBridgeStatus(rsvpRef, {
    status: "syncing",
    source: safeString(options.source, "backend"),
    attemptCount: Number(existing.attemptCount || 0) + 1,
  });

  try {
    const result = await postToGPlusRsvpBridge(payload);
    await markRsvpBridgeStatus(rsvpRef, {
      status: "synced",
      source: safeString(options.source, "backend"),
      gplusRsvpId: safeString(result.gplusRsvpId),
      gplusEventId: safeString(result.gplusEventId),
      entryQrToken: safeString(result.entryQrToken),
      alreadyProcessed: result.alreadyProcessed === true,
      confirmationSms: result.confirmationSms || null,
      lastError: FieldValue.delete(),
      syncedAt: FieldValue.serverTimestamp(),
      attemptCount: Number(existing.attemptCount || 0) + 1,
    });
    return result;
  } catch (error) {
    await markRsvpBridgeStatus(rsvpRef, {
      status: "failed",
      source: safeString(options.source, "backend"),
      lastError: safeString(error && error.message, "G+ RSVP bridge sync failed").slice(0, 1000),
      failedAt: FieldValue.serverTimestamp(),
      attemptCount: Number(existing.attemptCount || 0) + 1,
    });
    throw error;
  }
}

function normalizedForCompare(value) {
  if (!value) return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (Array.isArray(value)) return value.map(normalizedForCompare);
  if (typeof value === "object") {
    return Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .reduce((result, [key, entryValue]) => {
        result[key] = normalizedForCompare(entryValue);
        return result;
      }, {});
  }
  return value;
}

function changedTopLevelKeys(before = {}, after = {}) {
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...keys].filter((key) => (
    JSON.stringify(normalizedForCompare(before[key])) !==
    JSON.stringify(normalizedForCompare(after[key]))
  ));
}

function isRsvpBridgeOnlyWrite(before = {}, after = {}) {
  const changed = changedTopLevelKeys(before, after);
  return changed.length > 0 &&
    changed.every((key) => (
      key === "gplusRsvpBridge" ||
      key === "rsvpDelivery" ||
      key === "updatedAt"
    ));
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

exports.syncGPlusEventRsvp = onCall(
  { region: REGION, timeoutSeconds: 180 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const adminSnap = await db.collection("admins").doc(uid).get();
    if (!adminSnap.exists) {
      throw new HttpsError("permission-denied", "Only admins can retry G+ RSVP sync.");
    }
    const rsvpId = safeString(request.data && request.data.rsvpId);
    if (!rsvpId) {
      throw new HttpsError("invalid-argument", "rsvpId is required.");
    }
    return syncRsvpToGPlus(rsvpId, {
      force: request.data && request.data.force === true,
      source: "manual_retry",
    });
  },
);

exports.onGPlusEventRsvpWritten = onDocumentWritten(
  {
    region: REGION,
    document: "event_rsvps/{rsvpId}",
    timeoutSeconds: 180,
  },
  async (event) => {
    if (!event.data || !event.data.after.exists) return;

    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.data() || {};
    if (isRsvpBridgeOnlyWrite(before, after)) return;

    await syncRsvpToGPlus(event.params.rsvpId, {
      force: true,
      source: "firestore_trigger",
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

exports.retryGPlusRsvpBridgeFailures = onSchedule(
  {
    region: REGION,
    schedule: "every 15 minutes",
    timeoutSeconds: 300,
  },
  async () => {
    const failedSnap = await db
      .collection("event_rsvps")
      .where("gplusRsvpBridge.status", "==", "failed")
      .limit(25)
      .get();

    let retried = 0;
    for (const doc of failedSnap.docs) {
      try {
        await syncRsvpToGPlus(doc.id, {
          force: true,
          source: "scheduled_retry",
        });
        retried += 1;
      } catch (error) {
        console.error(`G+ RSVP bridge retry failed for ${doc.id}`, error);
      }
    }
    return { retried };
  },
);

module.exports.syncOrderToGPlusTicketing = syncOrderToGPlusTicketing;
module.exports.syncRsvpToGPlus = syncRsvpToGPlus;
module.exports.isGPlusEvent = isGPlusEvent;
