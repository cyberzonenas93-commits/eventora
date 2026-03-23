import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services/vennuzo_deep_link_service.dart';
import '../data/services/vennuzo_notification_service.dart';
import '../core/theme/vennuzo_theme.dart';
import '../data/repositories/vennuzo_repository.dart';
import '../features/events/event_detail_screen.dart';
import '../features/root/vennuzo_root_screen.dart';
import 'vennuzo_session_controller.dart';

class VennuzoApp extends StatefulWidget {
  const VennuzoApp({
    super.key,
    this.firebaseEnabled = true,
    this.skipLaunchOnboarding = false,
  });

  final bool firebaseEnabled;
  final bool skipLaunchOnboarding;

  @override
  State<VennuzoApp> createState() => _VennuzoAppState();
}

class _VennuzoAppState extends State<VennuzoApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    VennuzoNotificationService.instance.initialize(
      firebaseEnabled: widget.firebaseEnabled,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VennuzoDeepLinkService.instance.initialize(navigatorKey: _navigatorKey);
      VennuzoNotificationService.instance.setNotificationOpenedHandler((message) {
        final eventId = message.data['eventId']?.trim();
        if (eventId == null || eventId.isEmpty) return;
        final navigator = _navigatorKey.currentState;
        if (navigator == null) return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(eventId: eventId),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    VennuzoDeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => VennuzoSessionController(
            firebaseEnabled: widget.firebaseEnabled,
          ),
        ),
        ChangeNotifierProxyProvider<
          VennuzoSessionController,
          VennuzoRepository
        >(
          create: (_) => VennuzoRepository.seeded(
            firebaseEnabled: widget.firebaseEnabled,
          ),
          update: (_, session, repository) =>
              (repository ??
                    VennuzoRepository.seeded(
                      firebaseEnabled: widget.firebaseEnabled,
                    ))
                ..applyViewer(session.viewer),
        ),
      ],
      child: MaterialApp(
        title: 'Vennuzo',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: VennuzoTheme.lightTheme,
        home: VennuzoRootScreen(
          skipLaunchOnboarding: widget.skipLaunchOnboarding,
        ),
      ),
    );
  }
}
