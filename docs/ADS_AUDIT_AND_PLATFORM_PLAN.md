# Audience Ads / Event Promotion Platform – Audit & Plan

This document summarizes the audit of GPlus and Vennuzo for event promotion (SMS, push, wallet, Hubtel), what already works, what is missing, and the plan to turn Vennuzo into a paid event advertising platform with wallet-based campaign funding and 50% margin on SMS.

---

## 1. AUDIT SUMMARY

### 1.1 Vennuzo (this repo)

| Area | Status | Location / Notes |
|------|--------|------------------|
| **Event creation / management** | ✅ Implemented | Flutter: event editor; Studio: Events, EventEditorPage, portalData |
| **Event sharing** | ✅ Implemented | `share_links`, `buildEventLink` in event_notifications.js; Flutter ShareLinkService |
| **Push notifications** | ✅ Implemented | `push_queue` → `processPushQueue`, FCM sendEachForMulticast; tokens in `users.fcmToken` |
| **SMS sending** | ✅ Implemented | `event_notifications.js`: getHubtelSmsConfig (file + Firestore `app_config/hubtel`), sendHubtelSms, POST to smsc.hubtel.com, fallback GET |
| **Hubtel payment (tickets)** | ✅ Implemented | `event_payments.js`: initiateHubtelCheckout, hubtelCallback, status check; no wallet – direct order payment |
| **Campaign launch** | ✅ Implemented | `launchEventNotificationCampaign` callable: creates `promotion_campaigns` + `notification_jobs`, dispatches push/SMS to event audience (RSVPs + ticket buyers); audience from getEventAudience (marketingOnly), no PII exposed to client |
| **Notification jobs** | ✅ Implemented | `processNotificationJobs` (scheduled), dispatchNotificationJob (push → push_queue, SMS → sendHubtelSms) |
| **Flutter promote UX** | ✅ Implemented | campaign_composer_sheet.dart, vennuzo_cloud_sync_service launchPromotionCampaign |
| **Studio promote UX** | ❌ Missing | No “Promote event” flow in web dashboard |
| **Wallet for organizers** | ❌ Missing | No advertiser wallet; no preload-via-Hubtel for campaigns |
| **SMS pricing / margin** | ❌ Missing | SMS sent at provider cost; no 50% margin, no per-message sell price |
| **Campaign pricing packages** | ❌ Missing | No Starter Boost, Growth, etc.; no configurable pricing in admin |
| **Audience estimator (counts only)** | ⚠️ Partial | getEventAudience is server-only; no callable that returns pushCount/smsCount for UI |
| **Consent / opt-out** | ⚠️ Partial | marketingOnly filters by notificationPrefs.marketingOptIn; no dedicated suppression list or SMS opt-out collection |
| **Hubtel config** | ✅ Present | `hubtel_sms_config.js` (env / .env.local); Firestore `app_config/hubtel` fallback |

### 1.2 GPlus (gplus-app)

| Area | Status | Location / Notes |
|------|--------|------------------|
| **Event promotion (push)** | ✅ Implemented | engagement_push_notifications.js: event_promotion, event_countdown, discovery; push_queue pattern |
| **SMS campaigns** | ✅ Implemented | sms_invite_system.js: createSmsInviteCampaign, materializeSmsInviteRecipients, startSmsInviteCampaign, dispatcher; sendHubtelSms; audience from event_invite_contacts |
| **SMS audience** | ✅ Implemented | event_invite_contacts, backfill from event_rsvps, event_ticket_orders, etc.; sms_invite_opt_out |
| **Wallet (G-Spot)** | ✅ Implemented | gspot_wallet.js, wallet_provider_adapters.js; Hubtel top-up, callback, status check |
| **Hubtel config** | ✅ Implemented | hubtel_config.js, params.js, app_config/hubtel; payment + SMS env vars |
| **Share / deep link** | ✅ Implemented | share-link.js HTTP, share_links; gplusapp://share/event |
| **Admin SMS UI** | ✅ Implemented | Flutter: sms_invite_campaign_screen, sms_audience_sync_screen, sms_campaign_screen |

