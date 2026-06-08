# Vennuzo

Vennuzo is a Flutter event platform with:

- attendee discovery, RSVP, tickets, reminders, and sharing
- organizer workflows through Vennuzo Studio
- admin and superadmin console features
- Firebase-backed payments, SMS, push notifications, and organizer approvals

## Architecture overview

The repository contains three deployable components plus shared Firebase config:

| Component | Path | Stack |
| --- | --- | --- |
| Mobile app | `lib/`, `ios/`, `android/` | Flutter (Dart) |
| Cloud Functions | `functions/` | Node.js (Firebase Functions) |
| Studio admin / organizer web app | `studio/` | React + TypeScript (Vite) |

Shared Firebase configuration lives at the repo root: `firebase.json`, `.firebaserc`,
`firestore.rules`, `firestore.indexes.json`, and `storage.rules`.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) stable that ships Dart SDK
  `^3.11.0` (Flutter 3.41.x or newer). Run `flutter doctor` to confirm your toolchain.
- Node.js 22 for Cloud Functions (`functions/`) and Node.js 20+ for Studio (`studio/`).
- [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools`),
  authenticated with access to the `vennuzo` Firebase project.
- Xcode (for iOS builds) and Android SDK / Android Studio (for Android builds).

## Setup

Several secrets are intentionally untracked (see `.gitignore`). Obtain them before building.

### 1. Firebase config files

These are gitignored and must be placed manually:

- `android/app/google-services.json` — download from the Firebase console
  (Project settings -> Your apps -> Android app).
- `ios/Runner/GoogleService-Info.plist` — download from the Firebase console
  (Project settings -> Your apps -> iOS app).

### 2. Google Maps API key

The Android build reads `GOOGLE_MAPS_API_KEY` from `android/local.properties`
(falling back to the `GOOGLE_MAPS_API_KEY` environment variable). Create
`android/local.properties` if it does not exist and add:

```properties
GOOGLE_MAPS_API_KEY=your-android-maps-api-key
```

`android/local.properties` is gitignored. Configure the iOS Maps key per the
`google_maps_flutter_ios` setup in `ios/`.

### 3. Android release signing (release builds only)

Release builds load signing credentials from `android/key.properties`. Copy the
example and fill in your keystore details:

```bash
cp android/key.properties.example android/key.properties
```

If `android/key.properties` is absent, the Gradle build falls back to debug signing
(so `flutter run --release` still works locally) and prints a warning. `key.properties`
and `*.keystore` / `*.jks` files are gitignored — never commit them.

### 4. Cloud Functions environment

Copy `functions/.env.example` to your local env file and fill in the values.
Local-only env / secret files (`functions/.env.local`, `functions/.secret.local`) are
gitignored.

## Running each component

### Flutter app

```bash
flutter pub get
flutter run            # debug build on a connected device/simulator
```

### Cloud Functions (local emulator)

From the repo root:

```bash
npm run functions:serve   # firebase emulators:start --only functions
```

You can also drive functions interactively with `npm run functions:shell`.

### Studio (web admin / organizer app)

```bash
cd studio
npm install
npm run dev               # Vite dev server
npm run build             # production build (tsc -b && vite build)
```

## Tests and linting

### Flutter app (repo root)

```bash
flutter analyze
flutter test
```

### Cloud Functions (`functions/`)

```bash
cd functions
npm ci
npm run lint              # node --check on every function module
npm test                  # runs lint, then jest
```

The repo-root wrapper `npm run functions:lint` runs the same lint step.

### Studio (`studio/`)

```bash
cd studio
npm ci
npm run lint              # eslint
npm test                  # vitest run
npm run build             # type-checks via tsc -b
```

## Continuous integration

`.github/workflows/ci.yml` runs on pushes and pull requests to `main`. It has three
jobs: Flutter (`pub get` / `analyze` / `test`), Functions (`npm ci` / `lint` / `test`),
and Studio (`npm ci` / `lint` / `build` / `test`).

## Firebase / Functions workflow

Repo-root Firebase Functions scripts are defined in `package.json`:

- `npm run functions:lint`
- `npm run functions:list`
- `npm run functions:logs`
- `npm run functions:deploy` (and targeted `functions:deploy:*` variants)

For the full workflow, targeted deploy commands, and config notes, see
`docs/functions_workflow.md`.

## Documentation

Additional design notes, QA logs, and architecture docs live in the `docs/` directory,
including:

- `docs/firebase_architecture.md` — Firebase architecture overview
- `docs/functions_workflow.md` — Cloud Functions deploy workflow
- `docs/gplus_event_notifications_migration.md` — notifications migration notes
- `docs/store_policy_checklist.md` and `docs/app_store_submission_*.md` — store submission

Browse `docs/` for the complete set.
