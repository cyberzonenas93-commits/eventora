#!/usr/bin/env node
"use strict";

// Pulls the real G+ Media Desk gallery from the G+ app project and uses it to
// populate Vennuzo's G+ place profile. Source of truth in G+:
//   Firestore: moments_gallery
//   URLs: imageUrl || mediaUrl || thumbnailUrl || videoUrl
//
// Usage:
//   WRITE=1 node scripts/sync_gplus_moments_gallery.js
// Optional:
//   GPLUS_SERVICE_ACCOUNT_PATH=/path/to/service-account.json
//   VENNUZO_PROJECT_ID=eventora-10063
//   SOURCE_LIMIT=200
//   MAX_GALLERY=40

const os = require("os");
const path = require("path");
const admin = require("../functions/node_modules/firebase-admin");

const DEFAULT_GPLUS_SERVICE_ACCOUNT = path.join(
  os.homedir(),
  "Desktop",
  "gplus-app",
  "mac-worker",
  "service-account.json",
);

const GPLUS_SERVICE_ACCOUNT_PATH =
  process.env.GPLUS_SERVICE_ACCOUNT_PATH || DEFAULT_GPLUS_SERVICE_ACCOUNT;
const VENNUZO_PROJECT_ID = process.env.VENNUZO_PROJECT_ID || "eventora-10063";
const SOURCE_LIMIT = positiveInt(process.env.SOURCE_LIMIT, 200);
const MAX_GALLERY = positiveInt(process.env.MAX_GALLERY, 40);
const WRITE = process.env.WRITE === "1" || process.env.WRITE === "true";

const GPLUS_PLACE_ID = "gplus_nightclub";
const GPLUS_PROFILE_ID = "gplus";
const SOURCE_COLLECTION = "moments_gallery";
const MIRROR_COLLECTION = "gplus_media_gallery";

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || ""), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function firstString(source, keys) {
  for (const key of keys) {
    const value = safeString(source[key]);
    if (value) return value;
  }
  return "";
}

function urlForMoment(moment) {
  const type = safeString(moment.type || moment.mediaType).toLowerCase();
  const thumbnailUrl = firstString(moment, ["thumbnailUrl", "thumbUrl"]);
  const photoUrl = firstString(moment, [
    "imageUrl",
    "processedPhotoUrl",
    "photoUrl",
    "mediaUrl",
    "downloadUrl",
    "url",
  ]);

  if (type === "video") return thumbnailUrl;
  return photoUrl || thumbnailUrl;
}

function videoUrlForMoment(moment) {
  return firstString(moment, ["videoUrl", "processedVideoUrl"]);
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.getTime() : 0;
}

function mirrorIdForMoment(momentId) {
  return `moments_${String(momentId).replace(/[^A-Za-z0-9_-]+/g, "_").slice(0, 120)}`;
}

async function commitChunks(db, writes) {
  for (let index = 0; index < writes.length; index += 450) {
    const batch = db.batch();
    writes.slice(index, index + 450).forEach((write) => write(batch));
    await batch.commit();
  }
}

