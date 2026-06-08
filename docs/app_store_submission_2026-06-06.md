# App Store Submission Notes - 2026-06-06

## App Store Connect

- App: Vennuzo
- Apple ID: 6761087972
- Bundle ID: com.vennuzo.app
- App Store version record: 1.0
- Uploaded build: 2026060601
- Delivery UUID: a603c8d6-98a6-45dd-9a4a-0c314a5acac0
- Previous review submission ID: 97708ac2-0dce-4c6d-8c96-d38bceb89a12 (canceled to unlock screenshot metadata)
- Current review submission ID: f6717cd0-d918-4af9-91f2-b8da0de7dd22
- Review submission state: WAITING_FOR_REVIEW
- IPA: build/ios/ipa/Vennuzo.ipa

## Public Links

- Privacy policy: https://vennuzo-pages.web.app/privacy-policy.html
- Support URL: https://vennuzo-pages.web.app/support.html

Both pages were deployed to Firebase Hosting target `pages` and verified with HTTP 200 responses.

## Verification

- Simulator launches completed on iPhone 16e, iPhone 17 Pro Max, and iPad Pro 13-inch.
- Fresh screenshots were captured under:
  - screenshots/appstore-submit/iphone-6-9
  - screenshots/appstore-submit/ipad-13
- App Store Connect screenshot sets were replaced and fully processed:
  - APP_IPHONE_67: 6 screenshots
  - APP_IPAD_PRO_3GEN_129: 4 screenshots
- Archive and IPA export succeeded.
- Apple validation passed with no errors for `build/ios/ipa/Vennuzo.ipa`.
- IPA upload to App Store Connect succeeded.
- Build `2026060601` was attached to App Store version `1.0`.
- Export compliance was set to `usesNonExemptEncryption=false`.
- The initial review submission was canceled because screenshots cannot be uploaded while a version is `WAITING_FOR_REVIEW`.
- Fresh iPhone and iPad screenshots were uploaded through App Store Connect asset reservations and reached `COMPLETE`.
- The version was resubmitted to App Review and is waiting for review.

## Binary Checks

- CFBundleIdentifier: com.vennuzo.app
- CFBundleShortVersionString: 1.0.0
- CFBundleVersion: 2026060601
- Signing certificate: Apple Distribution
- APNs entitlement: production
- Sign in with Apple entitlement: present
- get-task-allow: false

## Privacy / Data Collection

Based on the app code, Info.plist permissions, Firebase services, Google Maps, Hubtel payment flow, image/file upload, QR scanning, push notifications, and the live privacy policy:

- Tracking: No. No ATT usage description was found and no cross-app advertising tracking flow was identified.
- Contact Info: collected and linked to the user for account, organizer, support, and payment/contact workflows.
- User Content: collected and linked to the user for profile images, event content, social posts, uploaded images/files, and support chat.
- Identifiers: collected and linked to the user for Firebase user IDs, installation/device messaging tokens, and app/account identifiers.
- Location: collected when the user grants permission for event discovery, event location, maps, and nearby/event placement features.
- Purchases / Financial Info: transaction/payment details are processed through Hubtel; full card details are not stored by Vennuzo.
- Usage Data: collected for app functionality, event activity, campaigns, and operational analytics where applicable.
- Diagnostics: collect if enabled by integrated services or Apple/app operational tooling.
- Sensitive categories not observed: health, fitness, contacts address book, browsing history, search history, and precise advertising tracking data.

App Store Connect already has the privacy policy URL set. The data-type questionnaire itself is a self-reported ASC privacy-label form and should match the categories above before final review submission.
