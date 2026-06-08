"use strict";

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");
const {
  PUBLIC_ROLE_OPTIONS,
  canRoleDeleteCollection,
  canRolePerform,
  canRoleReadCollection,
  canRoleWriteCollection,
  effectiveAdminRole,
  getAdminRoleLabel,
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
const { FieldValue, Timestamp, GeoPoint } = admin.firestore;

const REGION = "us-central1";
const BOOTSTRAP_SALT = "vennuzo-owner-bootstrap-v1";

const ADMIN_COLLECTIONS = {
  users: {
    path: "users",
    label: "Users",
    group: "Identity",
    summaryFields: ["displayName", "email", "roles", "adminRole", "status"],
    writable: true,
  },
  admins: {
    path: "admins",
    label: "Admins",
    group: "Identity",
    summaryFields: ["displayName", "email", "role", "status"],
    writable: true,
  },
  organizations: {
    path: "organizations",
    label: "Organizations",
    group: "Organizer Ops",
    summaryFields: ["name", "ownerId", "status", "city"],
    writable: true,
  },
  organization_members: {
    path: "organization_members",
    label: "Organization members",
    group: "Organizer Ops",
    summaryFields: ["organizationId", "userId", "role", "status"],
    writable: true,
  },
  organizer_applications: {
    path: "organizer_applications",
    label: "Organizer applications",
    group: "Organizer Ops",
    summaryFields: ["organizerName", "email", "status", "organizationId"],
    writable: true,
  },
  events: {
    path: "events",
    label: "Events",
    group: "Events",
    summaryFields: ["title", "organizationId", "status", "visibility", "city"],
    writable: true,
  },
  event_occurrences: {
    path: "event_occurrences",
    label: "Event occurrences",
    group: "Events",
    summaryFields: ["title", "eventId", "status", "occurrenceStartAt"],
    writable: true,
  },
  share_links: {
    path: "share_links",
    label: "Share links",
    group: "Events",
    summaryFields: ["title", "targetId", "slug", "status"],
    writable: true,
  },
  places: {
    path: "places",
    label: "Places",
    group: "Places",
    summaryFields: ["name", "organizationId", "city", "status", "featured"],
    writable: true,
  },
  place_menu_sections: {
    path: "place_menu_sections",
    label: "Place menu sections",
    group: "Places",
    summaryFields: ["placeId", "name", "visible", "sortOrder"],
    writable: true,
  },
  place_menu_items: {
    path: "place_menu_items",
    label: "Place menu items",
    group: "Places",
    summaryFields: ["placeId", "sectionId", "name", "price", "status"],
    writable: true,
  },
  place_reservations: {
    path: "place_reservations",
    label: "Place reservations",
    group: "Places",
    summaryFields: ["placeName", "guestName", "partySize", "status", "requestedAt"],
    writable: true,
  },
  place_subscriptions: {
    path: "place_subscriptions",
    label: "Place subscriptions",
    group: "Places",
    summaryFields: ["placeId", "userId", "status", "channels"],
    writable: true,
  },
  place_verifications: {
    path: "place_verifications",
    label: "Place verification requests",
    group: "Places",
    summaryFields: ["placeName", "method", "status", "contactEmail"],
    writable: false,
  },
  event_rsvps: {
    path: "event_rsvps",
    label: "RSVPs",
    group: "Tickets",
    summaryFields: ["eventTitle", "name", "phone", "status"],
    writable: true,
  },
  event_ticket_orders: {
    path: "event_ticket_orders",
    label: "Ticket orders",
    group: "Tickets",
    summaryFields: ["eventId", "buyerEmail", "paymentStatus", "totalAmount"],
    writable: true,
  },
  event_ticket_lookups: {
    path: "event_ticket_lookups",
    label: "Ticket lookups",
    group: "Tickets",
    summaryFields: ["eventId", "orderId", "status", "tierName"],
    writable: true,
  },
  ticket_admin_actions: {
    path: "ticket_admin_actions",
    label: "Ticket staff actions",
    group: "Tickets",
    summaryFields: ["type", "eventId", "orderId", "performedBy"],
    writable: true,
  },
  ticket_recovery_jobs: {
    path: "ticket_recovery_jobs",
    label: "Ticket recovery",
    group: "Tickets",
    summaryFields: ["orderId", "eventId", "issued", "status"],
    writable: true,
  },
  tablePackages: {
    path: "tablePackages",
    label: "Table packages",
    group: "Tickets",
    summaryFields: ["eventTitle", "name", "priceGhs", "status"],
    writable: true,
  },
  table_bookings: {
    path: "table_bookings",
    label: "Table bookings",
    group: "Tickets",
    summaryFields: ["eventId", "guestName", "packageName", "status"],
    writable: true,
  },
  table_package_bookings: {
    path: "table_package_bookings",
    label: "Table package payments",
    group: "Tickets",
    summaryFields: ["eventTitle", "packageName", "paymentStatus", "totalAmount"],
    writable: true,
  },
  event_ops_configs: {
    path: "event_ops_configs",
    label: "Event Ops configs",
    group: "Operations",
    summaryFields: ["eventTitle", "selectedPlan", "paymentMode", "setupComplete"],
    writable: true,
  },
  event_inventory_items: {
    path: "event_inventory_items",
    label: "Event inventory",
    group: "Operations",
    summaryFields: ["eventId", "name", "category", "sellingGhs"],
    writable: true,
  },
  event_ops_staff: {
    path: "event_ops_staff",
    label: "Event Ops staff",
    group: "Operations",
    summaryFields: ["eventId", "name", "role", "station"],
    writable: true,
  },
  event_ops_tabs: {
    path: "event_ops_tabs",
    label: "Event Ops tabs",
    group: "Operations",
    summaryFields: ["eventTitle", "customer", "status", "totalAmount"],
    writable: true,
  },
  event_ops_reports: {
    path: "event_ops_reports",
    label: "Event Ops reports",
    group: "Operations",
    summaryFields: ["eventTitle", "status", "tabCount", "createdAt"],
    writable: true,
  },
  event_ops_onboarding_visuals: {
    path: "event_ops_onboarding_visuals",
    label: "Event Ops onboarding visuals",
    group: "Operations",
    summaryFields: ["eventTitle", "status", "model", "updatedAt"],
    writable: false,
  },
  event_reminders: {
    path: "event_reminders",
    label: "Event reminders",
    group: "Tickets",
    summaryFields: ["eventId", "userId", "status", "scheduledAt"],
    writable: true,
  },
  event_reports: {
    path: "event_reports",
    label: "Event reports",
    group: "Safety",
    summaryFields: ["eventTitle", "reason", "createdAt", "status"],
    writable: true,
  },
  support_tickets: {
    path: "support_tickets",
    label: "Support tickets",
    group: "Safety",
    summaryFields: ["subject", "name", "email", "status", "adminUnreadCount"],
    writable: true,
  },
  event_posts: {
    path: "event_posts",
    label: "Social posts",
    group: "Social",
    summaryFields: ["eventId", "userId", "caption", "likeCount"],
    writable: true,
  },
  gplus_events: {
    path: "gplus_events",
    label: "G+ event mirror",
    group: "Social",
    summaryFields: ["title", "date", "status", "sourceEventId"],
    writable: true,
  },
  gplus_profiles: {
    path: "gplus_profiles",
    label: "G+ profile mirror",
    group: "Social",
    summaryFields: ["displayName", "username", "updatedAt", "sourceProfileId"],
    writable: true,
  },
  gplus_media_gallery: {
    path: "gplus_media_gallery",
    label: "G+ media gallery",
    group: "Social",
    summaryFields: ["eventId", "imageUrl", "caption", "updatedAt"],
    writable: true,
  },
  gplus_sync_status: {
    path: "gplus_sync_status",
    label: "G+ sync status",
    group: "Social",
    summaryFields: ["type", "status", "vennuzoEventId", "syncedAt"],
    writable: false,
  },
  gelo_content_queue: {
    path: "gelo_content_queue",
    label: "Gelo content queue",
    group: "Social",
    summaryFields: ["type", "title", "status", "eventId"],
    writable: true,
  },
  gelo_event_launch_drafts: {
    path: "gelo_event_launch_drafts",
    label: "Gelo event drafts",
    group: "Social",
    summaryFields: ["eventTitle", "status", "source", "updatedAt"],
    writable: true,
  },
  gelo_website_features: {
    path: "gelo_website_features",
    label: "Gelo website features",
    group: "Social",
    summaryFields: ["title", "featureType", "status", "urlPath"],
    writable: true,
  },
  event_reviews: {
    collectionGroup: "reviews",
    label: "Event reviews",
    group: "Social",
    summaryFields: ["eventId", "userId", "rating", "comment"],
    writable: true,
  },
  post_comments: {
    collectionGroup: "comments",
    label: "Post comments",
    group: "Social",
    summaryFields: ["postId", "userId", "text", "createdAt"],
    writable: true,
  },
  post_likes: {
    collectionGroup: "likes",
    label: "Post likes",
    group: "Social",
    summaryFields: ["postId", "userId", "createdAt"],
    writable: true,
  },
  social_follows: {
    collectionGroup: "following",
    label: "Social follows",
    group: "Social",
    summaryFields: ["followerId", "followingId", "createdAt"],
    writable: true,
  },
  event_saves: {
    collectionGroup: "saved",
    label: "Saved events",
    group: "Social",
    summaryFields: ["eventId", "userId", "createdAt"],
    writable: true,
  },
  promotion_campaigns: {
    path: "promotion_campaigns",
    label: "Promotion campaigns",
    group: "Marketing",
    summaryFields: ["targetType", "targetTitle", "eventTitle", "organizationId", "status", "channels"],
    writable: true,
  },
  audience_contacts: {
    path: "audience_contacts",
    label: "Audience contacts",
    group: "Marketing",
    summaryFields: ["organizationId", "email", "phone", "source"],
    writable: true,
  },
  advertiser_wallets: {
    path: "advertiser_wallets",
    label: "Advertiser wallets",
    group: "Marketing",
    summaryFields: ["availableBalance", "heldBalance", "currency"],
    writable: true,
  },
  wallet_transactions: {
    path: "wallet_transactions",
    label: "Wallet transactions",
    group: "Marketing",
    summaryFields: ["walletId", "type", "amount", "status"],
    writable: true,
  },
  notification_jobs: {
    path: "notification_jobs",
    label: "Notification jobs",
    group: "Marketing",
    summaryFields: ["eventId", "channel", "status", "campaignId"],
    writable: true,
  },
  push_queue: {
    path: "push_queue",
    label: "Push queue",
    group: "Marketing",
    summaryFields: ["title", "targetUid", "status", "kind"],
    writable: true,
  },
  sms_opt_out: {
    path: "sms_opt_out",
    label: "SMS opt-outs",
    group: "Marketing",
    summaryFields: ["phone", "source", "createdAt"],
    writable: true,
  },
  promo_packages: {
    path: "promo_packages",
    label: "Promo packages",
    group: "Marketing",
    summaryFields: ["name", "active", "order", "defaultSmsRateGhs"],
    writable: true,
  },
  partner_profiles: {
    path: "partner_profiles",
    label: "Partner profiles",
    group: "Marketing",
    summaryFields: ["name", "organizationId", "type", "status"],
    writable: true,
  },
  partner_event_links: {
    path: "partner_event_links",
    label: "Partner links",
    group: "Marketing",
    summaryFields: ["eventTitle", "partnerName", "refCode", "status"],
    writable: true,
  },
  partner_clicks: {
    path: "partner_clicks",
    label: "Partner clicks",
    group: "Marketing",
    summaryFields: ["eventId", "partnerLinkId", "refCode", "createdAt"],
    writable: true,
  },
  partner_payouts: {
    path: "partner_payouts",
    label: "Partner payouts",
    group: "Marketing",
    summaryFields: ["partnerProfileId", "amount", "status", "createdAt"],
    writable: true,
  },
  promo_mechanics: {
    path: "promo_mechanics",
    label: "Promo mechanics",
    group: "Marketing",
    summaryFields: ["eventTitle", "type", "title", "status"],
    writable: true,
  },
  promo_entries: {
    path: "promo_entries",
    label: "Promo entries",
    group: "Marketing",
    summaryFields: ["promoMechanicId", "name", "points", "status"],
    writable: true,
  },
  promo_redemptions: {
    path: "promo_redemptions",
    label: "Promo redemptions",
    group: "Marketing",
    summaryFields: ["eventId", "code", "name", "status"],
    writable: true,
  },
  promo_leaderboards: {
    path: "promo_leaderboards",
    label: "Promo leaderboards",
    group: "Marketing",
    summaryFields: ["eventId", "promoMechanicId", "status", "updatedAt"],
    writable: true,
  },
  promo_winners: {
    path: "promo_winners",
    label: "Promo winners",
    group: "Marketing",
    summaryFields: ["eventId", "promoMechanicId", "name", "status"],
    writable: true,
  },
  pending_event_changes: {
    path: "pending_event_changes",
    label: "Pending event changes",
    group: "Events",
    summaryFields: ["eventTitle", "organizationId", "status", "submittedBy"],
    writable: true,
  },
  event_ai_extractions: {
    path: "event_ai_extractions",
    label: "Flyer event extraction",
    group: "Events",
    summaryFields: ["organizationId", "status", "provider", "createdAt"],
    writable: true,
  },
  creative_brand_configs: {
    path: "creative_brand_configs",
    label: "Creative brand configs",
    group: "Creative",
    summaryFields: ["organizationId", "brandName", "tone", "updatedAt"],
    writable: true,
  },
  flyer_jobs: {
    path: "flyer_jobs",
    label: "Creative jobs",
    group: "Creative",
    summaryFields: ["organizationId", "serviceType", "status", "eventName"],
    writable: true,
  },
  flyer_sessions: {
    path: "flyer_sessions",
    label: "Creative sessions",
    group: "Creative",
    summaryFields: ["organizationId", "serviceType", "eventName", "priceChargedGhs"],
    writable: true,
  },
  payout_requests: {
    path: "payout_requests",
    label: "Payout requests",
    group: "Billing",
    summaryFields: ["organizationId", "amount", "status", "createdAt"],
    writable: true,
  },
  app_config: {
    path: "app_config",
    label: "App config",
    group: "System",
    summaryFields: ["updatedAt", "updatedBy"],
    writable: true,
  },
  rate_limits: {
    path: "rate_limits",
    label: "Rate limits",
    group: "System",
    summaryFields: ["uid", "operation", "count", "expiresAt"],
    writable: true,
  },
  admin_notifications: {
    path: "admin_notifications",
    label: "Admin alerts",
    group: "System",
    summaryFields: ["title", "kind", "status", "createdAt"],
    writable: false,
  },
};

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function hashBootstrapPassword(password) {
  return crypto
    .createHash("sha256")
    .update(`${BOOTSTRAP_SALT}:${safeString(password)}`)
    .digest("hex");
}

// Returns the expected bootstrap password hash from the environment, or "" when
// owner bootstrap has not been configured (in which case it is disabled — there
// is deliberately no hardcoded fallback).
function expectedBootstrapPasswordHash() {
  const configuredHash = safeString(process.env.VENNUZO_OWNER_BOOTSTRAP_PASSWORD_SHA256);
  if (configuredHash) {
    return configuredHash.toLowerCase();
  }
  const configuredPlain = safeString(process.env.VENNUZO_OWNER_BOOTSTRAP_PASSWORD);
  if (configuredPlain) {
    return hashBootstrapPassword(configuredPlain);
  }
  return "";
}

async function resolveAdminEmail(uid, adminData) {
  const docEmail = safeString(adminData && adminData.email).toLowerCase();
  if (docEmail) {
    return docEmail;
  }
  try {
    const authUser = await admin.auth().getUser(uid);
    return safeString(authUser.email).toLowerCase();
  } catch (error) {
    return "";
  }
}

async function assertAdmin(uid, options = {}) {
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const data = adminSnap.data() || {};
  const role = normalizeAdminRole(data.role);
  const status = safeString(data.status, "active").toLowerCase();
  if (!isKnownAdminRole(role) || status === "disabled") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const email = await resolveAdminEmail(uid, data);
  const isSuperAdmin = effectiveAdminRole(role) === "superadmin" && isAllowedSuperAdminEmail(email);
  if (options.requireSuperAdmin && !isSuperAdmin) {
    throw new HttpsError("permission-denied", "Superadmin access required.");
  }
  if (options.action && !canRolePerform(role, options.action)) {
    throw new HttpsError("permission-denied", "This admin role cannot perform that action.");
  }
  if (options.collectionId && options.access === "read" && !canRoleReadCollection(role, options.collectionId)) {
    throw new HttpsError("permission-denied", "This admin role cannot view that work area.");
  }
  if (options.collectionId && options.access === "write" && !canRoleWriteCollection(role, options.collectionId)) {
    throw new HttpsError("permission-denied", "This admin role cannot edit that work area.");
  }
  if (options.collectionId && options.access === "delete" && !canRoleDeleteCollection(role, options.collectionId)) {
    throw new HttpsError("permission-denied", "Only the owner can delete records.");
  }

  return {
    uid,
    email,
    role,
    roleLabel: getAdminRoleLabel(role),
    displayName: safeString(data.displayName, safeString(data.email, uid)),
    isSuperAdmin,
  };
}

function requireAuth(request, options = {}) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return assertAdmin(request.auth.uid, options);
}

