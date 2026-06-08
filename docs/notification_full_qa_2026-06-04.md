# Vennuzo Full Notifications QA - 2026-06-04

Run id: `notif_qa_1780590400466`
Project: `eventora-10063`
Primary test event: `notif_qa_1780590400466_event`

## Production Fixes Applied

- Added Firestore composite indexes for scheduled notification workers:
  - `notification_jobs`: `status ASC`, `scheduledAt ASC`
  - `event_reminders`: `status ASC`, `scheduledAt ASC`
- Updated production app config:
  - `app_config/site.publicUrl`, `publicBaseUrl`, `webUrl`: `https://vennuzo.com`
  - `app_config/share.webBaseUrl`: `https://vennuzo.com`
- Updated backend fallback domains from `https://vennuzo.web.app` to `https://vennuzo.com`.
- Updated `share_link.js` so legacy `share_links` records that point to `vennuzo.web.app` are refreshed to the configured Vennuzo domain.
- Migrated 3 existing stale `share_links` records from `vennuzo.web.app` to `vennuzo.com`.

## Config Verified

- SMS: Hubtel config present, sender ID `Vennuzo`.
- Email: SMTP config present and enabled.
- Push: both QA users had FCM tokens at test time.
- QA users:
  - `angelonartey@hotmail.com`
  - `cyberzonenas93@gmail.com`

## Notification Cases Tested

| Case | Evidence | Result |
| --- | --- | --- |
| Direct push queue | `push_queue/notif_qa_1780590400466_direct_push` | Sent |
| Event ops staff order push | `push_queue/notif_qa_1780590400466_event_ops_push` | Sent |
| RSVP confirmation push | latest queue `f7MnfCghce2VrAET7s96` | Sent, `vennuzo.com` link |
| RSVP organizer alert | `organizer_rsvp_alert` queue docs | Sent |
| Ticket reservation push | `event_ticket_reservation` queue doc | Sent |
| Reservation organizer alert | `organizer_reservation_alert` queue doc | Sent |
| Paid ticket confirmation push | `event_ticket_confirmation` queue doc | Sent |
| Paid ticket SMS | `event_ticket_orders/notif_qa_1780590400466_paid_order.ticketDelivery.sms` | Sent |
| Paid ticket email | `event_ticket_orders/notif_qa_1780590400466_paid_order.ticketDelivery.email` | Sent |
| Ticket sale organizer alert | `organizer_ticket_alert` queue doc | Sent |
| Scheduled campaign push | `notification_jobs/notif_qa_1780590400466_push_job` | Sent, 2 recipients |
| Scheduled campaign SMS | `notification_jobs/notif_qa_1780590400466_sms_job` | Sent, 1 recipient |
| Event reminder push | latest queue `1QP6c7x8dQiIkp6DFLik` | Sent, `vennuzo.com` link |
| Event report superadmin alert | `superadmin_event_reported` queue doc | Sent |
| Payout request superadmin alert | `superadmin_payout_request` queue doc | Sent |
| Organizer application superadmin alert | `superadmin_organizer_application` queue doc | Sent |
| Wallet low balance superadmin alert | `superadmin_wallet_low_balance` queue doc | Sent |
| SMS opt-out write path | Temporary QA opt-out doc | Wrote successfully, then removed |

## Scheduler/Logs

- `processNotificationJobs` successfully processed due campaign jobs after the index deploy.
- `processEventReminderNotifications` successfully processed due reminder jobs after the index deploy.
- Previous missing-index errors stopped after the index deploy/build.
- Startup warnings about missing environment variables are expected because production reads SMS, payment, and SMTP credentials from Firestore app config.

## Cleanup

- Synthetic event was hidden after testing:
  - `status: qa_complete`
  - `visibility: private`
- Synthetic share link was marked inactive.
- Temporary dummy `sms_opt_out/+233555000000` record was deleted.

## Remaining Human Confirmation

- Confirm actual device receipt/display behavior on iOS/Android for the pushed notifications.
- Confirm SMS receipt on `0595494113`.
- Confirm ticket email receipt in `angelonartey@hotmail.com`.
