"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const nodemailer = require("nodemailer");
const { queuePushNotification } = require("./event_notifications");
const { checkRateLimit } = require("./rate_limiter");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;
const REGION = "us-central1";

const EVENT_OPS_PLANS = new Set(["lite", "pro", "festival"]);
const EVENT_OPS_PLAN_PRICES_GHS = {
  lite: 250,
  pro: 500,
  festival: 1500,
};
const LOW_STOCK_ALERT_THRESHOLD = 5;
const MAX_ONBOARDING_VISUAL_GENERATIONS = 3;
const PAYMENT_MODES = new Set(["merchant_collected", "vennuzo_controlled"]);
const STAFF_ROLES = new Set(["Waiter", "Bartender", "Floor lead", "Owner", "Vendor"]);
const TAB_PAYMENT_METHODS = new Set(["Cash", "Merchant MoMo", "Card", "Bank transfer", "Other"]);
const STAFF_SESSION_TTL_MS = 1000 * 60 * 60 * 14;
const GEMINI_MODEL = "gemini-3-pro-image-preview";
const GEMINI_FALLBACK_MODELS = ["gemini-2.5-flash-image"];
const TEAM_PERMISSIONS = [
  "scanTickets",
  "manualVerifyTickets",
  "admitTickets",
  "collectCash",
  "issueTickets",
  "viewOrders",
  "viewAnalytics",
  "manageInventory",
  "manageStaff",
];
const ROLE_TEMPLATES = {
  owner: {
    label: "Owner",
    description: "Full control over the event, team, tickets, reports, and Event Ops.",
    permissions: Object.fromEntries(TEAM_PERMISSIONS.map((permission) => [permission, true])),
  },
  gate_lead: {
    label: "Gate lead",
    description: "Runs admissions, resolves manual checks, and sees the live scan log.",
    permissions: {
      scanTickets: true,
      manualVerifyTickets: true,
      admitTickets: true,
      collectCash: true,
      issueTickets: false,
      viewOrders: true,
      viewAnalytics: true,
      manageInventory: false,
      manageStaff: false,
    },
  },
  scanner: {
    label: "Scanner",
    description: "Scans QR codes and admits paid tickets at the door.",
    permissions: {
      scanTickets: true,
      manualVerifyTickets: false,
      admitTickets: true,
      collectCash: false,
      issueTickets: false,
      viewOrders: false,
      viewAnalytics: false,
      manageInventory: false,
      manageStaff: false,
    },
  },
  box_office: {
    label: "Box office",
    description: "Handles manual lookup, cash-at-gate collection, and complimentary ticket support.",
    permissions: {
      scanTickets: true,
      manualVerifyTickets: true,
      admitTickets: true,
      collectCash: true,
      issueTickets: true,
      viewOrders: true,
      viewAnalytics: false,
      manageInventory: false,
      manageStaff: false,
    },
  },
  inventory_staff: {
    label: "Inventory staff",
    description: "Runs event inventory, tabs, and staff sales reporting without ticket admin power.",
    permissions: {
      scanTickets: false,
      manualVerifyTickets: false,
      admitTickets: false,
      collectCash: false,
      issueTickets: false,
      viewOrders: true,
      viewAnalytics: true,
      manageInventory: true,
      manageStaff: false,
    },
  },
};

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function normalizeEmail(value) {
  return safeString(value).toLowerCase();
}

function boundedString(value, max = 240) {
  return safeString(value).slice(0, max);
}

function normalizeStaffAccessCode(value) {
  return safeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

function defaultStaffAccessCode(eventId, eventData) {
  const titleCode = normalizeStaffAccessCode(eventData && eventData.title);
  if (titleCode.length >= 3) return titleCode;
  return normalizeStaffAccessCode(eventId);
}

function moneyAmount(value, fallback = 0) {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return fallback;
  return Math.round(Math.max(amount, 0) * 100) / 100;
}

function eventOpsPlanPrice(plan) {
  return moneyAmount(EVENT_OPS_PLAN_PRICES_GHS[plan] || EVENT_OPS_PLAN_PRICES_GHS.pro);
}

function positiveInt(value, fallback = 1) {
  const amount = Number.parseInt(String(value), 10);
  if (!Number.isFinite(amount)) return fallback;
  return Math.max(amount, 1);
}

function nonNegativeInt(value, fallback = 0) {
  const amount = Number.parseInt(String(value), 10);
  if (!Number.isFinite(amount)) return fallback;
  return Math.max(amount, 0);
}

function pinCode() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token || "")).digest("hex");
}

function roleTemplate(role) {
  const normalized = safeString(role, "scanner").toLowerCase().replace(/[\s-]+/g, "_");
  return ROLE_TEMPLATES[normalized] ? normalized : "scanner";
}

function normalizedPermissions(input, role = "scanner") {
  const template = ROLE_TEMPLATES[roleTemplate(role)].permissions;
  const raw = input && typeof input === "object" ? input : {};
  return Object.fromEntries(
    TEAM_PERMISSIONS.map((permission) => [
      permission,
      raw[permission] === true || (raw[permission] !== false && template[permission] === true),
    ]),
  );
}

function teamMemberFromDoc(docSnap) {
  const data = docSnap.data() || {};
  const role = roleTemplate(data.role);
  return {
    id: docSnap.id,
    eventId: safeString(data.eventId),
    organizationId: safeString(data.organizationId),
    userId: safeString(data.userId),
    email: normalizeEmail(data.email),
    displayName: safeString(data.displayName, normalizeEmail(data.email)),
    role,
    roleLabel: ROLE_TEMPLATES[role].label,
    permissions: normalizedPermissions(data.permissions, role),
    status: safeString(data.status, "active"),
    acceptedAt: data.acceptedAt && data.acceptedAt.toDate ? data.acceptedAt.toDate().toISOString() : null,
  };
}

function inviteFromDoc(docSnap) {
  const data = docSnap.data() || {};
  const role = roleTemplate(data.role);
  return {
    id: docSnap.id,
    eventId: safeString(data.eventId),
    organizationId: safeString(data.organizationId),
    email: normalizeEmail(data.email),
    role,
    roleLabel: ROLE_TEMPLATES[role].label,
    permissions: normalizedPermissions(data.permissions, role),
    status: safeString(data.status, "pending"),
    acceptUrl: safeString(data.acceptUrl),
    createdAt: data.createdAt && data.createdAt.toDate ? data.createdAt.toDate().toISOString() : null,
    acceptedAt: data.acceptedAt && data.acceptedAt.toDate ? data.acceptedAt.toDate().toISOString() : null,
  };
}

function publicRoleTemplates() {
  return Object.entries(ROLE_TEMPLATES).map(([id, template]) => ({
    id,
    label: template.label,
    description: template.description,
    permissions: normalizedPermissions(template.permissions, id),
  }));
}

function publicSiteBaseUrl() {
  const configured = safeString(
    process.env.VENNUZO_PUBLIC_URL ||
      process.env.VENNUZO_PUBLIC_BASE_URL ||
      process.env.VENNUZO_SITE_URL,
    "https://vennuzo.com",
  );
  return configured.replace(/\/+$/, "");
}

async function getInviteEmailConfig() {
  const configSnap = await db.collection("app_config").doc("email").get();
  const config = configSnap.exists ? configSnap.data() || {} : {};
  const smtpHost = safeString(process.env.SMTP_HOST || config.smtpHost, "smtp.gmail.com");
  const smtpPort = Number(process.env.SMTP_PORT || config.smtpPort || 587);
  const smtpUser = safeString(process.env.SMTP_USER || config.smtpUser);
  const smtpPass = safeString(process.env.SMTP_PASS || config.smtpPass);
  const fromEmail = safeString(
    process.env.FROM_EMAIL || config.fromEmail || config.senderEmail || smtpUser,
    "tickets@vennuzo.app",
  );
  const fromName = safeString(process.env.FROM_NAME || config.fromName, "Vennuzo");
  return {
    enabled: config.enabled !== false && Boolean(smtpUser && smtpPass),
    smtpHost,
    smtpPort: Number.isFinite(smtpPort) ? smtpPort : 587,
    smtpUser,
    smtpPass,
    fromEmail,
    fromName,
  };
}