### 1.3 What works today (Vennuzo)

- Organizers can launch push + SMS campaigns from the **Flutter app** (campaign composer sheet) for an event. No wallet check; no per-SMS charge.
- Backend: audience = event RSVPs + ticket orders; deduped; push = users with fcmToken; SMS = valid Ghana phones; marketingOnly filters by marketingOptIn.
- Hubtel SMS and FCM push are wired; credentials from file or Firestore.

### 1.4 What’s broken / missing (Vennuzo)

- **No promote flow on Studio** – web dashboard has no way to create/launch a campaign.
- **No wallet** – organizers cannot “load wallet” to pay for campaigns; no reservation or deduction.
- **No SMS pricing** – no Hubtel rate capture, no 50% margin, no sell price per message.
- **No campaign packages** – no Starter Boost, Growth, etc., or admin-configurable pricing.
- **No audience count in UI** – client cannot show “~X push, ~Y SMS” before launch (optional getEventAudienceEstimate callable).

---

## 2. BUSINESS MODEL (CODE-READY PLAN)

### 2.1 Product goal

Turn Vennuzo into a **paid event advertising platform**: organizers fund a **wallet** via Hubtel checkout, then spend from the wallet on **SMS** and **push** campaigns. Platform earns margin on SMS (e.g. 50%); push can be flat fee or free initially.

### 2.2 SMS pricing

- **Hubtel cost**: Use rate returned by Hubtel when available; otherwise configurable default per message (e.g. from `pricing_settings` or env).
- **Sell price**:  
  `platform_sms_unit_price = ceil_to_safe_increment(hubtel_cost_per_sms * 1.5)`  
  (50% margin). Admin can override multiplier (e.g. 1.5) and default rate in settings.
- **Campaign estimate**: Before send, estimate cost = (smsAudienceCount * platform_sms_unit_price); reserve that amount from wallet; on completion, charge actual (or release unused).

### 2.3 Wallet

- **Entity**: `advertiser_wallets/{walletId}` where walletId = organizer id (e.g. userId or organizationId). Fields: availableBalance, heldBalance, currency, updatedAt.
- **Transactions**: `wallet_transactions` (or subcollection): type (top_up, campaign_reservation, campaign_charge, refund, admin_adjustment), amount, clientReference, status (pending, completed, failed, reversed), createdAt. All balance changes server-side only; idempotent by clientReference.
- **Funding**: Hubtel checkout for “wallet top-up”; callback verifies success, then credit wallet. Optional: transaction status check after 5 min if callback delayed; duplicate callback protection.

### 2.4 Campaign flow (with wallet)

1. Organizer creates campaign (event, message, channels: push/sms).
2. Backend estimates audience (push count, SMS count) and cost (SMS count * platform_sms_unit_price).
3. Check wallet balance >= estimated cost; if not, return “Insufficient balance” and prompt to load wallet.
4. Reserve estimated amount (heldBalance += amount; availableBalance -= amount).
5. On approval/launch: run send; record actual SMS sent; charge actual from reservation (or charge full reserved and release excess).
6. Statuses: draft, pending_funding, funded, pending_review (optional), approved, scheduled, running, completed, failed, refunded.

### 2.5 Packages (configurable)

- Stored in Firestore `pricing_settings` or `promo_packages`: e.g. Starter Boost, Growth Push, Weekend Blast, Premium Spotlight, Managed Promo.
- Each can have: name, minSpend, platformFee, smsMarginMultiplier, featuredPlacementAddOn, etc. Admin UI to edit; no hardcoded prices in code.

### 2.6 Consent / compliance

- **Existing**: marketingOnly uses notificationPrefs.marketingOptIn for push/SMS.
- **To add**: SMS opt-out collection (e.g. sms_opt_out or use GPlus-style sms_invite_opt_out); do-not-contact suppression list; exclude opt-outs and invalid/blacklisted numbers from audience and from billable count.
- **Rule**: Advertisers never see raw contact data; only aggregated counts and delivery stats.

---

## 3. IMPLEMENTATION PHASES (PRIORITIZED)

### Phase 1 – Promote on dashboard (done in this pass)

