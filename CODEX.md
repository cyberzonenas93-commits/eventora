# Vennuzo Engineering and Operations Memory

Last updated: 2026-06-09

## Repository Structure

- `lib/`: Flutter mobile application.
  - `lib/features/`: feature screens and UI flows.
  - `lib/data/services/`: Firebase, payments, places, notification, and sync services.
  - `lib/domain/models/`: typed domain models for events, places, accounts, creators, promotions, tickets, and services.
  - `lib/core/`: theme, Firebase bootstrap, art, utilities, and shared constants.
- `functions/`: Firebase Cloud Functions, Node.js 22, CommonJS modules.
- `studio/`: React + TypeScript + Vite web admin/organizer app.
- `ios/`, `android/`, `macos/`, `linux/`: platform shells.
- `assets/`, `studio/public/`, `public-pages/`: app, web, and public assets.
- `docs/`: architecture notes, QA logs, release notes, migration plans, and store submission records.
- Root Firebase config: `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`.

## Build Process

Flutter:

- Install dependencies: `flutter pub get`
- Analyze: `flutter analyze`
- Test: `flutter test`
- iOS App Store IPA:
  - `flutter build ipa --release --build-name=1.0.0 --build-number=<build> --export-options-plist=ios/ExportOptionsAppStore.plist`

Functions:

- From `functions/`: `npm test`
- Root helpers include `npm run functions:lint`, `npm run functions:deploy`, and targeted deploy scripts.

Studio:

- From `studio/`: `npm run lint`, `npm run build`, `npm run test`.

iOS release requirements:

- Bundle ID: `com.vennuzo.app`
- Team ID: `36TZ8UKL8W`
- Export options: `ios/ExportOptionsAppStore.plist`
- ASC API key ID used locally: `R7BYLGVT9L`
- Never print or commit issuer IDs, generated JWTs, or `.p8` private keys.

## Development Standards

- Prefer existing feature/service patterns before introducing abstractions.
- Keep Flutter screens responsive with explicit loading, error, and empty states.
- Use server-side Functions for privileged writes, payment settlement, notification dispatch, and cross-app bridge writes.
- Treat Firestore rules and indexes as part of each feature, not a deployment afterthought.
- Keep UI copy concise and production-facing; avoid placeholder flows in shipped surfaces.
- Manual code edits should be small and traceable; generated build artifacts should not be committed unless intentionally tracked.

## Testing Procedures

Primary release gates:

- `flutter analyze`
- `flutter test`
- `npm test` in `functions`
- `npm run lint` in `studio`
- `npm run build` in `studio`
- `npm run test` in `studio`

Additional release checks:

- `plutil -lint ios/Runner/Info.plist`
- Inspect exported IPA `Info.plist` for bundle id, version, build number, and Apple privacy purpose strings.
- Inspect IPA entitlements for production push, Sign in with Apple, and `get-task-allow=false`.
- `xcrun altool --validate-app` before upload.
- `xcrun altool --build-status` and ASC API readback after upload.

## Infrastructure

- Firebase Hosting serves Vennuzo/Studio/public pages through configured targets.
- Cloud Functions deploy to Firebase with Node.js 22.
- Firestore and Storage rules are tracked at the repo root.
- App Store Connect submission is currently handled with Apple CLI/API calls from the local machine.
- Monitoring/logging lives primarily in Firebase logs, Cloud Functions structured logger output, and Studio Sentry integration.

## Refactoring History

- Places experience has been progressively split into detail, gallery, management, reservation, and shared widget files.
- Place detail event rows now reuse `EventCard` so flyer rendering and event navigation stay consistent with Discover/creator surfaces.
- Staff location onboarding is available from the mobile Manage surface and reuses place management creation/claiming paths.
- Notification, payment, support, places, and G+ bridge functions are separated into domain modules instead of a single monolithic index.

## Operational Notes

