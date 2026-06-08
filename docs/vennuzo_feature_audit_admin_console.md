# Vennuzo Feature Audit and Admin Console Coverage

Date: 2026-06-02

This audit maps the current Vennuzo product surface to the new React admin console at `/admin` and the Firebase Hosting `admin` target for `admin.vennuzo.com`.

## Product Surfaces

| Surface | Screens / entry points | Primary records | Admin console coverage |
| --- | --- | --- | --- |
| Public web marketplace | `HomePage`, `PublicEventsPage`, `PublicEventDetailPage` | `events`, `event_occurrences`, `share_links` | `/admin/data/events`, `/admin/data/event_occurrences`, `/admin/data/share_links` |
| Public checkout | `CheckoutPage`, `CheckoutConfirmationPage` | `event_ticket_orders`, `event_ticket_lookups` | `/admin/data/event_ticket_orders`, `/admin/data/event_ticket_lookups` |
| Organizer Studio | `OverviewPage`, `EventsPage`, `EventEditorPage`, `OrdersPage`, `ContactsPage`, `PaymentsPayoutsPage`, `PromotePage`, `CreativeServicesPage`, `BillingPage`, `SettingsPage` | `organizations`, `organization_members`, `events`, `event_ticket_orders`, `event_rsvps`, `promotion_campaigns`, `advertiser_wallets`, `wallet_transactions`, `creative_brand_configs`, `flyer_jobs`, `flyer_sessions`, `billing_orders`, `billing_events` | `/admin/overview`, `/admin/data/*`, `/admin/campaigns`, `/admin/pricing` |
| Flutter attendee app | onboarding, discover, event detail, tickets, saved events, social feed/profile, account | `users`, `events`, `event_rsvps`, `event_ticket_orders`, `event_reminders`, `event_saves`, `event_reactions`, `event_reviews`, `event_posts`, `post_likes`, `post_comments`, `social_follows` | `/admin/data/users`, `/admin/data/events`, `/admin/data/event_rsvps`, `/admin/data/event_ticket_orders`, `/admin/data/event_reminders`, `/admin/data/event_saves`, `/admin/data/event_reviews`, `/admin/data/event_posts`, `/admin/data/post_likes`, `/admin/data/post_comments`, `/admin/data/social_follows` |
| Flutter organizer/admin app | manage, host access, promotions, creative services, admin dashboard/events/tickets/campaigns/settings/approvals | same as Studio plus `admins`, `organizer_applications`, `event_reports`, `notification_jobs`, `push_queue` | `/admin/approvals`, `/admin/data/admins`, `/admin/data/organizer_applications`, `/admin/data/event_reports`, `/admin/data/notification_jobs`, `/admin/data/push_queue` |
| Payments and billing | Hubtel ticket checkout, wallet top-up, subscription checkout, payout requests | `event_ticket_orders`, `advertiser_wallets`, `wallet_transactions`, `billing_orders`, `billing_events`, `payout_requests`, `app_config/hubtel` | `/admin/data/event_ticket_orders`, `/admin/data/advertiser_wallets`, `/admin/data/wallet_transactions`, `/admin/data/billing_orders`, `/admin/data/billing_events`, `/admin/data/payout_requests`, `/admin/data/app_config` |
| Marketing and notifications | push queue, SMS campaigns, imported audiences, opt-out webhook, reminders | `promotion_campaigns`, `audience_contacts`, `notification_jobs`, `push_queue`, `sms_opt_out`, `promo_packages`, `event_reminders` | `/admin/campaigns`, `/admin/optout`, `/admin/pricing`, `/admin/data/promotion_campaigns`, `/admin/data/audience_contacts`, `/admin/data/notification_jobs`, `/admin/data/push_queue`, `/admin/data/sms_opt_out` |
| Creative services | brand config, flyer jobs, delivered sessions, edit/redesign quotas | `creative_brand_configs`, `flyer_jobs`, `flyer_sessions`, `wallet_transactions` | `/admin/data/creative_brand_configs`, `/admin/data/flyer_jobs`, `/admin/data/flyer_sessions`, `/admin/data/wallet_transactions` |
| Safety and moderation | event reports, social posts/comments/reviews | `event_reports`, `event_posts`, `event_reviews`, `post_comments` | `/admin/data/event_reports`, `/admin/data/event_posts`, `/admin/data/event_reviews`, `/admin/data/post_comments` |
| Platform system | app config, pricing, Hubtel, rate limits, admin auth | `app_config`, `promo_packages`, `admins`, `users`, `rate_limits` | `/admin/data/app_config`, `/admin/pricing`, `/admin/data/admins`, `/admin/data/users`, `/admin/data/rate_limits` |

## Admin Console Implementation

- `firebase.json` already defines a Hosting target named `admin` pointing to `studio/dist`. The React app now redirects `admin.vennuzo.com` root traffic to `/admin/overview`.
- `/admin/overview` is the operational audit dashboard with counts, recent records, and every managed feature group.
- `/admin/data/:collectionId` is the superadmin data manager. It supports whitelisted Firestore top-level collections and collection-group records.
- `/admin/approvals`, `/admin/pricing`, `/admin/campaigns`, and `/admin/optout` preserve the existing focused superadmin tools.
- `/superadmin/*` legacy paths redirect to `/admin/*`.

## Backend Controls

New callables in `functions/admin_console.js`:

- `bootstrapOwnerAdmin` creates/promotes the owner superadmin account for the allow-listed owner email.
- `getAdminConsoleOverview` returns counts, recent records, and collection metadata.
- `listAdminConsoleDocuments` lists whitelisted platform collections and collection groups.
- `saveAdminConsoleDocument` lets superadmins create or update whitelisted records.
- `deleteAdminConsoleDocument` lets superadmins delete whitelisted records, excluding their own `users/{uid}` and `admins/{uid}` documents.
- `updateAdminAuthUser` lets superadmins update Firebase Auth email/display name/password/disabled status.

The owner email `angelonartey@hotmail.com` is already allow-listed in the existing superadmin checks and the new admin console bootstrap. For production, set `VENNUZO_OWNER_BOOTSTRAP_PASSWORD` or `VENNUZO_OWNER_BOOTSTRAP_PASSWORD_SHA256` in the Functions environment and remove reliance on the fallback hash after the first owner account is established.

