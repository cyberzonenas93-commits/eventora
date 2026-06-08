"use strict";

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");
const {
  canRolePerform,
  effectiveAdminRole,
  isAllowedSuperAdminEmail,
  isKnownAdminRole,
  normalizeAdminRole,
} = require("./admin_permissions");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

const REGION = "us-central1";
const ANALYTICS_EVENT_LIMIT = 5000;
const ANALYTICS_PARAM_DENYLIST = /email|phone|password|token|secret|address|name|note|message/i;
const ALLOWED_ANALYTICS_EVENTS = new Set([
  "page_view",
  "login",
  "sign_up",
  "logout",
  "public_search",
  "event_saved",
  "event_published",
  "checkout_started",
  "checkout_step",
  "checkout_abandoned",
  "event_shared",
  "event_rsvp",
  "payment_initiated",
  "payment_completed",
  "ticket_issued",
  "ticket_checked_in",
  "ticket_order_created",
  "ticket_purchase_returned",
  "campaign_launched",
  "billing_checkout_started",
  "wallet_topup_started",
  "organizer_application_saved",
  "organizer_application_submitted",
  "admin_action",
  "sms_opt_out_recorded",
]);

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function hashValue(value) {
  const input = safeString(value);
  if (!input) return "";
  return crypto.createHash("sha256").update(input).digest("hex").slice(0, 32);
}

function sanitizeEventName(value) {
  const name = safeString(value).toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "");
  if (!name || name.length > 40 || !/^[a-z][a-z0-9_]*$/.test(name)) {
    return "";
  }
  return name;
}

function sanitizePath(value) {
  const path = safeString(value).split("?")[0].split("#")[0];
  if (!path.startsWith("/")) return "";
  return path.slice(0, 180);
}

function sanitizeArea(value) {
  const area = safeString(value).toLowerCase().replace(/[^a-z0-9_/-]+/g, "_");
  return area.slice(0, 80);
}

function sanitizeParams(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.entries(value).reduce((params, [rawKey, rawValue]) => {
    const key = safeString(rawKey).replace(/[^a-zA-Z0-9_]+/g, "_").slice(0, 40);
    if (!key || ANALYTICS_PARAM_DENYLIST.test(key)) return params;
    if (rawValue == null) return params;
    if (typeof rawValue === "boolean") {
      params[key] = rawValue;
      return params;
    }
    if (typeof rawValue === "number") {
      if (Number.isFinite(rawValue)) params[key] = rawValue;
      return params;
    }
    if (typeof rawValue === "string") {
      const text = safeString(rawValue);
      if (!text || ANALYTICS_PARAM_DENYLIST.test(text)) return params;
      params[key] = text.slice(0, 120);
    }
    return params;
  }, {});
}

async function resolveAdminEmail(uid, adminData) {
  const docEmail = safeString(adminData && adminData.email).toLowerCase();
  if (docEmail) return docEmail;
  try {
    const authUser = await admin.auth().getUser(uid);
    return safeString(authUser.email).toLowerCase();
  } catch (error) {
    return "";
  }
}

async function assertAdminCan(uid, action) {
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const adminData = adminSnap.data() || {};
  const role = normalizeAdminRole(adminData.role);
  const status = safeString(adminData.status, "active").toLowerCase();
  const email = await resolveAdminEmail(uid, adminData);
  if (!isKnownAdminRole(role) || status === "disabled") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  if (effectiveAdminRole(role) === "superadmin" && !isAllowedSuperAdminEmail(email)) {
    throw new HttpsError("permission-denied", "Owner access required.");
  }
  if (!canRolePerform(role, action)) {
    throw new HttpsError("permission-denied", "This admin role cannot perform that action.");
  }
  return { uid, role };
}

