# Vennuzo iOS Full QA Log - 2026-06-02

## Scope

- Device pass 1: iPhone 17 Pro, iOS 26.5, fresh erased simulator.
- Required additional device passes: smaller iPhone, larger iPhone, restart/logged-in state.
- Data policy: use only test accounts and test records.

## Run Log

### 15:43

- Confirmed current XcodeBuildMCP defaults were empty.
- Discovered Flutter iOS workspace: `ios/Runner.xcworkspace`.
- Confirmed scheme: `Runner`.
- iPhone 17 Pro simulators available. No simulator was initially booted.

### 15:47

- Initial XcodeBuildMCP `build_run_sim` exceeded its 120 second tool timeout.
- Background `xcodebuild` was still active and targeting another iPhone 17 Pro simulator instance.
- Terminated the stalled background build to avoid competing iOS builds.

### 15:50

- Erased and booted iPhone 17 Pro simulator `7E7B0BC1-9FAD-4248-9CC8-BD1D79A309EF` for fresh install testing.
- Started `flutter run -d 7E7B0BC1-9FAD-4248-9CC8-BD1D79A309EF --debug`.
- Build is active and targeting the correct erased iPhone 17 Pro simulator.

### 15:56

- `flutter run` remained inside a quiet Xcode build for several minutes with near-idle CPU and no app-level output.
- Stopped the run to switch to verbose build diagnostics.

### 15:58

- Verbose `flutter build ios --simulator --debug -v` confirmed Xcode is compiling Firebase/gRPC and FirebaseFirestore native pods.
- A partial `Runner.app` exists, but manual install failed with `Missing bundle ID` because the app bundle is not yet finalized.
- Build remains in progress; no app-level QA findings yet.

### 16:02

- `flutter build ios --simulator --debug -v` completed successfully after 381.6 seconds.
- Installed `/Users/angelonartey/Desktop/vennuzo/build/ios/iphonesimulator/Runner.app` on fresh iPhone 17 Pro simulator `7E7B0BC1-9FAD-4248-9CC8-BD1D79A309EF`.
- Launched bundle `com.vennuzo.app`.
- Runtime log path: `/Users/angelonartey/Library/Developer/XcodeBuildMCP/workspaces/vennuzo-e0795ba20e6a/logs/com.vennuzo.app_2026-06-02T16-02-07-763Z_helperpid98102_ownerpid23022_74113593.log`.
- First runtime screen: onboarding page 1. Text and CTA are readable on iPhone 17 Pro.

### 16:05

- Completed onboarding pages 1-4 on iPhone 17 Pro. No overflow observed.
- Location permission prompt appears after onboarding. Tested `Don’t Allow`; app continues to Explore instead of blocking.
- Logged-out Explore search tested:
  - No-result query `zzzznotreal` shows clear empty state and recovery actions.
  - Valid query `DJ` shows event results with visible price badges.
- Event detail opens from search result.
- Finding: event-detail sticky ticket CTA used white/light text on bright cyan, making the price/action text too faint.
- Fix applied in `lib/features/events/event_detail_screen.dart`: active sticky CTA foreground now uses dark on-primary text/icon/separator.
- `flutter analyze` passed with no issues.

### 16:07

- Rebuilt patched iOS simulator app successfully.
- Reinstalled and relaunched patched build on iPhone 17 Pro.
- Verified prior spotlight CTA regression: `See full event` is readable on white button.
- Verified fixed event-detail bottom CTA: `From GHS 120.00` and `Get tickets` are now dark/readable on cyan.

### 16:14

- Event share sheet tested:
  - Public URL displays correctly: `https://vennuzo.web.app/events/event_after_dark`.
  - `Copy link` displays `Share link copied.`
  - Finding: `Share now` did not visibly present the native iOS share sheet in Simulator and gave no feedback.
  - Fix applied in `lib/features/events/event_share_sheet.dart`: `Share now` now copies the URL immediately, attempts native sharing asynchronously, and reports unavailable/cancelled/error states.
  - Verified `Share now` now immediately shows `Share link copied.`
- `flutter test` passed: 15 tests.
- `flutter analyze` passed after the share fix.

### 16:21

- Report event flow tested as guest:
  - Short detail text keeps `Submit report` disabled.
  - Valid detail text enables `Submit report`.
  - Finding: valid guest report initially failed with `We could not send your report right now.`
  - Cause: the app wrote directly to `event_reports` with extra fields, while Firestore rules only allow the minimal public report schema.
  - Fix applied:
    - Added deployed callable `submitEventReport` in `functions/event_safety.js`.
    - Exported it from `functions/index.js`.
    - Switched `lib/data/services/event_safety_service.dart` to call the function.
    - Added `event_safety.js` to the functions lint script.
  - Deployed `functions:submitEventReport` to the Vennuzo Firebase project.
  - Verified valid guest report now succeeds with `Thanks. Your report has been sent.`

