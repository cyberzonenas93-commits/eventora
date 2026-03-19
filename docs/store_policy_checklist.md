# Vennuzo Store Policy Checklist

This app now includes the main code-level safeguards that matter most for App Store and Play review:

- Guest access is available without forcing account creation.
- Account deletion is available inside the app.
- Phone number is optional at signup.
- Public event content now has an in-app reporting path.
- Ticket sales are treated as real-world event services rather than digital in-app content.
- Push notifications can be disabled in-app.
- SMS updates can be disabled in-app.
- Promotional event campaigns are gated behind explicit marketing opt-in.

## Official policy anchors

- Apple App Store Review Guidelines:
  - Account deletion and data minimization: [5.1.1 Data Collection and Storage](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
  - User-generated content safeguards: [1.2 User-Generated Content](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
  - Real-world services and ticketing payments: [3.1.5(a) Goods and Services Outside of the App](https://developer.apple.com/app-store/review/guidelines/#goods-and-services-outside-of-the-app)
- Google Play policy/help:
  - In-app account deletion: [Data deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
  - Real-world goods and services payments: [Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818)
  - User-generated content safeguards: [User generated content policy](https://support.google.com/googleplay/android-developer/answer/9876937)
  - User data minimization and disclosure: [User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311)

## Implemented in this build

- Guest browsing:
  - Public event discovery works without requiring signup.
  - Organizer-only surfaces prompt for sign-in instead of blocking the entire app.
- Account creation:
  - Signup uses display name, email, and password.
  - Phone number is optional and only stored if the user provides it.
- Account deletion:
  - Signed-in users can delete their account in-app.
  - The current flow deletes the Firebase Auth user and the `users/{uid}` profile document.
- Notifications:
  - FCM tokens are only stored for signed-in users with push enabled.
  - SMS and push preferences are editable inside the account screen.
  - Marketing campaigns only target opted-in attendees.
- Content reporting:
  - Event details include a report flow that submits to `event_reports`.

## Remaining release checklist before submission

- Publish a live privacy policy URL in both App Store Connect and Play Console metadata.
- Publish a support URL or support email in store metadata.
- Add backend-driven deletion for future live collections such as ticket orders, RSVPs, campaigns, and uploaded assets once those move fully to Firebase.
- Add moderation operations on the backend or admin side so `event_reports` are reviewed promptly.
- Make sure store screenshots and review notes clearly mention guest browsing and where account deletion lives.
- Keep any external ticket-payment copy focused on real-world event access, not digital unlocks.
