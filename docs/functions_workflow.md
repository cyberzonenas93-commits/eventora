# Eventora Firebase Functions Workflow

`Eventora` is already linked to Firebase project `eventora-10063`, so Cloud Functions can be managed directly from the repo root.

## Root commands

Run these from `/Users/angelonartey/Desktop/eventora_app`:

- `npm run functions:lint`
- `npm run functions:list`
- `npm run functions:logs`
- `npm run functions:serve`
- `npm run functions:shell`
- `npm run functions:deploy`
- `npm run functions:deploy:notifications`
- `npm run functions:deploy:payments`
- `npm run functions:deploy:organizers`

## Function groups

Notifications:
- `processPushQueue`
- `launchEventNotificationCampaign`
- `processNotificationJobs`
- `processEventReminderNotifications`
- `onEventRsvpCreated`
- `onEventTicketOrderCreated`
- `onEventTicketOrderUpdated`
- `sendTestEventSms`
- `sendTestEventPush`

Payments:
- `createEventTicketPaymentForOrder`
- `checkHubtelTicketStatus`
- `createWebEventTicketOrder`
- `hubtelCallback`
- `hubtelReturn`

Organizer approvals:
- `reviewOrganizerApplication`

## Where configuration comes from

- Firebase project binding: `.firebaserc`
- Functions source: `firebase.json` -> `functions.source = "functions"`
- Runtime code entry: `functions/index.js`
- Hubtel event payment config: Firestore document `app_config/hubtel`
- Hubtel SMS config:
  - preferred source: Firestore `app_config/hubtel`
  - local fallback: environment variables in the shell running the deploy or emulator

## Local SMS fallback environment variables

Only set these locally when needed:

- `HUBTEL_SMS_CLIENT_ID`
- `HUBTEL_SMS_CLIENT_SECRET`
- `HUBTEL_SMS_SENDER_ID`

You can keep these in `/Users/angelonartey/Desktop/eventora_app/functions/.env.local`
for local emulator work. That file is gitignored and should never be committed.

## Notes

- Do not commit live secrets into the repo.
- Deploying from the root is equivalent to deploying from inside `functions`, but it is safer for this workspace because it keeps the project id and function groups consistent.