- Add **Promote event** in Vennuzo Studio: page/modal to select event, enter message, choose channels (push, SMS), optionally schedule, then call `launchEventNotificationCampaign`. No wallet yet; campaigns run with current backend (no charge).

### Phase 2 – Wallet + Hubtel funding

- Add `advertiser_wallets`, `wallet_transactions`; Hubtel checkout for top-up; callback handler; status check fallback; idempotent credit; duplicate callback protection.

### Phase 3 – SMS pricing and margin

- Capture Hubtel rate when available; store in config or delivery record; compute platform_sms_unit_price = hubtel_rate * 1.5 (configurable); add `pricing_settings` (or use app_config); estimate cost before send.

### Phase 4 – Campaign reservation and charge

- Before launch: estimate cost, check balance, reserve. After send: charge actual from reservation, release remainder. Status transitions and ledger entries.

### Phase 5 – Audience estimator and consent

- Optional callable `getEventAudienceEstimate(eventId)` returning { pushCount, smsCount } (no PII). Harden consent: opt-out list, suppression list, eligibility filters.

### Phase 6 – Packages and admin

- Seed/editable promo packages and pricing in Firestore; admin UI for pricing, wallet adjustments, campaign approval (if needed).

### Phase 7 – GPlus cross-promotion

- Allow Vennuzo campaigns to optionally target GPlus channels (reuse GPlus push/SMS surfaces); attribution and logging.

---

## 4. ENV VARS / CONFIG (NO SECRETS IN CODE)

**Vennuzo functions today:**

- Hubtel SMS: `functions/hubtel_sms_config.js` reads `HUBTEL_SMS_CLIENT_ID`, `HUBTEL_SMS_CLIENT_SECRET`, `HUBTEL_SMS_SENDER_ID` (and `.env.local`). Firestore `app_config/hubtel` fallback.
- Hubtel payment (tickets): `event_payments.js` uses Firestore `app_config/hubtel` (and params).

**For wallet funding (when added):**

- Prefer same pattern: Firestore `app_config/hubtel` for payment API (or env in Cloud Functions config). Required keys: HUBTEL_PAY_API_ID, HUBTEL_PAY_API_KEY, HUBTEL_PAY_BASE_URL, HUBTEL_PAY_MERCHANT_ACCOUNT_NUMBER, HUBTEL_PAY_CALLBACK_URL, HUBTEL_PAY_RETURN_URL, HUBTEL_TXN_STATUS_BASE_URL, etc. Do not hardcode; document in README or this doc.

---

## 5. HUBTEL INTEGRATION NOTES

- **SMS**: Vennuzo uses POST to `https://smsc.hubtel.com/v1/messages/send` with Basic auth; fallback GET to `https://sms.hubtel.com/v1/messages/send`. Normalize Ghana numbers; validate sender ID (max 11 chars). When Hubtel returns rate per message, store it and use for margin calculation.
- **Payment**: Wallet top-up will use Hubtel checkout (initiate → redirect user → callback). Callback must verify signature/secret; only credit wallet after verified success; use clientReference for idempotency; optional status check if callback is delayed.

---

## 6. REMAINING GAPS AFTER PHASE 1

- Wallet creation and funding.
- SMS cost capture and 50% margin pricing.
- Campaign reservation and charge from wallet.
- getEventAudienceEstimate callable (optional).
- Admin pricing and package settings.
- Consent/opt-out and suppression list.
- Cross-ecosystem (GPlus) promotion.

---

## 7. HOW TO TEST CURRENT PROMOTE FLOW (STUDIO)

1. Deploy functions: `npm run functions:deploy:notifications`.
2. Ensure Hubtel SMS config: Firestore `app_config/hubtel` or `functions/.env.local` (clientId, clientSecret, senderId).
3. In Studio, open **Promote** (or **Promote event** from an event), select event, enter message, select Push and/or SMS, click Launch.
4. Check Firestore: `promotion_campaigns` and `notification_jobs` created; jobs processed (push_queue docs, SMS sent via Hubtel). Check `push_queue` docs for status.

---

---