async function sendEventTeamInviteEmail({ to, eventTitle, roleLabel, acceptUrl }) {
  const email = normalizeEmail(to);
  if (!email) return { status: "skipped", reason: "missing_email" };
  const config = await getInviteEmailConfig();
  if (!config.enabled) return { status: "skipped", reason: "email_not_configured" };
  const title = safeString(eventTitle, "this Vennuzo event");
  const role = safeString(roleLabel, "Event staff");
  const text = [
    `You have been invited to join ${title} on Vennuzo as ${role}.`,
    "",
    `Accept invite: ${acceptUrl}`,
    "",
    "After accepting, you will get the staff workspace and only the permissions assigned by the organizer.",
  ].join("\n");
  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#f6f7fb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
<table role="presentation" style="width:100%;border-collapse:collapse;background:#f6f7fb;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" style="max-width:620px;width:100%;border-collapse:collapse;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 18px 45px rgba(15,23,42,.10);">
<tr><td style="padding:30px;background:#080b18;color:#fff;"><p style="margin:0 0 8px;color:#8ef9ff;font-size:13px;letter-spacing:.08em;text-transform:uppercase;">Vennuzo event team</p><h1 style="margin:0;font-size:28px;line-height:1.15;">You have been invited</h1><p style="margin:14px 0 0;color:#dbeafe;font-size:16px;">${title}</p></td></tr>
<tr><td style="padding:30px;color:#111827;"><p style="margin:0 0 16px;font-size:16px;line-height:1.6;">You have been added as <strong>${role}</strong>. Accept the invite to access the staff workspace and your assigned event permissions.</p><p style="margin:24px 0;text-align:center;"><a href="${acceptUrl}" style="display:inline-block;padding:14px 24px;background:#0f766e;color:#fff;text-decoration:none;border-radius:999px;font-weight:800;">Accept invite</a></p><p style="margin:0;color:#6b7280;font-size:13px;line-height:1.6;word-break:break-all;">${acceptUrl}</p></td></tr>
</table></td></tr></table></body></html>`;
  const transporter = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpPort === 465,
    auth: { user: config.smtpUser, pass: config.smtpPass },
  });
  const info = await transporter.sendMail({
    from: `"${config.fromName}" <${config.fromEmail}>`,
    to: email,
    subject: `Join ${title} on Vennuzo`,
    text,
    html,
  });
  return { status: "sent", messageId: safeString(info && info.messageId) };
}

async function callGeminiImage({ apiKey, parts, model, aspectRatio = "16:9" }) {
  const resp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: {
        responseModalities: ["TEXT", "IMAGE"],
        imageConfig: { aspectRatio },
        temperature: 1.0,
      },
    }),
  });
  if (!resp.ok) {
    const errText = await resp.text().catch(() => "unknown");
    throw new Error(`Gemini image generation failed (${resp.status}, ${model}): ${errText.slice(0, 300)}`);
  }
  const data = await resp.json();
  const imagePart = (data.candidates?.[0]?.content?.parts || [])
    .find((part) => part.inlineData?.mimeType?.startsWith("image/"));
  if (!imagePart?.inlineData?.data) {
    const finishReason = data.candidates?.[0]?.finishReason || "unknown";
    throw new Error(`Gemini returned no image (finish=${finishReason})`);
  }
  return {
    buffer: Buffer.from(imagePart.inlineData.data, "base64"),
    mimeType: imagePart.inlineData.mimeType || "image/png",
  };
}

async function generateGeminiImageWithFallback({ apiKey, parts, aspectRatio = "16:9" }) {
  const models = [GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS];
  let lastError = null;
  for (const model of models) {
    try {
      return await callGeminiImage({ apiKey, parts, model, aspectRatio });
    } catch (error) {
      lastError = error;
      console.warn(`[event_ops] ${model} onboarding visual failed:`, error.message);
    }
  }
  throw lastError || new Error("Gemini image generation failed.");
}

async function loadEventOpsBrand(uid, organizationId) {
  const [brandSnap, appSnap, orgSnap] = await Promise.all([
    db.collection("creative_brand_configs").doc(organizationId).get(),
    db.collection("organizer_applications").doc(uid).get(),
    db.collection("organizations").doc(organizationId).get(),
  ]);
  const brand = brandSnap.exists ? brandSnap.data() || {} : {};
  const app = appSnap.exists ? appSnap.data() || {} : {};
  const org = orgSnap.exists ? orgSnap.data() || {} : {};
  return {
    brandName: safeString(brand.brandName, safeString(app.organizerName, safeString(org.name, "Vennuzo"))),
    tagline: safeString(brand.tagline, safeString(app.brandTagline)),
    brandStyle: safeString(brand.brandStyle, "premium, modern, event-led, Ghanaian creator energy"),
    brandColor: safeString(brand.brandColor, safeString(app.brandAccentColor, "#22c55e")),
  };
}

async function chargeEventOpsWallet({ organizationId, uid, eventId, amount, serviceType, description }) {
  const rounded = moneyAmount(amount);
  if (rounded <= 0) return null;
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `event_ops_${eventId}_${serviceType}_charge`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);

  await db.runTransaction(async (transaction) => {
    const [walletSnap, existingTxn] = await Promise.all([
      transaction.get(walletRef),
      transaction.get(txnRef),
    ]);
    if (existingTxn.exists && existingTxn.data().status === "completed") return;
    const wallet = walletSnap.exists ? walletSnap.data() || {} : {};
    const available = Number(wallet.availableBalance ?? 0);
    if (available < rounded) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient wallet balance. Need ${rounded.toFixed(2)} GHS; available ${available.toFixed(2)} GHS. Load your wallet in Payments & Payouts.`,
      );
    }
    const walletUpdate = {
      organizationId,
      ownerId: uid,
      availableBalance: FieldValue.increment(-rounded),
      currency: "GHS",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!walletSnap.exists) walletUpdate.createdAt = FieldValue.serverTimestamp();
    transaction.set(walletRef, walletUpdate, { merge: true });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "event_ops_charge",
      serviceType,
      amount: rounded,
      clientReference,
      eventId,
      description,
      status: "completed",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return clientReference;
}

