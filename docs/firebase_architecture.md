# Eventora Firebase Architecture

This document defines the concrete Firebase data model and backend contract for
the standalone Eventora app. It is derived from the event system inside the
original GPlus app, but normalized and scoped for a dedicated event platform.

## Goals

- Support public and private events
- Support organizer-owned events and multi-organization tenancy
- Support RSVP-only, ticket-only, and hybrid RSVP + optional ticket flows
- Support paid tickets, complimentary tickets, and pay-at-gate reservations
- Support QR ticket validation and lookup
- Support public share links and public ticket pages
- Support push, SMS, and share-link promotion campaigns
- Keep the schema straightforward for Flutter + Firestore + Cloud Functions

## Firebase Products

- Firebase Auth
- Cloud Firestore
- Cloud Functions
- Firebase Cloud Messaging
- Firebase Storage
- Firebase App Check
- Optional: Firebase Analytics

## Top-Level Collections

- `users`
- `organizations`
- `organization_members`
- `events`
- `event_occurrences`
- `event_rsvps`
- `event_ticket_orders`
- `event_ticket_lookups`
- `share_links`
- `promotion_campaigns`
- `notification_jobs`
- `audiences`

## Auth Model

Every signed-in user has a `users/{uid}` document.

Recommended fields:

```json
{
  "displayName": "Angel Artey",
  "email": "angel@eventora.app",
  "phone": "+233240000000",
  "photoUrl": "",
  "defaultOrganizationId": "org_123",
  "roles": ["attendee", "organizer"],
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp",
  "notificationPrefs": {
    "pushEnabled": true,
    "smsEnabled": true,
    "marketingOptIn": true
  }
}
```

## Organizations

Organizations are the top-level tenant boundary for Eventora.

`organizations/{organizationId}`