function timestampToDate(value) {
  if (!value) return null;
  if (value instanceof Timestamp || typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function dayKey(date) {
  return date.toISOString().slice(0, 10);
}

function dateDaysAgo(days) {
  const date = new Date();
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() - days + 1);
  return date;
}

function initDaily(days) {
  const start = dateDaysAgo(days);
  return Array.from({ length: days }, (_, index) => {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    return {
      date: dayKey(date),
      pageViews: 0,
      visitors: 0,
      signups: 0,
      orders: 0,
      revenue: 0,
      tickets: 0,
      eventsPublished: 0,
      campaigns: 0,
      visitorKeys: new Set(),
    };
  });
}

function normalizePaymentStatus(value) {
  return safeString(value).replace(/[_\s-]+/g, "").toLowerCase();
}

function isPaidOrder(data) {
  const status = normalizePaymentStatus(data.paymentStatus || data.status);
  return ["paid", "cashatgatepaid"].includes(status);
}

function orderTicketCount(data) {
  const selectedTiers = Array.isArray(data.selectedTiers) ? data.selectedTiers : [];
  if (selectedTiers.length > 0) {
    return selectedTiers.reduce((sum, tier) => sum + Number(tier.quantity || 0), 0);
  }
  return Number(data.ticketCount || data.quantity || 0);
}

function moneyAmount(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  return Math.round(amount * 100) / 100;
}

function selectedTiersFromOrder(data) {
  return Array.isArray(data.selectedTiers) ? data.selectedTiers : [];
}

function groupDate(value) {
  const date = timestampToDate(value);
  return date ? dayKey(date) : dayKey(new Date());
}

function percent(numerator, denominator) {
  if (!denominator) return 0;
  return Math.round((Number(numerator || 0) / Number(denominator || 1)) * 10000) / 100;
}

function chunked(values, size = 10) {
  const chunks = [];
  for (let i = 0; i < values.length; i += size) chunks.push(values.slice(i, i + size));
  return chunks;
}

async function assertOrganizationAnalyticsAccess(uid, organizationId) {
  const orgId = safeString(organizationId);
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  if (!orgId) throw new HttpsError("invalid-argument", "organizationId is required.");
  if (await hasPlatformAnalyticsAccess(uid)) return { uid, role: "admin" };
  if (orgId === `org_${uid}`) return { uid, role: "owner" };

  const [orgSnap, memberSnap, appSnap] = await Promise.all([
    db.collection("organizations").doc(orgId).get(),
    db.collection("organization_members").doc(`${orgId}_${uid}`).get(),
    db.collection("organizer_applications").doc(uid).get(),
  ]);
  const org = orgSnap.exists ? orgSnap.data() || {} : {};
  if (safeString(org.ownerId) === uid) return { uid, role: "owner" };
  const member = memberSnap.exists ? memberSnap.data() || {} : {};
  const permissions = member.permissions && typeof member.permissions === "object" ? member.permissions : {};
  if (
    safeString(member.organizationId) === orgId &&
    safeString(member.userId) === uid &&
    safeString(member.status, "active") !== "disabled" &&
    (permissions.viewAnalytics === true || permissions.manageEvents === true || safeString(member.role) === "owner")
  ) {
    return { uid, role: safeString(member.role, "member") };
  }
  const app = appSnap.exists ? appSnap.data() || {} : {};
  if (safeString(app.organizationId) === orgId && safeString(app.userId) === uid) {
    return { uid, role: "organizer" };
  }
  throw new HttpsError("permission-denied", "You cannot view analytics for this workspace.");
}

async function hasPlatformAnalyticsAccess(uid) {
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  const role = normalizeAdminRole(data.role);
  const status = safeString(data.status, "active").toLowerCase();
  if (!isKnownAdminRole(role) || status === "disabled") return false;
  return canRolePerform(role, "read_analytics");
}

async function docsForOrganization(collectionName, organizationId, max = 1000) {
  const snap = await db.collection(collectionName).where("organizationId", "==", organizationId).limit(max).get();
  return snap.docs.map((docSnap) => ({ id: docSnap.id, data: docSnap.data() || {} }));
}

async function docsForEventIds(collectionName, eventIds, maxPerChunk = 300) {
  const ids = eventIds.filter(Boolean);
  if (ids.length === 0) return [];
  const snapshots = await Promise.all(
    chunked(ids, 10).map((chunk) =>
      db.collection(collectionName).where("eventId", "in", chunk).limit(maxPerChunk).get(),
    ),
  );
  return snapshots.flatMap((snap) => snap.docs.map((docSnap) => ({ id: docSnap.id, data: docSnap.data() || {} })));
}

function sourceFromAnalytics(data) {
  const params = data.params && typeof data.params === "object" ? data.params : {};
  const raw =
    safeString(params.source) ||
    safeString(params.utm_source) ||
    safeString(params.channel) ||
    safeString(params.ref) ||
    safeString(params.referrer) ||
    safeString(data.path).includes("ref=") && "referral";
  const lower = safeString(raw, "direct").toLowerCase();
  if (lower.includes("instagram")) return "Instagram";
  if (lower.includes("whatsapp")) return "WhatsApp";
  if (lower.includes("sms")) return "SMS campaign";
  if (lower.includes("push")) return "Push campaign";
  if (lower.includes("featured")) return "Featured listing";
  if (lower.includes("qr")) return "QR poster scan";
  if (lower.includes("ref") || lower.includes("partner") || lower.includes("promo")) return "Promoter link";
  return lower === "direct" ? "Direct / unknown" : lower.replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function eventIdFromAnalytics(data) {
  const params = data.params && typeof data.params === "object" ? data.params : {};
  return safeString(params.event_id || params.eventId || params.event);
}

function buildInsightRows({ sourceRows, tierRows, funnel, campaigns, inventoryRows, staffRows }) {
  const bestSource = sourceRows.filter((row) => row.pageViews > 0).sort((a, b) => b.conversionRate - a.conversionRate)[0];
  const weakestTier = tierRows.filter((row) => row.capacity > 0).sort((a, b) => a.soldThrough - b.soldThrough)[0];
  const paidCampaign = campaigns.sort((a, b) => Number(b.ticketsSold || 0) - Number(a.ticketsSold || 0))[0];
  const lowStock = inventoryRows.filter((row) => row.stock <= 5).sort((a, b) => a.stock - b.stock)[0];
  const topStaff = staffRows.sort((a, b) => b.salesGhs - a.salesGhs)[0];
  return [
    bestSource
      ? `Your event page converts best from ${bestSource.source}.`
      : "Your attribution data is still warming up; direct and shared links will separate as traffic arrives.",
    weakestTier
      ? `${weakestTier.tierName} is underperforming at ${weakestTier.soldThrough}% sold-through.`
      : "Ticket tiers are healthy enough to monitor before making a pricing change.",
    paidCampaign
      ? `${paidCampaign.name} is the strongest campaign signal so far.`
      : "Launch a campaign to compare SMS, push, featured listings, and promoter links.",
    funnel.checkoutStarted > 0
      ? `${percent(funnel.paymentCompleted, funnel.checkoutStarted)}% of checkout starts become completed payments.`
      : "Checkout leakage will appear once buyers start the purchase flow.",
    lowStock ? `${lowStock.itemName} is low on stock.` : "",
    topStaff ? `${topStaff.staffName} leads staff-recorded sales.` : "",
  ].filter(Boolean);
}

async function countCollection(collectionName) {
  try {
    const snap = await db.collection(collectionName).count().get();
    return Number(snap.data().count || 0);
  } catch (error) {
    const snap = await db.collection(collectionName).limit(1000).get();
    return snap.size;
  }
}

async function countWhere(collectionName, field, operator, value) {
  try {
    const snap = await db.collection(collectionName).where(field, operator, value).count().get();
    return Number(snap.data().count || 0);
  } catch (error) {
    const snap = await db.collection(collectionName).where(field, operator, value).limit(1000).get();
    return snap.size;
  }
}

async function recentCollection(collectionName, startDate) {
  const snap = await db
    .collection(collectionName)
    .where("createdAt", ">=", Timestamp.fromDate(startDate))
    .limit(ANALYTICS_EVENT_LIMIT)
    .get();
  return snap.docs.map((docSnap) => ({ id: docSnap.id, data: docSnap.data() || {} }));
}

function addDailyValue(dailyByDate, dateValue, updater) {
  const date = timestampToDate(dateValue);
  if (!date) return;
  const entry = dailyByDate.get(dayKey(date));
  if (!entry) return;
  updater(entry);
}

exports.recordAnalyticsEvent = onCall(
  { region: REGION, timeoutSeconds: 15 },
  async (request) => {
    const name = sanitizeEventName(request.data && request.data.name);
    if (!name || !ALLOWED_ANALYTICS_EVENTS.has(name)) {
      throw new HttpsError("invalid-argument", "Unknown analytics event.");
    }

    const uid = request.auth && request.auth.uid ? request.auth.uid : "";
    const anonymousIdHash = hashValue(request.data && request.data.anonymousId);
    const rateKey = uid || anonymousIdHash || hashValue(request.rawRequest && request.rawRequest.ip) || "anonymous";
    await checkRateLimit(db, rateKey, "analytics_event", { maxCalls: 180, windowSeconds: 3600 });

    const params = sanitizeParams(request.data && request.data.params);
    const role = sanitizeArea(request.data && request.data.role);
    const organizationId = safeString(request.data && request.data.organizationId).slice(0, 80);
    const path = sanitizePath(request.data && request.data.path);

    await db.collection("analytics_events").add({
      name,
      uid: uid || null,
      anonymousIdHash: anonymousIdHash || null,
      role: role || null,
      organizationId: organizationId || null,
      path: path || null,
      area: sanitizeArea(request.data && request.data.area) || null,
      params,
      userAgentHash: hashValue(request.rawRequest && request.rawRequest.get("user-agent")),
      createdAt: FieldValue.serverTimestamp(),
    });

    return { success: true };
  },
);

exports.getAdminAnalyticsOverview = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    await assertAdminCan(request.auth.uid, "read_analytics");

    const start30 = dateDaysAgo(30);
    const start7 = dateDaysAgo(7);
    const daily = initDaily(30);
    const dailyByDate = new Map(daily.map((entry) => [entry.date, entry]));

    const [
      totalUsers,
      totalOrganizations,
      totalEvents,
      publishedEvents,
      totalOrders,
      totalCampaigns,
      totalSupportTickets,
      submittedApplications,
      analyticsEvents,
      recentOrders,
      recentUsers,
      recentOrganizations,
      recentEvents,
      recentCampaigns,
      recentSupportTickets,
    ] = await Promise.all([
      countCollection("users"),
      countCollection("organizations"),
      countCollection("events"),
      countWhere("events", "status", "==", "published"),
      countCollection("event_ticket_orders"),
      countCollection("promotion_campaigns"),
      countCollection("support_tickets"),
      countWhere("organizer_applications", "status", "==", "submitted"),
      recentCollection("analytics_events", start30),
      recentCollection("event_ticket_orders", start30),
      recentCollection("users", start30),
      recentCollection("organizations", start30),
      recentCollection("events", start30),
      recentCollection("promotion_campaigns", start30),
      recentCollection("support_tickets", start30),
    ]);

    const topEventsById = new Map();
    const campaignStatusCounts = {};
    const recentVisitorKeys = new Set();
    let pageViews30 = 0;
    let signups30 = 0;
    let checkoutStarts30 = 0;
    let ticketOrdersTracked30 = 0;
    let adminActions30 = 0;
    let revenue30 = 0;
    let tickets30 = 0;
    let paidOrders30 = 0;
    let campaignSpend30 = 0;

    for (const event of analyticsEvents) {
      const data = event.data;
      const visitorKey = safeString(data.uid) || safeString(data.anonymousIdHash);
      if (visitorKey) recentVisitorKeys.add(visitorKey);
      addDailyValue(dailyByDate, data.createdAt, (entry) => {
        if (visitorKey) entry.visitorKeys.add(visitorKey);
        if (data.name === "page_view") entry.pageViews += 1;
        if (data.name === "sign_up") entry.signups += 1;
      });
      if (data.name === "page_view") pageViews30 += 1;
      if (data.name === "sign_up") signups30 += 1;
      if (data.name === "checkout_started") checkoutStarts30 += 1;
      if (data.name === "ticket_order_created") ticketOrdersTracked30 += 1;
      if (data.name === "admin_action") adminActions30 += 1;
    }

    for (const order of recentOrders) {
      const data = order.data;
      if (!isPaidOrder(data)) continue;
      const amount = Number(data.totalAmount || 0);
      const tickets = orderTicketCount(data);
      paidOrders30 += 1;
      revenue30 += amount;
      tickets30 += tickets;
      addDailyValue(dailyByDate, data.createdAt, (entry) => {
        entry.orders += 1;
        entry.revenue += amount;
        entry.tickets += tickets;
      });
      const eventId = safeString(data.eventId, "unknown");
      const existing = topEventsById.get(eventId) || {
        eventId,
        title: safeString(data.eventTitle, eventId),
        revenue: 0,
        orders: 0,
        tickets: 0,
      };
      existing.revenue += amount;
      existing.orders += 1;
      existing.tickets += tickets;
      topEventsById.set(eventId, existing);
    }

    for (const user of recentUsers) {
      addDailyValue(dailyByDate, user.data.createdAt, (entry) => {
        entry.signups += 1;
      });
    }

    for (const event of recentEvents) {
      if (safeString(event.data.status).toLowerCase() === "published") {
        addDailyValue(dailyByDate, event.data.createdAt || event.data.updatedAt, (entry) => {
          entry.eventsPublished += 1;
        });
      }
    }

    for (const campaign of recentCampaigns) {
      const data = campaign.data;
      const status = safeString(data.status, "unknown").toLowerCase();
      campaignStatusCounts[status] = (campaignStatusCounts[status] || 0) + 1;
      campaignSpend30 += Number(data.totalSmsCharged || 0) + Number(data.totalPushCharged || 0);
      addDailyValue(dailyByDate, data.createdAt, (entry) => {
        entry.campaigns += 1;
      });
    }

    const since7 = (value) => {
      const date = timestampToDate(value);
      return Boolean(date && date >= start7);
    };
    const paidOrders7 = recentOrders.filter((order) => isPaidOrder(order.data) && since7(order.data.createdAt));
    const campaigns7 = recentCampaigns.filter((campaign) => since7(campaign.data.createdAt));
    const support7 = recentSupportTickets.filter((ticket) => since7(ticket.data.createdAt));

    return {
      generatedAt: new Date().toISOString(),
      totals: {
        users: totalUsers,
        organizations: totalOrganizations,
        events: totalEvents,
        publishedEvents,
        ticketOrders: totalOrders,
        campaigns: totalCampaigns,
        supportTickets: totalSupportTickets,
        submittedApplications,
      },
      last30: {
        pageViews: pageViews30,
        visitors: recentVisitorKeys.size,
        signups: signups30 || recentUsers.length,
        newOrganizations: recentOrganizations.length,
        paidOrders: paidOrders30,
        revenue: Math.round(revenue30 * 100) / 100,
        tickets: tickets30,
        checkoutStarts: checkoutStarts30,
        ticketOrdersTracked: ticketOrdersTracked30,
        campaigns: recentCampaigns.length,
        campaignSpend: Math.round(campaignSpend30 * 100) / 100,
        supportTickets: recentSupportTickets.length,
        adminActions: adminActions30,
      },
      last7: {
        paidOrders: paidOrders7.length,
        revenue: Math.round(
          paidOrders7.reduce((sum, order) => sum + Number(order.data.totalAmount || 0), 0) * 100,
        ) / 100,
        tickets: paidOrders7.reduce((sum, order) => sum + orderTicketCount(order.data), 0),
        campaigns: campaigns7.length,
        supportTickets: support7.length,
      },
      conversion: {
        eventPublishRate: totalEvents > 0 ? publishedEvents / totalEvents : 0,
        checkoutToOrderRate: checkoutStarts30 > 0 ? ticketOrdersTracked30 / checkoutStarts30 : null,
        averageOrderValue: paidOrders30 > 0 ? revenue30 / paidOrders30 : 0,
      },
      campaignStatusCounts,
      topEvents: [...topEventsById.values()]
        .sort((left, right) => right.revenue - left.revenue)
        .slice(0, 6)
        .map((event) => ({
          ...event,
          revenue: Math.round(event.revenue * 100) / 100,
        })),
      daily: daily.map(({ visitorKeys, ...entry }) => ({
        ...entry,
        visitors: visitorKeys.size,
        revenue: Math.round(entry.revenue * 100) / 100,
      })),
    };
  },
);

