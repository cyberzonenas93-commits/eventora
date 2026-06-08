# Vennuzo Production Readiness QA - 2026-06-04

## Backend fixes deployed

- Staff Mode now shows remaining stock in the item picker, blocks sold-out/over-stock orders, and shows recent closed tabs for staff.
- Team invite acceptance bug fixed by loading the event before notifying the organizer.
- Production monitoring added for failed/stuck push queue records, notification jobs, ticket recovery, creative jobs, video jobs, payouts, stale ticket payments, and stale table package payments.
- Firestore rules hardened for buyer-created ticket orders, server-only ops access codes, and production monitor alerts.

## Verified

- Free ticket issue path:
  - QA order `qWipNyCkqtrgcnzaU6JG`
  - `paymentStatus=paid`
  - ticket generated.
- Paid ticket checkout creation:
  - QA order `4InxyJvgzh2V2LmraYuh`
  - Hubtel checkout created.
- Failed Hubtel callback:
  - callback returned `success=false`
  - order marked `paymentStatus=failed`
  - no tickets issued.
- Ticket verification:
  - valid QR lookup passed.
  - first admit passed.
  - duplicate admit returned already-admitted state.
  - invalid QR returned not found.
  - scan logs were written.
- Event Ops authenticated flow:
  - organizer setup saved.
  - custom staff access code worked.
  - staff credential worked.
  - inventory order reduced stock.
  - tab close worked.
  - end-of-event report generated.
- Push backend:
  - representative ticket, RSVP, like, staff order, low stock, tab close, team invite, reminder, and campaign push jobs processed with `sentCount=1` and `failedCount=0`.
- Monitoring:
  - `monitorProductionOperations` is scheduled every 15 minutes in `eventora-10063`.
  - forced Scheduler run completed.
  - monitor opened production alerts for stale ticket payments and failed push delivery.
- Auth hosting:
  - `https://vennuzo.com/__/auth/handler` returns `200`.

## Cleanup completed

- QA events `prod_ready_qa_1780595188170_event` and `event_ops_auth_qa_1780595340654_event` were marked private/unpublished.
- Temporary Event Ops access/team docs were removed.
- Temporary QA auth users were deleted.
- The temporary monitor push record was removed.

## Still needs real-world QA

- Successful live Hubtel payment, settlement callback, refund, and payout/send-money path need supervised live payment or Hubtel sandbox credentials.
- Real-device push receipt still needs user confirmation on an installed device/TestFlight build.
- Apple/Google OAuth must be clicked through on `vennuzo.com`, iOS app, and TestFlight with an actual browser/device session.
- The current Event Ops staff workspace is web/PWA; a native iOS staff workspace is still a product build item.
- Fully server-only ticket lookup writes need a mobile callable migration before rules can block all direct writes.
- Host analytics and promotions attribution need production-data aggregation validation over real campaign/payment traffic.
