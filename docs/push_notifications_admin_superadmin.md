# Push notifications: admin & superadmin

## Currently implemented (organizer = event creator)

These go to the **event creator** (`events.createdBy`) when they have push enabled and an FCM token.

| Trigger | Title | Body | Kind |
|--------|--------|------|------|
| Someone RSVPs to an event | New RSVP | Someone just RSVP'd to {eventTitle}. | `organizer_rsvp_alert` |
| Someone creates a ticket reservation | New reservation | A reservation was made for {eventTitle}. | `organizer_reservation_alert` |
| Someone pays for tickets | New ticket sale | Tickets were sold for {eventTitle}. | `organizer_ticket_alert` |

Implementation: `functions/event_notifications.js` — `notifyOrganizersOfEventActivity()`, `getOrganizerPushTargets(eventData)`.

---

## Implemented push for admin / superadmin

Target audience: users in `admins` with `role === "superadmin"` (or `"admin"` where noted). They must have `fcmToken` and push enabled (same as `users`); you’d store FCM token either on the admin doc or on the linked `users` doc.

| # | Trigger | Suggested title | Suggested body | Audience | Notes |
|---|--------|------------------|----------------|----------|--------|
| 1 | New organizer application **submitted** | New organizer application | {organizerName} submitted an application for review. | Superadmins | Fire when `organizer_applications/{id}` status becomes `submitted` (or on create if submitted). |
| 2 | Organizer application **approved** / **rejected** | Application reviewed | Your organizer application was {approved \| rejected}. | Applicant (organizer) | Optional; may already be in-app/email. |
| 3 | **Event reported** (content/safety) | Event reported | An event was reported: {eventTitle}. Review in admin. | Admins / superadmins | Requires a “reports” or “flags” flow. |
| 4 | **Payout requested** or large payout | Payout request | Organizer payout requested: {amount} for {orgName}. | Superadmins (or finance role) | When a payout is requested or threshold exceeded. |
| 5 | **Campaign launched** (platform-level) | Campaign launched | A campaign was launched for {eventTitle} (push/SMS). | Admins | Optional visibility into platform activity. |
| 6 | **SMS / push delivery failure** spike | Delivery issues | High failure rate on notifications. Check logs. | Superadmins | When failure rate exceeds a threshold. |
| 7 | **New event published** (platform digest) | New event live | {eventTitle} is now live. | Admins | Optional; can be daily digest instead of per event. |
| 8 | **New admin account created** | Admin account created | {email} was granted {role} by {callerName}. | Superadmins | After `createAdminAccount` succeeds. |
| 9 | **Payment / Hubtel webhook failure** | Payment webhook failed | A payment webhook failed for order {orderId}. | Superadmins | When payment provider callback fails repeatedly. |
| 10 | **Quota or budget** (campaign / wallet) | Budget alert | Campaign or wallet budget alert: {detail}. | Superadmins / admins | When a campaign or wallet hits a limit. |

---

## Implementation notes for admin/superadmin push

1. **Resolve audience**  
   - Query `admins` where `role == "superadmin"` (and optionally `"admin"`).  
   - Get each admin’s UID; if FCM is on `users`, join with `users/{uid}`; else store `fcmToken` on `admins/{uid}` and use that.

2. **Reuse queue**  
   - Reuse `queuePushNotification()` and `processPushQueue`; pass `targets: [adminUid1, adminUid2, ...]`.  
   - Ensure each admin has a `users/{uid}` doc with `fcmToken` (and optional `notificationPrefs.pushEnabled`) if you use the existing processor, or extend the processor to read from `admins` when needed.

3. **Payload**  
   - Include `route` (e.g. `/admin/approvals`, `/admin/reports`) and any `eventId` / `applicationId` / `orderId` so the app can open the right screen when the notification is tapped.

4. **Kinds**  
   - Use distinct `kind` values (e.g. `superadmin_organizer_application`, `admin_event_reported`) for filtering and analytics.