function getDescriptor(collectionId) {
  const id = safeString(collectionId);
  const descriptor = ADMIN_COLLECTIONS[id];
  if (!descriptor) {
    throw new HttpsError("invalid-argument", "Unsupported admin collection.");
  }
  return { id, ...descriptor };
}

function serializeValue(value) {
  if (value == null) return value;
  if (value instanceof Timestamp || typeof value.toDate === "function") {
    const date = value.toDate();
    return {
      __type: "timestamp",
      iso: Number.isNaN(date.getTime()) ? null : date.toISOString(),
    };
  }
  if (value instanceof GeoPoint) {
    return {
      __type: "geoPoint",
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }
  if (
    value.path &&
    typeof value.path === "string" &&
    typeof value.isEqual === "function"
  ) {
    return {
      __type: "reference",
      path: value.path,
    };
  }
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, serializeValue(entry)]),
    );
  }
  return value;
}

function deserializeValue(value) {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map(deserializeValue);
  if (typeof value === "object") {
    const type = safeString(value.__type);
    if (type === "timestamp") {
      const date = new Date(value.iso);
      if (Number.isNaN(date.getTime())) return null;
      return Timestamp.fromDate(date);
    }
    if (type === "serverTimestamp") {
      return FieldValue.serverTimestamp();
    }
    if (type === "geoPoint") {
      const latitude = Number(value.latitude);
      const longitude = Number(value.longitude);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        throw new HttpsError("invalid-argument", "Invalid GeoPoint value.");
      }
      return new GeoPoint(latitude, longitude);
    }
    if (type === "reference") {
      const path = safeString(value.path);
      if (!path) throw new HttpsError("invalid-argument", "Reference path is required.");
      return db.doc(path);
    }
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== "__type")
        .map(([key, entry]) => [key, deserializeValue(entry)]),
    );
  }
  return value;
}

