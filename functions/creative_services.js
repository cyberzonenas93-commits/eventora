"use strict";

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { checkRateLimit } = require("./rate_limiter");
const { notifyUserPush, notifySuperAdmins } = require("./event_notifications");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;

const REGION = "us-central1";
const FLYER_PRICE_GHS = 50;
const TABLE_PACKAGE_FLYER_PRICE_GHS = 50;
const FLYER_VIDEO_PRICE_GHS = 100;
const INCLUDED_MINOR_EDITS = 10;
const INCLUDED_REDESIGNS = 2;
const GEMINI_MODEL = "gemini-3-pro-image-preview";
const GEMINI_FALLBACK_MODELS = ["gemini-2.5-flash-image"];
const MAX_REFERENCE_IMAGE_URLS = 200;
const MAX_INLINE_REFERENCE_IMAGES = 12;
const VEO_MODEL = "veo-3.1-generate-preview";
const VEO_RETRY_MODEL = "veo-3.1-fast-generate-preview";
const VEO_POLL_BASE = "https://generativelanguage.googleapis.com/v1beta";
const FLYER_VIDEO_DURATION_SECONDS = 8;

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

async function notifyCreativeUser(uid, { title, body, route, kind, jobId, serviceType }) {
  if (!uid || typeof notifyUserPush !== "function") return;
  await notifyUserPush(uid, {
    title,
    body,
    route: route || "/creative",
    kind,
    jobId,
    serviceType,
  }).catch((error) => {
    console.error("[creative_services] user notification failed", jobId, error);
  });
}

async function notifyCreativeAdmins({ title, body, kind, jobId }) {
  if (typeof notifySuperAdmins !== "function") return;
  await notifySuperAdmins({
    title,
    body,
    route: "/admin/settings",
    kind,
  }).catch((error) => {
    console.error("[creative_services] admin notification failed", jobId, error);
  });
}

function normalizePhoneNumber(phone) {
  const digits = String(phone || "").replace(/[^\d+]/g, "");
  if (!digits) return "";
  if (digits.startsWith("+233")) return digits;
  if (digits.startsWith("233") && digits.length === 12) return `+${digits}`;
  if (digits.startsWith("0") && digits.length === 10) return `+233${digits.slice(1)}`;
  if (digits.length === 9) return `+233${digits}`;
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function currencyAmount(value, fallback = 0) {
  const amount = Number(value);
  return Number.isFinite(amount) ? Math.round(amount * 100) / 100 : fallback;
}

function limitString(value, max = 1200) {
  return safeString(value).slice(0, max);
}

function uniqueLimitedStrings(values, max, stringMax = 4000) {
  const seen = new Set();
  const result = [];
  for (const value of Array.isArray(values) ? values : []) {
    const normalized = limitString(value, stringMax);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
    if (result.length >= max) break;
  }
  return result;
}

function selectReferenceImageUrls(urls, seed, max = MAX_INLINE_REFERENCE_IMAGES) {
  const pool = uniqueLimitedStrings(urls, MAX_REFERENCE_IMAGE_URLS);
  if (pool.length <= max) return pool;
  const stableSeed = safeString(seed, `${Date.now()}`);
  return pool
    .map((url, index) => ({
      url,
      score: crypto
        .createHash("sha256")
        .update(`${stableSeed}:${index}:${url}`)
        .digest("hex")
        .slice(0, 16),
    }))
    .sort((a, b) => a.score.localeCompare(b.score))
    .slice(0, max)
    .map((item) => item.url);
}

function normalizeTier(raw) {
  const name = limitString(raw && raw.name, 80);
  const price = limitString(raw && raw.price, 40);
  const itemsRaw = Array.isArray(raw && raw.items) ? raw.items : [];
  const items = itemsRaw.map((item) => limitString(item, 90)).filter(Boolean).slice(0, 12);
  return { name, price, items };
}

async function assertOrganizerAccess(uid, organizationId) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const orgId = safeString(organizationId, `org_${uid}`);
  if (orgId === `org_${uid}`) return orgId;

  const [memberSnap, applicationSnap] = await Promise.all([
    db.collection("organization_members").doc(`${orgId}_${uid}`).get(),
    db.collection("organizer_applications").doc(uid).get(),
  ]);
  const member = memberSnap.exists ? memberSnap.data() || {} : {};
  const application = applicationSnap.exists ? applicationSnap.data() || {} : {};
  const isMember = member.organizationId === orgId && member.status !== "disabled";
  const ownsApplication = application.organizationId === orgId && application.userId === uid;
  if (!isMember && !ownsApplication) {
    throw new HttpsError("permission-denied", "You can only use creative services for your own workspace.");
  }
  return orgId;
}

async function loadBrandConfig(uid, organizationId) {
  const [brandSnap, appSnap, orgSnap] = await Promise.all([
    db.collection("creative_brand_configs").doc(organizationId).get(),
    db.collection("organizer_applications").doc(uid).get(),
    db.collection("organizations").doc(organizationId).get(),
  ]);
  const brand = brandSnap.exists ? brandSnap.data() || {} : {};
  const app = appSnap.exists ? appSnap.data() || {} : {};
  const org = orgSnap.exists ? orgSnap.data() || {} : {};
  return {
    brandName: safeString(brand.brandName, safeString(app.organizerName, safeString(org.name, "Vennuzo creator"))),
    tagline: safeString(brand.tagline, safeString(app.brandTagline)),
    brandStyle: safeString(brand.brandStyle, "premium, modern, event-led, Ghanaian creator energy"),
    brandColor: safeString(brand.brandColor, safeString(app.brandAccentColor, "#7dd3fc")),
    logoUrl: safeString(brand.logoUrl, safeString(app.logoImageUrl)),
    phones: Array.isArray(brand.phones) ? brand.phones.map(safeString).filter(Boolean).slice(0, 3) : [],
    instagram: safeString(brand.instagram, safeString(app.instagram)),
    website: safeString(brand.website),
  };
}