### 16:33

- Signup/account flow tested:
  - Empty submit shows validation for display name, email, date of birth, password, and confirm password.
  - Password mismatch shows inline `Passwords do not match yet.`
  - Finding: `Date of birth` was visually tappable but not exposed as an accessibility/UI automation tap target.
  - Fix applied in `lib/features/account/sign_up_screen.dart`: explicit semantics/onTap added around the DOB field.
  - Verified DOB target appears in runtime snapshot and opens the date picker.
  - Finding: immediately after account creation, Account screen could show email-derived display name and `DOB/Contact Not provided` even though the profile write later persisted correctly.
  - Cause: auth-state hydration could read before `_upsertProfile` completed, then stale data won the UI race.
  - Fix applied in `lib/app/vennuzo_session_controller.dart`: hydration generation guard plus explicit post-create rehydrate after profile upsert.
  - Verified fresh account `test-ios-20260602-1633@vennuzo.test` immediately shows:
    - Display name `Ticket QA Tester`
    - DOB `Jan 16, 2005`
    - Contact `0550005678`

### 16:39

- Ticket checkout validation retested on iPhone 17 Pro after reinstalling the patched build.
- With `Early Access × 1` selected, buyer details step prefilled the logged-in test profile.
- Finding: before the fix, a bad phone value such as `+12` could still open Hubtel checkout.
- Fix verified in `lib/features/events/event_detail_screen.dart`: tapping `Pay GHS 120.00` with `+12` now stays inside Vennuzo and shows `Enter a valid Ghana mobile money number.`
- Confirmed no Safari/Hubtel redirect occurs for the invalid phone case.
- Valid phone `0550005678` tested with the same ticket order. The app successfully hands off to external Hubtel checkout at `pay.hubtel.com`.
- Stopped at the external checkout boundary; no real payment was completed.

### 16:44

- Passes tab tested with the two pending orders created by Hubtel checkout handoff.
- Order cards are visually readable: event title, buyer, order ID, amount, pending status, tier, and ticket section are visible.
- Finding: tapping `Copy order link` did not produce a reliable visible confirmation in the simulator.
- Fix applied in `lib/features/tickets/tickets_screen.dart`: order cards now keep the clipboard action and also change the button label/icon to `Copied` after success.
- Verified on iPhone 17 Pro: tapping `Copy order link` changes the button to `Copied`.

### 16:55

- Social tab tested while logged in:
  - Feed loads existing posts.
  - Like toggles from `Like post, 0 likes` to `Unlike post, 1 likes`.
  - Comments screen ignores empty sends, accepts a valid comment, and feed comment count updates to `1`.
  - Native Photos picker opens for `New Post`; selected image returns to Vennuzo composer.
  - Event dropdown opens and updates the selected event.
  - Social post upload writes successfully; new post appears in feed with selected event and caption.
- Finding: post upload had a working but weak loading state: disabled button/spinner with unchanged `Share Post` label.
- Fix applied in `lib/features/social/social_feed_screen.dart`: busy button label now reads `Publishing...`.
- Finding: `Share post` gave no reliable visible acknowledgement when native sharing did not visibly present.
- Fix applied in `lib/features/social/social_feed_screen.dart`: share copies post text first and feed card changes the share action to `Post copied` with a check state.
- Verified on iPhone 17 Pro: tapping `Share post` changes the semantic target to `Post copied`.
- Social Explore grid opens post detail and Back navigation returns to the grid.
- Social Saved shows saved events, `Remove from saved` removes the event, and the empty state appears.

### 17:01

- Reach tab checked while logged in:
  - Metrics render as `0 Campaigns`, `0 Live now`, `0 People reached`.
  - Text contrast/readability is acceptable on iPhone 17 Pro.
  - `Open host access` navigates to the organizer onboarding form.
- Host access / organizer onboarding tested with QA data:
  - Logo upload opens iOS Photos picker and returns selected image to the form.
  - Organizer profile fields accept name/contact/business/city/address/Instagram.
  - Government ID upload opens iOS Photos picker and returns selected image.
  - Registered-business switch toggles correctly.
  - Registration number, TIN, and bank-transfer payout fields accept data.
  - Payout method selector opens and switches from Mobile money to Bank transfer.
  - Submit without required confirmations shows `Confirm the payout and compliance checkboxes first.`
  - Save progress returns to enabled state.
  - Submitting with confirmations checked moves the application to `Submitted` and shows the review summary.
