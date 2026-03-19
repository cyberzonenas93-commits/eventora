import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../features/events/event_detail_screen.dart';

class VennuzoDeepLinkService {
  VennuzoDeepLinkService._();

  static final VennuzoDeepLinkService instance = VennuzoDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;
  String? _lastHandledEventId;

  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final initialLink = await _appLinks.getInitialLink();
      _handleUri(initialLink);
    } catch (error) {
      debugPrint('Initial deep link lookup failed: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error) {
        debugPrint('Deep link stream error: $error');
      },
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  void _handleUri(Uri? uri) {
    final eventId = _extractEventId(uri);
    if (eventId == null || eventId == _lastHandledEventId) {
      return;
    }

    _lastHandledEventId = eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey?.currentState;
      if (navigator == null) {
        return;
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
    });
  }

  String? _extractEventId(Uri? uri) {
    if (uri == null || uri.scheme != 'vennuzoapp') {
      return null;
    }

    final queryEventId = uri.queryParameters['eventId']?.trim();
    if (queryEventId != null && queryEventId.isNotEmpty) {
      return queryEventId;
    }

    final segments = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ];
    if (segments.length >= 3 &&
        segments.first == 'share' &&
        segments[1] == 'event') {
      final pathEventId = segments[2].trim();
      if (pathEventId.isNotEmpty) {
        return pathEventId;
      }
    }

    return null;
  }
}
