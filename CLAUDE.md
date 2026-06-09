# Vennuzo Product and Architecture Memory

Last updated: 2026-06-09

## Project Overview

Vennuzo is a Flutter-first event and places platform for attendees, organizers, venues, promoters, and admins. It supports discovery, RSVP, tickets, reminders, social activity, venue profiles, organizer workflows, staff tools, campaigns, support, and Firebase-backed notifications/payments.

Business goals:

- Make Vennuzo the primary discovery and operations layer for nightlife, events, and venue-led communities.
- Let venues such as G+ Nightclub own rich public profiles with media, menus, events, RSVP flows, and subscriptions.
- Give organizers/admins production-grade tooling for ticketing, campaigns, payments, support, and moderation.

Target users:

- Attendees discovering events and places.
- Venue and event staff onboarding locations, managing profiles, and checking tickets.
- Organizers/promoters managing events, orders, campaigns, and teams.
- Admin/superadmin operators managing safety, settings, approvals, support, and platform data.

## Architecture

Frontend architecture:

- Mobile app: Flutter/Dart in `lib/`, with feature folders under `lib/features`, services under `lib/data/services`, domain models under `lib/domain/models`, and app bootstrap under `lib/app` plus `lib/core`.
- Studio web app: React 19 + TypeScript + Vite in `studio/`, with pages under `studio/src/pages`, shared libraries under `studio/src/lib`, and Firebase adapters in `studio/src/firebase*.ts`.
- Public/static pages: `public-pages/`, `support.html`, and privacy/legal pages.

Backend architecture:

- Firebase Cloud Functions in `functions/`, Node.js 22 CommonJS modules split by domain: events, places, G+ sync, payments, notifications, admin, support, moderation, phone auth, and sharing.
- Firebase Auth is the identity layer for email/Google/Apple/phone sign-in capabilities.
- Firebase Cloud Messaging, Hubtel SMS, nodemailer, and Firestore-triggered jobs handle confirmations and notifications.

Database architecture:

- Cloud Firestore is the operational database.
- Firebase Storage stores media assets and user/place/event uploads.
- Firestore rules in `firestore.rules` enforce client-visible boundaries; privileged server writes use Admin SDK in Cloud Functions.
- Index definitions live in `firestore.indexes.json`.

Infrastructure architecture:

- Firebase project: `vennuzo` for app/studio/functions deployment scripts.
- Historical docs also reference production project `eventora-10063` for deployed rules/indexes and seeded G+ data.
- iOS App Store bundle: `com.vennuzo.app`, Apple app id `6761087972`, team `36TZ8UKL8W`.

## Engineering Decisions

- Use Firestore as the shared event, place, RSVP, ticket, campaign, and support data plane for mobile, Studio, and functions.
- Keep payout-sensitive and notification-sensitive state server-controlled via Cloud Functions rather than writable by clients.
- Use generated media and synced G+ media only as source data for place profiles; the app should render venue media from the canonical places/profile data rather than hard-coded assets.
- Use Firebase App Check in the app dependency set; iOS `Podfile.lock` must include the matching `firebase_app_check` pod.
- For App Store builds, increment Flutter build numbers monotonically and validate the exported IPA before upload.

Tradeoffs:

- Firestore keeps iteration fast but requires explicit index/rules discipline as places/events queries grow.
- Flutter provides one mobile codebase, but iOS release metadata and entitlements must be verified independently.
- The deprecated `appStoreVersionSubmissions` cancel endpoint is still needed as a fallback for removing a waiting review submission; new submissions should use `reviewSubmissions` plus `reviewSubmissionItems`.

## Database Documentation

Core collections:

- `users`, `admins`
- `organizations`, `organization_members`, `organizer_applications`
- `events`, `event_occurrences`, `event_rsvps`
- `event_ticket_orders`, `event_ticket_lookups`, `wallet_transactions`
- `places`, `place_claims`, `place_reservations`, `place_subscriptions`
- `promotion_campaigns`, `promo_packages`, `notification_jobs`, `event_reminders`
- `support_tickets`, `share_links`, `audiences`
- G+ sync/support collections are handled through `functions/gplus_sync.js`, `functions/gplus_ticket_bridge.js`, and places services.

Important indexes:

