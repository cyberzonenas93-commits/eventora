"use strict";

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
const VENNUZO_SCHEME = "vennuzoapp";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function projectId() {
  return safeString(process.env.GCLOUD_PROJECT || admin.app().options.projectId);
}

function functionsBaseUrl() {
  const pid = projectId();
  if (!pid) {
    throw new Error("GCLOUD_PROJECT is not available for Vennuzo share links.");
  }
  return `https://${REGION}-${pid}.cloudfunctions.net`;
}

async function getShareSettings() {
  try {
    const snap = await db.collection("app_config").doc("share").get();
    const data = snap.exists ? snap.data() || {} : {};
    return {
      iosDownloadUrl: safeString(
        data.iosDownloadUrl,
        "https://vennuzo.app/download/ios",
      ),
      androidDownloadUrl: safeString(
        data.androidDownloadUrl,
        "https://play.google.com/store/apps/details?id=com.vennuzo.app",
      ),
      webBaseUrl: safeString(data.webBaseUrl, "https://vennuzo.app"),
      defaultImageUrl: safeString(
        data.defaultImageUrl,
        "https://vennuzo.app/favicon.png",
      ),
      shareFunctionUrl: safeString(data.shareFunctionUrl),
    };
  } catch (error) {
    return {
      iosDownloadUrl: "https://vennuzo.app/download/ios",
      androidDownloadUrl:
        "https://play.google.com/store/apps/details?id=com.vennuzo.app",
      webBaseUrl: "https://vennuzo.app",
      defaultImageUrl: "https://vennuzo.app/favicon.png",
      shareFunctionUrl: "",
    };
  }
}

async function buildShareLinkUrl(shareId) {
  const settings = await getShareSettings();
  const base = safeString(settings.shareFunctionUrl, `${functionsBaseUrl()}/shareLink`);
  return `${base}?shareId=${encodeURIComponent(shareId)}`;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizeEventImageUrl(data = {}) {
  return safeString(
    data.imageUrl || data.flyerUrl || data.coverImageUrl || data.posterUrl,
  );
}

function minimumTicketPrice(ticketing) {
  if (!ticketing || !Array.isArray(ticketing.tiers)) {
    return null;
  }
  const prices = ticketing.tiers
    .map((tier) => Number(tier && tier.price))
    .filter((price) => Number.isFinite(price) && price > 0);
  if (prices.length === 0) {
    return null;
  }
  return Math.min(...prices);
}

function formatMoney(value, currency = "GHS") {
  const amount = Number(value || 0);
  return `${currency} ${amount.toFixed(2)}`;
}

function formatEventDate(value, timezone = "Africa/Accra") {
  const date = value && typeof value.toDate === "function" ? value.toDate() : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "Date to be announced";
  }
  return date.toLocaleString("en-GH", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone,
  });
}

function slugify(value) {
  return safeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-|-$/g, "");
}

function buildEventDeepLink(eventId) {
  return `${VENNUZO_SCHEME}://share/event?eventId=${encodeURIComponent(eventId)}`;
}

async function getEventSnapshot(eventId) {
  const safeEventId = safeString(eventId);
  if (!safeEventId) {
    return null;
  }
  const snap = await db.collection("events").doc(safeEventId).get();
  if (!snap.exists) {
    return null;
  }
  return {
    id: snap.id,
    data: snap.data() || {},
  };
}

function eventAllowsSharing(eventData) {
  const distribution = eventData && typeof eventData.distribution === "object"
    ? eventData.distribution
    : {};
  return distribution.allowSharing !== false;
}

function eventIsPublic(eventData) {
  return safeString(eventData && eventData.visibility, "public") !== "private";
}

