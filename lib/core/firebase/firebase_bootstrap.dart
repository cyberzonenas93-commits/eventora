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
      return true;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'duplicate-app') {
        return true;
      }
      debugPrint(
        'Vennuzo Firebase initialization failed: ${error.code} ${error.message ?? ''}',
      );
      return false;
    }
  }
}
