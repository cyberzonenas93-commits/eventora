"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

try {
  admin.app();
} catch (error) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;

const REGION = "us-central1";

function safeString(value, fallback = "") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

function slugify(value) {
  return safeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-|-$/g, "");
}

async function assertSuperAdmin(uid) {
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Only superadmins can review organizer applications.",
    );
  }

  const adminData = adminSnap.data() || {};
  const role = safeString(adminData.role).toLowerCase();
  if (role !== "superadmin") {
    throw new HttpsError(
      "permission-denied",
      "Only superadmins can review organizer applications.",
    );
  }

  return adminData;
}

exports.reviewOrganizerApplication = onCall(
  { region: REGION },
  async (request) => {
    const callerUid = request.auth && request.auth.uid;
    if (!callerUid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in as a superadmin before reviewing organizer applications.",
      );
    }

    await assertSuperAdmin(callerUid);

    const applicationId = safeString(request.data && request.data.applicationId);
    const decision = safeString(request.data && request.data.decision).toLowerCase();
    const reviewNotes = safeString(request.data && request.data.reviewNotes);

    if (!applicationId) {
      throw new HttpsError(
        "invalid-argument",
        "An organizer application ID is required.",
      );
    }

    if (!["under_review", "approved", "rejected"].includes(decision)) {
      throw new HttpsError(
        "invalid-argument",
        "Decision must be under_review, approved, or rejected.",
      );
    }

    const applicationRef = db.collection("organizer_applications").doc(applicationId);
    const applicationSnap = await applicationRef.get();
    if (!applicationSnap.exists) {
      throw new HttpsError("not-found", "Organizer application not found.");
    }

    const application = applicationSnap.data() || {};
    const userId = safeString(
      application.userId || application.uid || applicationId,
    );
    if (!userId) {
      throw new HttpsError(
        "failed-precondition",
        "Application is missing a userId.",
      );
    }

    const organizerName = safeString(
      application.organizerName,
      safeString(application.organization, "Eventora Organizer"),
    );
    const contactPerson = safeString(
      application.contactPerson,
      safeString(application.firstName || application.displayName),
    );
    const userRef = db.collection("users").doc(userId);
    const organizationId = safeString(
      application.organizationId,
      `org_${userId}`,
    );
    const slug = safeString(
      application.slug,
      slugify(organizerName) || organizationId,
    );
    const organizationRef = db.collection("organizations").doc(organizationId);
    const membershipRef = db
      .collection("organization_members")
      .doc(`${organizationId}_${userId}`);

    await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      const userData = userSnap.exists ? userSnap.data() || {} : {};

      transaction.set(
        applicationRef,
        {
          status: decision,
          reviewNotes,
          reviewedAt: FieldValue.serverTimestamp(),
          reviewedBy: callerUid,
          organizationId:
            decision === "approved" ? organizationId : application.organizationId || null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      if (decision === "under_review") {
        transaction.set(
          userRef,
          {
            displayName: safeString(userData.displayName, contactPerson),
            email: safeString(userData.email, application.email),
            organizerApplicationStatus: "under_review",
            organizerApplication: {
              status: "under_review",
              reviewNotes,
              updatedAt: FieldValue.serverTimestamp(),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return;
      }

      if (decision === "rejected") {
        transaction.set(
          userRef,
          {
            displayName: safeString(userData.displayName, contactPerson),
            email: safeString(userData.email, application.email),
            roles: FieldValue.arrayRemove("organizer"),
            organizerApproved: false,
            organizerApplicationStatus: "rejected",
            organizerApplication: {
              status: "rejected",
              reviewNotes,
              updatedAt: FieldValue.serverTimestamp(),
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return;
      }

      transaction.set(
        organizationRef,
        {
          name: organizerName,
          slug,
          ownerId: userId,
          city: safeString(application.city, "Accra"),
          country: safeString(application.country, "Ghana"),
          businessType: safeString(application.businessType, "Event Organizer"),
          contactPerson,
          contactEmail: safeString(application.email, userData.email),
          contactPhone: safeString(application.phone, userData.phone),
          businessAddress: safeString(application.businessAddress),
          instagram: safeString(application.instagram),
          logoImageUrl: safeString(application.logoImageUrl),
          status: "active",
          applicationId,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      transaction.set(
        membershipRef,
        {
          organizationId,
          userId,
          role: "owner",
          status: "active",
          permissions: {
            manageEvents: true,
            manageTickets: true,
            managePromotions: true,
            validateTickets: true,
          },
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      transaction.set(
        userRef,
        {
          displayName: safeString(userData.displayName, contactPerson),
          email: safeString(userData.email, application.email),
          phone: safeString(userData.phone, application.phone) || null,
          roles: FieldValue.arrayUnion("attendee", "organizer"),
          organizerApproved: true,
          organizerApplicationStatus: "approved",
          organizerApplication: {
            status: "approved",
            organizationId,
            reviewNotes,
            updatedAt: FieldValue.serverTimestamp(),
          },
          defaultOrganizationId: organizationId,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: userSnap.exists
            ? userData.createdAt || FieldValue.serverTimestamp()
            : FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    return {
      success: true,
      applicationId,
      decision,
      organizationId: decision === "approved" ? organizationId : null,
    };
  },
);