```json
{
  "name": "Pulse Culture",
  "slug": "pulse-culture",
  "ownerId": "uid_123",
  "logoUrl": "",
  "coverImageUrl": "",
  "bio": "",
  "city": "Accra",
  "country": "Ghana",
  "status": "active",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

## Organization Members

Membership and role scoping should be explicit.

`organization_members/{organizationId}_{uid}`

```json
{
  "organizationId": "org_123",
  "userId": "uid_123",
  "role": "owner",
  "permissions": {
    "manageEvents": true,
    "manageTickets": true,
    "managePromotions": true,
    "validateTickets": true
  },
  "status": "active",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

Roles:

- `owner`
- `admin`
- `event_manager`
- `checkin_staff`
- `marketing_manager`

## Events

Primary event documents live in `events`.

`events/{eventId}`

```json
{
  "organizationId": "org_123",
  "createdBy": "uid_123",
  "title": "Pulse Summit After Dark",
  "description": "A premium founder and creator event.",
  "venue": "Forum Hall",
  "city": "Accra",
  "country": "Ghana",
  "addressText": "Forum Hall, Accra",
  "geo": {
    "lat": 5.6037,
    "lng": -0.187
  },
  "flyerUrl": "",
  "galleryUrls": [],
  "visibility": "public",
  "status": "published",
  "startAt": "timestamp",
  "endAt": "timestamp",
  "timezone": "Africa/Accra",
  "recurrence": {
    "frequency": "weekly",
    "interval": 1,
    "endType": "afterOccurrences",
    "endDate": null,
    "endAfterOccurrences": 10
  },
  "ticketing": {
    "enabled": true,
    "requireTicket": true,
    "currency": "GHS",
    "tiers": [
      {
        "tierId": "vip",
        "name": "VIP Circle",
        "price": 480,
        "maxQuantity": 60,
        "sold": 24,
        "description": "Backstage lounge and artist meet window."
      }
    ]
  },
  "lineup": {
    "performers": "Sefa, Kxng Joey",
    "djs": "DJ Loft, Hype Monk",
    "mcs": "Naa Mingle"
  },
  "distribution": {
    "allowSharing": true,
    "sendPushNotification": true,
    "sendSmsNotification": true
  },
  "metrics": {
    "likesCount": 412,
    "rsvpCount": 190,
    "ticketCount": 246,
    "grossRevenue": 63240
  },
  "tags": ["ticketed", "featured", "music"],
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

Recommended enums:

- `visibility`: `public`, `private`, `unlisted`
- `status`: `draft`, `published`, `cancelled`, `completed`
- `recurrence.frequency`: `none`, `daily`, `weekly`, `monthly`
- `recurrence.endType`: `never`, `onDate`, `afterOccurrences`

## Event Occurrences

Unlike GPlus, recurrence should not be expanded only on the client. Materialize
occurrences for queryability.

`event_occurrences/{occurrenceId}`

```json
{
  "eventId": "event_123",
  "organizationId": "org_123",
  "seriesEventId": "event_123",
  "title": "Sunday Loop Market",
  "visibility": "public",
  "status": "published",
  "occurrenceStartAt": "timestamp",
  "occurrenceEndAt": "timestamp",
  "timezone": "Africa/Accra",
  "city": "Accra",
  "venue": "Cantonments Yard",
  "flyerUrl": "",
  "ticketingEnabled": false,
  "requireTicket": false,
  "createdAt": "serverTimestamp"
}
```

Use this collection for:

- customer discovery
- calendar views
- reminder scheduling
- upcoming-event notifications
- recurring-event analytics

## Event RSVPs

Keep RSVPs separate from ticket orders.

`event_rsvps/{eventId}_{uid}`

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "userId": "uid_123",
  "organizationId": "org_123",
  "eventTitle": "Open Canvas Rooftop Jam",
  "name": "Angel Artey",
  "phone": "+233240000000",
  "guestCount": 3,
  "bookTable": false,
  "status": "confirmed",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

Recommended additional subcollection for organizer browsing:

- `events/{eventId}/rsvps/{uid}`

That keeps event-scoped reads fast while preserving the global attendee-owned
document.

## Ticket Orders

Ticket orders remain the main checkout object.

`event_ticket_orders/{orderId}`

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "organizationId": "org_123",
  "eventTitle": "Pulse Summit After Dark",
  "buyerId": "uid_123",
  "buyerName": "Angel Artey",
  "buyerPhone": "+233240000000",
  "buyerEmail": "angel@eventora.app",
  "selectedTiers": [
    {
      "tierId": "vip",
      "name": "VIP Circle",
      "price": 480,
      "quantity": 2
    }
  ],
  "totalAmount": 960,
  "currency": "GHS",
  "status": "paid",
  "paymentStatus": "paid",
  "source": "app",
  "shareLinkId": "share_123",
  "tickets": {
    "order_001_vip_1": {
      "ticketId": "order_001_vip_1",
      "orderId": "order_001",
      "eventId": "event_123",
      "occurrenceId": "occ_123",
      "tierId": "vip",
      "tierName": "VIP Circle",
      "qrToken": "qr_123",
      "status": "issued",
      "attendeeName": "Angel Artey",
      "price": 480,
      "issuedAt": "timestamp",
      "admittedAt": null
    }
  },
  "paymentProvider": {
    "gateway": "hubtel",
    "checkoutUrl": "",
    "providerReference": "",
    "transactionId": ""
  },
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp",
  "paidAt": "timestamp"
}
```

Recommended enums:

- `status`: `pending`, `reserved`, `paid`, `cancelled`, `refunded`
- `paymentStatus`: `initiated`, `pending`, `paid`, `cashAtGate`, `cashAtGatePaid`, `complimentary`, `failed`, `refunded`
- `ticket.status`: `issued`, `unpaid`, `admitted`, `voided`

## Ticket Lookups

Keep QR/token lookup separate for fast check-in.

`event_ticket_lookups/{qrToken}`

```json
{
  "qrToken": "qr_123",
  "orderId": "order_001",
  "ticketId": "order_001_vip_1",
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "organizationId": "org_123",
  "buyerId": "uid_123",
  "attendeeName": "Angel Artey",
  "tierId": "vip",
  "tierName": "VIP Circle",
  "ticketStatus": "issued",
  "paymentStatus": "paid",
  "admittedAt": null,
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

This is the document scanned at the gate.

## Share Links

Share links should stay generic and multi-target.

`share_links/{shareId}`

```json
{
  "type": "event",
  "targetId": "event_123",
  "organizationId": "org_123",
  "title": "Pulse Summit After Dark",
  "description": "A premium founder and creator event.",
  "imageUrl": "",
  "slug": "pulse-summit-after-dark",
  "requireTicket": true,
  "status": "active",
  "createdBy": "uid_123",
  "createdAt": "serverTimestamp"
}
```

Supported `type` values:

- `event`
- `ticket`
- `campaign`

## Promotion Campaigns

Promotion campaigns are event-scoped growth objects.

`promotion_campaigns/{campaignId}`

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "organizationId": "org_123",
  "eventTitle": "Pulse Summit After Dark",
  "name": "48-hour ticket push",
  "status": "scheduled",
  "channels": ["push", "sms", "shareLink"],
  "scheduledAt": "timestamp",
  "pushAudience": 4300,
  "smsAudience": 920,
  "shareLinkEnabled": true,
  "budget": 1250,
  "message": "Doors open soon. Push urgency to ticket buyers.",
  "createdBy": "uid_123",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

Enums:

- `status`: `draft`, `scheduled`, `live`, `completed`, `cancelled`
- `channels`: `push`, `sms`, `shareLink`, `featured`

## Notification Jobs

Actual delivery work should be queued separately from campaigns.

`notification_jobs/{jobId}`

```json
{
  "organizationId": "org_123",
  "eventId": "event_123",
  "campaignId": "campaign_123",
  "type": "push",
  "status": "queued",
  "scheduledAt": "timestamp",
  "payload": {
    "title": "Event starts soon",
    "body": "Reserve your spot before doors open."
  },
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

## Audiences

Audience docs are optional but recommended if SMS and campaign tooling become
serious.

`audiences/{audienceId}`

```json
{
  "organizationId": "org_123",
  "eventId": "event_123",
  "source": "rsvp",
  "name": "Pulse Summit RSVP Audience",
  "contactCount": 920,
  "createdAt": "serverTimestamp"
}
```

Optional contacts subcollection:

- `audiences/{audienceId}/contacts/{contactId}`

## Storage Paths

Recommended Storage structure:

- `organizations/{organizationId}/branding/logo.jpg`
- `organizations/{organizationId}/branding/cover.jpg`
- `events/{eventId}/flyer.jpg`
- `events/{eventId}/gallery/{assetId}.jpg`
- `tickets/{orderId}/{ticketId}.png`

## Firestore Security Model

High-level rules:

- anyone can read `events` and `event_occurrences` where `visibility == public` and `status == published`
- private events require membership, ownership, or a valid share-link access flow
- attendees can read their own RSVP docs and their own ticket orders
- organizers can read orders, RSVPs, and campaigns for organizations they belong to
- check-in staff can read lookup docs for their organization and run validation flows
- only authorized organizers can create or update events for their organization
- only Cloud Functions should mutate ticket issuance, sold counts, payment status transitions, and ticket lookup docs

## Cloud Functions Contract

All payment, issuance, validation, and reminder-critical flows should be
server-side.

### 1. `createEventTicketPaymentForOrder`

Type:

- callable

Input:

```json
{
  "orderId": "order_123"
}
```

Output:

```json
{
  "checkoutUrl": "https://...",
  "orderId": "order_123",
  "paymentProvider": "hubtel"
}
```

Responsibilities:

- verify caller owns the order
- verify order is still payable
- create payment session
- write provider metadata back to the order

### 2. `createPublicEventTicketOrder`

Type:

- callable or HTTPS endpoint for public web checkout

Input:

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "buyerName": "Guest Buyer",
  "buyerPhone": "+233240000000",
  "buyerEmail": "guest@example.com",
  "selectedTiers": [
    {
      "tierId": "standard",
      "quantity": 2
    }
  ]
}
```

Output:

```json
{
  "orderId": "order_123",
  "checkoutUrl": "https://..."
}
```

Responsibilities:

- validate public event accessibility
- calculate totals server-side
- create guest order
- create payment session

### 3. `createFreeTicketReservation`

Type:

- callable

Input:

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "selections": {
    "gate": 2
  }
}
```

Output:

```json
{
  "orderId": "order_123",
  "status": "reserved"
}
```

Responsibilities:

- validate free/pay-at-gate tiers
- create reserved order
- reserve ticket capacity
- create unpaid tickets and lookup docs if desired

### 4. `handleEventTicketPaymentCallback`

Type:

- HTTPS webhook

Input:

- payment provider payload

Responsibilities:

- verify callback signature
- match provider reference to order
- mark order paid
- increment tier sold counts atomically
- issue per-ticket records
- create or update `event_ticket_lookups`
- write `paidAt`

### 5. `submitEventRsvp`

Type:

- callable

Input:

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "name": "Angel Artey",
  "phone": "+233240000000",
  "guestCount": 3,
  "bookTable": false
}
```

Output:

```json
{
  "ok": true,
  "rsvpId": "event_123_uid_123"
}
```

Responsibilities:

- upsert attendee RSVP
- increment or recompute event metrics
- attach phone number to event audience

### 6. `setEventReminder`

Type:

- callable

Input:

```json
{
  "eventId": "event_123",
  "occurrenceId": "occ_123",
  "timing": "oneDayBefore"
}
```

Output:

```json
{
  "ok": true
}
```

Recommended collection:

- `event_reminders/{occurrenceId}_{uid}`

### 7. `validateEventTicket`

Type:

- callable

Input:

```json
{
  "qrToken": "qr_123"
}
```

Output:

```json
{
  "ok": true,
  "ticketStatus": "admitted",
  "paymentStatus": "paid",
  "attendeeName": "Angel Artey",
  "tierName": "VIP Circle"
}
```

Responsibilities:

- verify staff role for the event organization
- load lookup doc
- prevent duplicate admission
- mark ticket admitted
- if pay-at-gate, update payment status to `cashAtGatePaid`

### 8. `lookupEventTicket`

Type:

- callable

Input:

```json
{
  "eventId": "event_123",
  "query": "0240000000"
}
```

Output:

```json
{
  "matches": [
    {
      "orderId": "order_123",
      "buyerName": "Angel Artey",
      "buyerPhone": "+233240000000",
      "ticketCount": 2,
      "paymentStatus": "paid"
    }
  ]
}
```

### 9. `createShareLink`

Type:

- callable

Input:

```json
{
  "type": "event",
  "targetId": "event_123"
}
```

Output:

```json
{
  "shareId": "share_123",
  "url": "https://eventora.app/e/share_123"
}
```

### 10. `launchPromotionCampaign`

Type:

- callable

Input:

```json
{
  "campaignId": "campaign_123"
}
```

Output:

```json
{
  "ok": true,
  "jobsCreated": 3
}
```

Responsibilities:

- verify organizer permission
- create `notification_jobs`
- mark campaign `scheduled` or `live`

## Flutter Repository Mapping

Map the current in-memory repository methods to Firebase-backed methods.

Current method to backend target:

- `discoverableEvents` -> query `event_occurrences` or `events`
- `managedEvents` -> query `events` by `organizationId` and membership
- `createEvent()` -> write to `events`, then materialize occurrences
- `updateEvent()` -> update `events`, then rebuild occurrences if schedule changed
- `createRsvp()` -> call `submitEventRsvp`
- `checkout()` -> call `createEventTicketPaymentForOrder` or `createFreeTicketReservation`
- `admitTicket()` -> call `validateEventTicket`
- `scheduleCampaign()` -> write `promotion_campaigns`, then call `launchPromotionCampaign`
- `buildShareLink()` -> call `createShareLink`

## Recommended Implementation Order

1. Auth + `users`
2. `organizations` + membership
3. `events`
4. `event_occurrences`
5. `event_rsvps`
6. `event_ticket_orders`
7. payment creation function
8. payment callback function
9. ticket lookup + validation
10. share links
11. reminders
12. promotion campaigns + notification jobs

## Notes Compared to GPlus

Improvements over the original GPlus event architecture:

- recurrence is materialized server-side
- organization tenancy is explicit
- organizer permissions are organization-scoped, not superadmin-centric
- ticket validation uses clean organization boundaries
- public/private access rules are clearer
- reminder flows are first-class
- promotion and delivery jobs are separated from campaign definitions