async function ensureEventShareLink({
  eventId,
  eventData,
  requesterUid = "",
  allowPrivate = false,
}) {
  const safeEventId = safeString(eventId);
  if (!safeEventId) {
    throw new HttpsError("invalid-argument", "An eventId is required.");
  }

  const existingRef = db.collection("share_links").doc(safeEventId);
  const existingSnap = await existingRef.get();
  if (existingSnap.exists) {
    const existingData = existingSnap.data() || {};
    const status = safeString(existingData.status, "active");
    const existingTargetId = safeString(existingData.targetId, safeEventId);
    if (existingTargetId === safeEventId && status === "active") {
      return {
        shareId: existingSnap.id,
        url: await buildShareLinkUrl(existingSnap.id),
        data: existingData,
      };
    }
  }

  const snapshot = eventData ? { id: safeEventId, data: eventData } : await getEventSnapshot(safeEventId);
  if (!snapshot) {
    throw new HttpsError("not-found", "That event could not be found.");
  }

  if (!eventAllowsSharing(snapshot.data)) {
    throw new HttpsError("failed-precondition", "Sharing is disabled for this event.");
  }

  if (!allowPrivate && !eventIsPublic(snapshot.data)) {
    const managerId = safeString(snapshot.data.createdBy);
    if (!requesterUid || requesterUid !== managerId) {
      throw new HttpsError("permission-denied", "Private events cannot be shared publicly.");
    }
  }

  const ticketing = snapshot.data.ticketing && typeof snapshot.data.ticketing === "object"
    ? snapshot.data.ticketing
    : {};
  const payload = {
    type: "event",
    targetId: safeEventId,
    eventId: safeEventId,
    organizationId: safeString(snapshot.data.organizationId),
    title: safeString(snapshot.data.title, "Upcoming Event"),
    description: safeString(snapshot.data.description),
    imageUrl: normalizeEventImageUrl(snapshot.data),
    slug: slugify(snapshot.data.title),
    requireTicket: ticketing.requireTicket === true,
    status: "active",
    createdBy: safeString(snapshot.data.createdBy, requesterUid),
    createdAt: existingSnap.exists && existingSnap.data()
      ? existingSnap.data().createdAt || FieldValue.serverTimestamp()
      : FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await existingRef.set(payload, { merge: true });
  return {
    shareId: existingRef.id,
    url: await buildShareLinkUrl(existingRef.id),
    data: payload,
  };
}

exports.createShareLink = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const type = safeString(request.data && request.data.type, "event");
    if (type !== "event") {
      throw new HttpsError(
        "unimplemented",
        "Vennuzo currently supports event share links only.",
      );
    }

    const targetId = safeString(request.data && request.data.targetId);
    const shareLink = await ensureEventShareLink({
      eventId: targetId,
      requesterUid: safeString(request.auth && request.auth.uid),
    });

    return {
      shareId: shareLink.shareId,
      url: shareLink.url,
    };
  },
);