- Test organizer application created for `test-ios-20260602-1633@vennuzo.test` with organizer name `Vennuzo QA Test Organizer`.

### 18:06

- Rebuilt and reinstalled the iOS simulator app after the Reach pending-state copy patch.
- Verified app restart/logged-in persistence on iPhone 17 Pro:
  - App relaunch restored the logged-in attendee shell without forcing sign-in.
  - Account profile still showed `Ticket QA Tester`, the QA email, DOB, phone, and attendee role.
- Verified Reach pending organizer state:
  - Reach CTA now shows `Review status` instead of stale `Finish host access`.
  - Tapping `Review status` opens the submitted host-access review page.
  - Review page shows the submitted organizer details for `Vennuzo QA Test Organizer`.
- Verified notification preference controls:
  - `Push notifications`, `SMS updates`, and `Promotional campaigns` switches are visible and readable.
  - Enabling `Promotional campaigns` exposes `Promotional push alerts`.
  - Event-type opt-in chips are visible and tappable.
  - Selected `Music` and `Nightlife`; no validation error or UI lock occurred.

### 18:11

- Finding: Account support area still depended on an email-style support entry in the mobile app, while the admin site already had `support_tickets` chat infrastructure.
- Fix applied:
  - Added `lib/features/account/support_chat_screen.dart`.
  - Replaced Account `Email support` with `Chat with support`.
  - Support chat collects user name, email, phone, topic, priority, subject, and first message.
  - Creates `support_tickets/{ticketId}` and appends `messages` in Firestore using the existing rules and `support_chat` Cloud Function trigger.
  - Existing admin support inbox and support-admin notification paths remain unchanged.
- Verified:
  - Chat screen opens from Account.
  - Name/email/phone prefill from the QA profile.
  - Created QA support ticket `QA ticket delivery question`.
  - Ticket persisted and reloaded after app reinstall/relaunch.
  - Existing ticket appears under `Your conversations`.
  - Backend trigger updated ticket status to `Needs reply` after the first user message.

### 18:15

- Finding: `Safety tips` and `Chat with support` rendered visible text but were not exposed as tappable button targets in the simulator runtime snapshot.
- Cause: custom `InkWell` support tiles lacked explicit button semantics.
- Fix applied in `lib/features/account/account_screen.dart`: `_SupportActionTile` now uses `Semantics(button: true, label, hint, onTap)`.
- Verified:
  - `Safety tips` appears as `tap|button|Safety tips`.
  - `Chat with support` appears as `tap|button|Chat with support`.
- Finding: support conversation reply input was exposed as a merged text-field label containing the whole conversation, and simulator text entry did not populate the reply controller.
- Fix applied in `lib/features/account/support_chat_screen.dart`:
  - Reply field now has its own semantics container.
  - Label changed to `Support reply`.
  - Added explicit hint text and stable key.
  - Existing support conversation cards have explicit button semantics.
- Verified:
  - Reply field appears as `typeText|text-field|Support reply`.
  - Typed follow-up text is retained in the field.
  - Tapping `Send message` saves the follow-up to the thread.
  - Latest message updates to `Follow-up from iOS QA after the reply input fix. Please ignore this test ticket.`

### 18:23

- Host tab pending-organizer state tested after support-chat fixes.
- Finding: Host hero showed `Finish setup to publish.` while the same screen also showed `Submitted` and `Host setup is in review`.
- Cause: `_ManageHero` only received a boolean `organizerReady`, so all non-ready organizer states used the same generic setup headline.
- Fix applied in `lib/features/manage/manage_screen.dart`:
  - Passes `viewer.organizerApplicationStatus` into `_ManageHero`.
  - Pending/submitted states now use `Host access is in review.`
  - Rejected states use `Update host application.`
  - Draft/not-started states keep `Finish setup to publish.`
- Verified on iPhone 17 Pro: Host tab now shows `Hosting hub Host access is in review. Submitted`.

### 18:31

- Owner account sign-in tested with `angelonartey@hotmail.com`.
- Verified owner profile loads with roles `admin, attendee, organizer, superadmin`.
- Verified workspace chooser appears for a multi-face account:
  - `Vennuzo app`
  - `Organizer portal`
  - `Superadmin console`
- Organizer portal tested:
  - Overview loads organizer metrics.
  - Events tab loads host metrics and event-management actions.
  - Tickets tab loads order metrics.
  - Promote tab loads campaign metrics.
  - Campaign composer opens and shows owner-audience messaging, opt-in push messaging, Hubtel SMS base cost, markup/wallet reserve copy. Composer closed without creating a live campaign.
  - Business tab loads wallet, CRM, payouts/billing/partners framing.
