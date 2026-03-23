"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { notifySuperAdmins, notifyUserPush } = require("./event_notifications");

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
      safeString(application.organization, "Vennuzo Organizer"),
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

    if (decision === "approved" || decision === "rejected") {
      await notifyUserPush(userId, {
        title: "Application reviewed",
        body:
          decision === "approved"
            ? "Your organizer application was approved. You can now create events."
            : "Your organizer application was rejected. Check the review notes for details.",
        route: "/account",
        kind: "organizer_application_reviewed",
      });
    }

    return {
      success: true,
      applicationId,
      decision,
      organizationId: decision === "approved" ? organizationId : null,
    };
  },
);

exports.createAdminAccount = onCall(
  { region: REGION },
  async (request) => {
    const callerUid = request.auth && request.auth.uid;
    if (!callerUid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in as a superadmin before creating admin accounts.",
      );
    }

    const callerAdmin = await assertSuperAdmin(callerUid);
    const displayName = safeString(request.data && request.data.displayName);
    const email = safeString(request.data && request.data.email).toLowerCase();
    const password = safeString(request.data && request.data.password);
    const phone = safeString(request.data && request.data.phone);
    const requestedRole = safeString(
      request.data && request.data.role,
      "admin",
    ).toLowerCase();
    const role = ["admin", "superadmin"].includes(requestedRole)
      ? requestedRole
      : "admin";

    if (displayName.length < 2) {
      throw new HttpsError(
        "invalid-argument",
        "Display name must be at least 2 characters.",
      );
    }

    if (!email || !email.includes("@")) {
      throw new HttpsError(
        "invalid-argument",
        "A valid email address is required.",
      );
    }

    if (password.length < 8) {
      throw new HttpsError(
        "invalid-argument",
        "Temporary password must be at least 8 characters.",
      );
    }

    let targetUser;
    let created = false;

    try {
      targetUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error && error.code === "auth/user-not-found") {
        targetUser = await admin.auth().createUser({
          email,
          password,
          displayName,
          phoneNumber: phone || undefined,
          emailVerified: false,
          disabled: false,
        });
        created = true;
      } else {
        throw error;
      }
    }

    const existingAdminSnap = await db.collection("admins").doc(targetUser.uid).get();
    const existingAdmin = existingAdminSnap.exists ? existingAdminSnap.data() || {} : {};
    const existingRole = safeString(existingAdmin.role).toLowerCase();

    if (existingRole) {
      throw new HttpsError(
        "already-exists",
        existingRole === role
          ? "That user already has this admin role."
          : "That user already has admin access. Edit their role manually if you need to change it.",
      );
    }

    if (!created) {
      await admin.auth().updateUser(targetUser.uid, {
        displayName,
        password,
        phoneNumber: phone || undefined,
        disabled: false,
      });
      targetUser = await admin.auth().getUser(targetUser.uid);
    }

    const adminRef = db.collection("admins").doc(targetUser.uid);
    const userRef = db.collection("users").doc(targetUser.uid);
    const now = FieldValue.serverTimestamp();
    const actorName = safeString(
      callerAdmin.displayName,
      safeString(callerAdmin.email, callerUid),
    );
    const roles = role === "superadmin" ? ["admin", "superadmin"] : ["admin"];

    await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      const userData = userSnap.exists ? userSnap.data() || {} : {};

      transaction.set(
        adminRef,
        {
          uid: targetUser.uid,
          displayName,
          email,
          phone: phone || null,
          role,
          status: "active",
          createdBy: callerUid,
          createdByName: actorName,
          createdAt: existingAdminSnap.exists
            ? existingAdmin.createdAt || now
            : now,
          updatedAt: now,
        },
        { merge: true },
      );

      transaction.set(
        userRef,
        {
          displayName,
          email,
          phone: phone || null,
          roles: Array.from(
            new Set(
              []
                .concat(Array.isArray(userData.roles) ? userData.roles : [])
                .concat(roles),
            ),
          ),
          adminRole: role,
          updatedAt: now,
          createdAt: userSnap.exists ? userData.createdAt || now : now,
        },
        { merge: true },
      );
    });

    await notifySuperAdmins({
      title: "Admin account created",
      body: `${email} was granted ${role} by ${actorName}.`,
      route: "/admin/settings",
      kind: "superadmin_admin_created",
      excludeUids: [callerUid, targetUser.uid],
    });

    return {
      success: true,
      uid: targetUser.uid,
      created,
      role,
    };
  },
);
