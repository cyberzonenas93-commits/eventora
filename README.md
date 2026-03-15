# Eventora

Eventora is a Flutter event platform with:

- attendee discovery, RSVP, tickets, reminders, and sharing
- organizer workflows through Eventora Studio
- admin and superadmin console features
- Firebase-backed payments, SMS, push notifications, and organizer approvals

## Firebase project

- Project ID: `eventora-10063`
- Functions are already wired through `firebase.json` and `.firebaserc`

## Main workspace commands

Run these from `/Users/angelonartey/Desktop/eventora_app`:

- `flutter analyze`
- `flutter test`
- `npm run functions:lint`
- `npm run functions:list`
- `npm run functions:deploy`

## Functions workflow

Repo-root Firebase Functions scripts are defined in `package.json`.

For the full workflow, targeted deploy commands, and config notes, see:

- `docs/functions_workflow.md`