function timestampMillis(data, field) {
  const value = data && data[field];
  if (!value) return 0;
  if (value instanceof Timestamp || typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (typeof value === "string") {
    const parsed = new Date(value).getTime();
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function sortDocsByRecent(left, right) {
  const fields = ["updatedAt", "createdAt", "submittedAt", "reviewedAt", "startAt"];
  const leftTime = Math.max(...fields.map((field) => timestampMillis(left.raw, field)));
  const rightTime = Math.max(...fields.map((field) => timestampMillis(right.raw, field)));
  return rightTime - leftTime;
}

async function countCollection(descriptor) {
  const source = descriptor.collectionGroup
    ? db.collectionGroup(descriptor.collectionGroup)
    : db.collection(descriptor.path);

  try {
    const countSnap = await source.count().get();
    return Number(countSnap.data().count || 0);
  } catch (error) {
    const snap = await source.limit(1000).get();
    return snap.size;
  }
}

async function listDocumentsForDescriptor(descriptor, maxDocs) {
  const limit = Math.min(Math.max(Number(maxDocs) || 50, 1), 250);
  const source = descriptor.collectionGroup
    ? db.collectionGroup(descriptor.collectionGroup)
    : db.collection(descriptor.path);
  const snap = await source.limit(limit).get();
  return snap.docs
    .map((docSnap) => ({
      id: docSnap.id,
      docPath: docSnap.ref.path,
      raw: docSnap.data() || {},
      data: serializeValue(docSnap.data() || {}),
    }))
    .sort(sortDocsByRecent)
    .map(({ raw, ...doc }) => doc);
}

function resolveDocumentPath(descriptor, input) {
  const providedPath = safeString(input.docPath);
  if (providedPath) {
    const segments = providedPath.split("/").filter(Boolean);
    if (descriptor.collectionGroup) {
      if (!segments.includes(descriptor.collectionGroup)) {
        throw new HttpsError("invalid-argument", "Document path does not match collection group.");
      }
      if (segments.length % 2 !== 0) {
        throw new HttpsError("invalid-argument", "Document path must point to a document.");
      }
      return providedPath;
    }
    const expectedPrefix = `${descriptor.path}/`;
    if (!providedPath.startsWith(expectedPrefix) || segments.length !== 2) {
      throw new HttpsError("invalid-argument", "Document path does not match collection.");
    }
    return providedPath;
  }

  if (descriptor.collectionGroup) {
    throw new HttpsError("invalid-argument", "A full document path is required for collection group writes.");
  }

  const docId = safeString(input.docId) || db.collection(descriptor.path).doc().id;
  if (docId.includes("/")) {
    throw new HttpsError("invalid-argument", "Document ID cannot contain slashes.");
  }
  return `${descriptor.path}/${docId}`;
}

exports.bootstrapOwnerAdmin = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    const email = safeString(request.data && request.data.email).toLowerCase();
    const password = safeString(request.data && request.data.password);
    const displayName = safeString(
      request.data && request.data.displayName,
      "Vennuzo Owner",
    );
    const rateLimitKey = `owner_bootstrap_${email || "anonymous"}`;
    await checkRateLimit(db, rateLimitKey, "bootstrapOwnerAdmin", {
      maxCalls: 5,
      windowSeconds: 300,
    });

    if (!isAllowedSuperAdminEmail(email)) {
      throw new HttpsError("permission-denied", "Owner bootstrap is restricted.");
    }
    const expectedHash = expectedBootstrapPasswordHash();
    if (!expectedHash) {
      // Fail closed: no hardcoded fallback. Owner bootstrap must be explicitly
      // enabled by setting VENNUZO_OWNER_BOOTSTRAP_PASSWORD_SHA256 (or
      // VENNUZO_OWNER_BOOTSTRAP_PASSWORD) in the function environment.
      throw new HttpsError(
        "failed-precondition",
        "Owner bootstrap is disabled. Configure VENNUZO_OWNER_BOOTSTRAP_PASSWORD_SHA256 to enable it.",
      );
    }
    if (!password) {
      throw new HttpsError("permission-denied", "Owner bootstrap credentials are invalid.");
    }
    const providedHashBuf = Buffer.from(hashBootstrapPassword(password));
    const expectedHashBuf = Buffer.from(expectedHash);
    if (
      providedHashBuf.length !== expectedHashBuf.length ||
      !crypto.timingSafeEqual(providedHashBuf, expectedHashBuf)
    ) {
      throw new HttpsError("permission-denied", "Owner bootstrap credentials are invalid.");
    }

    let authUser;
    let created = false;
    try {
      authUser = await admin.auth().getUserByEmail(email);
      await admin.auth().updateUser(authUser.uid, {
        email,
        password,
        displayName,
        disabled: false,
      });
      authUser = await admin.auth().getUser(authUser.uid);
    } catch (error) {
      if (!error || error.code !== "auth/user-not-found") {
        throw error;
      }
      authUser = await admin.auth().createUser({
        email,
        password,
        displayName,
        emailVerified: true,
        disabled: false,
      });
      created = true;
    }

    const now = FieldValue.serverTimestamp();
    await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(authUser.uid);
      const adminRef = db.collection("admins").doc(authUser.uid);
      const userSnap = await transaction.get(userRef);
      const userData = userSnap.exists ? userSnap.data() || {} : {};

      transaction.set(
        adminRef,
        {
          uid: authUser.uid,
          displayName,
          email,
          role: "superadmin",
          status: "active",
          bootstrapped: true,
          createdAt: userData.createdAt || now,
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(
        userRef,
        {
          displayName,
          email,
          roles: Array.from(
            new Set(
              []
                .concat(Array.isArray(userData.roles) ? userData.roles : [])
                .concat(["admin", "superadmin"]),
            ),
          ),
          adminRole: "superadmin",
          createdAt: userData.createdAt || now,
          updatedAt: now,
        },
        { merge: true },
      );
    });

    return { success: true, uid: authUser.uid, created };
  },
);

exports.getAdminConsoleOverview = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const context = await requireAuth(request);
    const countIds = [
      "users",
      "admins",
      "organizations",
      "organizer_applications",
      "events",
      "event_ticket_orders",
      "event_reports",
      "support_tickets",
      "promotion_campaigns",
      "notification_jobs",
      "flyer_jobs",
      "payout_requests",
    ];
    const recentIds = [
      "organizer_applications",
      "events",
      "event_ticket_orders",
      "event_reports",
      "support_tickets",
      "promotion_campaigns",
      "flyer_jobs",
      "notification_jobs",
    ];
    const allowedCountIds = countIds.filter((id) => canRoleReadCollection(context.role, id));
    const allowedRecentIds = recentIds.filter((id) => canRoleReadCollection(context.role, id));

    const countsEntries = await Promise.all(
      allowedCountIds.map(async (id) => {
        const descriptor = getDescriptor(id);
        return [id, await countCollection(descriptor)];
      }),
    );
    const recentEntries = await Promise.all(
      allowedRecentIds.map(async (id) => {
        const descriptor = getDescriptor(id);
        return [id, await listDocumentsForDescriptor(descriptor, 8)];
      }),
    );

    return {
      generatedAt: new Date().toISOString(),
      admin: context,
      counts: Object.fromEntries(countsEntries),
      recent: Object.fromEntries(recentEntries),
      roleOptions: PUBLIC_ROLE_OPTIONS,
      collections: Object.entries(ADMIN_COLLECTIONS)
        .filter(([id]) => canRoleReadCollection(context.role, id))
        .map(([id, descriptor]) => ({
          id,
          label: descriptor.label,
          group: descriptor.group,
          path: descriptor.path || `collectionGroup:${descriptor.collectionGroup}`,
          summaryFields: descriptor.summaryFields,
          writable: descriptor.writable === true && canRoleWriteCollection(context.role, id),
        })),
    };
  },
);

