import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services/eventora_deep_link_service.dart';
import '../data/services/eventora_notification_service.dart';
import '../core/theme/eventora_theme.dart';
import '../data/repositories/eventora_repository.dart';
import '../features/root/eventora_root_screen.dart';
import 'eventora_session_controller.dart';

class EventoraApp extends StatefulWidget {
  const EventoraApp({
    super.key,
    this.firebaseEnabled = true,
    this.skipLaunchOnboarding = false,
  });

  final bool firebaseEnabled;
  final bool skipLaunchOnboarding;

  @override
  State<EventoraApp> createState() => _EventoraAppState();
}

class _EventoraAppState extends State<EventoraApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    EventoraNotificationService.instance.initialize(
      firebaseEnabled: widget.firebaseEnabled,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EventoraDeepLinkService.instance.initialize(navigatorKey: _navigatorKey);
    });
  }

  @override
  void dispose() {
    EventoraDeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => EventoraSessionController(
            firebaseEnabled: widget.firebaseEnabled,
          ),
        ),
        ChangeNotifierProxyProvider<
          EventoraSessionController,
          EventoraRepository
        >(
          create: (_) => EventoraRepository.seeded(
            firebaseEnabled: widget.firebaseEnabled,
          ),
          update: (_, session, repository) =>
              (repository ??
                    EventoraRepository.seeded(
                      firebaseEnabled: widget.firebaseEnabled,
                    ))
                ..applyViewer(session.viewer),
        ),
      ],
      child: MaterialApp(
        title: 'Eventora',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: EventoraTheme.lightTheme,
        home: EventoraRootScreen(
          skipLaunchOnboarding: widget.skipLaunchOnboarding,
        ),
      ),
    );
  }
}
