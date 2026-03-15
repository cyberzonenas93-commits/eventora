import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB_1Baw7fcXLtG4WutG4OeUfQNSCZDRpJ8',
    appId: '1:872808273884:android:1c19ea85767aa0d88c2119',
    messagingSenderId: '872808273884',
    projectId: 'eventora-10063',
    storageBucket: 'eventora-10063.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBGjRTuEircFcvXjQoDOAhXwSXQoB91ZBw',
    appId: '1:872808273884:ios:938b3b6a19e1b0068c2119',
    messagingSenderId: '872808273884',
    projectId: 'eventora-10063',
    storageBucket: 'eventora-10063.firebasestorage.app',
    iosBundleId: 'com.eventora.app',
  );
}
