"use strict";

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const logger = require("./logger");
const {
  canRolePerform,
  effectiveAdminRole,
  isAllowedSuperAdminEmail,
  normalizeAdminRole,
} = require("./admin_permissions");
const {
  notifyUserPush,
  queuePushNotification,
} = require("./event_notifications");

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

function messagePreview(value) {
  const text = safeString(value).replace(/\s+/g, " ");
  if (text.length <= 160) {
    return text;
  }
  return `${text.slice(0, 157)}...`;
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

async function supportAdminPushTargets(excludeUid) {
  const snap = await db.collection("admins").get();
  const targets = [];
  for (const doc of snap.docs) {
    const uid = doc.id;
    if (uid === excludeUid) {
      continue;
    }

    const data = doc.data() || {};
    const role = normalizeAdminRole(data.role);
    const status = safeString(data.status, "active").toLowerCase();
    if (status === "disabled" || !canRolePerform(role, "manage_support")) {
      continue;
    }

    const email = await resolveAdminEmail(uid, data);
    if (effectiveAdminRole(role) === "superadmin" && !isAllowedSuperAdminEmail(email)) {
      continue;
    }

    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      continue;
    }
    const user = userSnap.data() || {};
    const prefs = user.notificationPrefs || {};
    if (prefs.pushEnabled === false || !safeString(user.fcmToken)) {
      continue;
    }
    targets.push(uid);
  }
  return targets;
}

async function notifySupportAdmins({ ticketId, ticket, body, senderId }) {
  const subject = safeString(ticket.subject, "Support ticket");
  const senderName = safeString(ticket.name, "A Vennuzo user");
  const title = `Support: ${subject}`;
  const notificationBody = `${senderName}: ${messagePreview(body)}`;

  await db.collection("admin_notifications").add({
    kind: "support_ticket",
    audience: "support",
    status: "unread",
    ticketId,
    title,
    body: notificationBody,
    route: "/admin/support",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const targets = await supportAdminPushTargets(senderId);
  if (targets.length === 0 || typeof queuePushNotification !== "function") {
    return;
  }
  await queuePushNotification({
    kind: "support_admin_alert",
    targets,
    payload: {
      title,
      body: notificationBody,
      route: "/admin/support",
      supportTicketId: ticketId,
    },
  });
}

exports.onSupportMessageCreated = onDocumentCreated(
  {
    document: "support_tickets/{ticketId}/messages/{messageId}",
    region: REGION,
  },
  async (event) => {
    const messageSnap = event.data;
    if (!messageSnap) {
      return;
    }

    const { ticketId } = event.params;
    const message = messageSnap.data() || {};
    const senderType = safeString(message.senderType, "user").toLowerCase();
    const senderId = safeString(message.senderId);
    const body = safeString(message.body);
    if (!ticketId || !body) {
      return;
    }

    const ticketRef = db.collection("support_tickets").doc(ticketId);
    const ticketSnap = await ticketRef.get();
    if (!ticketSnap.exists) {
      logger.warn("[support] Message created without parent ticket", { ticketId });
      return;
    }

    const ticket = ticketSnap.data() || {};
    const latestFields = {
      latestMessage: messagePreview(body),
      lastMessageAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (senderType === "admin") {
      const userId = safeString(ticket.userId);
      await ticketRef.set(
        {
          ...latestFields,
          status: "awaiting_user",
          adminUnreadCount: 0,
          userUnreadCount: FieldValue.increment(1),
          lastAdminMessageAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      if (userId) {
        await notifyUserPush(userId, {
          title: "Support replied",
          body: messagePreview(body),
          route: `/support/${ticketId}`,
          kind: "support_reply",
          supportTicketId: ticketId,
          ticketId,
        });
      }
      return;
    }

    const currentStatus = safeString(ticket.status, "open").toLowerCase();
    await ticketRef.set(
      {
        ...latestFields,
        status: currentStatus === "closed" ? "open" : "awaiting_support",
        adminUnreadCount: FieldValue.increment(1),
        lastCustomerMessageAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await notifySupportAdmins({ ticketId, ticket, body, senderId });
  },
);