## 8. IMPLEMENTATION REPORT (PHASE 1 – PROMOTE ON DASHBOARD)

### What existed already
- **Vennuzo:** `launchEventNotificationCampaign` callable; Hubtel SMS and push via `push_queue` and `notification_jobs`; Flutter campaign composer; Firestore `promotion_campaigns` with `isEventManager` (including `isOrgOwner`) so organizers can create campaigns.
- **GPlus:** Full SMS invite system, wallet (G-Spot), Hubtel config, admin SMS UI; event promotion push and SMS flows documented in audit.

### What was broken
- Nothing was broken; Studio simply had no UI to launch campaigns.

### What was fixed
- N/A for Phase 1.

### What was added
- **docs/ADS_AUDIT_AND_PLATFORM_PLAN.md** – Audit of Vennuzo + GPlus, business model (wallet, 50% SMS margin, packages), phased implementation plan, env/config notes, testing steps.
- **Studio Promote flow:**
  - **PromotePage** (`/promote`) – Event dropdown, message, title (optional), channels (Push, SMS), share-link option, “Launch campaign” calls `launchEventNotificationCampaign`. Supports `?eventId=xxx` to prefill event.
  - **Sidebar** – “Promote event” nav link under Create event.
  - **EventEditorPage** – “Promote event” button (when editing an existing event) linking to `/promote?eventId={id}`.

### Remaining gaps (for later phases)
- Wallet creation and Hubtel-funded top-up.
- SMS cost capture and 50% margin pricing; configurable pricing_settings.
- Campaign reservation and charge from wallet.
- Optional `getEventAudienceEstimate` callable.
- Admin pricing and package UI; consent/opt-out and suppression list; GPlus cross-promotion.

### How to test end-to-end (Phase 1)
1. Ensure Firebase project has Hubtel SMS config: Firestore `app_config/hubtel` (smsClientId, smsClientSecret, smsSenderId) or `functions/.env.local` for local emulator.
2. Deploy functions: `npm run functions:deploy:notifications`.
3. In Studio (vennuzo.web.app or local): sign in as organizer, open **Promote event** from sidebar or from an event’s **Promote event** button.
4. Select event, enter message, check Push and/or SMS, click **Launch campaign**.
5. In Firestore: `promotion_campaigns` and `notification_jobs` created; jobs run (push → `push_queue`, SMS → Hubtel). Check `push_queue` docs for sent/partial/failed.

---

---

## 9. IMPLEMENTATION REPORT (PHASES 3 & 4 – SMS PRICING, RESERVATION, CHARGE)

### What was added

**Phase 3 – SMS pricing and margin**
- **Pricing config:** `app_config/pricing` in Firestore (optional). Fields: `defaultSmsRateGhs` (default 0.05), `smsMarginMultiplier` (default 1.5). `getPricingConfig()` in `event_notifications.js` reads it and returns `platformSmsUnitPriceGhs = ceil(defaultSmsRateGhs * smsMarginMultiplier)`.
- Used when estimating campaign cost and when charging per SMS.

**Phase 4 – Campaign reservation and charge**
- **getEventAudienceEstimate** callable: takes `eventId`, returns `{ pushCount, smsCount, platformSmsUnitPriceGhs, estimatedSmsCostGhs }` (no PII). Used by Studio Promote page.
- **launchEventNotificationCampaign:** Gets audience counts and pricing; if SMS channel and `estimatedSmsCostGhs > 0`, calls `reserveCampaignBudget(organizationId, campaignId, estimatedSmsCostGhs)` before creating jobs. Reserve: `availableBalance -= amount`, `heldBalance += amount`, `wallet_transactions` doc `campaign_${campaignId}_reserve`. Campaign doc stores `pushAudience`, `smsAudience`, `walletReservationAmount`, `budget`.
- **assertEventManager:** Allows `organizationId === 'org_' + uid` (solo organizer) in addition to creator and organization_members.
- **dispatchNotificationJob (SMS):** After sending, calls `chargeCampaignSms(campaignId, jobId, sentCount, unitPriceGhs)`: `heldBalance -= charge`, campaign `totalSmsCharged += charge`, `wallet_transactions` doc `campaign_${campaignId}_charge_${jobId}`.
- **refreshCampaignStatus:** When status becomes `completed`, calls `finalizeCampaignWallet(campaignId)`: release unused = `reservedAmount - totalSmsCharged`; `availableBalance += release`, `heldBalance -= release`; campaign `walletFinalized: true`; `wallet_transactions` doc `campaign_${campaignId}_release`.

