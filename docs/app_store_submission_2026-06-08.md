# App Store Submission Notes - 2026-06-08

## App Store Connect

- App: Vennuzo
- Apple ID: 6761087972
- Bundle ID: com.vennuzo.app
- App Store version record: 1.0
- Uploaded build: 2026060801
- Build ID: afa674b1-e2c3-48f7-ac9f-85d90c2a90d8
- Delivery UUID: afa674b1-e2c3-48f7-ac9f-85d90c2a90d8
- Canceled review submission ID: d05eeb8b-3f20-460f-9451-79dd89ec6112
- Current review submission ID: ae301e35-1371-4931-8c36-7feb22bf8823
- Review submission state: WAITING_FOR_REVIEW
- IPA: build/ios/ipa-fixed/Vennuzo.ipa

## QA Gates

- `flutter analyze`: passed
- `flutter test`: passed, 21 tests
- `npm test` in `functions`: passed, 34 tests across 3 suites
- `npm test` in `studio`: passed, 5 tests
- `npm run build` in `studio`: passed
- `npm run lint` in `studio`: passed
- Firestore rules/index dry run: passed
- iOS Simulator smoke test on iPhone 16e: passed

## Production Updates

- Firestore rules and indexes deployed to `eventora-10063`.
- G+ profile/media sync functions deployed to `eventora-10063`.
- Hosting deployed for `vennuzo`, `studio`, `admin`, and `pages`.
- Live Firestore seed includes G+Nightclub plus Labadi Beach Club, Makola Social Market, and Jamestown Harbour Yard test places.

## Release Verification

- Archive and App Store IPA export succeeded.
- Apple validation initially caught a stale simulator `objective_c.framework` native asset in the IPA.
- The archive was corrected with the device-only `objective_c` framework, re-signed, re-exported, and revalidated.
- Apple validation passed with no errors for `build/ios/ipa-fixed/Vennuzo.ipa`.
- IPA upload to App Store Connect succeeded.
- Build `2026060801` processed to `VALID`.
- Export compliance was set to `usesNonExemptEncryption=false`.
- Build `2026060801` was attached to App Store version `1.0`.
- Version `1.0` was submitted to App Review and is waiting for review.
