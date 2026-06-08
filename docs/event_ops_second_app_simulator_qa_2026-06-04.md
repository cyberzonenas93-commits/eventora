# Event Ops Second App Simulator QA - 2026-06-04

## Scope

QA target: Event Ops staff/order-taking "second app" for inventory, open tabs, merchant-collected payments, staff sessions, stock movement, and host notifications.

Production staff URL tested in iOS Simulator Safari:

`https://vennuzo.com/staff/event_ops_staff_qa_1780592391455_event`

Native iOS app bundle tested:

`build/ios/iphonesimulator/Runner.app`

Simulator used:

`iPhone 17 Pro / iOS 26.4 / 2B8D8426-7287-4F7E-8FD1-E1D2BDEFE347`

## Test Data

QA event:

`event_ops_staff_qa_1780592391455_event`

Owner:

`angelonartey@hotmail.com`

Staff credential:

`QA Waiter Ama / Waiter / VIP Floor`

QA PIN:

`4826`

Inventory:

- `QA Champagne Bottle`: cost GHS 300, selling GHS 950, starting stock 6.
- `QA Premium Shisha`: cost GHS 70, selling GHS 180, starting stock 1.

The QA event was marked `private` and `qa_complete` after testing.

## Simulator Evidence

- Staff login screen rendered in iOS Safari: `/Users/angelonartey/Desktop/vennuzo/qa-screenshots/event-ops-staff-simulator-login-after-wait.png`
- Native Vennuzo app launched in iOS Simulator: `/Users/angelonartey/Desktop/vennuzo/qa-screenshots/event-ops-native-app-launch.png`
- Native app coordinate smoke attempt: `/Users/angelonartey/Desktop/vennuzo/qa-screenshots/event-ops-native-after-close-adjusted.png`

## Results

| Area | Result | Notes |
| --- | --- | --- |
| Staff web app loads on iOS Simulator | Pass | `/staff/:eventId` rendered the Vennuzo Staff Mode sign-in page in Safari. |
| Invalid staff PIN | Pass | `startEventOpsStaffSession` returned `functions/permission-denied`. |
| Valid staff PIN | Pass | Session created for `QA Waiter Ama`; inventory and tabs returned. |
| Staff workspace refresh | Pass | `getEventOpsStaffWorkspace` returned listed inventory and current tab state. |
| Open staff tab | Pass | Bottle tab opened for `Simulator VIP Table 9`; bottle stock decremented from 6 to 4. |
| Merchant-collected MoMo close | Pass | Bottle tab closed with payment method `Merchant MoMo`. |
| Oversell protection | Pass | Shisha quantity 2 rejected because only 1 unit remained. |
| Sell final unit | Pass | Shisha tab opened for quantity 1; stock decremented to 0. |
| Cash close | Pass | Shisha tab closed with payment method `Cash`; staff closed-sales total updated. |
| Inventory movements | Pass | One movement record was created per opened tab. |
| Staff session security | Pass | Session persisted with `tokenHash`; raw token not stored. |
| Push coverage | Pass | Push jobs for staff sign-in, order opened, low stock, and tab closed reached `sent`. |
| Native app launch | Pass | Existing iOS simulator bundle installed/launched successfully. |
| Native Event Ops staff mode | Gap | Native app links out to Event Ops Studio; the actual staff/order-taking app is web, not native. |
| Native coordinate navigation | Inconclusive | Xcode UI snapshot transport was down; coordinate taps were unreliable against the simulator surface. |
| Organizer authenticated report callable | Blocked | Local Admin SDK can read/write Firestore but cannot mint Firebase Auth custom tokens without a service-account signing credential. |

## Firestore Side Effects Verified

Final inventory:

- `QA Champagne Bottle`: stock `4`.
- `QA Premium Shisha`: stock `0`.

Closed tabs:

- `Simulator VIP Table 9`: `QA Champagne Bottle x 2`, GHS `1900`, payment `Merchant MoMo`.
- `Simulator Terrace`: `QA Premium Shisha x 1`, GHS `180`, payment `Cash`.

Total closed sales recorded:

`GHS 2080`

Push queue kinds observed with `sent` status:

- `event_ops_staff_signed_in`
- `event_ops_staff_order_created`
- `event_ops_low_stock`
- `event_ops_staff_tab_closed`

## Product/UX Findings

1. The "second app" currently exists as a mobile web staff app at `/staff/:eventId`, not as a separate native iOS staff workspace.
2. Staff Mode supports opening tabs and closing them after payment, but it does not show closed-tab history after closure.
3. Staff Mode item options do not visibly show remaining stock in the selector, which can make live service less confident.
4. Staff Mode has no visible barcode/QR/check-in affordance because this is inventory/order-focused, not ticket verification.
5. Native app Event Ops exposure is host-side only: `Open Event Ops` launches Studio via URL launcher.
6. Authenticated organizer callable QA needs either a signed-in browser automation session or a local service-account credential for Firebase custom token minting.

## Recommendation

Treat the web staff app as the current production Event Ops second app and ship it as a mobile web/PWA workflow for waiters.

For a true 10/10 native setup, add a native Staff Mode route to the iOS app that detects staff credentials and shows a separate workspace with:

- PIN/session login.
- Open tabs.
- Close paid tabs.
- Stock-aware item picker.
- Closed-tab history.
- Staff sales total.
- Low-stock warnings.
- Offline-safe queue later for weak venue networks.
