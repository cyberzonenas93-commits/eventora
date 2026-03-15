"use strict";

const crypto = require("crypto");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;

const REGION = "us-central1";
const EVENTORA_SCHEME = "eventoraapp";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) {
    return "";
  }
  if (digits.startsWith("+233")) {
    return digits;
  }
  if (digits.startsWith("233") && digits.length === 12) {
    return `+${digits}`;
  }
  if (digits.startsWith("0") && digits.length === 10) {
    return `+233${digits.slice(1)}`;
  }
  if (digits.length === 9) {
    return `+233${digits}`;
  }
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function projectId() {
  return safeString(process.env.GCLOUD_PROJECT || admin.app().options.projectId);
}

function functionsBaseUrl() {
  const pid = projectId();
  if (!pid) {
    throw new Error("GCLOUD_PROJECT is not available for Eventora payments.");
  }
  return `https://${REGION}-${pid}.cloudfunctions.net`;
}

async function getHubtelConfig() {
  const snap = await db.collection("app_config").doc("hubtel").get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "Hubtel config not found.");
  }

  const data = snap.data() || {};
  const apiKey = safeString(data.apiKey);
  const apiSecret = safeString(data.apiSecret);
  const merchantAccount = safeString(
    data.merchantAccountNumber || data.merchantAccount,
  );
  const callbackSecret = safeString(data.callbackSecret);

  if (!apiKey || !apiSecret || !merchantAccount) {
    throw new HttpsError(
      "failed-precondition",
      "Hubtel merchant credentials are not configured.",
    );
  }

  return {
    apiKey,
    apiSecret,
    merchantAccount,
    callbackSecret,
  };
}

function hubtelAuthHeader(config) {
  return `Basic ${Buffer.from(`${config.apiKey}:${config.apiSecret}`).toString("base64")}`;
}

function buildEventTicketReturnUrl(orderId, status) {
  const params = new URLSearchParams({
    type: "event_ticket",
    orderId,
    status,
  });
  return `${functionsBaseUrl()}/hubtelReturn?${params.toString()}`;
}

function normalizeHubtelStatus(value) {
  const normalized = safeString(value).toLowerCase();
  if (!normalized) {
    return "pending";
  }
  if (normalized === "success" || normalized === "paid") {
    return "paid";
  }
  if (normalized === "cancelled" || normalized === "canceled") {
    return "cancelled";
  }
  if (normalized === "failed" || normalized === "declined") {
    return "failed";
  }
  return normalized;
}

function isPaidStatus(value) {
  return normalizeHubtelStatus(value) === "paid";
}

function buildOrderSelections(selectedTiers) {
  const cleanedSelections = [];
  let totalAmount = 0;

  for (const rawSelection of Array.isArray(selectedTiers) ? selectedTiers : []) {
    const quantity = Number(rawSelection.quantity || 0);
    if (quantity <= 0) {
      continue;
    }
    const price = Number(rawSelection.price || rawSelection.amount || 0);
    const tierId = safeString(rawSelection.tierId);
    if (!tierId) {
      continue;
    }
    cleanedSelections.push({
      tierId,
      name: safeString(rawSelection.name, "General"),
      price,
      quantity,
    });
    totalAmount += price * quantity;
  }

  return {
    selectedTiers: cleanedSelections,
    totalAmount,
  };
}