- The App Store version `1.0` is currently submitted and waiting for review with build `2026060902`.
- New review submission ID: `730de9f2-40fc-4239-9e66-d442e0ad762d`.
- Build/delivery ID: `58704fe2-b4e0-45ff-9291-c562bb877fb5`.
- Prior waiting review submission `716078ad-eef0-4525-af3a-a65d3d4f8833` was removed before attaching build `2026060902`.
- Apple validation for `2026060901` warned about missing `NSLocationAlwaysAndWhenInUseUsageDescription`; build `2026060902` includes the fix.
- Keep at least 8-10 GB free before iOS archive/export. Cleaning `build/ios` and stale `DerivedData/Runner-*` is safe when no build is running.

## Known Limitations

- App Store automation should be moved into a script that masks sensitive values and records submission IDs automatically.
- Firestore rules emulator tests do not yet cover every places onboarding and venue media write path.
- Studio bundle includes large PDF/XLSX chunks; watch admin performance as data grows.
- G+ source media mapping needs a dedicated runbook covering media desk writes, sync script inputs, and Vennuzo places output.

## Changelog

2026-06-09:

- Updated place detail events UI to show flyer-led event cards with enabled RSVP/ticket actions.
- Added a widget regression test for place event flyer/action rendering.
- UX/robustness hardening pass on the places/events surfaces (post-audit):
  - Sold-out events: added `EventTicketing.isSoldOut`; place event cards and the
    event detail bottom bar now render a disabled "Sold out" action, and
    `_openCheckoutFlow` guards the deep-link auto-open. Settlement stock is still
    enforced atomically server-side in `event_payments.js` (`runTransaction`).
  - Place detail "not found" now renders an `AppBar` (back button) plus a loading
    state instead of a dead-end bare `Text`.
  - Added `placesLoading` / `eventsLoading` (backed by `_placesHydrated` /
    `_eventsHydrated`, set in the stream `.listen`/`onError`) so Places, place
    events, and place detail show spinners instead of flashing empty/not-found
    on cold load. Mirrors the existing `_campaignsHydrated` gate.
  - Reservations: `createPlaceReservation` is now `Future<PlaceReservation>`
    (awaits the cloud write, throws on failure); `_reserve` gates guests behind
    the auth prompt and shows a truthful success/failure snackbar.
  - Place subscribe is now guest-gated with confirmation feedback via
    `_togglePlaceSubscription` (repo no-ops silently for guests).
  - Polish: unified RSVP/ticket CTA copy across card + bottom bar, `EventCard`
    exposed as a button to screen readers, network flyers get a generative-art
    loading placeholder + bounded `cacheWidth`, RSVP guest count capped at 20,
    checkout generic-catch no longer leaks raw exception strings, redundant
    place-tab `Semantics` removed.
  - Added widget regression tests for the sold-out action and the not-found app bar.
  - Gates: `flutter analyze` clean; `flutter test` 29/29 passing.
- App-wide attendee-flow hardening pass (second audit, Discover/Account/Tickets/Social/cross-cutting):
  - Discover: loading state (via `eventsLoading`) instead of a "no events" flash on
    cold load; calendar "Previous month" disabled before the current month.
  - Likes: `toggleLike` was increment-only (and a no-op for live events) — now a real
    per-viewer toggle (`isEventLiked`) with correct icon/label/snackbar; fixed the
    misleading "Likes sync to your account" copy.
  - Reminders/push: `bindViewer` + `updateNotificationPrefs` now return whether push
    actually activated, so "Enable" only claims success when OS-authorized (otherwise
    points the user to Settings).
  - Onboarding: promo-push pref no longer persisted when marketing is opted out.
  - Deep links: replaced the permanent event-id dedup latch with a short-window URI
    dedup so the same shared link can be reopened.
  - Auth (account/): local `_submitting` guards close the double-submit window across
    `waitForAuthenticatedSession` (fixes phone-OTP re-consume / duplicate create-account);
    `launchUrl` wrapped in try/catch; real email regex; phone validator; DOB min-age 13;
    "Passwords do not match" copy.
  - Tickets: broadened payment-poll error handling (uncaught `FirebaseException` from
    `Source.server` no longer escapes the timer); re-entrancy guard on "Open Hubtel again"
    (double-charge path); "Close" exit on failed/pending; empty/invalid QR placeholder +
    `errorStateBuilder` + semantics; transient "Copied".
  - Social: comment submit catch+snackbar; image pick compression (`maxWidth`/`imageQuality`)
    + 10 MB guard; comments/feed/explore/profile StreamBuilders now have error (and
    loading/empty) branches instead of masking errors as empty; guest "sign in to comment"
    prompt; transient "Copied"; truthful unsave confirmation; full-screen viewer index clamp.
  - Deferred/flagged (need native config / content / product decision): Universal Links
    for shared `https://vennuzo.web.app` links (entitlements + hosted AASA/assetlinks);
    Terms page publication; guest-visible Host/Passes/Reach tabs; top-bar touch-target
    sizing (small-screen overflow risk).
  - Gates: `flutter analyze` clean; `flutter test` 29/29 passing.
