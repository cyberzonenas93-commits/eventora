#!/usr/bin/env node
"use strict";

// Pulls the public G+ menu and upcoming event source data from the G+ app
// project into Vennuzo. Source of truth in G+:
//   menu_items       -> Vennuzo place_menu_items
//   tablePackages    -> Vennuzo place_menu_items, Table Packages section
//   events           -> Vennuzo gplus_events mirror + linked placeId on events
//
// Usage:
//   WRITE=1 node scripts/sync_gplus_menu_and_events.js

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
const WRITE = process.env.WRITE === "1" || process.env.WRITE === "true";

const PLACE_ID = "gplus_nightclub";
const PLACE_NAME = "G+Nightclub";
const GPLUS_ORGANIZATION_ID = "org_gplus";
const GPLUS_CREATOR_ID = "gplus";
const GPLUS_ADDRESS = "UPSA Road, Madina, Accra, Ghana";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function safeId(value, fallback = "item") {
  return safeString(value, fallback)
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 100) || fallback;
}

function price(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.getTime() : 0;
}

function menuCategory(item) {
  return safeString(
    item.categoryName || item.category || item.cat || item.type || item.group || item.section,
    "Uncategorized",
  );
}

function isPackageCategory(category) {
  const lower = safeString(category).toLowerCase();
  return lower.includes("package") ||
    lower.includes("table booking") ||
    lower.includes("table package");
}

function sortCategories(categories) {
  return [...categories].sort((a, b) => {
    const aPkg = isPackageCategory(a);
    const bPkg = isPackageCategory(b);
    if (aPkg !== bPkg) return aPkg ? 1 : -1;
    return a.localeCompare(b);
  });
}

function imageUrl(item) {
  const raw = safeString(
    item.image || item.imageUrl || item.imageURL || item.img || item.photo || item.photoUrl || item.url,
  );
  return raw.startsWith("http://") || raw.startsWith("https://") ? raw : "";
}

function isAvailableMenuItem(item) {
  return item.available === true || item.available === "true" || item.available === 1;
}

function isEventUpcoming(event, nowMs) {
  const startAt = timestampMillis(event.startAt || event.date || event.eventDate || event.startsAt || event.startTime);
  const endAt = timestampMillis(event.endAt || event.endDate || event.endsAt) || startAt;
  const status = safeString(event.status || event.state).toLowerCase();
  return endAt >= nowMs && !["cancelled", "canceled", "draft"].includes(status);
}