function paymentStatusForOrderStatus(statusValue) {
  const normalized = normalizeHubtelStatus(statusValue);
  if (normalized === "paid") {
    return "paid";
  }
  if (normalized === "cancelled") {
    return "cancelled";
  }
  if (normalized === "failed") {
    return "failed";
  }
  return normalized || "pending";
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = safeString(value);
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function buildEventSnapshotForFirestore(eventId, snapshotData, existingEventData = {}) {
  const ticketing = snapshotData.ticketing || existingEventData.ticketing || {};
  const distribution = snapshotData.distribution || existingEventData.distribution || {};
  const metrics = snapshotData.metrics || existingEventData.metrics || {};

  return {
    organizationId: safeString(
      snapshotData.organizationId,
      safeString(existingEventData.organizationId),
    ),
    createdBy: safeString(
      snapshotData.createdBy,
      safeString(existingEventData.createdBy),
    ),
    title: safeString(snapshotData.title, safeString(existingEventData.title, "Event")),
    description: safeString(
      snapshotData.description,
      safeString(existingEventData.description),
    ),
    venue: safeString(snapshotData.venue, safeString(existingEventData.venue)),
    city: safeString(snapshotData.city, safeString(existingEventData.city)),
    visibility: safeString(
      snapshotData.visibility,
      safeString(existingEventData.visibility, "public"),
    ),
    status: safeString(
      snapshotData.status,
      safeString(existingEventData.status, "published"),
    ),
    timezone: safeString(
      snapshotData.timezone,
      safeString(existingEventData.timezone, "Africa/Accra"),
    ),
    startAt: snapshotData.startAt || existingEventData.startAt || null,
    endAt: snapshotData.endAt || existingEventData.endAt || null,
    ticketing: {
      enabled: ticketing.enabled !== false,
      requireTicket: ticketing.requireTicket === true,
      currency: safeString(ticketing.currency, "GHS"),
      tiers: Array.isArray(ticketing.tiers) ? ticketing.tiers : [],
    },
    distribution: {
      allowSharing: distribution.allowSharing !== false,
      sendPushNotification: distribution.sendPushNotification !== false,
      sendSmsNotification: distribution.sendSmsNotification !== false,
    },
    lineup: snapshotData.lineup || existingEventData.lineup || {},
    mood: safeString(snapshotData.mood, safeString(existingEventData.mood)),
    tags: Array.isArray(snapshotData.tags)
      ? snapshotData.tags
      : Array.isArray(existingEventData.tags)
        ? existingEventData.tags
        : [],
    metrics: {
      likesCount: Number(metrics.likesCount || 0),
      rsvpCount: Number(metrics.rsvpCount || 0),
      ticketCount: Number(metrics.ticketCount || 0),
      grossRevenue: Number(metrics.grossRevenue || 0),
    },
    updatedAt: FieldValue.serverTimestamp(),
    eventId,
  };
}

async function initiateHubtelCheckout({
  totalAmount,
  description,
  clientReference,
  payeeName,
  payeeMobileNumber,
  payeeEmail,
}) {
  const config = await getHubtelConfig();
  const requestBody = {
    totalAmount,
    description,
    clientReference,
    callbackUrl: `${functionsBaseUrl()}/hubtelCallback`,
    returnUrl: buildEventTicketReturnUrl(clientReference.replace(/^evt_/, ""), "success"),
    cancellationUrl: buildEventTicketReturnUrl(clientReference.replace(/^evt_/, ""), "cancelled"),
    merchantAccountNumber: config.merchantAccount,
    payeeName,
    payeeMobileNumber: payeeMobileNumber || undefined,
    payeeEmail: payeeEmail || undefined,
  };

  const response = await fetch("https://payproxyapi.hubtel.com/items/initiate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: hubtelAuthHeader(config),
    },
    body: JSON.stringify(requestBody),
  });

  const result = await response.json().catch(() => ({}));
  const checkoutUrl = safeString(
    result?.data?.checkoutDirectUrl || result?.data?.checkoutUrl,
  );
  if (!response.ok || !checkoutUrl) {
    console.error("Hubtel event checkout initiate failed", response.status, result);
    throw new HttpsError(
      "internal",
      "Failed to create Hubtel checkout. Please try again.",
    );
  }

  return {
    checkoutUrl,
    checkoutId: safeString(result?.data?.checkoutId),
    checkoutDirectUrl: safeString(result?.data?.checkoutDirectUrl),
    checkoutHostedUrl: safeString(result?.data?.checkoutUrl),
  };
}

function hasAdminAccess(adminData) {
  return Boolean(adminData && Object.keys(adminData).length > 0);
}