- Event discovery: `events(visibility,status,startAt)`, `events(source,status,visibility,startAt)`, `events(placeId,source,status,visibility,startAt)`.
- Organizer/event ops: `events(organizationId,startAt)`, `event_rsvps(organizationId,createdAt)`, `event_ticket_orders(organizationId,createdAt)`.
- Buyer history: `event_ticket_orders(buyerId,createdAt)`.
- Jobs/campaigns: `notification_jobs(status,scheduledAt)`, `event_reminders(status,scheduledAt)`, `promotion_campaigns(status,scheduledAt)`.
- Places indexes should be kept aligned with any new filters added to `lib/data/services/vennuzo_places_service.dart` and Studio Places pages.

## API Documentation

Cloud Functions domains:

- Notifications: `processPushQueue`, `launchEventNotificationCampaign`, `processNotificationJobs`, `processEventReminderNotifications`, RSVP/order triggers, test push/SMS endpoints.
- Payments: `createEventTicketPaymentForOrder`, `checkHubtelTicketStatus`, `createWebEventTicketOrder`, `hubtelCallback`, `hubtelReturn`.
- Places: `functions/places_platform.js`, `functions/places_lookup.js`, G+ profile/menu/media sync helpers.
- Admin/organizer: approvals, permissions, settings, analytics, support, content moderation.

Authentication:

- Client writes require Firebase Auth unless explicitly public.
- Admin/superadmin operations require admin docs or server-side Cloud Functions.
- Payment, ticket issuance, settlement, notification dispatch, and G+ bridge writes are server-owned.

## Security Notes

- Do not commit API keys, ASC issuer IDs, `.p8` private keys, Hubtel credentials, Firebase local env files, keystores, or generated JWTs.
- Firestore rules prevent clients from escalating `roles`/`adminRole` on user profiles.
- Ticket settlement and admission fields are intentionally blocked from client ticket-order creates.
- Support ticket creation validates required fields and ownership.
- Continue auditing Firestore rules when places onboarding expands, especially claim/write permissions and media upload paths.

## Performance Notes

- Places/events UI must avoid stream loops and repeated query rebuilds; preserve stable query inputs and pagination cursors.
- Use composite indexes for any multi-field Firestore query before shipping.
- Studio build currently includes large PDF/XLSX/vendor chunks; lazy loading should continue for admin-heavy pages.
- Media galleries should use thumbnails/pagination and avoid loading every full-size venue image at once.

## Technical Debt

- App Store automation is currently shell/API driven; wrap it in a checked script before repeated production releases.
- More Firestore rules emulator coverage is needed for places onboarding and venue media updates.
- G+ bridge paths should be documented end-to-end from source repo media desk writes into Vennuzo places.
- Consolidate notification confirmation behavior so Vennuzo-origin RSVPs always use Vennuzo sender branding while G+ app notifications remain venue-branded.

## Roadmap

Completed:

- Places profile UX improvements with clickable featured venues and grid-style media.
- Staff location onboarding entry point in the app.
- G+ RSVP bridge and notification confirmation work.
- App Store submission for version `1.0`, build `2026060902`.
- Place detail events now render flyer-led cards and expose RSVP/ticket actions.

Current work:

- Stabilize places/G+ content, media, menu, and events parity.
- Keep App Review submission monitored until accepted or action is needed.

Planned:

- Harden G+ media sync with source-of-truth documentation and automated regression tests.
- Add richer staff onboarding workflows in Studio and mobile.
- Expand Firestore index/rules coverage for venue search, claims, subscriptions, and reservations.

## Changelog

2026-06-09:

- Initialized `CLAUDE.md` because the required memory file was missing.
- Prepared and submitted iOS App Store build `2026060902` for Vennuzo version `1.0`.
- Added `NSLocationAlwaysAndWhenInUseUsageDescription` to satisfy Apple privacy validation expectations.
- Bumped Flutter build number to `1.0.0+2026060902`.
- Updated iOS pods lockfile to include declared `firebase_app_check` dependency.
- Verified QA gates across Flutter, Functions, Studio, local IPA inspection, Apple validation, upload, and ASC submission readback.
- Updated place/location event sections so events are clickable, show event flyers, and route users into the existing RSVP/ticket detail flow.
- Hardened the places/events UX after a full audit: sold-out events now show a disabled "Sold out" action instead of a dead-end checkout; place "not found" is recoverable (app bar + loading state); cold-load loading states replace empty/not-found flashes; place reservations and subscriptions are guest-gated with truthful feedback; plus CTA-copy, accessibility, and media-loading polish. Verified with `flutter analyze` (clean) and `flutter test` (29/29).
