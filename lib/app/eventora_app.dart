import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services/eventora_notification_service.dart';
import '../core/theme/eventora_theme.dart';
import '../data/repositories/eventora_repository.dart';
import '../features/root/eventora_root_screen.dart';
import 'eventora_session_controller.dart';

class EventoraApp extends StatelessWidget {
  const EventoraApp({super.key, this.firebaseEnabled = true});

  final bool firebaseEnabled;

  @override
  Widget build(BuildContext context) {
    EventoraNotificationService.instance.initialize(
      firebaseEnabled: firebaseEnabled,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              EventoraSessionController(firebaseEnabled: firebaseEnabled),
        ),
        ChangeNotifierProxyProvider<
          EventoraSessionController,
          EventoraRepository
        >(
          create: (_) =>
              EventoraRepository.seeded(firebaseEnabled: firebaseEnabled),
          update: (_, session, repository) =>
              (repository ??
                    EventoraRepository.seeded(firebaseEnabled: firebaseEnabled))
                ..applyViewer(session.viewer),
        ),
      ],
      child: MaterialApp(
        title: 'Eventora',
        debugShowCheckedModeBanner: false,
        theme: EventoraTheme.lightTheme,
        home: const EventoraRootScreen(),
      ),
    );
  }
}