async function authorizeOrderAccess(orderData, uid, action) {
  const buyerId = safeString(orderData.buyerId);
  if (!buyerId || buyerId === uid) {
    return;
  }

  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!hasAdminAccess(adminSnap.data())) {
    throw new HttpsError("permission-denied", `Not authorized to ${action} this order.`);
  }
}

function buildPlaceholderTicketId(orderId, tierId, sequence) {
  return `${orderId}_${tierId}_${sequence}`;
}

function randomQrToken() {
  return crypto.randomBytes(16).toString("hex");
}

function browserRedirectHtml({ orderId, status, deepLink }) {
  const statusLabel = status === "success" ? "Payment complete" : "Payment cancelled";
  const heading = status === "success"
    ? "Your Eventora payment is processing"
    : "Your Eventora payment was cancelled";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${statusLabel}</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(160deg, #111827 0%, #0f172a 55%, #f97316 140%);
      color: #fff7ed;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 24px;
    }
    .card {
      width: min(440px, 100%);
      background: rgba(15, 23, 42, 0.86);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 28px;
      padding: 28px;
      box-shadow: 0 24px 60px rgba(15, 23, 42, 0.45);
    }
    h1 {
      font-size: 28px;
      margin: 0 0 12px;
    }
    p {
      color: rgba(255, 247, 237, 0.84);
      line-height: 1.55;
      margin: 0 0 12px;
    }
    .button {
      display: inline-block;
      margin-top: 12px;
      background: #f97316;
      color: white;
      text-decoration: none;
      padding: 14px 18px;
      border-radius: 16px;
      font-weight: 700;
    }
    .meta {
      margin-top: 18px;
      padding: 12px 14px;
      border-radius: 16px;
      background: rgba(255, 255, 255, 0.08);
      color: rgba(255, 247, 237, 0.72);
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>${heading}</h1>
    <p>${status === "success"
      ? "Open Eventora to watch your ticket status. Tickets will appear automatically once Hubtel confirms the payment callback."
      : "Reopen Eventora to review the order or try the payment again."}</p>
    <a class="button" href="${deepLink}">Open Eventora</a>
    <div class="meta">Order ID: ${orderId}</div>
  </div>
  <script>
    setTimeout(function() { window.location = ${JSON.stringify(deepLink)}; }, 300);
  </script>
</body>
</html>`;
}

function buildBuyerPatch(orderData, callbackData) {
  const patch = {};
  const buyerPhone = firstNonEmpty(
    orderData.buyerPhone,
    normalizePhoneNumber(callbackData.CustomerPhoneNumber),
    normalizePhoneNumber(callbackData?.PaymentDetails?.MobileMoneyNumber),
  );
  const buyerName = firstNonEmpty(
    orderData.buyerName,
    callbackData.CustomerName,
    buyerPhone,
  );
  const buyerEmail = firstNonEmpty(
    orderData.buyerEmail,
    callbackData.CustomerEmail,
  );

  if (buyerPhone) {
    patch.buyerPhone = buyerPhone;
  }
  if (buyerName) {
    patch.buyerName = buyerName;
  }
  if (buyerEmail) {
    patch.buyerEmail = buyerEmail;
  }
  return patch;
}

async function handleEventTicketCallback(clientReference, data, response) {
  const orderId = safeString(clientReference).replace(/^evt_/, "");
  if (!orderId) {
    return response.status(400).json({ error: "Invalid client reference." });
  }

  const orderRef = db.collection("event_ticket_orders").doc(orderId);
  let orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    const fallbackSnap = await db
      .collection("event_ticket_orders")
      .where("paymentReference.clientReference", "==", clientReference)
      .limit(1)
      .get();
    if (!fallbackSnap.empty) {
      orderSnap = fallbackSnap.docs[0];
    }
  }

  if (!orderSnap.exists) {
    return response.status(404).json({ error: "Order not found.", orderId });
  }

  const orderData = orderSnap.data() || {};
  const normalizedStatus = normalizeHubtelStatus(data.Status);
  const paymentStatus = paymentStatusForOrderStatus(normalizedStatus);
  const buyerPatch = buildBuyerPatch(orderData, data);

  if (!isPaidStatus(normalizedStatus)) {
    await orderSnap.ref.set(
      {
        ...buyerPatch,
        status: normalizedStatus === "cancelled" ? "cancelled" : "pending",
        paymentStatus,
        paymentProvider: "hubtel",
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || orderData.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return response.status(200).json({
      success: false,
      orderId: orderSnap.id,
      status: normalizedStatus,
    });
  }

  if (
    safeString(orderData.status).toLowerCase() === "paid" &&
    orderData.tickets &&
    Object.keys(orderData.tickets).length > 0
  ) {
    await orderSnap.ref.set(
      {
        ...buyerPatch,
        paymentStatus: "paid",
        paymentProvider: "hubtel",
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || orderData.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return response.status(200).json({
      success: true,
      orderId: orderSnap.id,
      status: "paid",
      alreadyProcessed: true,
    });
  }

  await db.runTransaction(async (transaction) => {
    const freshOrderSnap = await transaction.get(orderSnap.ref);
    const freshOrder = freshOrderSnap.data() || {};
    const eventId = safeString(freshOrder.eventId);
    if (!eventId) {
      throw new HttpsError("failed-precondition", "Order is missing eventId.");
    }

    const eventRef = db.collection("events").doc(eventId);
    const eventSnap = await transaction.get(eventRef);
    const eventData = eventSnap.exists
      ? eventSnap.data() || {}
      : (freshOrder.eventSnapshot || {});
    if (Object.keys(eventData).length === 0) {
      throw new HttpsError("not-found", "Event snapshot not found for ticket order.");
    }
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? [...ticketing.tiers] : [];
    const tierIndex = new Map();
    tiers.forEach((tier, index) => {
      tierIndex.set(safeString(tier.tierId), index);
    });

    const selections = Array.isArray(freshOrder.selectedTiers)
      ? freshOrder.selectedTiers
      : [];
    const now = FieldValue.serverTimestamp();
    const issuedAtIso = new Date().toISOString();
    const buyerName = firstNonEmpty(
      buyerPatch.buyerName,
      freshOrder.buyerName,
      "Eventora attendee",
    );
    const issuedTickets = {};
    const lookupWrites = [];
    let ticketCount = 0;

    for (const selection of selections) {
      const tierId = safeString(selection.tierId);
      const quantity = Number(selection.quantity || 0);
      if (!tierId || quantity <= 0) {
        continue;
      }

      const tierPosition = tierIndex.get(tierId);
      if (tierPosition == null) {
        throw new HttpsError("failed-precondition", `Ticket tier ${tierId} no longer exists.`);
      }

      const tier = { ...tiers[tierPosition] };
      const sold = Number(tier.sold || 0);
      const maxQuantity = Number(tier.maxQuantity || 0);
      if (maxQuantity > 0 && sold + quantity > maxQuantity) {
        throw new HttpsError(
          "failed-precondition",
          `${safeString(tier.name, "Ticket")} no longer has enough inventory.`,
        );
      }
      tier.sold = sold + quantity;
      tiers[tierPosition] = tier;

      for (let index = 0; index < quantity; index += 1) {
        ticketCount += 1;
        const ticketId = buildPlaceholderTicketId(orderSnap.id, tierId, ticketCount);
        const qrToken = randomQrToken();
        issuedTickets[ticketId] = {
          ticketId,
          orderId: orderSnap.id,
          eventId,
          occurrenceId: safeString(freshOrder.occurrenceId, `${eventId}_primary`),
          tierId,
          tierName: safeString(selection.name, safeString(tier.name, "General")),
          qrToken,
          status: "issued",
          attendeeName: buyerName,
          price: Number(selection.price || 0),
          issuedAt: now,
          issuedAtIso,
          updatedAt: now,
        };
        lookupWrites.push({
          qrToken,
          payload: {
            qrToken,
            orderId: orderSnap.id,
            ticketId,
            eventId,
            occurrenceId: safeString(freshOrder.occurrenceId, `${eventId}_primary`),
            organizationId: safeString(
              freshOrder.organizationId,
              eventData.organizationId,
            ),
            buyerId: safeString(freshOrder.buyerId),
            attendeeName: buyerName,
            tierId,
            tierName: safeString(selection.name, safeString(tier.name, "General")),
            ticketStatus: "issued",
            paymentStatus: "paid",
            createdAt: now,
            updatedAt: now,
          },
        });
      }
    }

    transaction.set(
      orderSnap.ref,
      {
        ...buyerPatch,
        status: "paid",
        paymentStatus: "paid",
        paymentProvider: "hubtel",
        ticketCount,
        tickets: issuedTickets,
        paidAt: now,
        paymentDetails: {
          checkoutId: safeString(data.CheckoutId),
          salesInvoiceId: safeString(data.SalesInvoiceId),
          amount: Number(data.Amount || freshOrder.totalAmount || 0),
          customerPhoneNumber: firstNonEmpty(
            data.CustomerPhoneNumber,
            data?.PaymentDetails?.MobileMoneyNumber,
          ),
          paymentType: safeString(data?.PaymentDetails?.PaymentType),
          channel: safeString(data?.PaymentDetails?.Channel),
          callbackReceivedAt: now,
        },
        updatedAt: now,
      },
      { merge: true },
    );

    transaction.set(
      eventRef,
      {
        ...buildEventSnapshotForFirestore(
          eventId,
          freshOrder.eventSnapshot || eventData,
          eventData,
        ),
        ticketing: {
          ...ticketing,
          tiers,
        },
        metrics: {
          ...(eventData.metrics || {}),
          ticketCount: FieldValue.increment(ticketCount),
          grossRevenue: FieldValue.increment(Number(freshOrder.totalAmount || 0)),
        },
        updatedAt: now,
      },
      { merge: true },
    );

    for (const lookup of lookupWrites) {
      transaction.set(
        db.collection("event_ticket_lookups").doc(lookup.qrToken),
        lookup.payload,
        { merge: true },
      );
    }
  });

  return response.status(200).json({
    success: true,
    orderId: orderSnap.id,
    status: "paid",
  });
}

exports.createEventTicketPaymentForOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const orderId = safeString(request.data && request.data.orderId);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in before paying for tickets.");
    }
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }

    const orderRef = db.collection("event_ticket_orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Event ticket order not found.");
    }

    const orderData = orderSnap.data() || {};
    await authorizeOrderAccess(orderData, uid, "pay for");

    const eventId = safeString(orderData.eventId);
    if (!eventId) {
      throw new HttpsError("failed-precondition", "Order is missing eventId.");
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    const eventData = eventSnap.exists
      ? eventSnap.data() || {}
      : (orderData.eventSnapshot || {});
    if (Object.keys(eventData).length === 0) {
      throw new HttpsError("not-found", "Event snapshot not found for this order.");
    }
    const { selectedTiers, totalAmount } = buildOrderSelections(
      orderData.selectedTiers,
    );
    const effectiveAmount = Number(orderData.totalAmount || totalAmount);
    if (!effectiveAmount || effectiveAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Total ticket amount must be greater than zero for payment.",
      );
    }

    const buyerName = firstNonEmpty(orderData.buyerName, "Guest");
    const buyerPhone = normalizePhoneNumber(orderData.buyerPhone);
    const buyerEmail = safeString(orderData.buyerEmail);
    const eventTitle = safeString(eventData.title, safeString(orderData.eventTitle, "Event"));
    const clientReference = `evt_${orderId}`;
    const checkout = await initiateHubtelCheckout({
      totalAmount: effectiveAmount,
      description: `Tickets: ${eventTitle}`,
      clientReference,
      payeeName: buyerName,
      payeeMobileNumber: buyerPhone,
      payeeEmail: buyerEmail,
    });

    await orderRef.set(
      {
        selectedTiers,
        totalAmount: effectiveAmount,
        paymentProvider: "hubtel",
        paymentStatus: "pending",
        paymentReference: {
          checkoutId: checkout.checkoutId,
          clientReference,
          checkoutUrl: checkout.checkoutHostedUrl || checkout.checkoutUrl,
          checkoutDirectUrl: checkout.checkoutDirectUrl || null,
          initiatedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      orderId,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
      clientReference,
    };
  },
);

exports.checkHubtelTicketStatus = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const orderId = safeString(request.data && request.data.orderId);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in before checking ticket status.");
    }
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId is required.");
    }

    const orderRef = db.collection("event_ticket_orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Event ticket order not found.");
    }

    const orderData = orderSnap.data() || {};
    await authorizeOrderAccess(orderData, uid, "check");

    const clientReference = safeString(orderData?.paymentReference?.clientReference);
    if (!clientReference) {
      throw new HttpsError(
        "failed-precondition",
        "Payment has not been initiated for this order yet.",
      );
    }

    const config = await getHubtelConfig();
    const url =
      `https://api-txnstatus.hubtel.com/transactions/${config.merchantAccount}` +
      `/status?clientReference=${encodeURIComponent(clientReference)}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: hubtelAuthHeader(config),
      },
    });

    if (response.status === 403) {
      throw new HttpsError(
        "permission-denied",
        "Server IP is not whitelisted with Hubtel.",
      );
    }

    const result = await response.json().catch(() => ({}));
    if (result.responseCode !== "0000" || !result.data) {
      return {
        success: false,
        status: "unknown",
        raw: result,
      };
    }

    const normalizedStatus = normalizeHubtelStatus(result.data.status);
    await orderRef.set(
      {
        status: normalizedStatus === "paid"
          ? "paid"
          : normalizedStatus === "cancelled"
            ? "cancelled"
            : safeString(orderData.status, "pending"),
        paymentStatus: paymentStatusForOrderStatus(normalizedStatus),
        paymentProvider: "hubtel",
        paymentDetails: {
          transactionId: safeString(result.data.transactionId),
          externalTransactionId: safeString(result.data.externalTransactionId),
          paymentMethod: safeString(result.data.paymentMethod),
          amount: Number(result.data.amount || orderData.totalAmount || 0),
          charges: Number(result.data.charges || 0),
          amountAfterCharges: Number(result.data.amountAfterCharges || 0),
          currencyCode: safeString(result.data.currencyCode),
          statusCheckedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      status: normalizedStatus,
      isPaid: normalizedStatus === "paid",
      details: result.data,
    };
  },
);

exports.createWebEventTicketOrder = onCall(
  {
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const selections = request.data && request.data.selections;
    const buyerName = safeString(request.data && request.data.buyerName);
    const buyerPhone = normalizePhoneNumber(request.data && request.data.buyerPhone);
    const buyerEmail = safeString(request.data && request.data.buyerEmail);

    if (!eventId) {
      throw new HttpsError("invalid-argument", "eventId is required.");
    }
    if (!selections || typeof selections !== "object") {
      throw new HttpsError("invalid-argument", "selections is required.");
    }
    if (!buyerName || !buyerPhone || !buyerEmail) {
      throw new HttpsError(
        "invalid-argument",
        "buyerName, buyerPhone, and buyerEmail are required.",
      );
    }

    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found.");
    }

    const eventData = eventSnap.data() || {};
    const ticketing = eventData.ticketing || {};
    const tiers = Array.isArray(ticketing.tiers) ? ticketing.tiers : [];
    if (!ticketing.enabled || tiers.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Ticketing is not enabled for this event.",
      );
    }

    const tierById = new Map();
    for (const tier of tiers) {
      tierById.set(safeString(tier.tierId), tier);
    }

    const selectedTiers = [];
    let totalAmount = 0;
    for (const [tierId, rawQuantity] of Object.entries(selections)) {
      const quantity = Number(rawQuantity || 0);
      if (quantity <= 0) {
        continue;
      }
      const tier = tierById.get(safeString(tierId));
      if (!tier) {
        continue;
      }
      const price = Number(tier.price || 0);
      if (price <= 0) {
        continue;
      }
      selectedTiers.push({
        tierId: safeString(tier.tierId),
        name: safeString(tier.name, "General"),
        price,
        quantity,
      });
      totalAmount += price * quantity;
    }

    if (selectedTiers.length === 0 || totalAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Select at least one paid ticket tier.",
      );
    }

    const orderRef = db.collection("event_ticket_orders").doc();
    await orderRef.set({
      eventId,
      occurrenceId: `${eventId}_primary`,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      buyerId: null,
      buyerName,
      buyerPhone,
      buyerEmail,
      selectedTiers,
      totalAmount,
      currency: safeString(ticketing.currency, "GHS"),
      status: "pending",
      paymentStatus: "initiated",
      source: "web",
      eventSnapshot: buildEventSnapshotForFirestore(eventId, eventData),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const checkout = await initiateHubtelCheckout({
      totalAmount,
      description: `Tickets: ${safeString(eventData.title, "Event")}`,
      clientReference: `evt_${orderRef.id}`,
      payeeName: buyerName,
      payeeMobileNumber: buyerPhone,
      payeeEmail: buyerEmail,
    });

    await orderRef.set(
      {
        paymentProvider: "hubtel",
        paymentStatus: "pending",
        paymentReference: {
          checkoutId: checkout.checkoutId,
          clientReference: `evt_${orderRef.id}`,
          checkoutUrl: checkout.checkoutHostedUrl || checkout.checkoutUrl,
          checkoutDirectUrl: checkout.checkoutDirectUrl || null,
          initiatedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      success: true,
      orderId: orderRef.id,
      checkoutUrl: checkout.checkoutUrl,
      checkoutId: checkout.checkoutId,
    };
  },
);

exports.hubtelCallback = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 180,
  },
  async (request, response) => {
    try {
      if (request.method !== "POST") {
        return response.status(405).json({ error: "Method not allowed." });
      }

      const payload = request.body || {};
      const data = payload.Data || {};
      const clientReference = safeString(data.ClientReference);
      if (!clientReference) {
        return response.status(400).json({ error: "Invalid callback payload." });
      }

      const config = await getHubtelConfig();
      if (config.callbackSecret) {
        const incomingSignature = safeString(request.headers["x-hubtel-signature"]);
        const expectedSignature = crypto
          .createHmac("sha256", config.callbackSecret)
          .update(JSON.stringify(payload))
          .digest("hex");
        if (!incomingSignature || incomingSignature !== expectedSignature) {
          return response.status(401).json({ error: "Invalid callback signature." });
        }
      }

      if (clientReference.startsWith("evt_")) {
        return handleEventTicketCallback(clientReference, data, response);
      }

      return response.status(400).json({
        error: "Unsupported Hubtel client reference.",
        clientReference,
      });
    } catch (error) {
      console.error("hubtelCallback error", error);
      return response.status(500).json({
        error: safeString(error && error.message, "Hubtel callback failed."),
      });
    }
  },
);

exports.hubtelReturn = onRequest(
  {
    cors: true,
    region: REGION,
    timeoutSeconds: 60,
  },
  async (request, response) => {
    const type = safeString(request.query.type, "event_ticket");
    const orderId = safeString(request.query.orderId);
    const status = safeString(request.query.status, "success");

    if (type !== "event_ticket" || !orderId) {
      return response.status(400).send("Invalid return payload.");
    }

    const deepLink =
      `${EVENTORA_SCHEME}://payment-status?orderId=${encodeURIComponent(orderId)}` +
      `&status=${encodeURIComponent(status)}`;

    return response
      .status(200)
      .set("Content-Type", "text/html; charset=utf-8")
      .send(browserRedirectHtml({ orderId, status, deepLink }));
  },
);
