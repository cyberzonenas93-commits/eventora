# Places as Google Business — Design Spec

**Date:** 2026-06-08
**Status:** Approved (Tier 2 scope, Approach A, phone-OTP primary). User delegated remaining decisions ("be autonomous").
**Owner:** Vennuzo Places feature

## Goal

Turn Vennuzo Places into a Google-Business-style model: a place exists as a public
listing, an owner **claims** it, **verifies** ownership via a low-friction method,
and verification unlocks management + trust/promotional powers. Unverified places
stay discoverable (chipped) but cannot promote or transact.

This also closes audit findings:
- **CRITICAL:** `places` rule lets a manager self-set `verified`/`featured`/`verificationStatus` via the raw SDK → bypasses admin review + paid-push/featured gate.
- **HIGH:** Google Places lookup callables are unauthenticated (billed-API abuse).
- **MEDIUM:** `coverUrl`/`galleryUrls` stored as unvalidated arbitrary URLs (SSRF surface).
- **HIGH (media UX):** `_PlaceImage` uses raw uncached/un-downsized `Image.network`.

## Scope (locked)

- **In:** verified-ownership lifecycle; Google-anchored claim + free-form fallback;
  multi-method verification (phone OTP primary, email code, document → admin fallback);
  server-controlled trust fields; owner-uploaded media; dedup on `googlePlaceId`;
  UI states (unverified chip, claim/verify CTA, verified badge, gated actions).
- **Out (deferred):** publicly-seeded *unclaimed* listings sourced from Google (Tier 3),
  listing-quality crowdsourcing, owner analytics/insights dashboards, live Google-photo
  display (ToS forbids storage; can be added as display-only later).

## Lifecycle (state machine — `verificationStatus`, server-controlled only)

```
  (Google search) ──claim──▶ unverified ◀──add free-form──
                                  │ owner starts verification
        ┌─────────────────────────┼──────────────────────────┐
   phone-OTP / email code          │                    document upload
        │ (instant)                │                     │ (admin queue)
        ▼                          │                     ▼
     verified ◀──admin approve──────┼──────────────  pending_review
        ▲                          │              admin reject │
 admin  │ suspend                  │                           ▼
        ▼                          │                       rejected
     suspended                     │
```

- **unverified** — created/claimed by owner. Editable; publicly discoverable with an
  "Unverified" chip once it passes the quality floor (name + cover + category) and
  `status == 'active'`. Cannot use featured / paid push / payments / official review-replies.
- **pending_review** — only the document path parks here.
- **verified** — full powers + badge. **Ownership locked** (disputes go to admin).
- **rejected / suspended** — admin states.

Common path: **unverified → verified in ~30s via phone OTP, no admin in the loop.**

### Ownership rules
- While **unverified**: first party to verify owns the listing.
- Once **verified**: ownership is **locked**; later disputants must use admin dispute
  (manual), never auto-takeover. A squatter can never displace a real owner (real owner
  verifies and wins); a verified listing can never be stolen.

## Data model

### `places/{placeId}`
`placeId` is deterministic for Google-anchored places (`gpl_<sha1(googlePlaceId)>`),
so one venue = one doc (dedup). Free-form places get a generated id.

| Field | Writer | Notes |
|---|---|---|
| `googlePlaceId` | **server** | dedup anchor; null for free-form |
| `ownerId`, `claimedBy`, `claimedAt` | **server** | set at claim |
| `verificationStatus` | **server** | state machine |
| `verified`, `featured` | **server** | derived from status; never client-set |
| `verificationMethod` | **server** | phone / email / document |
| `organizationId` | **server** | `org_<ownerUid>` (immutable) |
| `name, description, category, hours, address, location, phone, contactEmail` | owner via callable | editable while unverified |
| `coverUrl`, `logoUrl`, `galleryUrls` | owner via callable | **must be within the Vennuzo Firebase Storage bucket** (server-validated) |
| `status` | **server** | `active` once quality floor met, else `incomplete` |
| `metrics` | **server** | denormalized rating/reviewCount |

### `place_verification_otps/{placeId}_{method}` (server-only, no client read/write)
Hashed OTP, salt, TTL (`expiresAt`), `attempts`, `method`, `target` (masked phone/email).
Mirrors `phone_auth` OTP store. TTL via Firestore policy.

### `place_verifications/{...}` (existing, unchanged)
Document-submission records the admin reviews. Server-write-only, admin-readable.

## Security rules

```
match /places/{placeId} {
  allow read: if resource.data.status == 'active'
    || isEventManager(resource.data.organizationId);
  allow create, update: if false;   // all writes via callables (Admin SDK)
  allow delete: if isAdmin();
}

match /place_verification_otps/{id} {
  allow read, write: if false;       // Admin SDK only
}
```

- Trust fields become physically unwritable by clients → CRITICAL bypass closed; the
  "spam-create places via SDK" HIGH closes too (creation flows through rate-limited callable).
