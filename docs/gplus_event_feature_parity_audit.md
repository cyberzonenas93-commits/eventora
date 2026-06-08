# GPlus Event Feature Parity Audit For Vennuzo

Date: 2026-06-02

This audit compares the event-related GPlus product surface with the current
Vennuzo app, Studio website, and Firebase Functions code. It avoids historical
customer/import data found in the GPlus repo and focuses only on product
features, source files, functions, collections, and user/admin behavior.

## Source Scope

Primary GPlus repo reviewed: `/Users/angelonartey/Desktop/gplus-app`.

Key GPlus event sources:

- Flutter event UI: `lib/screens/events_screen_user.dart`,
  `lib/screens/shared_event_screen.dart`, `lib/screens/rsvp_screen.dart`,
  `lib/screens/my_rsvps_screen.dart`, `lib/screens/event_ticket_checkout_sheet.dart`,
  `lib/screens/my_event_tickets_screen.dart`, `lib/screens/ticket_detail_screen.dart`,
  `lib/screens/book_table_screen.dart`, `lib/screens/book_table_packages_screen.dart`,
  `lib/screens/table_booking_form_screen.dart`, `lib/screens/my_bookings_screen.dart`,
  `lib/screens/booking_details_screen.dart`.
- Flutter admin/organizer UI: `lib/screens/events_screen.dart`,
  `lib/screens/create_event_screen.dart`, `lib/screens/edit_event_screen.dart`,
  `lib/screens/rsvp_list_screen.dart`, `lib/screens/admin/event_ticket_sales_screen.dart`,
  `lib/screens/admin/event_ticket_lookup_screen.dart`,
  `lib/screens/admin/event_ticket_print_screen.dart`,
  `lib/screens/admin/issue_free_tickets_screen.dart`,
  `lib/screens/admin/award_tickets_screen.dart`,
  `lib/screens/admin/pending_event_changes_screen.dart`,
  `lib/screens/admin/sms_invite_campaign_screen.dart`,
  `lib/screens/admin/scheduled_blasts_screen.dart`,
  `lib/screens/admin/promoters_screen.dart`,
  `lib/screens/admin/flyer_generator_screen.dart`,
  `lib/screens/admin/flyer_studio_screen.dart`,
  `lib/screens/admin_table_management_screen.dart`,
  `lib/screens/admin_table_package_bookings_screen.dart`,
  `lib/screens/admin/member_scan_analytics_screen.dart`,
  and `lib/screens/organizer/*`.
- GPlus Functions: `functions/web-event-tickets.js`, `functions/hubtel.js`,
  `functions/public_ticket.js`, `functions/table-bookings.js`,
  `functions/table-package-bookings.js`, `functions/organizer_rsvp_feed.js`,
  `functions/organizer-sales.js`, `functions/promo_campaigns.js`,
  `functions/sms_invite_system.js`, `functions/whatsapp_blast.js`,
  `functions/promoter_distribution.js`, `functions/promo_kit_distribution.js`,
  `functions/flyer_engine.js`, `functions/flyer_external.js`,
  `functions/event_ai.js`, `functions/membership.js`,
  `functions/issue-free-tickets-sms.js`, and
  `functions/award-tickets-to-user.js`.
- GPlus public websites: `public-rsvp/index.html`,
  `public-rsvp/organizer-feed.html`, `public-tickets/index.html`,
  `public-tickets/ticket.html`, `public-site/reserve.html`,
  `public-site/promo-kit.html`, `public-organizers/index.html`,
  `public-organizers/organizer-sales.html`, `public-promo/index.html`,
  and `public-flyers/index.html`.

Current Vennuzo sources reviewed:

- Flutter app: `lib/features/discover/discover_screen.dart`,
  `lib/features/events/event_detail_screen.dart`,
  `lib/features/events/event_editor_screen.dart`,
  `lib/features/tickets/tickets_screen.dart`,
  `lib/features/admin/admin_tickets_screen.dart`,
  `lib/features/promotions/promotions_screen.dart`,
  `lib/features/creative/creative_services_screen.dart`,
  `lib/features/organizer/*`, and domain/service models.