- Finding: Creative services opened from Business but had no app-level Back/AppBar control when pushed as a route, which could trap users without a system back gesture.
- Fix applied in `lib/features/creative/creative_services_screen.dart`: added `AppBar(title: Text('Creative services'))`.
- Verified visually on iPhone 17 Pro:
  - Creative services opens with wallet/top-up fields and paid flyer/table-flyer pricing.
  - Back control returns visually to the Business tab.
- Tool/semantics observation: after returning visually to Business, XcodeBuildMCP runtime snapshots continued reporting Creative services text fields until app reset. Fresh screenshots showed Business correctly. I reset the app before continuing admin QA.

### 18:38

- Superadmin console verified on iPhone 17 Pro with the authorized owner account:
  - Dashboard metrics loaded.
  - Events tab loaded.
  - Tickets tab loaded.
  - Campaigns tab loaded.
  - Admin tab loaded and showed the owner as `SUPERADMIN`.
- Web admin support inbox verified at `http://127.0.0.1:5173/admin/support`.
- Verified `/admin/support` requires admin sign-in before showing ticket data.
- Signed in as `angelonartey@hotmail.com` and confirmed the mobile-created QA support ticket is visible:
  - Subject: `QA ticket delivery question`.
  - User: `Ticket QA Tester`.
  - Email: `test-ios-20260602-1633@vennuzo.test`.
  - Phone: `+233550005678`.
  - Messages loaded from the mobile app thread.
- Admin desktop notification control tested:
  - Button is present.
  - This browser session returned `Desktop notifications were not enabled.`
  - No web console errors were logged.
- Verified two-way support from the web admin:
  - Reply input enabled `Send reply` after text entry.
  - Sent safe QA reply: `QA admin reply from web support inbox. Please ignore this test message.`
  - Ticket status changed to `Replied`.
  - New message appeared as `Vennuzo support`.
  - Ticket assigned to `angelonartey@hotmail.com`.
  - No browser console errors were logged.
- Returned to the iOS app and signed in again as the QA account.
- Verified Account support chat shows the admin reply:
  - Conversation card changed to `Replied`.
  - Latest preview shows `QA admin reply from web support inbox. Please ignore this test message.`
  - Conversation initially showed `1 new`, then cleared after opening.
  - Full timeline shows both user messages and the `Vennuzo support` admin message.
- Verified the QA user notification preferences persisted after sign-out/sign-in:
  - Push notifications enabled.
  - SMS updates enabled.
  - Promotional campaigns enabled.
  - Promotional push alerts enabled.
  - Music and Nightlife event type preferences remained selected.

### 18:51

- Public web event/share/checkout smoke tested through the local Studio site.
- Verified public event detail page loads without app install or auth:
  - `/events/qa_recurring_workshop` shows public event details, RSVP CTA, QR-entry messaging, share button, and RSVP checkout panel.
  - `/events/qa_featured_map_night` shows paid tiers, remaining quantities, public CTA, QR-entry messaging, and checkout link.
- Verified public RSVP flow:
  - RSVP button starts disabled.
  - Filled `Web QA RSVP Guest`, `0550009876`, and `web-qa-rsvp-20260602@vennuzo.test`.
  - RSVP submitted and confirmed on-page without requiring the app.
  - No Vennuzo browser console errors were logged.
- Finding: public paid checkout accepted invalid buyer contact details.
  - Repro: selected one `General` ticket on `/checkout/qa_featured_map_night`, entered `bad-email` and phone `123`.
  - Result before fix: `Pay GH₵80` enabled and started the Hubtel handoff.
  - Risk: invalid email/phone could create pending orders that cannot receive SMS/email tickets and may fail Hubtel payment contact expectations.
- Fix applied in `studio/src/pages/CheckoutPage.tsx`:
  - Added email validation.
  - Added Ghana mobile normalization/validation for `0XXXXXXXXX` and `233XXXXXXXXX` inputs.
  - Sends normalized `+233...` phone numbers to the order function.
  - Submit button now stays disabled until name, email, and Ghana mobile are valid.
  - `handlePay` also blocks malformed details before creating an order.
