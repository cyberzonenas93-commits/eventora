# Event Ops Runtime QA

Date: 2026-06-03

This is the test path for Event Ops, inventory, staff credentials, Staff Mode,
merchant-collected tabs, and end-of-event reports.

## Local Emulator Setup

Use emulators before deploying new callables:

1. Copy `studio/.env.example` to `studio/.env.local`.
2. Set:

```env
VITE_USE_FIREBASE_EMULATORS=true
VITE_FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1
VITE_FIREBASE_AUTH_EMULATOR_PORT=9099
VITE_FIREBASE_FIRESTORE_EMULATOR_HOST=127.0.0.1
VITE_FIREBASE_FIRESTORE_EMULATOR_PORT=8080
VITE_FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1
VITE_FIREBASE_FUNCTIONS_EMULATOR_PORT=5001
```

3. Run Firebase emulators for Auth, Firestore, and Functions.
4. Run Studio locally.
5. Create/sign in as an organizer, create an event, then open
   `/studio/operations?eventId=<eventId>`.

## QA Flow

1. In Studio Operations, select an event.
2. Click `Setup Event Ops`.
3. Pick `Event Ops Pro`.
4. Add at least three inventory items with cost, selling price, and stock.
5. Create at least two staff credentials.
6. Confirm Staff Mode links point to `/staff/<eventId>`.
7. Open `/staff/<eventId>`.
8. Sign in with a staff PIN.
9. Open a tab for an item.
10. Confirm the tab appears in Studio Operations.
11. Close the tab after merchant-collected payment.
12. Confirm staff sales and closed-tab KPIs update.
13. Generate the end-of-event PDF.
14. Confirm an `event_ops_reports` record is created.

## Production Deployment Note

The Staff Mode and Event Ops frontend can run before deployment, but real
Firestore sync requires the following callables to be deployed:

- `getEventOpsWorkspace`
- `saveEventOpsConfig`
- `createEventOpsInventoryItem`
- `createEventOpsStaffCredential`
- `createEventOpsTab`
- `closeEventOpsTab`
- `generateEventOpsReport`
- `startEventOpsStaffSession`
- `getEventOpsStaffWorkspace`
- `createEventOpsStaffTab`
- `closeEventOpsStaffTab`

Until those are deployed, Studio falls back to local draft mode where possible.