- Studio website: `studio/src/App.tsx`, `studio/src/pages/*`,
  `studio/src/lib/portalData.ts`, `studio/src/lib/types.ts`,
  and `studio/src/lib/adminConsole.ts`.
- Vennuzo Functions: `functions/event_payments.js`,
  `functions/event_notifications.js`, `functions/share_link.js`,
  `functions/creative_services.js`, `functions/billing.js`,
  `functions/admin_console.js`, and `functions/organizer_applications.js`.

## Executive Result

Vennuzo has strong parity for core multi-organizer events: public event pages,
shareable event URLs, paid web ticket checkout without installing the app,
Hubtel ticket payment, QR ticket issuance, SMS/email ticket delivery, app
discovery, organizer Studio, owned-audience paid push/SMS campaigns, campaign
wallets, brand-based paid flyer generation, billing, payouts, CRM contacts, and
admin collection oversight.

Vennuzo does not yet have full parity with the venue-specific GPlus systems.
The largest missing areas are table reservations, membership/discount passes,
promoter affiliate operations, GPlus-style promo game mechanics, WhatsApp/SMS
command-center depth, public RSVP/table upsell pages, public ticket viewer
pages, organizer share dashboards, and dedicated ticket recovery/free-ticket
admin tooling.

Because GPlus is a single-venue nightlife app and Vennuzo is a multi-organizer
event platform, these should be ported as tenant-safe Vennuzo equivalents rather
than copied as G+ branded or single-venue flows.

## User-Facing Parity Matrix