exports.listAdminConsoleDocuments = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const descriptor = getDescriptor(request.data && request.data.collectionId);
    const context = await requireAuth(request, {
      access: "read",
      collectionId: descriptor.id,
    });
    const docs = await listDocumentsForDescriptor(
      descriptor,
      request.data && request.data.limit,
    );
    return {
      collection: {
        id: descriptor.id,
        label: descriptor.label,
        group: descriptor.group,
        path: descriptor.path || `collectionGroup:${descriptor.collectionGroup}`,
        summaryFields: descriptor.summaryFields,
        writable: descriptor.writable === true && canRoleWriteCollection(context.role, descriptor.id),
      },
      docs,
    };
  },
);

exports.saveAdminConsoleDocument = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const descriptor = getDescriptor(request.data && request.data.collectionId);
    const context = await requireAuth(request, {
      access: "write",
      collectionId: descriptor.id,
    });
    if (descriptor.writable !== true) {
      throw new HttpsError("permission-denied", "This work area is read-only.");
    }

    const docPath = resolveDocumentPath(descriptor, request.data || {});
    const merge = request.data && request.data.merge !== false;
    const rawData = request.data && request.data.data;
    if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) {
      throw new HttpsError("invalid-argument", "Record details must be an object.");
    }

    const payload = deserializeValue(rawData);
    payload.updatedAt = payload.updatedAt || FieldValue.serverTimestamp();
    payload.updatedBy = payload.updatedBy || context.uid;
    await db.doc(docPath).set(payload, { merge });
    const snap = await db.doc(docPath).get();

    return {
      success: true,
      doc: {
        id: snap.id,
        docPath: snap.ref.path,
        data: serializeValue(snap.data() || {}),
      },
    };
  },
);

