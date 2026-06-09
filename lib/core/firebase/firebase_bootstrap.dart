import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

class FirebaseBootstrap {
  static Future<bool> initialize() async {
    if (kIsWeb) {
      return false;
    }

    final supported = switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      TargetPlatform.macOS => true,
      _ => false,
    };
    if (!supported) {
      return false;
    }

    if (Firebase.apps.isNotEmpty) {
      await _activateAppCheck();
      return true;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _activateAppCheck();
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'duplicate-app') {
        await _activateAppCheck();
        return true;
      }
      debugPrint(
        'Vennuzo Firebase initialization failed: ${error.code} ${error.message ?? ''}',
      );
      return false;
    }
  }

  /// Activates Firebase App Check so an attestation token is attached to
  /// backend requests (Firestore, Cloud Functions, Storage). Enforcement is
  /// NOT turned on here — that is a Firebase console step taken after a
  /// monitoring period. Until then, activation must be non-fatal: any failure
  /// is logged and startup continues unaffected.
  ///
  /// Providers (release builds):
  ///   - iOS:     App Attest, automatically falling back to Device Check on
  ///              OS versions that lack App Attest support (iOS < 14).
  ///   - Android: Play Integrity.
  ///   - Debug:   debug providers so local/dev/simulator runs still get tokens.
  static Future<void> _activateAppCheck() async {
    try {
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (error) {
      debugPrint('Vennuzo Firebase App Check activation skipped: $error');
    }
  }
}