- Verified after fix:
  - Invalid `bad-email` + `123` leaves `Pay GH₵80` disabled and stays on `/checkout/qa_featured_map_night`.
  - Valid `web-qa-ticket-20260602@vennuzo.test` + `0550009876` enables payment.
  - Clicking valid payment redirects to Hubtel hosted checkout at `https://pay.hubtel.com/.../direct`.
  - Hubtel page shows `Hubtel Checkout`, `Mobile Money`, `Bank Card`, and `CANCEL`.
  - Payment was not completed.
  - Console noise observed only on the third-party Hubtel page, not on the Vennuzo checkout page.

### 18:59

- Smaller-device pass run on iPhone 17e, iOS 26.5, fresh install.
- XcodeBuildMCP `build_run_sim` timed out while compiling native gRPC pods for a duplicate simulator build. The orphaned build process was stopped and the existing universal simulator app bundle was installed instead.
- Verified installed app binary supports both `x86_64` and `arm64` simulator architectures.
- Verified fresh first-launch state:
  - Onboarding page 1 (`Discover`) fits and is readable.
  - Onboarding page 2 (`Connect`) fits and is readable.
  - Onboarding page 3 (`Create`) fits and is readable.
  - `Skip`, `Continue`, and `Start exploring` controls are visible and tappable.
  - Location permission prompt copy is readable.
  - `Don’t Allow` path enters guest mode without a blank screen or crash.
- Verified small-device guest Explore state:
  - Search field is visible.
  - Account entry is visible.
  - Five bottom tabs fit.
  - Spotlight event opens.
- Verified spotlight contrast on iPhone 17e:
  - `See full event` CTA is visible with dark text on white.
  - Date/location/price chips are readable.
  - Screenshot captured at `/var/folders/xw/v74cphzx21lcclm7v14dbx3c0000gn/T/screenshot_optimized_d45b759f-c02d-40f5-87e8-4ce6739b615b.jpg`.

### 19:25

- Larger-device pass run on iPhone 17 Pro Max.
- Simulator/tool note:
  - The first Pro Max app install and launch timed out through XcodeBuildMCP/CoreSimulator.
  - The delayed install eventually completed, and a later direct launch succeeded.
  - A second alternate Pro Max runtime also timed out during install, confirming the issue was simulator installation service instability rather than Vennuzo app startup.
- Verified larger first-launch state after successful launch:
  - Onboarding page 1 (`Discover`) is readable and unclipped.
  - Onboarding page 2 (`Connect`) is readable and unclipped.
  - Onboarding page 3 (`Create`) is readable and unclipped.
  - Location permission prompt is readable, with `Allow Once`, `Allow While Using App`, and `Don’t Allow`.
  - `Don’t Allow` path enters guest Explore.
- Verified Pro Max guest Explore:
  - Search field is visible.
  - Account entry is visible.
  - Category chips are visible.
  - Featured cards are present.
  - Five bottom tabs fit.
  - Screenshot captured at `/var/folders/xw/v74cphzx21lcclm7v14dbx3c0000gn/T/screenshot_optimized_f6f19f1b-a4c9-488e-b661-c0cdd0b7168f.jpg`.
- Tool/semantics observation: after the Pro Max screenshot, runtime snapshots temporarily returned an empty target set even though the screenshot showed the app UI. I did not continue interacting with stale Pro Max refs.

### 19:31

- Final validation sweep:
  - `flutter analyze`: passed, no issues found.
  - `flutter test`: passed, 15 tests.
  - `npm test` in `functions`: passed, lint plus 25 Jest tests.
  - `npm run build` in `studio`: passed, production Vite build completed.
  - `flutter build ios --simulator --debug`: passed, built `build/ios/iphonesimulator/Runner.app`.
- Runtime logs reviewed:
  - iPhone 17 Pro log: no Vennuzo crash/Firebase error lines found.
  - iPhone 17e log: no Vennuzo crash/Firebase error lines found.
  - iPhone 17 Pro Max log: no Vennuzo crash/Firebase error lines found.
  - Only repeated matched warning was the iOS Simulator/WebKit accessibility duplicate-class warning emitted by the simulator runtime.
- Deployed verified Studio build to Firebase Hosting:
  - `hosting:vennuzo` → `https://vennuzo.web.app`
  - `hosting:studio` → `https://vennuzo-studio.web.app`
  - `hosting:admin` → `https://vennuzo-admin.web.app`

## Current Open Items

- None from this pass that remain unaddressed in code.
- External/tool caveats:
  - Real remote push delivery cannot be fully proven on iOS Simulator/APNs. The app preference/token paths and support/admin notification paths were verified, but production APNs delivery should be confirmed on a physical TestFlight device.
  - Hubtel checkout was tested only to the hosted payment boundary; no real payment was completed.
  - Desktop/browser notification permission returned `Desktop notifications were not enabled.` in the in-app browser session.