async function uploadEventOpsOnboardingImage({ uid, eventId, slot, eventTitle, buffer, mimeType }) {
  const bucket = admin.storage().bucket();
  const ext = mimeType.includes("jpeg") ? "jpg" : "png";
  const safeName = safeString(eventTitle, eventId).replace(/[^a-z0-9]/gi, "-").toLowerCase().slice(0, 44) || "event";
  const storagePath = `event_ops_onboarding/${uid}/${eventId}/${slot}-${safeName}-${Date.now()}.${ext}`;
  const file = bucket.file(storagePath);
  await file.save(buffer, {
    metadata: {
      contentType: mimeType,
      cacheControl: "public, max-age=31536000",
    },
  });
  await file.makePublic().catch(() => {});
  return {
    storagePath,
    imageUrl: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(storagePath)}?alt=media`,
  };
}

function buildOnboardingPrompt({ brief, eventTitle, eventData, brand, workspace }) {
  const inventoryNames = workspace.inventory.map((item) => item.name).filter(Boolean).slice(0, 8).join(", ") || "bottles, food, table packages, add-ons";
  const staffRoles = workspace.staff.map((member) => member.role).filter(Boolean).slice(0, 6).join(", ") || "waiters, bartenders, vendors, floor leads";
  const venue = safeString(eventData.venueName || eventData.venue || eventData.locationName || eventData.city, "a premium Ghana event venue");
  return `Create one premium Vennuzo Event Ops onboarding illustration for a product setup flow.

Visual brief: ${brief.visual}.
Event: ${eventTitle}.
Venue/context: ${venue}.
Organizer brand: ${brand.brandName}; style: ${brand.brandStyle}; accent color: ${brand.brandColor}; tagline: ${brand.tagline || "none"}.
Current setup context: inventory examples include ${inventoryNames}; staff roles include ${staffRoles}; payment mode is merchant-collected; Vennuzo-controlled payments are shown as coming soon only.

Art direction:
- State-of-the-art SaaS/event operations visual, clean and premium, made for an onboarding page.
- Show real product concepts: inventory catalog, staff order app, open/closed tabs, merchant-collected payment recording, analytics, and end-of-event PDF reporting where relevant.
- Ghana nightlife/concert/event energy, but keep the UI operational, legible, and trustworthy.
- Use tasteful depth, rich lighting, polished UI surfaces, and human hands/staff only if useful.
- Do not use GPlus branding, third-party logos, fake venue logos, watermarks, or unreadable paragraphs.
- Any visible text must be short, intentional labels only. Prefer clear UI shapes and visual hierarchy over lots of words.
- Return only the final 16:9 onboarding graphic.`;
}

function onboardingVisualBriefs() {
  return [
    {
      id: "ops_overview",
      title: "Your event command center",
      body: "Set up inventory, staff credentials, orders, payments, and reporting before the event opens.",
      visual: "A premium dashboard command center showing event inventory, staff, live tabs, and sales metrics in one clear setup overview.",
    },
    {
      id: "staff_orders",
      title: "A focused staff app",
      body: "Waiters and vendors sign in with special credentials and only see the order tools they need.",
      visual: "A separate mobile staff app experience with a waiter creating an order, open tabs beside it, and admin push notification cues.",
    },
    {
      id: "merchant_close_tabs",
      title: "Merchant-collected payments",
      body: "Vendors collect money their own way, then close paid tabs so every sale is recorded.",
      visual: "A merchant-collected payment flow: cash, MoMo, card, and bank transfer icons feeding into a clean closed-tab record, with Vennuzo-controlled mode locked as coming soon.",
    },
    {
      id: "event_report",
      title: "End-of-event reporting",
      body: "Generate a PDF-style summary with staff sales, inventory movement, margins, and open tab status.",
      visual: "A polished end-of-event report visual with staff-by-staff sales breakdown, category totals, inventory movement, margin cards, and a PDF export moment.",
    },
  ];
}

function publicStaffWorkspace({ config, inventory, staffMember, tabs }) {
  return {
    config,
    staff: {
      id: staffMember.id,
      name: staffMember.name,
      role: staffMember.role,
      station: staffMember.station,
    },
    inventory: inventory.filter((item) => item.listed),
    tabs: tabs.filter((tab) => tab.staffId === staffMember.id || tab.status === "open"),
  };
}

async function hasAdminAccess(uid) {
  if (!uid) return false;
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) return false;
  const data = snap.data() || {};
  return safeString(data.status, "active").toLowerCase() !== "disabled";
}

async function assertOrganizationManager(uid, organizationId) {
  const orgId = safeString(organizationId);
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!orgId) throw new HttpsError("invalid-argument", "organizationId is required.");
  if (await hasAdminAccess(uid)) return;
  if (orgId === `org_${uid}`) return;

  const [orgSnap, memberSnap, applicationSnap] = await Promise.all([
    db.collection("organizations").doc(orgId).get(),
    db.collection("organization_members").doc(`${orgId}_${uid}`).get(),
    db.collection("organizer_applications").doc(uid).get(),
  ]);
  const org = orgSnap.exists ? orgSnap.data() || {} : {};
  if (safeString(org.ownerId) === uid) return;

  const member = memberSnap.exists ? memberSnap.data() || {} : {};
  if (
    safeString(member.organizationId) === orgId &&
    safeString(member.userId) === uid &&
    safeString(member.status, "active").toLowerCase() !== "disabled"
  ) {
    return;
  }

  const application = applicationSnap.exists ? applicationSnap.data() || {} : {};
  if (safeString(application.organizationId) === orgId && safeString(application.userId) === uid) {
    return;
  }

  throw new HttpsError("permission-denied", "You cannot manage this organizer workspace.");
}

async function assertEventManager(uid, eventId) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const id = safeString(eventId);
  if (!id) throw new HttpsError("invalid-argument", "eventId is required.");
  const eventSnap = await db.collection("events").doc(id).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");

  const eventData = eventSnap.data() || {};
  if (await hasAdminAccess(uid)) return { eventRef: eventSnap.ref, eventData };
  if (safeString(eventData.createdBy) === uid) return { eventRef: eventSnap.ref, eventData };
  await assertOrganizationManager(uid, safeString(eventData.organizationId));
  return { eventRef: eventSnap.ref, eventData };
}

function eventOpsConfigFromDoc(docSnap, eventId, eventData) {
  const data = docSnap && docSnap.exists ? docSnap.data() || {} : {};
  const staffAccessCode = safeString(data.staffAccessCode) || defaultStaffAccessCode(eventId, eventData);
  return {
    id: eventId,
    eventId,
    organizationId: safeString(data.organizationId, safeString(eventData.organizationId)),
    eventTitle: safeString(data.eventTitle, safeString(eventData.title, "Event")),
    staffAccessCode,
    staffAccessCodeNormalized: normalizeStaffAccessCode(staffAccessCode),
    setupStarted: data.setupStarted === true,
    setupComplete: data.setupComplete === true,
    selectedPlan: EVENT_OPS_PLANS.has(data.selectedPlan) ? data.selectedPlan : "pro",
    planPriceGhs: eventOpsPlanPrice(EVENT_OPS_PLANS.has(data.selectedPlan) ? data.selectedPlan : "pro"),
    eventOpsPaid: data.eventOpsPaid === true,
    eventOpsActivatedAt: data.eventOpsActivatedAt && data.eventOpsActivatedAt.toDate
      ? data.eventOpsActivatedAt.toDate().toISOString()
      : null,
    eventOpsChargeReference: safeString(data.eventOpsChargeReference),
    paymentMode: PAYMENT_MODES.has(data.paymentMode) ? data.paymentMode : "merchant_collected",
    vennuzoControlledStatus: "coming_soon",
  };
}

function inventoryFromDoc(docSnap) {
  const data = docSnap.data() || {};
  return {
    id: docSnap.id,
    eventId: safeString(data.eventId),
    organizationId: safeString(data.organizationId),
    name: safeString(data.name),
    category: safeString(data.category, "General"),
    costGhs: moneyAmount(data.costGhs),
    sellingGhs: moneyAmount(data.sellingGhs),
    stock: nonNegativeInt(data.stock),
    linkedPackage: safeString(data.linkedPackage),
    listed: data.listed !== false,
  };
}

function staffFromDoc(docSnap) {
  const data = docSnap.data() || {};
  return {
    id: docSnap.id,
    eventId: safeString(data.eventId),
    organizationId: safeString(data.organizationId),
    name: safeString(data.name),
    role: safeString(data.role, "Waiter"),
    pin: safeString(data.pin),
    station: safeString(data.station, "Floor"),
    active: data.active !== false,
  };
}

function tabFromDoc(docSnap) {
  const data = docSnap.data() || {};
  return {
    id: docSnap.id,
    eventId: safeString(data.eventId),
    organizationId: safeString(data.organizationId),
    staffId: safeString(data.staffId),
    customer: safeString(data.customer, "Walk-in"),
    itemId: safeString(data.itemId),
    itemName: safeString(data.itemName),
    quantity: Number(data.quantity || 1),
    unitSellingGhs: moneyAmount(data.unitSellingGhs),
    unitCostGhs: moneyAmount(data.unitCostGhs),
    totalAmount: moneyAmount(data.totalAmount),
    status: safeString(data.status, "open"),
    paymentMethod: safeString(data.paymentMethod, "Pending"),
    createdAt: data.createdAt && data.createdAt.toDate ? data.createdAt.toDate().toISOString() : null,
    closedAt: data.closedAt && data.closedAt.toDate ? data.closedAt.toDate().toISOString() : null,
  };
}

function summarizeTabs({ tabs, staff }) {
  const closed = tabs.filter((tab) => tab.status === "closed");
  const open = tabs.filter((tab) => tab.status === "open");
  const recordedSales = closed.reduce((sum, tab) => sum + Number(tab.totalAmount || 0), 0);
  const estimatedCost = closed.reduce((sum, tab) => sum + Number(tab.unitCostGhs || 0) * Number(tab.quantity || 1), 0);
  const staffBreakdown = staff.map((member) => {
    const staffTabs = closed.filter((tab) => tab.staffId === member.id);
    return {
      staffId: member.id,
      name: member.name,
      role: member.role,
      closedTabs: staffTabs.length,
      salesGhs: moneyAmount(staffTabs.reduce((sum, tab) => sum + Number(tab.totalAmount || 0), 0)),
    };
  });
  return {
    openTabs: open.length,
    closedTabs: closed.length,
    recordedSalesGhs: moneyAmount(recordedSales),
    estimatedCostGhs: moneyAmount(estimatedCost),
    estimatedMarginGhs: moneyAmount(recordedSales - estimatedCost),
    staffBreakdown,
  };
}

async function loadWorkspace(uid, eventId) {
  const { eventData } = await assertEventManager(uid, eventId);
  const organizationId = safeString(eventData.organizationId);
  const [configSnap, inventorySnap, staffSnap, tabsSnap] = await Promise.all([
    db.collection("event_ops_configs").doc(eventId).get(),
    db.collection("event_inventory_items").where("eventId", "==", eventId).limit(300).get(),
    db.collection("event_ops_staff").where("eventId", "==", eventId).limit(100).get(),
    db.collection("event_ops_tabs").where("eventId", "==", eventId).limit(500).get(),
  ]);
  const config = eventOpsConfigFromDoc(configSnap, eventId, eventData);
  const inventory = inventorySnap.docs.map(inventoryFromDoc);
  const staff = staffSnap.docs.map(staffFromDoc);
  const tabs = tabsSnap.docs.map(tabFromDoc);
  return {
    config: { ...config, organizationId },
    inventory,
    staff,
    tabs,
    summary: summarizeTabs({ tabs, staff }),
  };
}

async function assertEventTeamPermission(uid, eventId, permission) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!TEAM_PERMISSIONS.includes(permission)) {
    throw new HttpsError("invalid-argument", "Unknown team permission.");
  }
  try {
    const managerContext = await assertEventManager(uid, eventId);
    return {
      ...managerContext,
      actor: {
        userId: uid,
        role: "owner",
        roleLabel: "Owner",
        permissions: normalizedPermissions({}, "owner"),
        manager: true,
      },
    };
  } catch (error) {
    if (error instanceof HttpsError && error.code !== "permission-denied") {
      throw error;
    }
  }

  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const eventData = eventSnap.data() || {};
  const memberSnap = await db.collection("event_team_members").doc(`${eventId}_${uid}`).get();
  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "You are not on this event team.");
  }
  const member = teamMemberFromDoc(memberSnap);
  if (member.status !== "active" || member.eventId !== eventId) {
    throw new HttpsError("permission-denied", "This event team access is inactive.");
  }
  if (member.permissions[permission] !== true) {
    throw new HttpsError("permission-denied", "Your event role cannot perform this action.");
  }
  return {
    eventRef: eventSnap.ref,
    eventData,
    actor: {
      userId: uid,
      role: member.role,
      roleLabel: member.roleLabel,
      permissions: member.permissions,
      manager: false,
      teamMemberId: member.id,
    },
  };
}

async function loadEventTeamWorkspace(uid, eventId) {
  const { eventData, actor } = await assertEventTeamPermission(uid, eventId, "viewOrders");
  const organizationId = safeString(eventData.organizationId);
  const [membersSnap, invitesSnap, scanLogsSnap] = await Promise.all([
    db.collection("event_team_members").where("eventId", "==", eventId).limit(200).get(),
    db.collection("event_team_invites").where("eventId", "==", eventId).limit(200).get(),
    db.collection("ticket_scan_logs").where("eventId", "==", eventId).limit(100).get(),
  ]);
  return {
    eventId,
    organizationId,
    eventTitle: safeString(eventData.title, "Event"),
    actor,
    roleTemplates: publicRoleTemplates(),
    members: membersSnap.docs.map(teamMemberFromDoc),
    invites: invitesSnap.docs.map(inviteFromDoc),
    scanLogs: scanLogsSnap.docs.map((docSnap) => {
      const data = docSnap.data() || {};
      return {
        id: docSnap.id,
        type: safeString(data.type),
        qrToken: safeString(data.qrToken),
        ticketId: safeString(data.ticketId),
        attendeeName: safeString(data.attendeeName),
        tierName: safeString(data.tierName),
        status: safeString(data.status),
        outcome: safeString(data.outcome),
        performedBy: safeString(data.performedBy),
        performedByEmail: safeString(data.performedByEmail),
        role: safeString(data.role),
        createdAt: data.createdAt && data.createdAt.toDate ? data.createdAt.toDate().toISOString() : null,
      };
    }).sort((a, b) => String(b.createdAt || "").localeCompare(String(a.createdAt || ""))),
  };
}

async function organizerPushTargets(eventData) {
  const createdBy = safeString(eventData.createdBy);
  if (!createdBy) return [];
  const userSnap = await db.collection("users").doc(createdBy).get();
  if (!userSnap.exists) return [];
  const user = userSnap.data() || {};
  const prefs = user.notificationPrefs || {};
  if (prefs.pushEnabled === false || !user.fcmToken) return [];
  return [createdBy];
}

async function notifyOrganizerPush(eventData, { kind, title, body, eventId, route }) {
  const targets = await organizerPushTargets(eventData);
  if (targets.length === 0) return null;
  return queuePushNotification({
    kind,
    targets,
    payload: {
      title,
      body,
      eventId,
      route: route || `/studio/operations?eventId=${eventId}`,
    },
    eventId,
  });
}

async function notifyLowStockIfNeeded(eventData, tab) {
  const stockBefore = Number(tab && tab.stockBefore);
  const stockAfter = Number(tab && tab.stockAfter);
  if (!Number.isFinite(stockBefore) || !Number.isFinite(stockAfter)) return;
  if (stockAfter > LOW_STOCK_ALERT_THRESHOLD) return;
  if (stockBefore <= LOW_STOCK_ALERT_THRESHOLD && stockAfter !== 0) return;
  await notifyOrganizerPush(eventData, {
    kind: "event_ops_low_stock",
    title: stockAfter <= 0 ? "Inventory sold out" : "Low stock alert",
    body: stockAfter <= 0
      ? `${safeString(tab.itemName, "An item")} is now sold out.`
      : `${safeString(tab.itemName, "An item")} has ${stockAfter} left.`,
    eventId: safeString(tab.eventId),
  });
}

async function createTabWithInventory({ eventId, eventData, staffId, itemId, quantity, customer, createdBy, createdByStaffId, requireListed }) {
  const staffRef = db.collection("event_ops_staff").doc(staffId);
  const itemRef = db.collection("event_inventory_items").doc(itemId);
  const tabRef = db.collection("event_ops_tabs").doc();
  const movementRef = db.collection("event_inventory_movements").doc();
  let createdTab = null;

  await db.runTransaction(async (transaction) => {
    const [staffSnap, itemSnap] = await Promise.all([
      transaction.get(staffRef),
      transaction.get(itemRef),
    ]);
    if (!staffSnap.exists) throw new HttpsError("not-found", "Staff credential not found.");
    if (!itemSnap.exists) throw new HttpsError("not-found", "Inventory item not found.");
    const staff = staffSnap.data() || {};
    const item = itemSnap.data() || {};
    if (safeString(staff.eventId) !== eventId || safeString(item.eventId) !== eventId) {
      throw new HttpsError("permission-denied", "Staff and item must belong to this event.");
    }
    if (staff.active === false) {
      throw new HttpsError("failed-precondition", "This staff credential is inactive.");
    }
    if (requireListed && item.listed === false) {
      throw new HttpsError("permission-denied", "Item is not available for this event.");
    }

    const currentStock = nonNegativeInt(item.stock);
    if (currentStock < quantity) {
      throw new HttpsError(
        "failed-precondition",
        `${safeString(item.name, "This item")} has only ${currentStock} unit${currentStock === 1 ? "" : "s"} left.`,
      );
    }

    const stockAfter = currentStock - quantity;
    const unitSellingGhs = moneyAmount(item.sellingGhs);
    const unitCostGhs = moneyAmount(item.costGhs);
    const tabPayload = {
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      staffId,
      staffName: safeString(staff.name),
      customer: boundedString(customer, 120) || "Walk-in",
      itemId,
      itemName: safeString(item.name),
      quantity,
      unitSellingGhs,
      unitCostGhs,
      totalAmount: moneyAmount(unitSellingGhs * quantity),
      status: "open",
      paymentMethod: "Pending",
      inventoryMovementId: movementRef.id,
      stockBefore: currentStock,
      stockAfter,
      ...(createdBy ? { createdBy } : {}),
      ...(createdByStaffId ? { createdByStaffId } : {}),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    transaction.update(itemRef, {
      stock: stockAfter,
      soldCount: FieldValue.increment(quantity),
      lastOrderTabId: tabRef.id,
      lastInventoryMovementId: movementRef.id,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(tabRef, tabPayload);
    transaction.set(movementRef, {
      eventId,
      organizationId: safeString(eventData.organizationId),
      itemId,
      itemName: safeString(item.name),
      staffId,
      staffName: safeString(staff.name),
      tabId: tabRef.id,
      type: "tab_opened",
      quantityChange: -quantity,
      stockBefore: currentStock,
      stockAfter,
      unitSellingGhs,
      unitCostGhs,
      totalAmount: moneyAmount(unitSellingGhs * quantity),
      createdBy: createdBy || createdByStaffId || "",
      createdByStaffId: createdByStaffId || "",
      createdAt: FieldValue.serverTimestamp(),
    });
    createdTab = {
      id: tabRef.id,
      eventId,
      staffName: safeString(staff.name),
      itemName: safeString(item.name),
      totalAmount: moneyAmount(unitSellingGhs * quantity),
      stockBefore: currentStock,
      stockAfter,
    };
  });

  return createdTab;
}

async function loadStaffSession({ eventId, sessionId, sessionToken }) {
  const id = safeString(sessionId);
  const token = safeString(sessionToken);
  if (!id || !token) throw new HttpsError("unauthenticated", "Staff session is required.");
  const sessionSnap = await db.collection("event_ops_staff_sessions").doc(id).get();
  if (!sessionSnap.exists) throw new HttpsError("unauthenticated", "Staff session expired.");
  const session = sessionSnap.data() || {};
  if (safeString(session.eventId) !== eventId) throw new HttpsError("permission-denied", "Session is for another event.");
  if (safeString(session.status, "active") !== "active") throw new HttpsError("unauthenticated", "Staff session is not active.");
  if (safeString(session.tokenHash) !== hashToken(token)) throw new HttpsError("unauthenticated", "Invalid staff session.");
  const expiresAt = session.expiresAt && session.expiresAt.toMillis ? session.expiresAt.toMillis() : 0;
  if (expiresAt < Date.now()) throw new HttpsError("unauthenticated", "Staff session expired.");

  const staffId = safeString(session.staffId);
  const staffSnap = await db.collection("event_ops_staff").doc(staffId).get();
  if (!staffSnap.exists) throw new HttpsError("not-found", "Staff credential not found.");
  const staff = staffFromDoc(staffSnap);
  if (staff.eventId !== eventId || staff.active === false) {
    throw new HttpsError("permission-denied", "Staff credential is not active for this event.");
  }
  return { sessionId: id, session, staff };
}

async function loadStaffWorkspace(eventId, staffMember) {
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const eventData = eventSnap.data() || {};
  const [configSnap, inventorySnap, tabsSnap] = await Promise.all([
    db.collection("event_ops_configs").doc(eventId).get(),
    db.collection("event_inventory_items").where("eventId", "==", eventId).limit(300).get(),
    db.collection("event_ops_tabs").where("eventId", "==", eventId).limit(500).get(),
  ]);
  const config = eventOpsConfigFromDoc(configSnap, eventId, eventData);
  const inventory = inventorySnap.docs.map(inventoryFromDoc);
  const tabs = tabsSnap.docs.map(tabFromDoc);
  return publicStaffWorkspace({ config, inventory, staffMember, tabs });
}

async function writeEventOpsConfig({ eventId, eventData, payload, requestedStaffAccessCode }) {
  const configRef = db.collection("event_ops_configs").doc(eventId);
  const accessCodes = db.collection("event_ops_access_codes");
  const requestedCode = safeString(requestedStaffAccessCode);

  await db.runTransaction(async (transaction) => {
    const configSnap = await transaction.get(configRef);
    const existing = configSnap.exists ? configSnap.data() || {} : {};
    const existingCode = safeString(existing.staffAccessCode);
    const nextRawCode = requestedCode || existingCode || defaultStaffAccessCode(eventId, eventData);
    const nextNormalized = normalizeStaffAccessCode(nextRawCode);

    if (!nextNormalized || nextNormalized.length < 3) {
      throw new HttpsError("invalid-argument", "Staff app code must be at least 3 letters or numbers.");
    }

    const nextCodeRef = accessCodes.doc(nextNormalized);
    const nextCodeSnap = await transaction.get(nextCodeRef);
    const reservedEventId = nextCodeSnap.exists ? safeString(nextCodeSnap.data() && nextCodeSnap.data().eventId) : "";
    if (reservedEventId && reservedEventId !== eventId) {
      throw new HttpsError("already-exists", "That staff app code is already being used by another event.");
    }

    const previousNormalized = safeString(existing.staffAccessCodeNormalized);
    if (previousNormalized && previousNormalized !== nextNormalized) {
      transaction.delete(accessCodes.doc(previousNormalized));
    }

    transaction.set(nextCodeRef, {
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      code: nextNormalized,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: nextCodeSnap.exists ? nextCodeSnap.data().createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
    }, { merge: true });

    transaction.set(configRef, {
      ...payload,
      staffAccessCode: nextNormalized,
      staffAccessCodeNormalized: nextNormalized,
      ...(configSnap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
    }, { merge: true });
  });
}

async function resolveStaffEvent(eventKey) {
  const raw = safeString(eventKey);
  if (!raw) throw new HttpsError("invalid-argument", "Event code is required.");

  const directSnap = await db.collection("events").doc(raw).get();
  if (directSnap.exists) {
    return { eventId: raw, eventSnap: directSnap };
  }

  const normalized = normalizeStaffAccessCode(raw);
  if (!normalized) throw new HttpsError("not-found", "Event not found.");
  const codeSnap = await db.collection("event_ops_access_codes").doc(normalized).get();
  if (!codeSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const eventId = safeString(codeSnap.get("eventId"));
  if (!eventId) throw new HttpsError("not-found", "Event not found.");
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
  return { eventId, eventSnap };
}

exports.getEventOpsWorkspace = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    return { success: true, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.getEventTeamWorkspace = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    if (!eventId) throw new HttpsError("invalid-argument", "eventId is required.");
    return { success: true, ...(await loadEventTeamWorkspace(uid, eventId)) };
  },
);

exports.createEventTeamInvite = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const email = normalizeEmail(request.data && request.data.email);
    const role = roleTemplate(request.data && request.data.role);
    const { eventData } = await assertEventManager(uid, eventId);
    if (!email || !email.includes("@")) throw new HttpsError("invalid-argument", "A valid email is required.");

    const token = crypto.randomBytes(32).toString("hex");
    const inviteRef = db.collection("event_team_invites").doc();
    const permissions = normalizedPermissions(request.data && request.data.permissions, role);
    const acceptUrl = `${publicSiteBaseUrl()}/invite/${inviteRef.id}?token=${encodeURIComponent(token)}`;
    await inviteRef.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      email,
      role,
      roleLabel: ROLE_TEMPLATES[role].label,
      permissions,
      status: "pending",
      acceptUrl,
      tokenHash: hashToken(token),
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      emailStatus: "pending",
    });
    let emailDelivery = { status: "skipped", reason: "not_attempted" };
    try {
      emailDelivery = await sendEventTeamInviteEmail({
        to: email,
        eventTitle: safeString(eventData.title, "Event"),
        roleLabel: ROLE_TEMPLATES[role].label,
        acceptUrl,
      });
      await inviteRef.set({
        emailStatus: emailDelivery.status,
        emailMessageId: safeString(emailDelivery.messageId),
        emailReason: safeString(emailDelivery.reason),
        emailedAt: emailDelivery.status === "sent" ? FieldValue.serverTimestamp() : null,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (error) {
      emailDelivery = { status: "error", reason: safeString(error && error.message, "email_failed").slice(0, 240) };
      await inviteRef.set({
        emailStatus: "error",
        emailReason: emailDelivery.reason,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    return {
      success: true,
      inviteId: inviteRef.id,
      acceptUrl,
      token,
      emailDelivery,
      ...(await loadEventTeamWorkspace(uid, eventId)),
    };
  },
);

exports.acceptEventTeamInvite = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const authEmail = normalizeEmail(request.auth && request.auth.token && request.auth.token.email);
    const inviteId = safeString(request.data && request.data.inviteId);
    const token = safeString(request.data && request.data.token);
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    if (!inviteId || !token) throw new HttpsError("invalid-argument", "Invite link is incomplete.");

    const inviteRef = db.collection("event_team_invites").doc(inviteId);
    const inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists) throw new HttpsError("not-found", "Invite not found.");
    const invite = inviteSnap.data() || {};
    const email = normalizeEmail(invite.email);
    if (safeString(invite.status, "pending") !== "pending") {
      throw new HttpsError("failed-precondition", "This invite is no longer pending.");
    }
    if (safeString(invite.tokenHash) !== hashToken(token)) {
      throw new HttpsError("permission-denied", "Invite token is invalid.");
    }
    if (email && authEmail && email !== authEmail) {
      throw new HttpsError("permission-denied", `This invite was sent to ${email}. Sign in with that email.`);
    }

    const eventId = safeString(invite.eventId);
    const organizationId = safeString(invite.organizationId);
    const role = roleTemplate(invite.role);
    const permissions = normalizedPermissions(invite.permissions, role);
    const memberRef = db.collection("event_team_members").doc(`${eventId}_${uid}`);
    const eventSnap = await db.collection("events").doc(eventId).get();
    await db.runTransaction(async (transaction) => {
      transaction.set(memberRef, {
        eventId,
        organizationId,
        userId: uid,
        email: authEmail || email,
        displayName: safeString(request.auth.token && request.auth.token.name, authEmail || email),
        role,
        roleLabel: ROLE_TEMPLATES[role].label,
        permissions,
        status: "active",
        acceptedInviteId: inviteId,
        acceptedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(db.collection("organization_members").doc(`${organizationId}_${uid}`), {
        organizationId,
        userId: uid,
        email: authEmail || email,
        role: "event_staff",
        permissions,
        status: "active",
        acceptedInviteId: inviteId,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(db.collection("users").doc(uid), {
        email: authEmail || email,
        roles: FieldValue.arrayUnion("event_staff"),
        defaultOrganizationId: organizationId,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(inviteRef, {
        status: "accepted",
        acceptedBy: uid,
        acceptedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    if (eventSnap.exists) {
      await notifyOrganizerPush(eventSnap.data() || {}, {
        kind: "event_team_invite_accepted",
        title: "Team invite accepted",
        body: `${authEmail || email} joined ${safeString(invite.eventTitle, "your event")} as ${ROLE_TEMPLATES[role].label}.`,
        eventId,
        route: `/studio/team?eventId=${eventId}`,
      });
    }
    return {
      success: true,
      eventId,
      organizationId,
      role,
      permissions,
      redirectPath: `/staff/${eventId}`,
    };
  },
);

exports.updateEventTeamMember = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const memberUserId = safeString(request.data && request.data.userId);
    const role = roleTemplate(request.data && request.data.role);
    const status = safeString(request.data && request.data.status, "active") === "disabled" ? "disabled" : "active";
    await assertEventManager(uid, eventId);
    if (!memberUserId) throw new HttpsError("invalid-argument", "userId is required.");
    await db.collection("event_team_members").doc(`${eventId}_${memberUserId}`).set({
      role,
      roleLabel: ROLE_TEMPLATES[role].label,
      permissions: normalizedPermissions(request.data && request.data.permissions, role),
      status,
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { success: true, ...(await loadEventTeamWorkspace(uid, eventId)) };
  },
);

exports.getEventOpsOnboardingVisuals = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    await assertEventManager(uid, eventId);
    const snap = await db.collection("event_ops_onboarding_visuals").doc(eventId).get();
    const data = snap.exists ? snap.data() || {} : {};
    const generationCount = Number(data.generationCount || 0);
    return {
      success: true,
      status: safeString(data.status, snap.exists ? "complete" : "empty"),
      visuals: Array.isArray(data.visuals) ? data.visuals : [],
      generationCount,
      generationsRemaining: Math.max(MAX_ONBOARDING_VISUAL_GENERATIONS - generationCount, 0),
      updatedAt: data.updatedAt && data.updatedAt.toDate ? data.updatedAt.toDate().toISOString() : null,
    };
  },
);

exports.generateEventOpsOnboardingVisuals = onCall(
  { region: REGION, timeoutSeconds: 540, memory: "1GiB", secrets: ["GEMINI_API_KEY"] },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const apiKey = safeString(process.env.GEMINI_API_KEY);
    if (!apiKey) throw new HttpsError("failed-precondition", "GEMINI_API_KEY is not configured.");

    const organizationId = safeString(eventData.organizationId, `org_${uid}`);
    const eventTitle = safeString(eventData.title, "Event Ops setup");
    const [workspace, brand] = await Promise.all([
      loadWorkspace(uid, eventId),
      loadEventOpsBrand(uid, organizationId),
    ]);
    const visualRef = db.collection("event_ops_onboarding_visuals").doc(eventId);
    const existingVisualSnap = await visualRef.get();
    const existingVisualData = existingVisualSnap.exists ? existingVisualSnap.data() || {} : {};
    const generationCount = Number(existingVisualData.generationCount || 0);
    if (generationCount >= MAX_ONBOARDING_VISUAL_GENERATIONS) {
      throw new HttpsError(
        "resource-exhausted",
        `This event has used all ${MAX_ONBOARDING_VISUAL_GENERATIONS} included Gemini onboarding visual generations.`,
      );
    }
    await visualRef.set({
      eventId,
      organizationId,
      eventTitle,
      status: "generating",
      generatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    try {
      const visuals = [];
      for (const brief of onboardingVisualBriefs()) {
        const prompt = buildOnboardingPrompt({ brief, eventTitle, eventData, brand, workspace });
        const image = await generateGeminiImageWithFallback({
          apiKey,
          parts: [{ text: prompt }],
          aspectRatio: "16:9",
        });
        const uploaded = await uploadEventOpsOnboardingImage({
          uid,
          eventId,
          slot: brief.id,
          eventTitle,
          buffer: image.buffer,
          mimeType: image.mimeType,
        });
        visuals.push({
          id: brief.id,
          title: brief.title,
          body: brief.body,
          imageUrl: uploaded.imageUrl,
          storagePath: uploaded.storagePath,
        });
      }

      await visualRef.set({
        eventId,
        organizationId,
        eventTitle,
        status: "complete",
        visuals,
        generationCount: generationCount + 1,
        generationsRemaining: Math.max(MAX_ONBOARDING_VISUAL_GENERATIONS - generationCount - 1, 0),
        model: GEMINI_MODEL,
        generatedBy: uid,
        generatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return {
        success: true,
        status: "complete",
        visuals,
        generationCount: generationCount + 1,
        generationsRemaining: Math.max(MAX_ONBOARDING_VISUAL_GENERATIONS - generationCount - 1, 0),
      };
    } catch (error) {
      await visualRef.set({
        status: "error",
        error: safeString(error && error.message, "Gemini generation failed.").slice(0, 500),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      throw new HttpsError("internal", "Gemini could not generate the Event Ops onboarding visuals right now.");
    }
  },
);

exports.saveEventOpsConfig = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const selectedPlan = safeString(request.data && request.data.selectedPlan, "pro");
    const paymentMode = safeString(request.data && request.data.paymentMode, "merchant_collected");
    const staffAccessCode = boundedString(request.data && request.data.staffAccessCode, 80);
    if (!EVENT_OPS_PLANS.has(selectedPlan)) throw new HttpsError("invalid-argument", "Invalid Event Ops plan.");
    if (!PAYMENT_MODES.has(paymentMode)) throw new HttpsError("invalid-argument", "Invalid payment mode.");
    if (paymentMode === "vennuzo_controlled") {
      throw new HttpsError("failed-precondition", "Vennuzo-controlled event payments are coming soon.");
    }

    const payload = {
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      setupStarted: request.data && request.data.setupStarted === true,
      setupComplete: request.data && request.data.setupComplete === true,
      selectedPlan,
      paymentMode,
      vennuzoControlledStatus: "coming_soon",
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await writeEventOpsConfig({ eventId, eventData, payload, requestedStaffAccessCode: staffAccessCode });
    return { success: true, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.activateEventOpsPackage = onCall(
  { region: REGION, timeoutSeconds: 90 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const selectedPlan = safeString(request.data && request.data.selectedPlan, "pro");
    const paymentMode = safeString(request.data && request.data.paymentMode, "merchant_collected");
    const staffAccessCode = boundedString(request.data && request.data.staffAccessCode, 80);
    if (!EVENT_OPS_PLANS.has(selectedPlan)) throw new HttpsError("invalid-argument", "Invalid Event Ops plan.");
    if (!PAYMENT_MODES.has(paymentMode)) throw new HttpsError("invalid-argument", "Invalid payment mode.");
    if (paymentMode === "vennuzo_controlled") {
      throw new HttpsError("failed-precondition", "Vennuzo-controlled event payments are coming soon.");
    }

    const organizationId = safeString(eventData.organizationId, `org_${uid}`);
    const configRef = db.collection("event_ops_configs").doc(eventId);
    const configSnap = await configRef.get();
    const existing = configSnap.exists ? configSnap.data() || {} : {};
    if (existing.eventOpsPaid === true) {
      return { success: true, chargeReference: safeString(existing.eventOpsChargeReference), ...(await loadWorkspace(uid, eventId)) };
    }

    const priceGhs = eventOpsPlanPrice(selectedPlan);
    const chargeReference = await chargeEventOpsWallet({
      organizationId,
      uid,
      eventId,
      amount: priceGhs,
      serviceType: `event_ops_${selectedPlan}`,
      description: `${selectedPlan} Event Ops package activation`,
    });

    await writeEventOpsConfig({
      eventId,
      eventData,
      requestedStaffAccessCode: staffAccessCode,
      payload: {
        eventId,
        organizationId,
        eventTitle: safeString(eventData.title, "Event"),
        setupStarted: true,
        setupComplete: true,
        selectedPlan,
        planPriceGhs: priceGhs,
        paymentMode,
        eventOpsPaid: true,
        eventOpsActivatedAt: FieldValue.serverTimestamp(),
        eventOpsChargeReference: chargeReference,
        vennuzoControlledStatus: "coming_soon",
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      },
    });

    return { success: true, chargeReference, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.createEventOpsInventoryItem = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const name = boundedString(request.data && request.data.name, 120);
    if (!name) throw new HttpsError("invalid-argument", "Item name is required.");

    const ref = db.collection("event_inventory_items").doc();
    await ref.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      name,
      category: boundedString(request.data && request.data.category, 80) || "General",
      costGhs: moneyAmount(request.data && request.data.costGhs),
      sellingGhs: moneyAmount(request.data && request.data.sellingGhs),
      stock: nonNegativeInt(request.data && request.data.stock),
      linkedPackage: boundedString(request.data && request.data.linkedPackage, 120),
      listed: request.data && request.data.listed === false ? false : true,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, itemId: ref.id, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.createEventOpsStaffCredential = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const name = boundedString(request.data && request.data.name, 120);
    if (!name) throw new HttpsError("invalid-argument", "Staff name is required.");
    const role = boundedString(request.data && request.data.role, 40) || "Waiter";

    const ref = db.collection("event_ops_staff").doc();
    await ref.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      name,
      role: STAFF_ROLES.has(role) ? role : "Waiter",
      pin: pinCode(),
      station: boundedString(request.data && request.data.station, 80) || "Floor",
      active: true,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, staffId: ref.id, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.createEventOpsTab = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const staffId = safeString(request.data && request.data.staffId);
    const itemId = safeString(request.data && request.data.itemId);
    if (!staffId || !itemId) throw new HttpsError("invalid-argument", "staffId and itemId are required.");

    const quantity = positiveInt(request.data && request.data.quantity);
    const tab = await createTabWithInventory({
      eventId,
      eventData,
      staffId,
      itemId,
      quantity,
      customer: boundedString(request.data && request.data.customer, 120) || "Walk-in",
      createdBy: uid,
      requireListed: false,
    });

    await notifyOrganizerPush(eventData, {
      kind: "event_ops_order_created",
      title: "New event order",
      body: `${safeString(tab.staffName, "Staff")} opened a ${safeString(tab.itemName, "new")} tab.`,
      eventId,
    });
    await notifyLowStockIfNeeded(eventData, tab);

    return { success: true, tabId: tab.id, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.closeEventOpsTab = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const tabId = safeString(request.data && request.data.tabId);
    const paymentMethod = safeString(request.data && request.data.paymentMethod, "Cash");
    await assertEventManager(uid, eventId);
    if (!tabId) throw new HttpsError("invalid-argument", "tabId is required.");
    if (!TAB_PAYMENT_METHODS.has(paymentMethod)) throw new HttpsError("invalid-argument", "Invalid payment method.");

    const ref = db.collection("event_ops_tabs").doc(tabId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Tab not found.");
    const tab = snap.data() || {};
    if (safeString(tab.eventId) !== eventId) throw new HttpsError("permission-denied", "Tab belongs to another event.");
    if (safeString(tab.status) === "closed") {
      return { success: true, tabId, ...(await loadWorkspace(uid, eventId)) };
    }
    await ref.set(
      {
        status: "closed",
        paymentMethod,
        closedBy: uid,
        closedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await notifyOrganizerPush((await db.collection("events").doc(eventId).get()).data() || {}, {
      kind: "event_ops_tab_closed",
      title: "Tab closed",
      body: `${safeString(tab.itemName, "A tab")} was closed as ${paymentMethod} for GHS ${moneyAmount(tab.totalAmount).toFixed(2)}.`,
      eventId,
    });
    return { success: true, tabId, ...(await loadWorkspace(uid, eventId)) };
  },
);

exports.generateEventOpsReport = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const uid = safeString(request.auth && request.auth.uid);
    const eventId = safeString(request.data && request.data.eventId);
    const { eventData } = await assertEventManager(uid, eventId);
    const workspace = await loadWorkspace(uid, eventId);
    const reportRef = db.collection("event_ops_reports").doc();
    await reportRef.set({
      eventId,
      organizationId: safeString(eventData.organizationId),
      eventTitle: safeString(eventData.title, "Event"),
      config: workspace.config,
      summary: workspace.summary,
      inventoryCount: workspace.inventory.length,
      staffCount: workspace.staff.length,
      tabCount: workspace.tabs.length,
      status: "generated",
      generatedBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { success: true, reportId: reportRef.id, ...workspace };
  },
);

exports.startEventOpsStaffSession = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const eventKey = safeString(request.data && request.data.eventId);
    const pin = safeString(request.data && request.data.pin);
    if (!eventKey || !pin) throw new HttpsError("invalid-argument", "Event code and PIN are required.");
    const { eventId, eventSnap } = await resolveStaffEvent(eventKey);
    // Throttle PIN guessing: max 10 attempts per event per caller per 10 minutes.
    const staffPinKey = safeString(
      (request.rawRequest && request.rawRequest.ip) || (request.auth && request.auth.uid),
      "unknown",
    );
    await checkRateLimit(db, `staffpin_${eventId}_${staffPinKey}`, "startEventOpsStaffSession", {
      maxCalls: 10,
      windowSeconds: 600,
    });
    const staffSnap = await db
      .collection("event_ops_staff")
      .where("eventId", "==", eventId)
      .limit(100)
      .get();
    const staffDoc = staffSnap.docs.find((docSnap) => {
      const staffData = docSnap.data() || {};
      return staffData.active !== false && safeString(staffData.pin) === pin;
    });
    if (!staffDoc) throw new HttpsError("permission-denied", "Invalid staff PIN.");

    const staff = staffFromDoc(staffDoc);
    const token = crypto.randomBytes(32).toString("hex");
    const sessionRef = db.collection("event_ops_staff_sessions").doc();
    await sessionRef.set({
      eventId,
      organizationId: staff.organizationId,
      staffId: staff.id,
      staffName: staff.name,
      role: staff.role,
      station: staff.station,
      tokenHash: hashToken(token),
      status: "active",
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + STAFF_SESSION_TTL_MS),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (eventSnap.exists) {
      await notifyOrganizerPush(eventSnap.data() || {}, {
        kind: "event_ops_staff_signed_in",
        title: "Staff signed in",
        body: `${staff.name} signed in as ${staff.role} at ${staff.station}.`,
        eventId,
      });
    }

    return {
      success: true,
      sessionId: sessionRef.id,
      sessionToken: token,
      expiresAt: new Date(Date.now() + STAFF_SESSION_TTL_MS).toISOString(),
      ...(await loadStaffWorkspace(eventId, staff)),
    };
  },
);

exports.getEventOpsStaffWorkspace = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const { staff } = await loadStaffSession({
      eventId,
      sessionId: request.data && request.data.sessionId,
      sessionToken: request.data && request.data.sessionToken,
    });
    return { success: true, ...(await loadStaffWorkspace(eventId, staff)) };
  },
);

exports.createEventOpsStaffTab = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const { staff } = await loadStaffSession({
      eventId,
      sessionId: request.data && request.data.sessionId,
      sessionToken: request.data && request.data.sessionToken,
    });
    const itemId = safeString(request.data && request.data.itemId);
    if (!itemId) throw new HttpsError("invalid-argument", "itemId is required.");
    const eventSnap = await db.collection("events").doc(eventId).get();
    if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");
    const eventData = eventSnap.data() || {};

    const quantity = positiveInt(request.data && request.data.quantity);
    const tab = await createTabWithInventory({
      eventId,
      staffId: staff.id,
      eventData,
      itemId,
      quantity,
      customer: boundedString(request.data && request.data.customer, 120) || "Walk-in",
      createdByStaffId: staff.id,
      requireListed: true,
    });

    await notifyOrganizerPush(eventData, {
      kind: "event_ops_staff_order_created",
      title: "New staff order",
      body: `${staff.name} opened a ${safeString(tab.itemName, "new")} tab.`,
      eventId,
    });
    await notifyLowStockIfNeeded(eventData, tab);

    return { success: true, tabId: tab.id, ...(await loadStaffWorkspace(eventId, staff)) };
  },
);

exports.closeEventOpsStaffTab = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    const eventId = safeString(request.data && request.data.eventId);
    const { staff } = await loadStaffSession({
      eventId,
      sessionId: request.data && request.data.sessionId,
      sessionToken: request.data && request.data.sessionToken,
    });
    const tabId = safeString(request.data && request.data.tabId);
    const paymentMethod = safeString(request.data && request.data.paymentMethod, "Cash");
    if (!tabId) throw new HttpsError("invalid-argument", "tabId is required.");
    if (!TAB_PAYMENT_METHODS.has(paymentMethod)) throw new HttpsError("invalid-argument", "Invalid payment method.");
    const ref = db.collection("event_ops_tabs").doc(tabId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Tab not found.");
    const tab = snap.data() || {};
    if (safeString(tab.eventId) !== eventId) throw new HttpsError("permission-denied", "Tab belongs to another event.");
    const elevatedRoles = new Set(["Floor lead", "Owner", "Bartender"]);
    if (safeString(tab.staffId) !== staff.id && !elevatedRoles.has(staff.role)) {
      throw new HttpsError("permission-denied", "You can only close your assigned tabs.");
    }
    await ref.set(
      {
        status: "closed",
        paymentMethod,
        closedByStaffId: staff.id,
        closedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    const eventSnap = await db.collection("events").doc(eventId).get();
    if (eventSnap.exists) {
      await notifyOrganizerPush(eventSnap.data() || {}, {
        kind: "event_ops_staff_tab_closed",
        title: "Staff closed a tab",
        body: `${staff.name} closed ${safeString(tab.itemName, "a tab")} as ${paymentMethod} for GHS ${moneyAmount(tab.totalAmount).toFixed(2)}.`,
        eventId,
      });
    }
    return { success: true, tabId, ...(await loadStaffWorkspace(eventId, staff)) };
  },
);