exports.deleteAdminConsoleDocument = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    const descriptor = getDescriptor(request.data && request.data.collectionId);
    const context = await requireAuth(request, {
      access: "delete",
      collectionId: descriptor.id,
    });
    if (descriptor.writable !== true) {
      throw new HttpsError("permission-denied", "This work area is read-only.");
    }
    const docPath = resolveDocumentPath(descriptor, request.data || {});
    if (docPath === `admins/${context.uid}` || docPath === `users/${context.uid}`) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot delete your own admin or user document from the console.",
      );
    }
    await db.doc(docPath).delete();
    return { success: true, docPath };
  },
);

exports.updateAdminAuthUser = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    const context = await requireAuth(request, { action: "update_auth_users" });
    const uid = safeString(request.data && request.data.uid);
    const email = safeString(request.data && request.data.email).toLowerCase();
    const displayName = safeString(request.data && request.data.displayName);
    const password = safeString(request.data && request.data.password);
    const disabled =
      request.data && typeof request.data.disabled === "boolean"
        ? request.data.disabled
        : undefined;

    if (!uid && !email) {
      throw new HttpsError("invalid-argument", "Provide a uid or email.");
    }
    if (uid && uid === context.uid && disabled === true) {
      throw new HttpsError("failed-precondition", "You cannot disable your own account.");
    }
    if (password && password.length < 8) {
      throw new HttpsError("invalid-argument", "Password must be at least 8 characters.");
    }

    const target = uid
      ? await admin.auth().getUser(uid)
      : await admin.auth().getUserByEmail(email);
    const update = {};
    if (email) update.email = email;
    if (displayName) update.displayName = displayName;
    if (password) update.password = password;
    if (disabled !== undefined) update.disabled = disabled;

    const updated = Object.keys(update).length
      ? await admin.auth().updateUser(target.uid, update)
      : target;

    await db.collection("users").doc(updated.uid).set(
      {
        email: updated.email || email || null,
        displayName: updated.displayName || displayName || null,
        authDisabled: updated.disabled === true,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: context.uid,
      },
      { merge: true },
    );

    return {
      success: true,
      uid: updated.uid,
      email: updated.email || "",
      disabled: updated.disabled === true,
    };
  },
);