function normalizeSourceEvent(event) {
  return {
    ...event,
    organizationId: safeString(event.organizationId, GPLUS_ORGANIZATION_ID),
    createdBy: safeString(event.createdBy || event.organizerId, GPLUS_CREATOR_ID),
    venue: safeString(event.venue || event.location, "G+"),
    city: safeString(event.city || event.locationCity, "Accra"),
    addressText: safeString(event.addressText || event.address, GPLUS_ADDRESS),
    placeId: safeString(event.placeId || event.venueId || event.locationId, PLACE_ID),
    visibility: safeString(event.visibility, "public"),
    status: safeString(event.status || event.state, "published"),
    source: "gplus",
    sourceEventId: safeString(event.sourceEventId || event.gplusEventId || event.id),
  };
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
    "gplus-source-menu-events",
  );
  const destinationApp = admin.initializeApp(
    {
      credential: admin.credential.applicationDefault(),
      projectId: VENNUZO_PROJECT_ID,
    },
    "vennuzo-destination-menu-events",
  );

  const sourceDb = sourceApp.firestore();
  const destinationDb = destinationApp.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const nowMs = Date.now();

  const [menuSnap, tableSnap, eventSnap, existingSectionsSnap, existingItemsSnap, existingEventsSnap] =
    await Promise.all([
      sourceDb.collection("menu_items").orderBy("name").get(),
      sourceDb.collection("tablePackages").where("isVisible", "==", true).get(),
      sourceDb.collection("events").get(),
      destinationDb.collection("place_menu_sections").where("placeId", "==", PLACE_ID).get(),
      destinationDb.collection("place_menu_items").where("placeId", "==", PLACE_ID).get(),
      destinationDb.collection("events").where("source", "==", "gplus").get(),
    ]);

  const menuItems = menuSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter(isAvailableMenuItem)
    .sort((a, b) => menuCategory(a).localeCompare(menuCategory(b)) || safeString(a.name).localeCompare(safeString(b.name)));
  const tablePackages = tableSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => price(a.price || a.minSpend) - price(b.price || b.minSpend));
  const sourceEvents = eventSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((event) => isEventUpcoming(event, nowMs))
    .sort((a, b) => timestampMillis(a.startAt || a.date) - timestampMillis(b.startAt || b.date));

  const categories = sortCategories(new Set(menuItems.map(menuCategory)));
  if (tablePackages.length && !categories.includes("Table Packages")) {
    categories.push("Table Packages");
  }
  const sectionByCategory = new Map(
    categories.map((category, index) => [
      category,
      {
        id: `gplus_menu_${safeId(category, "category")}`,
        category,
        sortOrder: index + 1,
      },
    ]),
  );

  const writes = [];

  existingSectionsSnap.docs.forEach((doc) => {
    writes.push((batch) => {
      batch.set(doc.ref, {
        visible: false,
        status: "hidden",
        supersededBy: "gplus_menu_sync",
        updatedAt: now,
      }, { merge: true });
    });
  });

  existingItemsSnap.docs.forEach((doc) => {
    writes.push((batch) => {
      batch.set(doc.ref, {
        status: "hidden",
        supersededBy: "gplus_menu_sync",
        updatedAt: now,
      }, { merge: true });
    });
  });

  categories.forEach((category) => {
    const section = sectionByCategory.get(category);
    writes.push((batch) => {
      batch.set(destinationDb.collection("place_menu_sections").doc(section.id), {
        placeId: PLACE_ID,
        name: category,
        description: category === "Table Packages"
          ? "Live public table packages from G+."
          : `Live ${category} menu from G+.`,
        sortOrder: section.sortOrder,
        visible: true,
        source: "gplus_menu_sync",
        updatedAt: now,
      }, { merge: true });
    });
  });

  menuItems.forEach((item, index) => {
    const category = menuCategory(item);
    const section = sectionByCategory.get(category);
    writes.push((batch) => {
      batch.set(destinationDb.collection("place_menu_items").doc(`gplus_menu_item_${safeId(item.id)}`), {
        placeId: PLACE_ID,
        sectionId: section.id,
        name: safeString(item.name, "Menu item"),
        description: safeString(item.description || item.details || item.size),
        price: price(item.price ?? item.ghs ?? item.cost),
        currency: "GHS",
        imageUrl: imageUrl(item) || null,
        featured: isPackageCategory(category),
        status: "available",
        sortOrder: index + 1,
        options: Array.isArray(item.options) ? item.options.map(safeString).filter(Boolean) : [],
        tags: [category, "gplus", "menu"].filter(Boolean),
        source: "gplus_menu_items",
        sourceItemId: item.id,
        sourceCategory: category,
        updatedAt: now,
      }, { merge: true });
    });
  });

  const tableSection = sectionByCategory.get("Table Packages");
  tablePackages.forEach((table, index) => {
    const tablePrice = price(table.price || table.minSpend);
    const perks = Array.isArray(table.perks) ? table.perks.map(safeString).filter(Boolean) : [];
    writes.push((batch) => {
      batch.set(destinationDb.collection("place_menu_items").doc(`gplus_table_package_${safeId(table.id)}`), {
        placeId: PLACE_ID,
        sectionId: tableSection.id,
        name: `${safeString(table.name || table.title, "Table")} Table Package`,
        description: [
          table.capacity ? `Capacity ${table.capacity}` : "",
          table.minSpend ? `Minimum spend GHS ${Number(table.minSpend).toLocaleString("en-GH")}` : "",
          perks.length ? `Includes ${perks.join(", ")}` : "",
        ].filter(Boolean).join(" · "),
        price: tablePrice,
        currency: "GHS",
        imageUrl: imageUrl(table) || null,
        featured: true,
        status: safeString(table.status).toLowerCase() === "hidden" ? "hidden" : "available",
        sortOrder: index + 1,
        options: perks,
        tags: ["Table Packages", "gplus", "reservation"],
        source: "gplus_tablePackages",
        sourceItemId: table.id,
        minSpend: price(table.minSpend),
        capacity: Number(table.capacity) || null,
        updatedAt: now,
      }, { merge: true });
    });
  });

  sourceEvents.forEach((event) => {
    const normalized = normalizeSourceEvent(event);
    writes.push((batch) => {
      batch.set(destinationDb.collection("gplus_events").doc(event.id), {
        ...normalized,
        syncedFromSourceAt: now,
        updatedAt: normalized.updatedAt || now,
      }, { merge: true });
    });
  });

  existingEventsSnap.docs.forEach((doc) => {
    writes.push((batch) => {
      batch.set(doc.ref, {
        placeId: PLACE_ID,
        addressText: GPLUS_ADDRESS,
        updatedAt: now,
      }, { merge: true });
    });
  });

  writes.push((batch) => {
    batch.set(destinationDb.collection("gplus_sync_status").doc("menu_and_events"), {
      type: "menu_and_events",
      source: "gplus",
      sourceProject: sourceServiceAccount.project_id || "gplus-admin",
      destinationPlaceId: PLACE_ID,
      status: "synced",
      menuItemCount: menuItems.length,
      tablePackageCount: tablePackages.length,
      sectionCount: categories.length,
      upcomingEventCount: sourceEvents.length,
      syncedAt: now,
      updatedAt: now,
    }, { merge: true });
  });

  const summary = {
    write: WRITE,
    sourceProject: sourceServiceAccount.project_id || "gplus-admin",
    destinationProject: VENNUZO_PROJECT_ID,
    menuItemCount: menuItems.length,
    tablePackageCount: tablePackages.length,
    sectionCount: categories.length,
    upcomingEventCount: sourceEvents.length,
    firstMenuItems: menuItems.slice(0, 6).map((item) => item.name),
    firstUpcomingEvents: sourceEvents.slice(0, 6).map((event) => event.title || event.name || event.eventName),
  };

  if (WRITE) {
    await commitChunks(destinationDb, writes);
    summary.status = "synced";
  }

  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