| GPlus user feature | GPlus behavior | Vennuzo status | Notes / required Vennuzo work |
| --- | --- | --- | --- |
| Event discovery | App home/explore, upcoming strip, event splash, public website event sections. | Present | Vennuzo has app discovery, featured/announcement placements, public event list, and public detail pages. |
| Event detail | Flyer/media, event metadata, RSVP/ticket CTA, share sheet, reminders. | Present | Vennuzo has event detail, social posts, map, tickets, reminders, save/share/report. |
| Public event page | `gplusnightclub.com`, RSVP site, tickets site. | Present for details and paid checkout | Vennuzo has `/events` and `/events/:eventId`; non-ticket RSVP still points users toward the app instead of offering a full public web RSVP form. |
| Public RSVP / guest list | Public RSVP form, table package upsell, app download prompt, public RSVP tracking. | Partial | Vennuzo has app RSVP and Firestore RSVP records. Add public web RSVP form for non-ticket events and optional table upsell. |
| RSVP confirmation | Push/SMS confirmations and organizer alerts. | Present | Vennuzo functions send RSVP confirmation push/SMS and organizer/superadmin alerts. |
| Event reminders | App reminder button plus scheduled event reminders. | Present | Vennuzo has reminders and scheduled push/SMS reminder processing. |
| Paid ticket tiers | Multi-tier paid checkout in app and web. | Present | Growth plan unlocks advanced ticketing; web checkout supports paid tiers. |
| Free reservations / pay at gate | Free tiers create reserved/unpaid tickets and cash-at-gate flow. | Partial | Vennuzo app supports zero-price reservations and cash-at-gate admission. Public web checkout currently ignores zero-price tiers and requires a paid selection. |
| Web ticket purchase without app | Public web ticket checkout via Hubtel. | Present | Vennuzo `/checkout/:eventId` supports browser purchase without app download. |
| Ticket confirmation | QR ticket in app, SMS, email, public ticket link. | Present/Partial | Vennuzo sends SMS/email and has `/checkout/:orderId/confirmation`. Add a simpler `/tickets/:orderId` public ticket viewer and `getPublicTicket` HTTP endpoint for GPlus parity. |
| My tickets | App wallet with QR details and status. | Present | Vennuzo has ticket wallet and payment status screens. |
| Ticket sharing | Share/copy ticket link. | Present/Partial | Vennuzo builds public ticket links to confirmation route. Dedicated public ticket route still missing. |
| QR entry | QR token per ticket and gate admission. | Present/Partial | Vennuzo writes `event_ticket_lookups` and has admin ticket desk. Add server callable `validateEventTicket` and `confirmCashForReservationTicket` for stronger staff-device parity. |
| Table booking | App table booking, table package upsell, web reserve page. | Missing | Vennuzo only has RSVP `bookTable` intent and table-package flyer generation. Needs real `tablePackages`, `table_bookings`, deposits, full payment, callbacks, availability, and customer booking screens. |
| Table package booking | Public/app package booking with deposit/full payment and discounts. | Missing | Need `createTablePackageBooking`, table package inventory, booking status, Hubtel callbacks, customer/staff notifications. |
| Bill split | Booking details can split a bill into Hubtel links. | Missing | Needs split participants, payment links, callback reconciliation. |
| Pre-orders | Table booking supports pre-order items. | Missing | Needs menu/item selection and booking pre-order model. |
| GCoins / points payment | Event tickets and table packages can be paid with GCoins in GPlus. | Missing | Vennuzo has campaign/creative wallet, not attendee reward wallet. Decide whether Vennuzo needs attendee credits. |
| Membership pass | Member onboarding, QR pass, priority RSVP, discounts, welcome perks. | Missing | Vennuzo has `organization_members` for staff/organizer roles, not attendee memberships. Needs tenant-scoped membership/pass model if required. |
| Member ticket discount | Ticket checkout supports member discount toggle and redemption. | Missing | Needs organizer membership/pass rules, scan/commit/release redemption functions, and checkout discount application. |
| Promo participation | Raffles, leaderboards, referral program, challenges, flash offers, birthday club, check-in challenges. | Partial/Missing | Vennuzo has paid delivery campaigns and placements, but not GPlus promo game mechanics. |
| Promo opt-in | Audience preferences and opt-out handling. | Present | Vennuzo account prefs gate promotional push by event type/city/tags and SMS opt-out is implemented. |
| WhatsApp reminders/blasts | WhatsApp blast system, inbox/chat, webhook, RSVP reminders. | Missing | Vennuzo currently uses push/SMS/email/support chat, not WhatsApp campaign delivery. |
| Share links | Share-link function with OG page and web fallback. | Present/Partial | Vennuzo event share links exist. GPlus also supports organizer feed and ticket/share variants. |
| Public promo kit | Shareable promo kit page with flyer/video/ticket/RSVP assets. | Missing | Vennuzo creative services has generated assets, but no public promo-kit bundle page. |
| Social/event media | Posts, event photos, saves, reviews. | Present | Vennuzo has social feed, saves, reviews, event post grid. |

## Organizer/Admin Parity Matrix