async function chargeWallet({ organizationId, uid, jobId, amount, serviceType, description }) {
  const rounded = currencyAmount(amount);
  if (rounded <= 0) return null;
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `creative_${jobId}_charge`;
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
      type: "creative_service_charge",
      serviceType,
      amount: rounded,
      clientReference,
      jobId,
      description,
      status: "completed",
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return clientReference;
}

async function refundWalletCharge({ organizationId, uid, jobId, amount, serviceType, reason }) {
  const rounded = currencyAmount(amount);
  if (rounded <= 0) return;
  const walletRef = db.collection("advertiser_wallets").doc(organizationId);
  const clientReference = `creative_${jobId}_refund`;
  const txnRef = db.collection("wallet_transactions").doc(clientReference);
  await db.runTransaction(async (transaction) => {
    const [walletSnap, existingTxn] = await Promise.all([
      transaction.get(walletRef),
      transaction.get(txnRef),
    ]);
    if (existingTxn.exists && existingTxn.data().status === "completed") return;
    const walletUpdate = {
      organizationId,
      ownerId: uid,
      availableBalance: FieldValue.increment(rounded),
      currency: "GHS",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!walletSnap.exists) walletUpdate.createdAt = FieldValue.serverTimestamp();
    transaction.set(walletRef, walletUpdate, { merge: true });
    transaction.set(txnRef, {
      walletId: organizationId,
      type: "creative_service_refund",
      serviceType,
      amount: rounded,
      clientReference,
      jobId,
      reason: safeString(reason, "generation_failed"),
      status: "completed",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function useIncludedQuota({ uid, sourceSessionId, quotaField }) {
  if (!sourceSessionId) return { used: false };
  const sessionRef = db.collection("flyer_sessions").doc(sourceSessionId);
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(sessionRef);
    if (!snap.exists) throw new HttpsError("not-found", "Source flyer session not found.");
    const data = snap.data() || {};
    if (data.uid !== uid) throw new HttpsError("permission-denied", "You can only edit your own flyer.");
    const remaining = Number(data[quotaField] ?? 0);
    if (remaining <= 0) return { used: false, sourceData: data };
    transaction.update(sessionRef, {
      [quotaField]: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { used: true, sourceData: data, remainingAfter: remaining - 1 };
  });
}

async function restoreIncludedQuota({ uid, sourceSessionId, quotaField }) {
  if (!sourceSessionId || !quotaField) return;
  const sessionRef = db.collection("flyer_sessions").doc(sourceSessionId);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(sessionRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (data.uid !== uid) return;
    transaction.update(sessionRef, {
      [quotaField]: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function fetchInlineImage(urlOrDataUrl, label = "image") {
  const value = safeString(urlOrDataUrl);
  if (!value) return null;
  if (value.startsWith("data:")) {
    const match = value.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) return null;
    return { inlineData: { mimeType: match[1], data: match[2] }, label };
  }
  const resp = await fetch(value);
  if (!resp.ok) throw new Error(`Could not fetch ${label} (${resp.status})`);
  const contentType = resp.headers.get("content-type") || "image/png";
  const buffer = Buffer.from(await resp.arrayBuffer());
  return { inlineData: { mimeType: contentType, data: buffer.toString("base64") }, label };
}

function exactTextLines(jobData, brand) {
  const lines = [];
  const presentedBy = safeString(jobData.presentedBy, `${brand.brandName} PRESENTS`);
  if (presentedBy) lines.push(presentedBy.toUpperCase());
  if (jobData.eventName) lines.push(safeString(jobData.eventName).toUpperCase());
  const dateTime = [jobData.date, jobData.time].map(safeString).filter(Boolean).join(" · ");
  if (dateTime) lines.push(dateTime);
  if (jobData.venue) lines.push(safeString(jobData.venue));
  if (jobData.djs) lines.push(`DJs: ${safeString(jobData.djs)}`);
  if (jobData.mc) lines.push(`MC: ${safeString(jobData.mc)}`);
  if (jobData.host) lines.push(`Host: ${safeString(jobData.host)}`);
  if (jobData.performers) lines.push(safeString(jobData.performers));
  const phones = safeString(jobData.phonesOverride, brand.phones.join(" / "));
  const instagram = safeString(jobData.instagramOverride, brand.instagram);
  const website = safeString(jobData.websiteOverride, brand.website);
  const footer = safeString(jobData.footerOverride, brand.tagline);
  if (phones) lines.push(`Reservations: ${phones}`);
  if (instagram) lines.push(instagram.startsWith("@") ? instagram : `@${instagram}`);
  if (website) lines.push(website);
  if (footer) lines.push(footer);
  return lines;
}

function buildVisualTerritories(jobData, brand) {
  const brandAccent = safeString(brand.brandColor, "the brand accent color");
  const eventName = safeString(jobData.eventName, "the event");
  const subject = safeString(
    jobData.imageSubject || jobData.modelDescription,
    "derive a bold visual subject from the event name, venue, audience, and creative direction",
  );
  return [
    `Electric editorial: real photographic atmosphere for ${eventName}, dramatic rim light in ${brandAccent}, smoke, lens flare, wet pavement or glass reflections, confident human subject or crowd silhouette, negative space reserved for type.`,
    `Luxury nightlife: champagne gold and deep shadow, cinematic bottle-service or rooftop-city energy, realistic bokeh, polished fashion styling, premium Accra event mood, no generic club clip-art.`,
    `Underground poster: high-contrast shadows, selective neon, gritty film grain, layered depth, asymmetric composition, strong human-made poster craft rather than centered AI symmetry.`,
    `Subject-led concept: ${subject}; make the subject feel specific and intentional, with the event theme driving wardrobe, lighting, props, architecture, and palette.`,
  ].join("\n");
}

function strictTextRules(lines) {
  return `Render ONLY these exact strings. Any visible text not listed here is a defect. Do not add extra words, placeholder text, fake prices, fake sponsors, third-party nightclub branding, plus-sign venue marks, watermarks, random letters, aspect-ratio labels, crop notes, or production notes such as "Full aspect ratio", "9:16", "poster", "flyer", or "mockup":
${lines.map((line) => `- ${line}`).join("\n")}`;
}

function agencyQualityRules() {
  return `Quality standard:
- Make it look like a real senior designer finished it for a premium venue or festival campaign, not a template and not a generic AI poster.
- Use real photographic or high-end photo-composite texture: lens flares, bokeh, film grain, light scatter, haze, reflections, depth of field, imperfect human-made lighting.
- Typography should be hand-placed: bold condensed uppercase headline, elegant supporting details, subtle tracking, tasteful shadows or glow, intentional offsets, strong hierarchy.
- Prefer asymmetric editorial layout with negative space, thin accent rules, cropped subjects, layered foreground/background depth, and confident scale contrast.
- Avoid smooth gradient-only backgrounds, centered symmetry, flat digital illustration, clip-art icons, fake logos, and decorative clutter.
- The artwork fills the entire vertical canvas edge to edge, with no border and no mockup frame. Do not write canvas, ratio, format, or production instructions into the image. Text must be crisp and phone-readable.`;
}

function buildEventFlyerPrompt(jobData, brand) {
  const lines = exactTextLines(jobData, brand);
  return `You are a world-class event flyer art director. Create a complete, print-ready 9:16 event flyer for a Vennuzo organizer with the same creative ambition as the strongest GPlus flyers, but without using GPlus branding.

Brand:
- Brand name: ${brand.brandName}
- Brand style: ${brand.brandStyle}
- Brand color: ${brand.brandColor}
- Tagline: ${brand.tagline || "none"}

Event brief:
- Event name: ${safeString(jobData.eventName)}
- Creative direction: ${limitString(jobData.creativeDescription || jobData.preferences || jobData.theme, 1600)}
- Visual subject: ${safeString(jobData.imageSubject || jobData.modelDescription || "derive the strongest subject from the event name")}
- Notes: ${limitString(jobData.notes, 700)}

Creative territories to draw from. Choose one strong direction or blend two if it improves the result:
${buildVisualTerritories(jobData, brand)}

${agencyQualityRules()}

Visible text rules:
${strictTextRules(lines)}

Brand rules:
- Use the brand color as an accent, not as the whole palette. Let the event theme decide the full color grade.
- If a logo image is provided, use it faithfully. Do not invent alternate logos or venue marks.
- Event title appears once, dominant. Supporting details stay smaller, clean, and readable.`;
}

function buildTablePackagePrompt(jobData, brand) {
  const tiers = (Array.isArray(jobData.tiers) ? jobData.tiers : []).map(normalizeTier).filter((tier) => tier.name);
  const tierTextLines = tiers.flatMap((tier) => [
    tier.name,
    tier.price,
    ...tier.items,
  ].filter(Boolean));
  const tierLines = tiers.map((tier, index) => {
    const items = tier.items.map((item) => `    - ${item}`).join("\n") || "    - Items to be confirmed";
    return `Tier ${index + 1}: ${tier.name}\n  Price: ${tier.price || "TBA"}\n  Includes:\n${items}`;
  }).join("\n\n");
  const headerLines = exactTextLines(jobData, brand);
  return `You are a world-class nightlife and hospitality flyer art director. Create a complete, print-ready 9:16 table-package flyer for a Vennuzo organizer with the same creative ambition as the strongest GPlus table flyers, but without using GPlus branding.

Brand:
- Brand name: ${brand.brandName}
- Brand style: ${brand.brandStyle}
- Brand color: ${brand.brandColor}

Visible text rules:
${strictTextRules([...headerLines, ...tierTextLines])}

Table packages, render every tier name, price, and item exactly:
${tierLines}

Creative territories to draw from. Choose one strong direction or blend two if it improves the result:
${buildVisualTerritories(jobData, brand)}

${agencyQualityRules()}

Design rules:
- Tier cards must feel native to the event theme, not generic menu boxes. Use glass, foil, shadow, photo cutouts, or editorial panels only when they help legibility.
- Choose layout by tier count: 4 tiers as balanced 2x2, 3 tiers as strong vertical stack, 1 tier as one hero panel, 5-6 tiers as organized two-column rhythm.
- Do not add placeholder text, fake package names, fake menu items, watermarks, logos, or brands that were not provided.
- Use the organizer brand color as an accent, but let the event theme drive the full palette.`;
}

function buildMinorEditPrompt(jobData) {
  return `Edit the supplied flyer image in place. Apply only this small requested change:
${limitString(jobData.editInstruction || jobData.refinement, 900)}

Preserve the existing flyer composition, crop, subject, colors, lighting, typography hierarchy, brand marks, dates, venue, contact details, and all visible text unless the requested edit explicitly changes one of those items. Do not redesign the flyer. Do not add any third-party nightclub branding, plus-sign venue marks, unrelated website text, or extra branding. Return the edited flyer only, as a 9:16 image.`;
}

async function callGeminiImage({ apiKey, parts, model, aspectRatio = "9:16" }) {
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

async function generateWithFallback({ apiKey, parts }) {
  const models = [GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS];
  let lastError = null;
  for (const model of models) {
    try {
      return await callGeminiImage({ apiKey, parts, model });
    } catch (error) {
      lastError = error;
      console.warn(`[creative_services] ${model} failed:`, error.message);
    }
  }
  throw lastError || new Error("Gemini image generation failed.");
}

const VEO_PRESERVE_PREFIX = "LOCKED-OFF CAMERA. PRESERVE ALL TEXT, LOGOS, DATES, VENUE DETAILS, SOCIAL HANDLES, PRICES, AND GRAPHIC MARKS EXACTLY AS IN THE SOURCE FLYER. Do not redraw, re-letter, distort, blur, shimmer, animate, or change any text or logo. Motion is limited to scene elements away from text and the existing hero/visual elements only. ";

function buildVeoFlyerMotionPrompt(jobData) {
  const eventName = safeString(jobData.eventName, "the event");
  return `${VEO_PRESERVE_PREFIX}Create one premium 8-second Instagram Story event flyer animation for ${eventName}. The original flyer remains the fixed composition. Add tasteful Ghana nightlife event energy: subtle ambient smoke, soft bokeh light pulses, gentle fabric or hero subject movement where already present, restrained glow from existing light sources, and a final held frame where every word and logo is crisp and unchanged. No camera pan, no zoom, no parallax, no new text, no new branding, no rewritten typography. Soundtrack direction: polished Afrobeats/Afro-fusion club energy, warm percussion, clean bass, cinematic finish.`;
}

function sanitizePromptForRai(prompt) {
  const replacements = [
    [/\bsexual(?:ly)?\b/gi, "performance"],
    [/\bseductive(?:ly)?\b/gi, "confidently"],
    [/\bsultry\b/gi, "editorial"],
    [/\bsexy\b/gi, "striking"],
    [/\bprovocative(?:ly)?\b/gi, "boldly"],
    [/\berotic\b/gi, "expressive"],
    [/\bsensual(?:ly)?\b/gi, "gracefully"],
    [/\brevealing\b/gi, "fashion-forward"],
    [/\bnaked\b|\bnude\b/gi, ""],
    [/\btwerk(?:ing)?\b/gi, "rhythmic Afrobeats movement"],
    [/\bdolly\b|\bpush.?in\b|\bpan\b|\borbit\b|\bparallax\b|\bzoom\b/gi, ""],
  ];
  let out = safeString(prompt);
  for (const [pattern, replacement] of replacements) out = out.replace(pattern, replacement);
  return `${VEO_PRESERVE_PREFIX}${out}`.replace(/\s{2,}/g, " ").trim();
}

async function fetchImageForVeo(imageUrl) {
  const resp = await fetch(imageUrl);
  if (!resp.ok) throw new Error(`Failed to fetch source flyer image (${resp.status}): ${await resp.text().catch(() => "")}`);
  const buffer = Buffer.from(await resp.arrayBuffer());
  if (buffer.length <= 0) throw new Error("Source flyer image is empty.");
  const contentType = safeString(resp.headers.get("content-type"), "image/png").split(";")[0].trim();
  return {
    imageBase64: buffer.toString("base64"),
    imageMime: contentType.startsWith("image/") ? contentType : "image/png",
    byteLength: buffer.length,
  };
}

async function veoSubmit({ prompt, imageBase64, imageMime, geminiKey, model = VEO_MODEL }) {
  const instance = { prompt };
  if (imageBase64) {
    instance.image = { bytesBase64Encoded: imageBase64, mimeType: imageMime || "image/png" };
  }
  const resp = await fetch(`${VEO_POLL_BASE}/models/${model}:predictLongRunning?key=${geminiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      instances: [instance],
      parameters: {
        aspectRatio: "9:16",
        sampleCount: 1,
        durationSeconds: FLYER_VIDEO_DURATION_SECONDS,
        personGeneration: "allow_all",
      },
    }),
  });
  if (!resp.ok) throw new Error(`Veo submit failed (${resp.status}): ${await resp.text()}`);
  const data = await resp.json();
  if (!data.name) throw new Error(`Veo returned no operation name: ${JSON.stringify(data)}`);
  return data.name;
}

function extractVeoVideoUri(pollData) {
  const samples = pollData.response?.generateVideoResponse?.generatedSamples ||
    pollData.response?.videos ||
    pollData.response?.generatedVideos ||
    pollData.response?.predictions;
  const sample = Array.isArray(samples) ? samples[0] : samples;
  return sample?.video?.uri || sample?.uri || sample?.gcsUri;
}

async function veoPoll(operationName, geminiKey, maxWaitMs = 480000) {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    await sleep(12000);
    const pollResp = await fetch(`${VEO_POLL_BASE}/${operationName}?key=${geminiKey}`);
    if (!pollResp.ok) {
      console.warn(`[creative_services] Veo poll non-OK (${pollResp.status}) for ${operationName}`);
      continue;
    }
    const pollData = await pollResp.json();
    if (pollData.error) throw new Error(`Veo error: ${pollData.error.message || JSON.stringify(pollData.error)}`);
    if (!pollData.done) continue;
    const raiCount = pollData.response?.generateVideoResponse?.raiMediaFilteredCount;
    if (raiCount > 0) {
      const err = new Error("rai_blocked");
      err.raiCount = raiCount;
      throw err;
    }
    const videoUri = extractVeoVideoUri(pollData);
    if (!videoUri) throw new Error(`Veo returned no video URI: ${JSON.stringify(pollData).slice(0, 500)}`);
    return videoUri;
  }
  throw new Error("Veo video generation timed out after 8 minutes");
}

async function downloadVeoVideo(videoUri, geminiKey) {
  const sep = videoUri.includes("?") ? "&" : "?";
  const resp = await fetch(`${videoUri}${sep}alt=media&key=${geminiKey}`);
  if (!resp.ok) throw new Error(`Veo video download failed (${resp.status}): ${await resp.text().catch(() => "")}`);
  const buffer = Buffer.from(await resp.arrayBuffer());
  if (buffer.length <= 0) throw new Error("Veo returned an empty video file.");
  return buffer;
}

async function uploadGeneratedImage({ uid, kind, eventName, buffer, mimeType }) {
  const bucket = admin.storage().bucket();
  const ext = mimeType.includes("jpeg") ? "jpg" : "png";
  const safeName = safeString(eventName, kind).replace(/[^a-z0-9]/gi, "-").toLowerCase().slice(0, 44) || kind;
  const storagePath = `creative_services/${kind}/${uid}/${safeName}-${Date.now()}.${ext}`;
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

async function uploadGeneratedVideo({ uid, kind, eventName, buffer }) {
  const bucket = admin.storage().bucket();
  const safeName = safeString(eventName, kind).replace(/[^a-z0-9]/gi, "-").toLowerCase().slice(0, 44) || kind;
  const storagePath = `creative_services/${kind}/${uid}/${safeName}-${Date.now()}.mp4`;
  const file = bucket.file(storagePath);
  await file.save(buffer, {
    metadata: {
      contentType: "video/mp4",
      cacheControl: "public, max-age=31536000",
    },
  });
  await file.makePublic().catch(() => {});
  return {
    storagePath,
    videoUrl: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(storagePath)}?alt=media`,
  };
}

exports.getCreativeServicesConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = request.auth.uid;
    const organizationId = await assertOrganizerAccess(uid, request.data && request.data.organizationId);
    const brand = await loadBrandConfig(uid, organizationId);
    return {
      organizationId,
      brand,
      pricing: {
        flyerGhs: FLYER_PRICE_GHS,
        tablePackageFlyerGhs: TABLE_PACKAGE_FLYER_PRICE_GHS,
        flyerVideoGhs: FLYER_VIDEO_PRICE_GHS,
        includedMinorEdits: INCLUDED_MINOR_EDITS,
        includedRedesigns: INCLUDED_REDESIGNS,
      },
    };
  },
);

exports.saveCreativeBrandConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = request.auth.uid;
    const organizationId = await assertOrganizerAccess(uid, request.data && request.data.organizationId);
    const phones = Array.isArray(request.data && request.data.phones)
      ? request.data.phones.map(normalizePhoneNumber).filter(Boolean).slice(0, 3)
      : [];
    const payload = {
      organizationId,
      ownerId: uid,
      brandName: limitString(request.data && request.data.brandName, 120),
      tagline: limitString(request.data && request.data.tagline, 160),
      brandStyle: limitString(request.data && request.data.brandStyle, 600),
      brandColor: limitString(request.data && request.data.brandColor, 40),
      logoUrl: limitString(request.data && request.data.logoUrl, 1200),
      phones,
      instagram: limitString(request.data && request.data.instagram, 120),
      website: limitString(request.data && request.data.website, 240),
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    };
    await db.collection("creative_brand_configs").doc(organizationId).set(payload, { merge: true });
    return { success: true, brand: payload };
  },
);

exports.submitCreativeFlyerJob = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = request.auth.uid;
    const data = request.data || {};
    await checkRateLimit(db, uid, "submitCreativeFlyerJob", { maxCalls: 8, windowSeconds: 3600 });
    const organizationId = await assertOrganizerAccess(uid, data.organizationId);
    const serviceType = safeString(data.serviceType, "event_flyer");
    const editMode = safeString(data.editMode).toLowerCase();
    if (!["event_flyer", "table_package_flyer"].includes(serviceType)) {
      throw new HttpsError("invalid-argument", "serviceType must be event_flyer or table_package_flyer.");
    }
    const isMinorEdit = editMode === "minor";
    const isRedesign = editMode === "redesign";
    if (!isMinorEdit && !safeString(data.eventName)) {
      throw new HttpsError("invalid-argument", "eventName is required.");
    }
    if (serviceType === "table_package_flyer" && !isMinorEdit) {
      const tiers = Array.isArray(data.tiers) ? data.tiers.map(normalizeTier).filter((tier) => tier.name) : [];
      if (tiers.length === 0) throw new HttpsError("invalid-argument", "Add at least one table package tier.");
    }

    const jobRef = db.collection("flyer_jobs").doc();
    const referenceImageUrls = uniqueLimitedStrings(data.referenceImageUrls, MAX_REFERENCE_IMAGE_URLS);
    const selectedReferenceImageUrls = selectReferenceImageUrls(
      referenceImageUrls,
      `${jobRef.id}:${safeString(data.eventName)}:${safeString(data.creativeDescription || data.preferences || data.theme)}`,
    );
    let price = serviceType === "table_package_flyer" ? TABLE_PACKAGE_FLYER_PRICE_GHS : FLYER_PRICE_GHS;
    let quotaUse = { used: false };
    if (isMinorEdit) {
      quotaUse = await useIncludedQuota({
        uid,
        sourceSessionId: safeString(data.sourceSessionId),
        quotaField: "minorEditsRemaining",
      });
      if (quotaUse.used) price = 0;
    } else if (isRedesign) {
      quotaUse = await useIncludedQuota({
        uid,
        sourceSessionId: safeString(data.sourceSessionId),
        quotaField: "redesignsRemaining",
      });
      if (quotaUse.used) price = 0;
    }

    let debitTransactionId = null;
    if (price > 0) {
      debitTransactionId = await chargeWallet({
        organizationId,
        uid,
        jobId: jobRef.id,
        amount: price,
        serviceType,
        description: serviceType === "table_package_flyer" ? "Table package flyer generation" : "Event flyer generation",
      });
    }

    await jobRef.set({
      uid,
      organizationId,
      serviceType,
      editMode: editMode || null,
      status: "pending",
      currentStep: "Queued",
      progress: 0,
      priceChargedGhs: price,
      debitTransactionId,
      quotaCovered: quotaUse.used === true,
      sourceSessionId: safeString(data.sourceSessionId) || null,
      eventName: limitString(data.eventName, 160),
      date: limitString(data.date, 80),
      time: limitString(data.time, 80),
      venue: limitString(data.venue, 160),
      djs: limitString(data.djs, 220),
      mc: limitString(data.mc, 120),
      host: limitString(data.host, 120),
      performers: limitString(data.performers, 240),
      dresscode: limitString(data.dresscode, 160),
      notes: limitString(data.notes, 900),
      preferences: limitString(data.preferences, 1000),
      creativeDescription: limitString(data.creativeDescription, 1600),
      imageSubject: limitString(data.imageSubject, 300),
      modelDescription: limitString(data.modelDescription, 300),
      phoneNumber: normalizePhoneNumber(data.phoneNumber),
      phonesOverride: limitString(data.phonesOverride, 160),
      instagramOverride: limitString(data.instagramOverride, 120),
      websiteOverride: limitString(data.websiteOverride, 240),
      footerOverride: limitString(data.footerOverride, 200),
      presentedBy: limitString(data.presentedBy, 160),
      uploadedFlyerUrl: limitString(data.uploadedFlyerUrl, 1200),
      customBgUrl: limitString(data.customBgUrl, 1200),
      sourceFlyerUrl: limitString(data.sourceFlyerUrl, 1200),
      editInstruction: limitString(data.editInstruction || data.refinement, 900),
      referenceImageUrls,
      selectedReferenceImageUrls,
      referenceImageCount: referenceImageUrls.length,
      selectedReferenceImageCount: selectedReferenceImageUrls.length,
      tiers: Array.isArray(data.tiers) ? data.tiers.map(normalizeTier).filter((tier) => tier.name).slice(0, 8) : [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      jobId: jobRef.id,
      status: "pending",
      priceChargedGhs: price,
      quotaCovered: quotaUse.used === true,
    };
  },
);

exports.submitCreativeFlyerVideoJob = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = request.auth.uid;
    const data = request.data || {};
    await checkRateLimit(db, uid, "submitCreativeFlyerVideoJob", { maxCalls: 4, windowSeconds: 3600 });
    const organizationId = await assertOrganizerAccess(uid, data.organizationId);
    const sourceSessionId = safeString(data.sourceSessionId);
    if (!sourceSessionId) {
      throw new HttpsError("invalid-argument", "sourceSessionId is required.");
    }

    const sourceSnap = await db.collection("flyer_sessions").doc(sourceSessionId).get();
    if (!sourceSnap.exists) throw new HttpsError("not-found", "Source flyer session not found.");
    const source = sourceSnap.data() || {};
    if (source.uid !== uid || source.organizationId !== organizationId) {
      throw new HttpsError("permission-denied", "You can only animate flyers from your own workspace.");
    }
    const flyerUrl = safeString(source.imageUrl, safeString(source.downloadUrl));
    if (!flyerUrl) throw new HttpsError("failed-precondition", "Source flyer has no image URL.");

    const jobRef = db.collection("flyer_video_jobs").doc();
    const debitTransactionId = await chargeWallet({
      organizationId,
      uid,
      jobId: jobRef.id,
      amount: FLYER_VIDEO_PRICE_GHS,
      serviceType: "flyer_video",
      description: "Flyer video animation",
    });

    await jobRef.set({
      uid,
      organizationId,
      serviceType: "flyer_video",
      sourceSessionId,
      flyerUrl,
      eventName: limitString(source.eventName || data.eventName, 160),
      status: "pending",
      currentStep: "Queued",
      progress: 0,
      priceChargedGhs: FLYER_VIDEO_PRICE_GHS,
      debitTransactionId,
      engine: "gplus_veo_3_1",
      veoModel: VEO_MODEL,
      durationSeconds: FLYER_VIDEO_DURATION_SECONDS,
      aspectRatio: "9:16",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      jobId: jobRef.id,
      status: "pending",
      priceChargedGhs: FLYER_VIDEO_PRICE_GHS,
    };
  },
);

exports.processCreativeFlyerJob = onDocumentCreated(
  {
    document: "flyer_jobs/{jobId}",
    region: REGION,
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const jobData = snap.data() || {};
    if (jobData.status !== "pending" || !jobData.serviceType) return;
    const jobRef = snap.ref;
    const jobId = event.params.jobId;
    const uid = safeString(jobData.uid);
    const organizationId = safeString(jobData.organizationId);

    try {
      const geminiKey = process.env.GEMINI_API_KEY;
      if (!geminiKey) throw new Error("GEMINI_API_KEY not configured.");

      await jobRef.update({
        status: "processing",
        currentStep: "Loading brand",
        progress: 10,
        startedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const brand = await loadBrandConfig(uid, organizationId);
      const parts = [];
      const logo = await fetchInlineImage(brand.logoUrl, "brand logo").catch(() => null);
      const isMinorEdit = safeString(jobData.editMode).toLowerCase() === "minor";
      const isTablePackage = jobData.serviceType === "table_package_flyer";
      const selectedReferenceUrls = Array.isArray(jobData.selectedReferenceImageUrls) && jobData.selectedReferenceImageUrls.length > 0
        ? uniqueLimitedStrings(jobData.selectedReferenceImageUrls, MAX_INLINE_REFERENCE_IMAGES)
        : selectReferenceImageUrls(
          jobData.referenceImageUrls,
          `${jobId}:${safeString(jobData.eventName)}:${safeString(jobData.creativeDescription || jobData.preferences || jobData.theme)}`,
        );
      let prompt = "";

      async function appendReferenceImageParts() {
        let count = 0;
        for (const url of selectedReferenceUrls) {
          const ref = await fetchInlineImage(url, `reference image ${count + 1}`).catch(() => null);
          if (!ref) continue;
          count += 1;
          parts.push({
            text: `REFERENCE IMAGE ${count}. This is one sample from the organizer's wider media library. Use it for event mood, people, venue, or styling cues without copying visible text.`,
          });
          parts.push({ inlineData: ref.inlineData });
        }
        if (count > 0) {
          parts.push({
            text: `Use the ${count} supplied reference images as a diverse rotating sample. Avoid overusing one repeated subject or the same small set of photos when the brief allows variety.`,
          });
        }
      }

      if (isMinorEdit) {
        await jobRef.update({ currentStep: "Reading source flyer", progress: 20 });
        const source = await fetchInlineImage(jobData.sourceFlyerUrl || jobData.uploadedFlyerUrl, "source flyer");
        if (!source) throw new Error("Minor edit requires a source flyer image.");
        parts.push({ text: "SOURCE FLYER IMAGE. Use this exact flyer as the base." });
        parts.push({ inlineData: source.inlineData });
        prompt = buildMinorEditPrompt(jobData);
      } else if (isTablePackage) {
        const uploaded = await fetchInlineImage(jobData.uploadedFlyerUrl, "uploaded flyer").catch(() => null);
        if (uploaded) {
          parts.push({ text: "BASE FLYER IMAGE. Preserve this image as the visual base and add table-package content on top." });
          parts.push({ inlineData: uploaded.inlineData });
        }
        if (logo) {
          parts.push({ text: "BRAND LOGO IMAGE. Use this logo faithfully; do not invent alternate marks or unrelated venue branding." });
          parts.push({ inlineData: logo.inlineData });
        }
        await appendReferenceImageParts();
        prompt = buildTablePackagePrompt(jobData, brand);
      } else {
        const bg = await fetchInlineImage(jobData.customBgUrl || jobData.uploadedFlyerUrl, "custom background").catch(() => null);
        if (bg) {
          parts.push({ text: "OPTIONAL STYLE/BACKGROUND REFERENCE. Use its palette and atmosphere without copying unwanted text." });
          parts.push({ inlineData: bg.inlineData });
        }
        if (logo) {
          parts.push({ text: "BRAND LOGO IMAGE. Use this logo faithfully; do not invent alternate marks or unrelated venue branding." });
          parts.push({ inlineData: logo.inlineData });
        }
        await appendReferenceImageParts();
        prompt = buildEventFlyerPrompt(jobData, brand);
      }

      parts.push({ text: prompt });

      await jobRef.update({ currentStep: "Rendering with Gemini", progress: 45, prompt });
      const result = await generateWithFallback({ apiKey: geminiKey, parts });

      await jobRef.update({ currentStep: "Saving flyer", progress: 85 });
      const kind = isTablePackage ? "table_package_flyer" : isMinorEdit ? "minor_edit" : "event_flyer";
      const uploaded = await uploadGeneratedImage({
        uid,
        kind,
        eventName: jobData.eventName || kind,
        buffer: result.buffer,
        mimeType: result.mimeType,
      });

      const rootSessionId = safeString(jobData.sourceSessionId) || null;
      const sessionRef = await db.collection("flyer_sessions").add({
        uid,
        organizationId,
        serviceType: jobData.serviceType,
        editMode: safeString(jobData.editMode) || null,
        sourceSessionId: rootSessionId,
        eventName: safeString(jobData.eventName),
        prompt,
        downloadUrl: uploaded.imageUrl,
        imageUrl: uploaded.imageUrl,
        storagePath: uploaded.storagePath,
        priceChargedGhs: Number(jobData.priceChargedGhs || 0),
        quotaCovered: jobData.quotaCovered === true,
        minorEditsRemaining: isMinorEdit ? null : INCLUDED_MINOR_EDITS,
        redesignsRemaining: isMinorEdit ? null : INCLUDED_REDESIGNS,
        tiers: Array.isArray(jobData.tiers) ? jobData.tiers : [],
        brandSnapshot: brand,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      await jobRef.update({
        status: "complete",
        currentStep: "Done",
        progress: 100,
        imageUrl: uploaded.imageUrl,
        sessionId: sessionRef.id,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await notifyCreativeUser(uid, {
        title: "Flyer ready",
        body: `${safeString(jobData.eventName, "Your flyer")} is ready to download.`,
        route: "/creative",
        kind: "creative_flyer_ready",
        jobId,
        serviceType: safeString(jobData.serviceType, "event_flyer"),
      });
    } catch (error) {
      console.error("[creative_services] flyer job failed", jobId, error);
      const amount = Number(jobData.priceChargedGhs || 0);
      const editMode = safeString(jobData.editMode).toLowerCase();
      const quotaField = editMode === "minor"
        ? "minorEditsRemaining"
        : editMode === "redesign"
          ? "redesignsRemaining"
          : "";
      if (jobData.quotaCovered === true && quotaField) {
        await restoreIncludedQuota({
          uid,
          sourceSessionId: safeString(jobData.sourceSessionId),
          quotaField,
        }).catch((quotaError) => {
          console.error("[creative_services] quota restore failed", jobId, quotaError);
        });
      }
      if (amount > 0) {
        await refundWalletCharge({
          organizationId,
          uid,
          jobId,
          amount,
          serviceType: safeString(jobData.serviceType),
          reason: error.message,
        }).catch((refundError) => {
          console.error("[creative_services] refund failed", jobId, refundError);
        });
      }
      await jobRef.update({
        status: "error",
        error: safeString(error.message, "Generation failed."),
        refundedGhs: amount > 0 ? amount : 0,
        quotaRestored: jobData.quotaCovered === true && Boolean(quotaField),
        currentStep: "Failed",
        updatedAt: FieldValue.serverTimestamp(),
      }).catch(() => {});
      await notifyCreativeUser(uid, {
        title: "Flyer generation failed",
        body: amount > 0
          ? "We could not generate your flyer, so your wallet was refunded."
          : "We could not generate your flyer. Try adjusting the brief and generate again.",
        route: "/creative",
        kind: "creative_flyer_failed",
        jobId,
        serviceType: safeString(jobData.serviceType, "event_flyer"),
      });
      await notifyCreativeAdmins({
        title: "Creative job failed",
        body: `Flyer job ${jobId} failed for ${safeString(jobData.eventName, "an event")}.`,
        kind: "superadmin_creative_job_failed",
        jobId,
      });
    }
  },
);

exports.processCreativeFlyerVideoJob = onDocumentCreated(
  {
    document: "flyer_video_jobs/{jobId}",
    region: REGION,
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const jobData = snap.data() || {};
    if (jobData.status !== "pending" || jobData.serviceType !== "flyer_video") return;
    const jobRef = snap.ref;
    const jobId = event.params.jobId;
    const uid = safeString(jobData.uid);
    const organizationId = safeString(jobData.organizationId);
    const sourceSessionId = safeString(jobData.sourceSessionId);

    try {
      const geminiKey = safeString(process.env.GEMINI_API_KEY);
      if (!geminiKey) throw new Error("GEMINI_API_KEY not configured.");

      await jobRef.update({
        status: "processing",
        currentStep: "Preparing flyer for Veo 3.1",
        progress: 15,
        startedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const flyerImage = await fetchImageForVeo(safeString(jobData.flyerUrl));
      const motionPrompt = buildVeoFlyerMotionPrompt(jobData);
      await jobRef.update({
        currentStep: "Starting Veo 3.1 image-to-video",
        progress: 30,
        engine: "gplus_veo_3_1",
        veoModel: VEO_MODEL,
        motionPrompt,
        sourceImageMime: flyerImage.imageMime,
        sourceImageBytes: flyerImage.byteLength,
        updatedAt: FieldValue.serverTimestamp(),
      });

      let operationName = await veoSubmit({
        prompt: motionPrompt,
        imageBase64: flyerImage.imageBase64,
        imageMime: flyerImage.imageMime,
        geminiKey,
        model: VEO_MODEL,
      });
      await jobRef.update({
        currentStep: "Rendering with Veo 3.1",
        progress: 50,
        veoOperationName: operationName,
        updatedAt: FieldValue.serverTimestamp(),
      });

      let videoUri;
      let finalMotionPrompt = motionPrompt;
      try {
        videoUri = await veoPoll(operationName, geminiKey);
      } catch (firstError) {
        if (firstError.message !== "rai_blocked") throw firstError;
        const sanitizedPrompt = sanitizePromptForRai(motionPrompt);
        finalMotionPrompt = sanitizedPrompt;
        await jobRef.update({
          currentStep: "Retrying Veo 3.1 with safer editorial motion",
          progress: 60,
          motionPrompt: sanitizedPrompt,
          retryReason: "rai_blocked",
          updatedAt: FieldValue.serverTimestamp(),
        });
        operationName = await veoSubmit({
          prompt: sanitizedPrompt,
          imageBase64: flyerImage.imageBase64,
          imageMime: flyerImage.imageMime,
          geminiKey,
          model: VEO_MODEL,
        });
        await jobRef.update({
          veoOperationName: operationName,
          updatedAt: FieldValue.serverTimestamp(),
        });
        try {
          videoUri = await veoPoll(operationName, geminiKey);
        } catch (secondError) {
          if (secondError.message !== "rai_blocked") throw secondError;
          await jobRef.update({
            currentStep: "Retrying on Veo 3.1 Fast",
            progress: 70,
            veoModel: VEO_RETRY_MODEL,
            updatedAt: FieldValue.serverTimestamp(),
          });
          operationName = await veoSubmit({
            prompt: sanitizedPrompt,
            imageBase64: flyerImage.imageBase64,
            imageMime: flyerImage.imageMime,
            geminiKey,
            model: VEO_RETRY_MODEL,
          });
          await jobRef.update({
            veoOperationName: operationName,
            updatedAt: FieldValue.serverTimestamp(),
          });
          videoUri = await veoPoll(operationName, geminiKey);
        }
      }

      await jobRef.update({
        currentStep: "Uploading video",
        progress: 88,
        veoVideoUri: videoUri,
        updatedAt: FieldValue.serverTimestamp(),
      });
      const videoBuffer = await downloadVeoVideo(videoUri, geminiKey);
      const uploaded = await uploadGeneratedVideo({
        uid,
        kind: "flyer_video",
        eventName: safeString(jobData.eventName, "flyer-video"),
        buffer: videoBuffer,
      });

      await jobRef.update({
        status: "complete",
        currentStep: "Done",
        progress: 100,
        videoUrl: uploaded.videoUrl,
        videoStoragePath: uploaded.storagePath,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (sourceSessionId) {
        await db.collection("flyer_sessions").doc(sourceSessionId).set({
          latestVideoJobId: jobId,
          latestVideoUrl: uploaded.videoUrl,
          latestVideoMotionPrompt: finalMotionPrompt,
          latestVideoEngine: "gplus_veo_3_1",
          latestVideoDurationSeconds: FLYER_VIDEO_DURATION_SECONDS,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      await notifyCreativeUser(uid, {
        title: "Flyer video ready",
        body: `${safeString(jobData.eventName, "Your animated flyer")} is ready to download.`,
        route: "/creative",
        kind: "creative_flyer_video_ready",
        jobId,
        serviceType: "flyer_video",
      });
    } catch (error) {
      console.error("[creative_services] flyer video job failed", jobId, error);
      const amount = Number(jobData.priceChargedGhs || 0);
      if (amount > 0) {
        await refundWalletCharge({
          organizationId,
          uid,
          jobId,
          amount,
          serviceType: "flyer_video",
          reason: error.message,
        }).catch((refundError) => {
          console.error("[creative_services] flyer video refund failed", jobId, refundError);
        });
      }
      const cleanError = error.message === "rai_blocked"
        ? "Animation blocked by Google content policy. Try a simpler flyer image or less intense motion."
        : safeString(error.message, "Video generation failed.");
      await jobRef.update({
        status: "error",
        error: cleanError,
        refundedGhs: amount > 0 ? amount : 0,
        currentStep: "Failed",
        updatedAt: FieldValue.serverTimestamp(),
      }).catch(() => {});
      await notifyCreativeUser(uid, {
        title: "Flyer video failed",
        body: amount > 0
          ? "We could not animate your flyer, so your wallet was refunded."
          : "We could not animate your flyer. Try another flyer or simpler motion.",
        route: "/creative",
        kind: "creative_flyer_video_failed",
        jobId,
        serviceType: "flyer_video",
      });
      await notifyCreativeAdmins({
        title: "Creative video job failed",
        body: `Veo 3.1 flyer video job ${jobId} failed for ${safeString(jobData.eventName, "an event")}.`,
        kind: "superadmin_creative_video_job_failed",
        jobId,
      });
    }
  },
);