**Studio Promote page**
- Calls `getEventAudienceEstimate` when event is selected; shows “~X push · ~Y SMS · Est. cost GHS Z (SMS)”.
- On launch error containing “insufficient”, shows link to Payments & Payouts to load wallet.
- Side panel copy updated: SMS charged from wallet; link to Payments.

### How to test (Phases 3 & 4)
1. Create `app_config/pricing` in Firestore (optional) with `defaultSmsRateGhs`, `smsMarginMultiplier`.
2. Load wallet in Studio Payments & Payouts (Hubtel top-up).
3. Promote page: select event with SMS audience; confirm estimate shows; launch campaign. If balance too low, see “Insufficient wallet balance” and link to Payments.
4. After campaign runs: check `advertiser_wallets` (held then released), `wallet_transactions` (reservation, per-job charge, release), `promotion_campaigns` (`totalSmsCharged`, `walletFinalized`).

---

## 10. IMPLEMENTATION REPORT (PHASE 5 + CAMPAIGN HISTORY)

### Phase 5 – SMS opt-out and consent
- **Collection `sms_opt_out`:** Document ID = normalized Ghana phone. Cloud Functions only (Firestore rules: no client read/write).
- **getEventAudience / getEventAudienceEstimate:** Exclude phones in `sms_opt_out` from SMS (set `allowSms: false`). Batch get by doc id in chunks of 30.
- **recordSmsOptOut** callable: Accepts `phone` (optional `source`). Writes `sms_opt_out/{phone}`. Use from web form or "Reply STOP" handler.

### Studio – Campaign history
- **listOrganizerCampaigns(organizationId):** Query `promotion_campaigns` by `organizationId`, order by `createdAt` desc. Index: organizationId ASC, createdAt DESC.
- **Promote page:** "Recent campaigns" in side panel (name, event, status, amount charged); refreshes after launch.

---

## 11. IMPLEMENTATION REPORT (PHASE 6 + PUBLIC OPT-OUT)

### Phase 6 – Promo packages
- **getPricingConfig(packageId):** If `packageId` is set, reads `promo_packages/{packageId}` and uses its `defaultSmsRateGhs` and `smsMarginMultiplier` (then still overridden by `app_config/pricing` if present). Campaign doc stores `packageId`; SMS charge uses campaign’s package for unit price.
- **listPromoPackages** callable: Returns active packages from `promo_packages` where `active == true`, ordered by `order`. Fields: id, name, description, defaultSmsRateGhs, smsMarginMultiplier, minSpend, order.
- **Promote page:** Loads packages, shows optional "Pricing package" dropdown; passes `packageId` to `getEventAudienceEstimate` and `launchEventNotificationCampaign`. Index: `promo_packages` (active ASC, order ASC). Firestore rules: server-only (no client read/write).
- **Seed packages:** Create docs in `promo_packages` with `active: true`, `order`, `name`, `defaultSmsRateGhs`, `smsMarginMultiplier` as needed.

### Public SMS opt-out
- **recordSmsOptOutPublic** (HTTP): POST endpoint, CORS enabled. Body `{ "phone": "..." }`. Normalizes and validates Ghana number, writes `sms_opt_out/{phone}` with source `public_form`. Returns 200 JSON or 400 error.
- **Hosting rewrite (vennuzo):** `/api/sms-opt-out` → function `recordSmsOptOutPublic`.
- **Unsubscribe page:** Route `/unsubscribe` (no auth). Form with phone input; POSTs to `/api/sms-opt-out`; shows success or error. Link back to Vennuzo.

---

*Document generated as part of the Audience Ads / Event Promotion Platform implementation. Update as wallet, pricing, and packages are added.*
