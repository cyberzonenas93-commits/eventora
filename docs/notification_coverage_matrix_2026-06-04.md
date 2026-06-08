# Vennuzo Notification Coverage Matrix - 2026-06-04

## Covered Before This Pass

| Workflow | Recipient | Channel |
| --- | --- | --- |
| RSVP created | attendee | push, SMS when enabled |
| RSVP created | organizer | push |
| Cash-at-gate ticket reservation | buyer | push, SMS when available |
| Ticket reservation created | organizer | push |
| Paid ticket confirmation | buyer | push, SMS, email |
| Paid ticket sale | organizer | push |
| Scheduled event reminder | attendee | push, SMS when enabled |
| Campaign launched/scheduled | audience | push, SMS |
| Event reported | superadmins | push |
| Payout requested | superadmins | push |
| Payout sent/failed | superadmins | push |
| Organizer application submitted | superadmins | push |
| Organizer application reviewed | applicant | push |
| New event published | superadmins | push |
| Payment webhook alert | superadmins | push |
| Wallet low balance | superadmins | push |
| Support user message | support admins | push |
| Support admin reply | user | push |
| Event team invite created | invited staff | email |
| Event ops order opened | organizer | push |

## Added In This Pass

| Workflow | Recipient | Channel |
| --- | --- | --- |
| Flyer generation complete | creator | push |
| Flyer generation failed/refunded | creator | push |
| Flyer generation failed | superadmins | push |
| Flyer video generation complete | creator | push |
| Flyer video generation failed/refunded | creator | push |
| Flyer video generation failed | superadmins | push |
| Event team invite accepted | organizer | push |
| Event ops staff signed in | organizer | push |
| Event ops tab closed by organizer/admin | organizer | push |
| Event ops staff tab closed | organizer | push |
| Event ops inventory crosses low stock/sold out | organizer | push |
| Free table package booking confirmed | organizer | push |
| Paid table package booking confirmed | organizer | push |

## Intentionally Quiet

| Workflow | Reason |
| --- | --- |
| Ticket validation scans | Too noisy for every successful scan; scan logs and analytics capture the event. |
| Pending table package checkout | Avoids notifying hosts for abandoned or unpaid checkouts. |
| Event ops report generated synchronously | The caller gets the report immediately; no async wait state. |
| Campaign estimate/list/read calls | Informational only; no state change. |

## Required Runtime Conditions

- Recipient must have `users/{uid}.fcmToken`.
- Recipient notification preferences must not disable push.
- SMS requires valid Ghana phone and Hubtel config.
- Email requires SMTP config.
- Public links should use `https://vennuzo.com`.