| GPlus organizer/admin feature | GPlus behavior | Vennuzo status | Notes / required Vennuzo work |
| --- | --- | --- | --- |
| Organizer application | Users apply, admins review/approve. | Present | Vennuzo has organizer applications, approvals, workspace setup, role/face chooser. |
| Organizer portal | Flutter and web organizer dashboards. | Present | Vennuzo has in-app organizer screens and Studio website. |
| Event CRUD | Create/edit/update/delete events, tiers, flyers, recurring groups. | Present/Partial | Vennuzo app supports recurrence and maps; Studio currently saves recurrence as `none` and lacks full recurring occurrence management. |
| Event AI from flyer | Extract event details and table packages from flyer. | Missing | GPlus has `extractEventDetailsFromFlyer` and `extractTablePackagesFromFlyer`; Vennuzo does not. |
| Pending event changes | Organizer changes can be reviewed/approved. | Missing | Vennuzo has organizer approval but no `pending_event_changes` workflow. |
| RSVP list | Admin/organizer RSVP inspection and member badges. | Partial | Vennuzo has RSVP records/CRM/contact summaries; add dedicated live RSVP list/feed and web RSVP viewer. |
| Shared organizer RSVP feed | Public link for organizer to watch RSVP/ticket flow. | Missing | Add `organizer_rsvp_feed` share type and `getSharedOrganizerRsvpFeed` callable/page. |
| Organizer sales dashboard | Public access link for event sales/bar-sales summaries. | Partial/Missing | Vennuzo Studio orders/payments cover organizer-owned ticket sales. It lacks shareable access links and GPlus venue POS/bar-sales window reporting. |
| Ticket sales screen | Ticket orders, tiers, revenue. | Present | Vennuzo has Studio orders, overview metrics, admin ticket desk. |
| Ticket lookup/scanning | Lookup QR, validate, admit, collect cash. | Present/Partial | Vennuzo has admin lookup/admit and lookup docs. Add server callable and scanner-camera flow for full GPlus parity. |
| Ticket printing | Admin ticket print screen. | Missing | Add printable ticket batch/export if needed. |
| Issue free tickets | Admin grants free tickets and sends SMS. | Missing | Add admin free-ticket/comp issuance flow and SMS delivery. |
| Award tickets | Admin awards tickets to user(s). | Missing | Add user search, award flow, audit logs. |
| Ticket recovery | Manual recovery/credit utilities. | Missing | Add safe admin recovery function instead of ad hoc scripts. |
| Table package admin | Manage packages, bookings, availability, deposits. | Missing | Required for table parity. |
| Waiter/table ops | Staff table status, reserved/available, package management. | Missing | Required if Vennuzo needs venue/table operations. |
| Campaign delivery | Push/SMS campaigns, schedules, audience estimates. | Present | Vennuzo has owned-audience push/SMS campaigns, schedule, estimates, wallet reservations/charges/releases. |
| Premium placements | Featured banner and fullscreen announcement. | Present | Vennuzo supports featured and announcement channels. |
| SMS invite campaigns | Rich SMS campaign engine, recipient materialization, automatic event reminders, opt-out. | Partial | Vennuzo has simpler owned-audience SMS jobs, opt-out, and test SMS. GPlus has deeper recipient materialization, enrichment, inbound, command-center features. |
| WhatsApp blasts | Create, schedule, process, analytics. | Missing | Not in Vennuzo. |
| Promo campaign mechanics | Raffles, leaderboards, winners, promo codes, birthday club, points/check-in triggers. | Missing/Partial | Vennuzo currently focuses on delivery/placement campaigns. |
| Promo kit distribution | Send promo kits to staff/promoters. | Missing | Needed for GPlus parity around flyer/video/event link distribution. |
| Promoter management | Promoter CRUD, opt-out, assignment, dashboards, payouts. | Partial | Vennuzo Studio has a Growth-gated placeholder page only. Needs live partner records, event links, attribution, commissions, payouts. |
| Public promoter portal | Promoter login/dashboard with assignments and earnings. | Missing | GPlus `public-promo` equivalent not present. |
| Ad promotions | Ad wallet, campaigns, review, serving, analytics. | Partial | Vennuzo has premium event placements and campaign wallet, not a full vendor ad serving network. |
| Creative flyer engine | Flyer Studio/editor, external flyer site, brand config, generated assets, table package flyers. | Present/Partial | Vennuzo has Gemini generation, brand config, paid wallet, flyer/table-flyer jobs, edits/redesigns. It lacks the full GPlus public-flyers Fabric editor, reference library, vote/preview tooling, and generated prompt asset workflow. |
| Membership admin | Member list, demographics, scan analytics, redemption logs. | Missing | Needs tenant-scoped membership product first. |
| Hubtel monitor/config | Hubtel monitoring/config and balances. | Partial | Vennuzo uses Hubtel for tickets/wallet/billing and has admin config collections, but lacks GPlus-style Hubtel monitor dashboards. |
| Payouts | Organizer/merchant payout support. | Present/Partial | Vennuzo has payout profile and payout request support. Visible Studio payout flow is less complete than GPlus venue finance tools. |
| Admin console | Data manager, roles, pricing, campaign oversight. | Present | Vennuzo has React `/admin` console with role-gated collection access. |
| Support chat | App support chat and admin notifications. | Present | Vennuzo added support chat/admin support surface. |

## Concrete Missing Build List

### P0: Required To Claim Full GPlus Event Parity

