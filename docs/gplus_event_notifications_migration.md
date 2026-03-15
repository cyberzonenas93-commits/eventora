# GPlus Event Notifications to Eventora

This note captures how GPlus currently handles event SMS and push delivery, and
how that setup was ported into Eventora.

## How GPlus handles SMS

GPlus keeps its SMS stack in `functions/sms_invite_system.js`.

The important pieces are:

- Hubtel credentials are resolved from `functions/hubtel_sms_config.js` first.
- If the file is missing, GPlus falls back to env params or `app_config/hubtel`
  in Firestore.
- Hubtel delivery uses `https://smsc.hubtel.com/v1/messages/send` with Basic
  auth, and falls back to the older `https://sms.hubtel.com/v1/messages/send`
  endpoint if needed.
- Phone numbers are normalized to Ghana mobile format before dispatch.
- Audience building comes from `event_rsvps`, `event_ticket_orders`, and other
  transactional collections.
- Campaigns are modeled separately from recipients, then dispatched in batches.

The credentials reused in Eventora come from GPlus:

- `clientId: mkdkdqru`
- `clientSecret: xzeyqzjc`
- `senderId: GPlus`

## How GPlus handles push

GPlus uses a Firestore queue called `push_queue`.

The core pattern is:

- other functions create `push_queue` documents
- `functions/push-queue-processor.js` reacts to new queue docs
- the processor loads `users/{uid}.fcmToken`
- it sends FCM multicast notifications
- invalid tokens are removed from Firestore

This queue pattern is the cleanest part of the original design, so Eventora
keeps it.

## What Eventora now does

Eventora now has its own Firebase Functions package in `functions/`.

Implemented backend flows:

- `launchEventNotificationCampaign`
  - creates `promotion_campaigns`
  - creates `notification_jobs`
  - dispatches push and SMS campaigns immediately or on schedule
- `processNotificationJobs`
  - scheduled processor for queued jobs
- `processPushQueue`
  - sends multicast FCM notifications from `push_queue`
- `processEventReminderNotifications`
  - sends scheduled reminder push and SMS from `event_reminders`
- `onEventRsvpCreated`
  - sends RSVP confirmation push and SMS
- `onEventTicketOrderCreated`
  - sends reservation / ticket confirmation push and SMS
- `sendTestEventSms`
- `sendTestEventPush`

Implemented Flutter-side flows:

- FCM token registration and refresh sync
- foreground local notification display
- account-level push, SMS, and marketing preferences
- Firestore sync for:
  - events
  - event occurrences
  - RSVPs
  - ticket orders
  - ticket lookups
  - reminders
  - promotion campaigns

## Collections Eventora now uses for notifications

- `users`
- `organizations`
- `organization_members`
- `events`
- `event_occurrences`
- `event_rsvps`
- `event_ticket_orders`
- `event_ticket_lookups`
- `event_reminders`
- `promotion_campaigns`
- `notification_jobs`
- `push_queue`

## Policy-safe behavior added in Eventora

- phone number is still optional during signup
- SMS reminders and ticket messages only send when a phone number exists
- promotional campaigns only target users who opted into marketing
- push can be disabled at account level
- SMS can be disabled at account level
- guest access remains open for discovery

## Remaining deployment requirement

iOS push delivery still needs the Apple APNs key or certificate uploaded in the
Firebase console for the `eventora-10063` project. The app code and entitlements
are wired, but APNs credentials are still an Apple-side deployment step.
