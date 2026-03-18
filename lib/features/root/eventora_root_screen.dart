import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../data/services/eventora_launch_preferences.dart';
import '../admin/admin_face_chooser_screen.dart';
import '../onboarding/eventora_onboarding_screen.dart';
import '../admin/admin_shell_screen.dart';
import '../shell/eventora_shell_screen.dart';
import '../../widgets/eventora_splash_stage.dart';

class EventoraRootScreen extends StatefulWidget {
  const EventoraRootScreen({super.key, this.skipLaunchOnboarding = false});

  final bool skipLaunchOnboarding;

  @override
  State<EventoraRootScreen> createState() => _EventoraRootScreenState();
}

class _EventoraRootScreenState extends State<EventoraRootScreen> {
  bool _isCheckingOnboarding = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
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

    final shouldShow = await EventoraLaunchPreferences.shouldShowOnboarding();
    if (!mounted) {
      return;
    }
    setState(() {
      _isCheckingOnboarding = false;
      _showOnboarding = shouldShow;
    });
  }

  Future<void> _finishOnboarding() async {
    await EventoraLaunchPreferences.markOnboardingCompleted();
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
      return EventoraOnboardingScreen(onFinished: _finishOnboarding);
    }

    final session = context.watch<EventoraSessionController>();

    if (session.isInitializing) {
      return const _RootLoadingScreen();
    }

    if (session.needsWorkspaceChoice) {
      return const AdminFaceChooserScreen();
    }

    if (session.isAdminWorkspace) {
      return const AdminShellScreen();
    }

    return const EventoraShellScreen();
  }
}

class _RootLoadingScreen extends StatelessWidget {
  const _RootLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: EventoraSplashStage(subtitle: null, showLoader: true),
    );
  }
}