exports.shareLink = onRequest(
  {
    region: REGION,
    cors: true,
  },
  async (req, res) => {
    try {
      const shareId = safeString(req.query && req.query.shareId);
      if (!shareId) {
        res.status(400).send("shareId is required");
        return;
      }

      const shareSnap = await db.collection("share_links").doc(shareId).get();
      if (!shareSnap.exists) {
        res.status(404).send("This share link is no longer available.");
        return;
      }

      const shareData = shareSnap.data() || {};
      if (safeString(shareData.status, "active") !== "active") {
        res.status(404).send("This share link is no longer active.");
        return;
      }

      const type = safeString(shareData.type, "event");
      if (type !== "event") {
        res.status(400).send("Unsupported share link type.");
        return;
      }

      const eventId = safeString(shareData.targetId || shareData.eventId);
      const eventSnapshot = await getEventSnapshot(eventId);
      const eventData = eventSnapshot ? eventSnapshot.data : {};
      const settings = await getShareSettings();
      const title = safeString(
        shareData.title || eventData.title,
        "Discover Vennuzo events",
      );
      const description = safeString(
        shareData.description || eventData.description,
        "Open this link in Vennuzo to view the event and ticket options.",
      );
      const imageUrl = safeString(
        shareData.imageUrl || normalizeEventImageUrl(eventData),
        settings.defaultImageUrl,
      );
      const venue = safeString(eventData.venue);
      const city = safeString(eventData.city);
      const timezone = safeString(eventData.timezone, "Africa/Accra");
      const eventDate = formatEventDate(eventData.startAt, timezone);
      const ticketing = eventData.ticketing && typeof eventData.ticketing === "object"
        ? eventData.ticketing
        : {};
      const entryPrice = minimumTicketPrice(ticketing);
      const priceLabel = entryPrice == null
        ? "Free entry"
        : `From ${formatMoney(entryPrice, safeString(ticketing.currency, "GHS"))}`;
      const shareUrl = await buildShareLinkUrl(shareId);
      const deepLink = buildEventDeepLink(eventId);
      const venueLabel = [venue, city].filter(Boolean).join(", ");
      const safeTitle = escapeHtml(title);
      const safeDescription = escapeHtml(description);
      const safeImageUrl = escapeHtml(imageUrl);
      const safeShareUrl = escapeHtml(shareUrl);
      const safeDeepLink = escapeHtml(deepLink);
      const safeEventDate = escapeHtml(eventDate);
      const safeVenue = escapeHtml(venueLabel || "Venue to be announced");
      const safePriceLabel = escapeHtml(priceLabel);
      const safeIosUrl = escapeHtml(settings.iosDownloadUrl);
      const safeAndroidUrl = escapeHtml(settings.androidDownloadUrl);

      const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${safeTitle}</title>
  <meta property="og:title" content="${safeTitle}" />
  <meta property="og:description" content="${safeDescription}" />
  <meta property="og:image" content="${safeImageUrl}" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${safeShareUrl}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${safeTitle}" />
  <meta name="twitter:description" content="${safeDescription}" />
  <meta name="twitter:image" content="${safeImageUrl}" />
  <style>
    :root {
      color-scheme: dark;
      --ink: #121e31;
      --teal: #0e8b8c;
      --coral: #ff6a3d;
      --gold: #ffc857;
      --paper: rgba(255,255,255,0.14);
      --line: rgba(255,255,255,0.16);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: white;
      background:
        radial-gradient(circle at top left, rgba(255,200,87,0.16), transparent 28%),
        radial-gradient(circle at bottom right, rgba(255,106,61,0.28), transparent 32%),
        linear-gradient(160deg, #0f1a2a 0%, #0f7f86 52%, #ff6a3d 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      width: min(100%, 560px);
      border-radius: 32px;
      padding: 28px;
      background: rgba(10, 14, 24, 0.56);
      border: 1px solid var(--line);
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.28);
      backdrop-filter: blur(12px);
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 14px;
      border-radius: 999px;
      background: var(--paper);
      font-size: 14px;
      font-weight: 700;
    }
    h1 {
      margin: 20px 0 12px;
      font-size: clamp(2rem, 5vw, 3rem);
      line-height: 0.96;
    }
    p {
      margin: 0;
      color: rgba(255,255,255,0.88);
      line-height: 1.6;
      font-size: 16px;
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin: 20px 0 24px;
    }
    .meta span {
      display: inline-flex;
      align-items: center;
      padding: 10px 14px;
      border-radius: 18px;
      background: rgba(255,255,255,0.12);
      font-weight: 700;
      font-size: 14px;
    }
    .art {
      width: 100%;
      border-radius: 24px;
      aspect-ratio: 16 / 10;
      object-fit: cover;
      margin-bottom: 18px;
      background: rgba(255,255,255,0.08);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 24px;
    }
    a.button {
      flex: 1;
      min-width: 180px;
      text-decoration: none;
      color: white;
      text-align: center;
      padding: 15px 18px;
      border-radius: 18px;
      border: 1px solid var(--line);
      font-weight: 700;
    }
    a.button.primary {
      background: white;
      color: var(--ink);
      border: none;
    }
    .hint {
      margin-top: 16px;
      font-size: 13px;
      color: rgba(255,255,255,0.72);
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Vennuzo share link</div>
    <img class="art" src="${safeImageUrl}" alt="${safeTitle}" />
    <h1>${safeTitle}</h1>
    <p>${safeDescription}</p>
    <div class="meta">
      <span>${safeEventDate}</span>
      <span>${safeVenue}</span>
      <span>${safePriceLabel}</span>
    </div>
    <div class="actions">
      <a class="button primary" href="${safeDeepLink}" onclick="return openApp(event)">Open in Vennuzo</a>
      <a class="button" href="${safeIosUrl}" target="_blank" rel="noopener">Get the iPhone app</a>
      <a class="button" href="${safeAndroidUrl}" target="_blank" rel="noopener">Get the Android app</a>
    </div>
    <p class="hint">If the app is installed, this link opens the event directly. Otherwise, download Vennuzo and reopen the same link.</p>
  </div>
  <script>
    const deepLink = "${safeDeepLink}";
    const iosStore = "${safeIosUrl}";
    const androidStore = "${safeAndroidUrl}";

    function isIOS() {
      return /iPad|iPhone|iPod/.test(navigator.userAgent);
    }

    function openApp(event) {
      if (event) event.preventDefault();
      const fallback = isIOS() ? iosStore : androidStore;
      const start = Date.now();
      window.location.href = deepLink;
      setTimeout(function () {
        if (Date.now() - start < 1600 && fallback) {
          window.location.href = fallback;
        }
      }, 1200);
      return false;
    }
  </script>
</body>
</html>`;

      res.status(200).send(html);
    } catch (error) {
      console.error("shareLink error:", error);
      res.status(500).send("Unable to build share link.");
    }
  },
);

exports.ensureEventShareLink = ensureEventShareLink;
exports.buildShareLinkUrl = buildShareLinkUrl;