1. Public web RSVP flow for non-ticket events.
2. Public ticket viewer route and HTTP/callable ticket lookup endpoint.
3. Server-side `validateEventTicket` and `confirmCashForReservationTicket`
   functions with role checks and audit logs.
4. Free/comp ticket issuance with SMS/email delivery.
5. Shareable organizer RSVP/ticket feed link.
6. Partner/promoter live model: partner profiles, event links, attribution,
   clicks, ticket orders, revenue, commission/payout state.
7. Table reservation engine: `tablePackages`, `table_bookings`,
   `table_package_bookings`, web/app booking UI, Hubtel callbacks,
   availability, staff/admin management.

### P1: Important GPlus Growth/Ops Parity

1. GPlus promo mechanics: raffle, leaderboard, referral campaign, challenge,
   flash offer, birthday club, check-in challenge, promo-code redemption.
2. Promo-kit bundle page and distribution to staff/promoters.
3. WhatsApp campaign/reminder stack with consent, templates, analytics, and
   opt-out handling.
4. Event AI extraction from flyer and table package flyer.
5. Pending event change approval workflow.
6. Ticket print/export/recovery admin tools.
7. Recurring occurrence management in Studio, not only in the Flutter editor.

### P2: Venue-Specific Or Optional For Vennuzo

1. Membership/pass product with discount QR, scan analytics, redemption limits,
   and member demographics.
2. Attendee reward wallet/GCoins/points and check-in rewards.
3. Venue POS/bar-sales reporting window for organizer sales access.
4. Full GPlus-style public flyer editor/reference/voting site.
5. SMS command center with inbound message management and name enrichment.

## Collections Vennuzo Already Uses

- `events`
- `event_occurrences`
- `event_rsvps`
- `event_ticket_orders`
- `event_ticket_lookups`
- `event_reminders`
- `promotion_campaigns`
- `notification_jobs`
- `push_queue`
- `audience_contacts`
- `sms_opt_out`
- `promo_packages`
- `advertiser_wallets`
- `wallet_transactions`
- `creative_brand_configs`
- `flyer_jobs`
- `flyer_sessions`
- `organizer_applications`
- `organizations`
- `organization_members`
- `payout_requests`
- `billing_orders`
- `billing_events`
- `support_threads`

## Collections/Surfaces To Add For Full Parity

- `tablePackages`
- `table_bookings`
- `table_package_bookings`
- `partner_profiles` or `promoters`
- `partner_assignments` or `promoter_assignments`
- `partner_clicks`
- `partner_payouts`
- `organizer_feed_links` or `share_links` with type `organizer_rsvp_feed`
- `public_ticket_views` audit logs, if public ticket opens should be tracked
- `promo_referrals`
- `promo_entries`
- `promo_redemptions`
- `promo_leaderboards`
- `promo_winners`
- `whatsapp_blasts`
- `whatsapp_recipients`
- `whatsapp_messages`
- `pending_event_changes`
- `ticket_admin_actions`
- `ticket_recovery_jobs`
- `membership_passes` / `organization_memberships`
- `membership_redemptions`
- `membership_scan_logs`

## Recommended Implementation Order

1. Finish public/event ticket basics first:
   web RSVP, public ticket viewer, validation callable, comp tickets.
2. Build organizer share/reporting:
   RSVP feed link, ticket sales access link, partner attribution primitives.
3. Build table reservations:
   packages, bookings, web/app checkout, admin/staff operations.
4. Expand promotions:
   promo mechanics, promo kits, WhatsApp, richer SMS command tooling.
5. Decide whether membership/rewards belong in Vennuzo as multi-tenant products.

## Bottom Line

Not all GPlus event-related features are present in Vennuzo yet. The core event
marketplace, ticketing, Hubtel checkout, delivery notifications, campaign wallet,
owned-audience push/SMS, creative flyer generation, Studio, billing, payouts, and
admin console are present. The full GPlus event operating system includes several
additional venue, table, membership, promoter, promo-game, WhatsApp, and staff
ops systems that still need to be built as Vennuzo-native multi-organizer
features.
