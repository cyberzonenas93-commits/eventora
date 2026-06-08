import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../data/services/vennuzo_launch_preferences.dart';
import '../admin/admin_face_chooser_screen.dart';
import '../onboarding/vennuzo_onboarding_screen.dart';
import '../admin/admin_shell_screen.dart';
import '../shell/vennuzo_shell_screen.dart';
import '../../widgets/vennuzo_splash_stage.dart';

class VennuzoRootScreen extends StatefulWidget {
  const VennuzoRootScreen({super.key, this.skipLaunchOnboarding = false});

  final bool skipLaunchOnboarding;

  @override
  State<VennuzoRootScreen> createState() => _VennuzoRootScreenState();
}

class _VennuzoRootScreenState extends State<VennuzoRootScreen> {
  bool _isCheckingOnboarding = true;
  bool _showOnboarding = false;
  String? _syncingOnboardingPrefsForUid;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/logo-splash-opaque.png'), context);
    precacheImage(const AssetImage('assets/logo.png'), context);
  }

  Future<void> _loadOnboardingState() async {
    if (widget.skipLaunchOnboarding) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingOnboarding = false;
        _showOnboarding = false;
      });
      return;
    }

    final shouldShow = await VennuzoLaunchPreferences.shouldShowOnboarding();
    if (!mounted) {
      return;
    }
    setState(() {
      _isCheckingOnboarding = false;
      _showOnboarding = shouldShow;
    });
  }

  Future<void> _finishOnboarding(
    VennuzoOnboardingPreferences preferences,
  ) async {
    await VennuzoLaunchPreferences.saveOnboardingPreferences(preferences);
    await VennuzoLaunchPreferences.markOnboardingCompleted();
    if (!mounted) {
      return;
    }
    setState(() {
      _showOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingOnboarding) {
      return const _RootLoadingScreen();
    }

    if (_showOnboarding) {
      return VennuzoOnboardingScreen(onFinished: _finishOnboarding);
    }

    final session = context.watch<VennuzoSessionController>();

    if (session.isInitializing) {
      return const _RootLoadingScreen();
    }

    _maybeSyncOnboardingPreferences(session);

    if (session.needsWorkspaceChoice) {
      return const AdminFaceChooserScreen();
    }

    if (session.isAdminWorkspace) {
      return const AdminShellScreen();
    }

    return const VennuzoShellScreen();
  }

  void _maybeSyncOnboardingPreferences(VennuzoSessionController session) {
    final uid = session.viewer.uid;
    if (!session.firebaseEnabled ||
        session.isProcessing ||
        uid == null ||
        uid.isEmpty ||
        _syncingOnboardingPrefsForUid == uid) {
      return;
    }

    _syncingOnboardingPrefsForUid = uid;
    unawaited(() async {
      try {
        final shouldSync =
            await VennuzoLaunchPreferences.shouldSyncOnboardingPreferencesFor(
              uid,
            );
        if (!shouldSync) return;
        final prefs =
            await VennuzoLaunchPreferences.loadOnboardingPreferences();
        await session.updateNotificationPrefs(
          marketingOptIn:
              session.viewer.notificationPrefs.marketingOptIn ||
              prefs.marketingOptIn,
          promotionalPushEnabled: prefs.promotionalPushEnabled,
          promotionalEventTypes: prefs.categoryIds,
          promotionalCities: prefs.city.trim().isEmpty
              ? const <String>[]
              : <String>[prefs.city.trim()],
        );
        await VennuzoLaunchPreferences.markOnboardingPreferencesSynced(uid);
      } catch (_) {
        _syncingOnboardingPrefsForUid = null;
      }
    }());
  }
}

class _RootLoadingScreen extends StatelessWidget {
  const _RootLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: VennuzoSplashStage(subtitle: null, showLoader: true),
    );
  }
}
