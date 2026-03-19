# Vennuzo

Vennuzo is a Flutter event platform with:

- attendee discovery, RSVP, tickets, reminders, and sharing
- organizer workflows through Vennuzo Studio
- admin and superadmin console features
- Firebase-backed payments, SMS, push notifications, and organizer approvals

## Firebase project

- Project ID: `eventora-10063` (can be migrated to a new Vennuzo Firebase project later)
- Functions are already wired through `firebase.json` and `.firebaserc`

## Main workspace commands

Run these from the repo root (e.g. `~/Desktop/vennuzo` or your clone path):

- `flutter analyze`
- `flutter test`
- `npm run functions:lint`
- `npm run functions:list`
- `npm run functions:deploy`

## Functions workflow

Repo-root Firebase Functions scripts are defined in `package.json`.

For the full workflow, targeted deploy commands, and config notes, see:

- `docs/functions_workflow.md`

## Renaming the repo to Vennuzo

To match the new app name everywhere:

1. **On GitHub/GitLab**: In the repository Settings, change the repository name from `eventora_app` to `vennuzo` (or `Vennuzo`).
2. **Update your local remote** (after renaming on the server):
   ```bash
   git remote set-url origin https://github.com/YOUR_USERNAME/vennuzo.git
   ```
3. **Optional – rename the local folder**:
   ```bash
   cd .. && mv eventora_app vennuzo && cd vennuzo
   ```
