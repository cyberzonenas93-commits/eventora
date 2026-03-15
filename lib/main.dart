import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/eventora_app.dart';
import 'core/firebase/firebase_bootstrap.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.initialize();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseEnabled = await FirebaseBootstrap.initialize();
  if (firebaseEnabled) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  runApp(EventoraApp(firebaseEnabled: firebaseEnabled));
}