- Reads unchanged: an unverified-but-`active` place stays publicly discoverable.
- `place_verifications`, menus, sections, reservations: already `if false` — unchanged.
- Storage `place-verifications/{userId}/…`: owner-scoped, image/PDF, 25 MB (already hardened).

## Cloud Functions (callables)

All require `request.auth`. Reuse `safeString`, constant-time compare, hashed+salted OTP,
TTL and attempt caps from `phone_auth.js`. Rate-limited via `rate_limiter.js`.

1. **Gate existing lookups behind auth** — `autocompleteEventPlaces`,
   `getEventPlaceDetails`, `reverseGeocodeEventCoordinates`: add an auth check
   (closes the unauthenticated billed-API finding). App requires sign-in anyway.
2. **`claimOrCreatePlace({ googlePlaceId?, placeData? })`** — auth + rate limit (20/hr).
   - Google-anchored: resolve details (reuse `getEventPlaceDetails` logic), compute
     `placeId = gpl_<sha1(googlePlaceId)>`. If the doc exists and is `verified` by another
     org → reject (`already-claimed`). If it exists and is `unverified` → reassign
     `ownerId`/`organizationId` to caller (first-to-verify will lock). Prefill
     name/address/phone/location from Google. `verificationStatus='unverified'`.
   - Free-form: generate id; store caller-supplied profile fields (sanitized); no `googlePlaceId`.
   - Never sets `verified`/`featured`.
3. **`upsertPlaceProfile`** — keep, but: (a) strip/ignore any client-supplied
   `verified`/`featured`/`verificationStatus`/`googlePlaceId`/`ownerId`; (b) validate that
   `coverUrl`/`logoUrl`/`galleryUrls` hosts are within the Vennuzo Storage bucket
   (`<bucket>.firebasestorage.app` / `storage.googleapis.com/<bucket>`), else reject.
4. **`startPlaceVerification({ placeId, method })`** — auth + `assertPlaceManager`.
   - `phone`: require a place phone; generate OTP, hash+store, send via Hubtel SMS. Rate-limited per place + per uid.
   - `email`: code to `contactEmail`.
   - `document`: expects a prior Storage upload ref → create `place_verifications` submission + notify admins; set `verificationStatus='pending_review'`.
5. **`confirmPlaceVerification({ placeId, code })`** — auth + manager. Constant-time OTP
   check w/ attempts + TTL. On success: `verificationStatus='verified'`, `verified=true`,
   set `verificationMethod`, lock `ownerId`, delete OTP doc.
6. **`reviewPlaceVerification`** (admin) — existing; approve sets verified, reject sets rejected.

## Media handling

- New Storage path **`place-media/{placeId}/{allPaths=**}`**: `read: if true`;
  `write: if isSignedIn() && (isDelete() || (isImageUpload(15) && <caller manages the place's org>))`.
- `upsertPlaceProfile` validates media URL hosts (allow-list) → closes the unvalidated-URL finding.
- **Flutter `_PlaceImage`** → `CachedNetworkImage` with placeholder + error + `cacheWidth`
  downsizing (reuse `social_post_image.dart` pattern). Add tap-to-fullscreen viewer.
- No Google photo storage (ToS). Live display-only deferred.

## UI states

### Flutter Places tab
- "Unverified" chip on unverified places; verified badge on verified.
- Owner sees "Claim this place" (if unclaimed) / "Verify ownership" (if claimed-unverified) CTA.
- Featured/push/payments actions hidden or disabled-with-explainer until verified.
- Claim flow: search (reuse autocomplete) → select → `claimOrCreatePlace` → profile editor →
  Verify sheet (phone OTP primary: send code → enter code → verified).

### Studio PlacesPage
- Add claim + verify + media-upload UI; show status badge; gate paid actions on verified.
- Opportunistic: extract tab panels from the ~859-line god component as we touch it.

## Phasing

- **Phase 1 — Security foundation (ship first):** rules lockdown (`places` server-only +
  `place_verification_otps`); make `upsertPlaceProfile` fully server-authoritative for trust
  fields + media URL allow-list; gate the 3 lookups behind auth. Rules + functions tests.
- **Phase 2 — Claim + phone-OTP:** `claimOrCreatePlace`, `startPlaceVerification`,
  `confirmPlaceVerification` (phone); Flutter claim + verify UI (minimal); studio claim/verify.
- **Phase 3 — Email/doc methods + polish:** email-code method; document fallback wired to
  existing admin review; `_PlaceImage` cached/downsized + fullscreen viewer; `place-media`
  upload UX; verified badge polish; studio god-component decomposition.

## Testing

- **Rules:** `@firebase/rules-unit-testing` — a manager **cannot** set `verified:true`/`featured:true`
  on their own place; `place_verification_otps` is unreadable by clients; emulator compile-check.
- **Functions:** jest — `claimOrCreatePlace` dedup (verified vs unverified), OTP start/confirm
  (success, wrong code, expired, attempt cap) mirroring `phone_auth.test.js`, media URL allow-list,
  trust-field stripping in `upsertPlaceProfile`.
- **Flutter:** `flutter analyze` + widget tests for unverified/verified/CTA states.