- Operator surfaces + backend security + Studio hardening (third audit pass):
  - SECURITY (firestore.rules + functions): closed a privilege-escalation hole where any
    signed-in user could author `organizer_applications/{uid}` claiming a victim org and
    gain event-manager rights — hardened both `ownsOrganizerApplication` (read side, also
    neutralizes pre-existing malicious docs) and `canWriteOwnOrganizerApplication` to
    require `org_<uid>`. `isAdmin()` now checks `status != 'disabled'` (revoked admins kept
    client write access). `hasAdminAccess` in `gplus_sync.js`/`places_platform.js` now
    excludes `read_only`; `assertPlaceManager` uses `hasAdminAccess` (was bare `exists`).
    `createWebEventTicketOrder` now bounds per-tier quantity + order total (was unbounded).
    Added `functions/tests/rules/organizer_application_rules.test.js` (escalation regression).
  - Admin mobile: gate-admission confirmation + truthful result (no fake local admit for
    unpaid; route to scanner cash flow); scanner admit/cash confirmations; superadmin
    client guard on approvals; copyable order link; inert admin cards marked "Coming soon".
  - Organizer/promotions: campaign launch try/catch + double-submit guard; payout
    `bank-transfer` label fix; wallet top-up phone validation; business wallet error/retry
    state (was showing GHS 0 on error); network-image error/loading builders.
  - Studio: admission `qrToken` no longer sent to api.qrserver.com (client-side QR via
    `qrcode`); `rel="noopener noreferrer"` on staff links; lazy chunk-load retry.
  - Deep links: in-app parser now also accepts the `https` share-link format (full
    Universal Links still needs native entitlements + hosted AASA/assetlinks + deploy).
  - Gates: `flutter analyze`+`flutter test` (29/29); `functions` `npm test` (69/69) +
    `npm run test:rules` (10/10); `studio` `npm run lint`+`build` clean.
- Optional polish (formerly deferred): top-bar Account + switch-workspace buttons now have
  >=44px tap targets (visual unchanged; verified against the small-screen overflow test);
  password show/hide toggles on sign-in + sign-up fields; "Reopen payment" affordance on
  failed/stuck orders in the Passes list (routes into VennuzoTicketPaymentStatusScreen).
  Gates: `flutter analyze` clean; `flutter test` 29/29.
- Branch `fix/places-events-ux-hardening` pushed; PR #1 opened against `main`.
- Closed the moderation/support least-privilege bypass at the rules layer: `event_reports`
  updates now require `canModerateReports()` and `support_tickets` updates + admin support
  messages require `canManageSupport()` (role sets mirror `functions/admin_permissions.js`;
  superadmin aliases included). A non-write-role admin (e.g. marketing_manager, read_only)
  can no longer bypass the console with a direct client write. Added
  `functions/tests/rules/admin_role_rules.test.js`; `npm run test:rules` 15/15.
  Assumption: admin `role` values are stored canonically (snake_case) — verify before
  deploying if any legacy non-canonical role docs exist.
- Verified-not-code / flagged: Terms page is a deploy only (`firebase deploy --only
  hosting:pages` publishes `public-pages/terms.html` → `vennuzo-pages.web.app`; link already
  correct). `bootstrapOwnerAdmin` left as-is by design (fail-closed + email-restricted +
  rate-limited break-glass; an "active superadmin exists" guard would risk lockout for a LOW
  finding) — harden operationally by unsetting/rotating the bootstrap secret post-setup.
  Universal Links still needs Android signing SHA-256 + hosted AASA at the share domain
  (`vennuzo.web.app`, a different hosting site than `public-pages`) + a real-device test.