async function main() {
  const sourceServiceAccount = require(path.resolve(GPLUS_SERVICE_ACCOUNT_PATH));
  const sourceApp = admin.initializeApp(
    {
      credential: admin.credential.cert(sourceServiceAccount),
      projectId: sourceServiceAccount.project_id || "gplus-admin",
      storageBucket: "gplus-admin.firebasestorage.app",
    },
    "gplus-source",
  );
  const destinationApp = admin.initializeApp(
    {
      credential: admin.credential.applicationDefault(),
      projectId: VENNUZO_PROJECT_ID,
    },
    "vennuzo-destination",
  );

  const sourceDb = sourceApp.firestore();
  const destinationDb = destinationApp.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const snap = await sourceDb
    .collection(SOURCE_COLLECTION)
    .orderBy("uploadedAt", "desc")
    .limit(SOURCE_LIMIT)
    .get();

  const seenUrls = new Set();
  const media = snap.docs
    .map((doc) => {
      const data = doc.data() || {};
      const imageUrl = urlForMoment(data);
      const videoUrl = videoUrlForMoment(data);
      return {
        id: doc.id,
        data,
        imageUrl,
        videoUrl,
        uploadedAt: data.uploadedAt || data.createdAt || null,
        sortAt: timestampMillis(data.uploadedAt || data.createdAt),
      };
    })
    .filter((item) => item.data.isActive !== false)
    .filter((item) => item.imageUrl)
    .filter((item) => {
      if (seenUrls.has(item.imageUrl)) return false;
      seenUrls.add(item.imageUrl);
      return true;
    })
    .sort((a, b) => b.sortAt - a.sortAt)
    .slice(0, MAX_GALLERY);

  const galleryUrls = media.map((item) => item.imageUrl);
  if (!galleryUrls.length) {
    throw new Error(`No active media URLs found in ${SOURCE_COLLECTION}.`);
  }

  const summary = {
    write: WRITE,
    sourceProject: sourceServiceAccount.project_id || "gplus-admin",
    destinationProject: VENNUZO_PROJECT_ID,
    sourceCollection: SOURCE_COLLECTION,
    scanned: snap.size,
    selected: media.length,
    coverUrl: galleryUrls[0],
    firstIds: media.slice(0, 5).map((item) => item.id),
  };

  if (!WRITE) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const writes = [];
  media.forEach((item, index) => {
    const source = item.data;
    writes.push((batch) => {
      batch.set(
        destinationDb.collection(MIRROR_COLLECTION).doc(mirrorIdForMoment(item.id)),
        {
          source: "gplus_moments_gallery",
          sourceProject: sourceServiceAccount.project_id || "gplus-admin",
          sourceCollection: SOURCE_COLLECTION,
          sourceMediaId: item.id,
          placeId: GPLUS_PLACE_ID,
          creatorId: GPLUS_PROFILE_ID,
          imageUrl: item.imageUrl,
          thumbnailUrl: safeString(source.thumbnailUrl || source.thumbUrl) || null,
          videoUrl: item.videoUrl || null,
          mediaUrl: item.imageUrl,
          type: safeString(source.type || source.mediaType, "photo"),
          title: safeString(source.title || source.batchTag || source.driveFileName),
          caption: safeString(source.caption || source.description),
          tags: Array.isArray(source.tags) ? source.tags.map(safeString).filter(Boolean) : [],
          isActive: true,
          primary: index === 0,
          uploadedAt: item.uploadedAt,
          sourceUpdatedAt: source.updatedAt || null,
          syncedAt: now,
          updatedAt: now,
        },
        { merge: true },
      );
    });
  });

  writes.push((batch) => {
    batch.set(
      destinationDb.collection("places").doc(GPLUS_PLACE_ID),
      {
        coverUrl: galleryUrls[0],
        galleryUrls,
        mediaDeskGallerySource: "gplus/moments_gallery",
        mediaDeskGallerySyncedAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  writes.push((batch) => {
    batch.set(
      destinationDb.collection("creator_profiles").doc(GPLUS_PROFILE_ID),
      {
        coverUrl: galleryUrls[0],
        mediaDeskGallerySyncedAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  writes.push((batch) => {
    batch.set(
      destinationDb.collection("gplus_sync_status").doc("media_desk_moments_gallery"),
      {
        type: "media_gallery",
        source: "gplus_moments_gallery",
        sourceProject: sourceServiceAccount.project_id || "gplus-admin",
        sourceCollection: SOURCE_COLLECTION,
        destinationPlaceId: GPLUS_PLACE_ID,
        status: "synced",
        selectedCount: media.length,
        scannedCount: snap.size,
        coverUrl: galleryUrls[0],
        galleryUrls,
        syncedAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  await commitChunks(destinationDb, writes);
  console.log(JSON.stringify({ ...summary, status: "synced" }, null, 2));
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