exports.getHostAnalyticsOverview = onCall(
  { region: REGION, timeoutSeconds: 90, memory: "512MiB" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const organizationId = safeString(request.data && request.data.organizationId);
    const requestedEventId = safeString(request.data && request.data.eventId);
    await assertOrganizationAnalyticsAccess(request.auth.uid, organizationId);

    const events = await docsForOrganization("events", organizationId, 250);
    const eventIds = events.map((event) => event.id);
    const visibleEventIds = requestedEventId ? eventIds.filter((id) => id === requestedEventId) : eventIds;
    const eventTitleById = new Map(events.map((event) => [event.id, safeString(event.data.title, event.id)]));
    const eventDataById = new Map(events.map((event) => [event.id, event.data]));
    if (requestedEventId && !eventTitleById.has(requestedEventId)) {
      throw new HttpsError("permission-denied", "This event is not in your workspace.");
    }

    const [
      aggregateDaily,
      aggregateFunnel,
      aggregateCampaign,
      aggregateStaff,
      aggregateInventory,
      orders,
      rsvps,
      campaigns,
      analyticsEvents,
      walletTransactions,
      tablePackages,
      partnerLinks,
      scanLogs,
      tabs,
      inventoryItems,
      refunds,
      payouts,
    ] = await Promise.all([
      docsForOrganization("event_daily_metrics", organizationId, 500),
      docsForOrganization("event_funnel_metrics", organizationId, 300),
      docsForOrganization("event_campaign_metrics", organizationId, 500),
      docsForOrganization("event_staff_metrics", organizationId, 500),
      docsForOrganization("event_inventory_metrics", organizationId, 500),
      docsForOrganization("event_ticket_orders", organizationId, 1000),
      docsForOrganization("event_rsvps", organizationId, 1000),
      docsForOrganization("promotion_campaigns", organizationId, 500),
      docsForOrganization("analytics_events", organizationId, 5000),
      docsForOrganization("wallet_transactions", organizationId, 1000),
      docsForEventIds("tablePackages", visibleEventIds, 200),
      docsForOrganization("partner_event_links", organizationId, 500),
      docsForEventIds("ticket_scan_logs", visibleEventIds, 500),
      docsForOrganization("event_ops_tabs", organizationId, 1000),
      docsForOrganization("event_inventory_items", organizationId, 1000),
      docsForOrganization("refunds", organizationId, 500).catch(() => []),
      docsForOrganization("payout_requests", organizationId, 500).catch(() => []),
    ]);

    const eventFilter = (doc) => !requestedEventId || safeString(doc.data.eventId) === requestedEventId;
    const scopedOrders = orders.filter(eventFilter);
    const scopedRsvps = rsvps.filter(eventFilter);
    const scopedCampaigns = campaigns.filter(eventFilter);
    const scopedAnalytics = analyticsEvents.filter((event) => {
      const eventId = eventIdFromAnalytics(event.data);
      return !requestedEventId || eventId === requestedEventId || safeString(event.data.path).includes(`/events/${requestedEventId}`);
    });
    const scopedTabs = tabs.filter(eventFilter);
    const scopedInventoryItems = inventoryItems.filter(eventFilter);
    const scopedTablePackages = tablePackages.filter(eventFilter);
    const scopedScanLogs = scanLogs.filter(eventFilter);

    const paidStatuses = new Set(["paid", "cashatgatepaid", "complimentary", "cashatgate"]);
    const failedStatuses = new Set(["failed", "cancelled", "canceled"]);
    const pendingStatuses = new Set(["pending", "initiated", "unpaid"]);
    const paidOrders = scopedOrders.filter((order) => paidStatuses.has(normalizePaymentStatus(order.data.paymentStatus || order.data.status)));
    const failedOrders = scopedOrders.filter((order) => failedStatuses.has(normalizePaymentStatus(order.data.paymentStatus || order.data.status)));
    const pendingOrders = scopedOrders.filter((order) => pendingStatuses.has(normalizePaymentStatus(order.data.paymentStatus || order.data.status)));
    const cashOrders = scopedOrders.filter((order) => normalizePaymentStatus(order.data.paymentStatus || order.data.status).includes("cashatgate"));
    const compOrders = scopedOrders.filter((order) => normalizePaymentStatus(order.data.paymentStatus || order.data.source) === "complimentary" || safeString(order.data.source) === "complimentary");
    const grossSales = moneyAmount(paidOrders.reduce((sum, order) => sum + Number(order.data.totalAmount || 0), 0));
    const refundsGhs = moneyAmount(refunds.filter(eventFilter).reduce((sum, refund) => sum + Number(refund.data.amount || refund.data.amountGhs || 0), 0));
    const campaignSpend = moneyAmount(scopedCampaigns.reduce((sum, campaign) =>
      sum + Number(campaign.data.totalSmsCharged || 0) + Number(campaign.data.totalPushCharged || 0) + Number(campaign.data.walletReservationAmount || 0),
    0));
    const platformFees = moneyAmount(paidOrders.reduce((sum, order) => sum + Number(order.data.platformFeeGhs || order.data.platformFee || order.data.serviceFee || 0), 0));
    const netRevenue = moneyAmount(grossSales - platformFees - refundsGhs);
    const ticketsSold = paidOrders.reduce((sum, order) => sum + orderTicketCount(order.data), 0);
    const cashAtGateCollected = moneyAmount(cashOrders.reduce((sum, order) => sum + Number(order.data.totalAmount || 0), 0));
    const payoutReadyBalance = moneyAmount(payouts.reduce((sum, payout) => {
      const status = safeString(payout.data.status);
      return status === "pending" || status === "ready" ? sum + Number(payout.data.amount || payout.data.amountGhs || 0) : sum;
    }, netRevenue));

    const pageViews = scopedAnalytics.filter((event) => event.data.name === "page_view").length ||
      aggregateDaily.filter(eventFilter).reduce((sum, row) => sum + Number(row.data.pageViews || row.data.views || 0), 0);
    const likes = events
      .filter((event) => !requestedEventId || event.id === requestedEventId)
      .reduce((sum, event) => sum + Number((event.data.metrics || {}).likesCount || event.data.likesCount || 0), 0);
    const shares = scopedAnalytics.filter((event) => event.data.name === "event_shared").length;
    const checkoutStarted = scopedAnalytics.filter((event) => event.data.name === "checkout_started").length ||
      aggregateFunnel.filter(eventFilter).reduce((sum, row) => sum + Number(row.data.checkoutStarted || 0), 0);
    const paymentInitiated = scopedAnalytics.filter((event) => event.data.name === "payment_initiated").length ||
      scopedOrders.filter((order) => normalizePaymentStatus(order.data.paymentStatus).includes("initiated")).length;
    const paymentCompleted = paidOrders.length;
    const checkedIn = scopedScanLogs.filter((log) => ["admit", "cash_collect_and_admit"].includes(safeString(log.data.type))).length;
    const ticketIssued = ticketsSold;
    const conversionRate = percent(paymentCompleted, pageViews || scopedRsvps.length + paidOrders.length);
    const roi = campaignSpend > 0 ? Math.round(((grossSales - campaignSpend) / campaignSpend) * 10000) / 100 : 0;

    const salesByDate = new Map();
    for (const order of paidOrders) {
      const date = groupDate(order.data.createdAt);
      const existing = salesByDate.get(date) || { date, grossSales: 0, tickets: 0, orders: 0 };
      existing.grossSales += Number(order.data.totalAmount || 0);
      existing.tickets += orderTicketCount(order.data);
      existing.orders += 1;
      salesByDate.set(date, existing);
    }
    const tierById = new Map();
    for (const event of events.filter((event) => !requestedEventId || event.id === requestedEventId)) {
      const ticketing = event.data.ticketing && typeof event.data.ticketing === "object" ? event.data.ticketing : {};
      const tiers = Array.isArray(ticketing.tiers) ? ticketing.tiers : [];
      for (const tier of tiers) {
        const id = safeString(tier.tierId || tier.id || tier.name);
        if (!id) continue;
        tierById.set(id, {
          tierId: id,
          eventId: event.id,
          eventTitle: eventTitleById.get(event.id) || event.id,
          tierName: safeString(tier.name, "General"),
          price: Number(tier.price || 0),
          capacity: Number(tier.maxQuantity || tier.capacity || 0),
          sold: Number(tier.sold || 0),
          revenue: 0,
        });
      }
    }
    for (const order of paidOrders) {
      for (const tier of selectedTiersFromOrder(order.data)) {
        const id = safeString(tier.tierId || tier.id || tier.name);
        const existing = tierById.get(id) || {
          tierId: id || "unknown",
          eventId: safeString(order.data.eventId),
          eventTitle: eventTitleById.get(safeString(order.data.eventId)) || safeString(order.data.eventTitle, "Unknown event"),
          tierName: safeString(tier.name || tier.tierName, "General"),
          price: Number(tier.price || 0),
          capacity: 0,
          sold: 0,
          revenue: 0,
        };
        const quantity = Number(tier.quantity || 0);
        existing.sold += quantity;
        existing.revenue += Number(tier.price || existing.price || 0) * quantity;
        tierById.set(existing.tierId, existing);
      }
    }
    const tierRows = [...tierById.values()].map((tier) => ({
      ...tier,
      revenue: moneyAmount(tier.revenue),
      soldThrough: percent(tier.sold, tier.capacity),
    })).sort((a, b) => b.revenue - a.revenue);

    const sourceMap = new Map();
    for (const event of scopedAnalytics) {
      const source = sourceFromAnalytics(event.data);
      const existing = sourceMap.get(source) || {
        source,
        linkClicks: 0,
        pageViews: 0,
        rsvps: 0,
        ticketsSold: 0,
        revenue: 0,
        campaignSpend: 0,
      };
      if (event.data.name === "page_view") existing.pageViews += 1;
      if (event.data.name === "event_shared") existing.linkClicks += 1;
      if (event.data.name === "event_rsvp") existing.rsvps += 1;
      if (event.data.name === "ticket_order_created" || event.data.name === "payment_completed") existing.ticketsSold += 1;
      sourceMap.set(source, existing);
    }
    for (const link of partnerLinks.filter(eventFilter)) {
      const source = "Promoter link";
      const existing = sourceMap.get(source) || { source, linkClicks: 0, pageViews: 0, rsvps: 0, ticketsSold: 0, revenue: 0, campaignSpend: 0 };
      existing.linkClicks += Number(link.data.clicks || 0);
      existing.ticketsSold += Number(link.data.orders || 0);
      existing.revenue += Number(link.data.revenue || 0);
      sourceMap.set(source, existing);
    }
    const sourceRows = [...sourceMap.values()].map((row) => ({
      ...row,
      revenue: moneyAmount(row.revenue),
      conversionRate: percent(row.ticketsSold, row.pageViews || row.linkClicks),
      costPerTicket: row.ticketsSold > 0 ? moneyAmount(row.campaignSpend / row.ticketsSold) : 0,
      roi: row.campaignSpend > 0 ? percent(row.revenue - row.campaignSpend, row.campaignSpend) : 0,
    })).sort((a, b) => b.revenue - a.revenue);

    const campaignRows = scopedCampaigns.map((campaign) => {
      const eventId = safeString(campaign.data.eventId);
      const spend = Number(campaign.data.totalSmsCharged || 0) + Number(campaign.data.totalPushCharged || 0) + Number(campaign.data.walletReservationAmount || 0);
      const campaignMetrics = aggregateCampaign.find((row) => row.id === campaign.id || safeString(row.data.campaignId) === campaign.id);
      const sold = Number(campaignMetrics?.data.ticketsSold || campaign.data.ticketsSold || 0);
      const revenue = Number(campaignMetrics?.data.revenue || campaign.data.revenue || 0);
      return {
        id: campaign.id,
        eventId,
        eventTitle: eventTitleById.get(eventId) || safeString(campaign.data.eventTitle, "Event"),
        name: safeString(campaign.data.name, "Campaign"),
        channels: Array.isArray(campaign.data.channels) ? campaign.data.channels.map(String) : [],
        clicks: Number(campaignMetrics?.data.clicks || campaign.data.clicks || 0),
        pageViews: Number(campaignMetrics?.data.pageViews || 0),
        rsvps: Number(campaignMetrics?.data.rsvps || 0),
        ticketsSold: sold,
        revenue: moneyAmount(revenue),
        spendGhs: moneyAmount(spend),
        conversionRate: percent(sold, campaignMetrics?.data.clicks || campaignMetrics?.data.pageViews || 0),
        costPerTicket: sold > 0 ? moneyAmount(spend / sold) : 0,
        roi: spend > 0 ? percent(revenue - spend, spend) : 0,
      };
    });

    const promoterRows = partnerLinks.filter(eventFilter).map((link) => {
      const revenue = Number(link.data.revenue || 0);
      const commissionRate = Number(link.data.commissionRate || 0);
      const clicks = Number(link.data.clicks || 0);
      const sales = Number(link.data.orders || 0);
      return {
        id: link.id,
        name: safeString(link.data.partnerName || link.data.refCode, "Promoter"),
        refCode: safeString(link.data.refCode),
        clicks,
        sales,
        rsvps: Number(link.data.rsvps || 0),
        revenue: moneyAmount(revenue),
        commissionOwed: moneyAmount(revenue * (commissionRate / 100)),
        conversionRate: percent(sales, clicks),
        fraudSignals: Number(link.data.duplicateClicks || 0),
      };
    });

    const staffSales = new Map();
    for (const tab of scopedTabs) {
      const staffId = safeString(tab.data.staffId || tab.data.closedByStaffId || tab.data.createdByStaffId, "unknown");
      const existing = staffSales.get(staffId) || {
        staffId,
        staffName: safeString(tab.data.staffName, "Staff"),
        role: safeString(tab.data.staffRole || tab.data.role, "Staff"),
        openTabs: 0,
        closedTabs: 0,
        salesGhs: 0,
      };
      if (safeString(tab.data.status, "open") === "closed") {
        existing.closedTabs += 1;
        existing.salesGhs += Number(tab.data.totalAmount || 0);
      } else {
        existing.openTabs += 1;
      }
      staffSales.set(staffId, existing);
    }
    const staffRows = [...staffSales.values()].map((row) => ({ ...row, salesGhs: moneyAmount(row.salesGhs) }));

    const inventoryRows = scopedInventoryItems.map((item) => {
      const soldCount = Number(item.data.soldCount || 0);
      const selling = Number(item.data.sellingGhs || 0);
      const cost = Number(item.data.costGhs || 0);
      return {
        id: item.id,
        itemName: safeString(item.data.name, "Item"),
        category: safeString(item.data.category, "General"),
        stock: Number(item.data.stock || 0),
        soldCount,
        salesGhs: moneyAmount(soldCount * selling),
        costOfGoodsGhs: moneyAmount(soldCount * cost),
        grossMarginGhs: moneyAmount(soldCount * (selling - cost)),
        lowStock: Number(item.data.stock || 0) <= 5,
      };
    });
    const tablePackageRows = scopedTablePackages.map((pkg) => ({
      id: pkg.id,
      name: safeString(pkg.data.name, "Table package"),
      priceGhs: moneyAmount(pkg.data.priceGhs),
      quantity: Number(pkg.data.quantity || 0),
      booked: Number(pkg.data.booked || 0),
      revenue: moneyAmount(Number(pkg.data.booked || 0) * Number(pkg.data.priceGhs || 0)),
      soldThrough: percent(pkg.data.booked, pkg.data.quantity),
    }));

    const duplicateScans = scopedScanLogs.filter((log) => safeString(log.data.outcome).includes("already")).length;
    const invalidScans = scopedScanLogs.filter((log) => safeString(log.data.status) === "error" || safeString(log.data.outcome).includes("invalid")).length;
    const entryPaceByHour = new Map();
    for (const log of scopedScanLogs) {
      const date = timestampToDate(log.data.createdAt);
      if (!date) continue;
      const key = `${String(date.getHours()).padStart(2, "0")}:00`;
      entryPaceByHour.set(key, (entryPaceByHour.get(key) || 0) + 1);
    }
    const entryPace = [...entryPaceByHour.entries()].map(([hour, admits]) => ({ hour, admits })).sort((a, b) => a.hour.localeCompare(b.hour));

    const funnel = {
      pageView: pageViews,
      likedOrSaved: likes,
      shared: shares,
      rsvp: scopedRsvps.length,
      checkoutStarted,
      paymentInitiated,
      paymentCompleted,
      ticketIssued,
      checkedIn,
    };
    const insightRows = buildInsightRows({ sourceRows, tierRows, funnel, campaigns: campaignRows, inventoryRows, staffRows });

    return {
      success: true,
      generatedAt: new Date().toISOString(),
      organizationId,
      eventId: requestedEventId || null,
      aggregateSources: {
        eventDailyMetrics: aggregateDaily.length,
        eventFunnelMetrics: aggregateFunnel.length,
        eventCampaignMetrics: aggregateCampaign.length,
        eventStaffMetrics: aggregateStaff.length,
        eventInventoryMetrics: aggregateInventory.length,
        fallbackRawEvents: scopedAnalytics.length,
      },
      executive: {
        grossSales,
        netRevenue,
        ticketsSold,
        rsvps: scopedRsvps.length,
        conversionRate,
        eventPageViews: pageViews,
        likesOrSaves: likes,
        shares,
        campaignSpend,
        roi,
        cashAtGateCollected,
        refunds: refundsGhs,
        payoutReadyBalance,
        insight: insightRows.slice(0, 3).join(" "),
      },
      sales: {
        overTime: [...salesByDate.values()].sort((a, b) => a.date.localeCompare(b.date)).map((row) => ({
          ...row,
          grossSales: moneyAmount(row.grossSales),
        })),
        tierBreakdown: tierRows,
        averageOrderValue: paidOrders.length ? moneyAmount(grossSales / paidOrders.length) : 0,
        buyerCount: new Set(paidOrders.map((order) => safeString(order.data.buyerEmail || order.data.buyerPhone || order.id))).size,
        ticketCount: ticketsSold,
        compTickets: compOrders.reduce((sum, order) => sum + orderTicketCount(order.data), 0),
        cashAtGateTickets: cashOrders.reduce((sum, order) => sum + orderTicketCount(order.data), 0),
        failedPayments: failedOrders.length,
        pendingPayments: pendingOrders.length,
        refunds: refundsGhs,
        abandonedCheckout: Math.max(0, checkoutStarted - paymentCompleted),
        fastestTier: tierRows.sort((a, b) => b.soldThrough - a.soldThrough)[0] || null,
        suggestedTierToPromote: tierRows.sort((a, b) => (a.soldThrough - b.soldThrough) || (b.capacity - a.capacity))[0] || null,
      },
      audience: {
        ageGenderAvailable: false,
        consentedDemographics: [],
        cities: [...new Map(events.filter((event) => !requestedEventId || event.id === requestedEventId).map((event) => [safeString(event.data.city, "Unknown"), { city: safeString(event.data.city, "Unknown"), count: 1 }])).values()],
        returningAttendees: 0,
        newAttendees: paidOrders.length,
        mostEngagedUsers: [],
        topBuyers: paidOrders
          .map((order) => ({ name: safeString(order.data.buyerName, "Buyer"), email: maskForAnalytics(order.data.buyerEmail), spend: Number(order.data.totalAmount || 0), tickets: orderTicketCount(order.data) }))
          .sort((a, b) => b.spend - a.spend)
          .slice(0, 10)
          .map((row) => ({ ...row, spend: moneyAmount(row.spend) })),
        rsvpToPurchaseConversion: percent(paidOrders.length, scopedRsvps.length),
        likedSavedNotPurchased: Math.max(0, likes - paidOrders.length),
        waitlistOrInterested: Math.max(0, likes + scopedRsvps.length - paidOrders.length),
      },
      funnel,
      funnelRows: [
        ["Event page view", funnel.pageView],
        ["Like / save", funnel.likedOrSaved],
        ["Share", funnel.shared],
        ["RSVP", funnel.rsvp],
        ["Checkout started", funnel.checkoutStarted],
        ["Payment initiated", funnel.paymentInitiated],
        ["Payment completed", funnel.paymentCompleted],
        ["Ticket issued", funnel.ticketIssued],
        ["Checked in", funnel.checkedIn],
      ].map(([label, value], index, rows) => ({
        label,
        value,
        conversionFromPrevious: index === 0 ? 100 : percent(value, rows[index - 1][1]),
      })),
      marketing: {
        attribution: sourceRows,
        campaigns: campaignRows,
      },
      promoters: promoterRows,
      door: {
        ticketsIssued: ticketIssued,
        guestsAdmitted: checkedIn,
        noShows: Math.max(0, ticketsSold - checkedIn),
        duplicateScanAttempts: duplicateScans,
        invalidScans,
        cashCollectedAtGate: cashAtGateCollected,
        scanLogs: scopedScanLogs.slice(0, 100).map((log) => ({
          id: log.id,
          type: safeString(log.data.type),
          attendeeName: safeString(log.data.attendeeName),
          tierName: safeString(log.data.tierName),
          staffMember: safeString(log.data.performedByEmail || log.data.performedBy || "Staff"),
          role: safeString(log.data.role),
          outcome: safeString(log.data.outcome),
          createdAt: timestampToDate(log.data.createdAt)?.toISOString() || "",
        })),
        entryPace,
        peakEntryWindow: entryPace.sort((a, b) => b.admits - a.admits)[0] || null,
      },
      inventory: {
        salesByItem: inventoryRows,
        salesByStaff: staffRows,
        openTabs: scopedTabs.filter((tab) => safeString(tab.data.status, "open") === "open").length,
        closedTabs: scopedTabs.filter((tab) => safeString(tab.data.status) === "closed").length,
        voidedOrders: scopedTabs.filter((tab) => ["voided", "cancelled", "canceled"].includes(safeString(tab.data.status))).length,
        grossMargin: moneyAmount(inventoryRows.reduce((sum, row) => sum + row.grossMarginGhs, 0)),
        costOfGoodsSold: moneyAmount(inventoryRows.reduce((sum, row) => sum + row.costOfGoodsGhs, 0)),
        lowStockAlerts: inventoryRows.filter((row) => row.lowStock),
        tablePackagePerformance: tablePackageRows,
      },
      crm: {
        actions: [
          { id: "rsvps_not_bought", label: "Message RSVPs who have not bought", audienceSize: Math.max(0, scopedRsvps.length - paidOrders.length), segment: "RSVP no purchase" },
          { id: "checked_in_last_time", label: "Message people who checked in last time", audienceSize: checkedIn, segment: "Checked in" },
          { id: "vip_buyers", label: "Message VIP buyers", audienceSize: tierRows.filter((tier) => /vip|table/i.test(tier.tierName)).reduce((sum, tier) => sum + tier.sold, 0), segment: "VIP buyers" },
          { id: "liked_saved_not_bought", label: "Message people who liked/saved but have not bought", audienceSize: Math.max(0, likes - paidOrders.length), segment: "Liked no purchase" },
          { id: "city_category", label: "Message city/category segment", audienceSize: scopedRsvps.length + paidOrders.length, segment: "City/category" },
        ],
      },
      aiInsights: insightRows.map((text, index) => ({
        id: `insight_${index + 1}`,
        title: index === 0 ? "Best channel" : index === 1 ? "Underperforming area" : "Recommended action",
        body: text,
      })),
      reports: {
        csvExports: ["executive", "sales", "audience", "funnel", "marketing", "door", "inventory", "crm"],
        pdfReports: ["event_summary", "end_of_event", "staff_sales", "inventory_margin"],
      },
    };
  },
);

function maskForAnalytics(value) {
  const email = safeString(value);
  if (!email || !email.includes("@")) return "";
  const [name, domain] = email.split("@");
  return `${name.slice(0, 1)}***@${domain}`;
}
