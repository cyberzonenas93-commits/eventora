# App Store Submission Notes - 2026-06-07

## App Store Connect

- App: Vennuzo
- Apple ID: 6761087972
- Bundle ID: com.vennuzo.app
- App Store version record: 1.0
- Uploaded build: 2026060701
- Build ID: b7d7315f-6966-4515-81fa-f0e6cf6a20fe
- Delivery UUID: b7d7315f-6966-4515-81fa-f0e6cf6a20fe
- Canceled review submission ID: c158b67b-c5e7-4854-800e-9605d2192eaa
- Current review submission ID: d05eeb8b-3f20-460f-9451-79dd89ec6112
- Review submission state: WAITING_FOR_REVIEW
- IPA: build/ios/ipa/Vennuzo.ipa

## QA Gates

- `flutter analyze`: passed
- `flutter test`: passed, 21 tests
- `npm test` in `functions`: passed, 34 tests across 3 suites
- `npm test` in `studio`: passed, 5 tests
- `npm run build` in `studio`: passed
- `npm run lint` in `studio`: passed after accessibility and hook-dependency fixes
- iOS Simulator smoke test on iPhone 16e: passed

## Release Verification

- Archive and App Store IPA export succeeded.
- IPA binary values:
  - CFBundleIdentifier: com.vennuzo.app
  - CFBundleShortVersionString: 1.0.0
  - CFBundleVersion: 2026060701
- Apple validation passed with no errors for `build/ios/ipa/Vennuzo.ipa`.
- IPA upload to App Store Connect succeeded.
- Build `2026060701` processed to `VALID`.
- Export compliance was set to `usesNonExemptEncryption=false`.
- Build `2026060701` was attached to App Store version `1.0`.
- Version `1.0` was submitted to App Review and is waiting for review.

## Notes

- The previous waiting submission was canceled so the new build could replace the attached build.
- Local disk pressure caused one transient upload-state error during upload; disposable Vennuzo build caches were cleared and the upload recovered successfully.
