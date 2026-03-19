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

    final shouldShow = await VennuzoLaunchPreferences.shouldShowOnboarding();
    if (!mounted) {
      return;
    }
    setState(() {
      _isCheckingOnboarding = false;
      _showOnboarding = shouldShow;
    });
  }

  Future<void> _finishOnboarding() async {
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

    if (session.needsWorkspaceChoice) {
      return const AdminFaceChooserScreen();
    }

    if (session.isAdminWorkspace) {
      return const AdminShellScreen();
    }

    return const VennuzoShellScreen();
  }
}

class _RootLoadingScreen extends StatelessWidget {
  const _RootLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: VennuzoSplashStage(subtitle: null, showLoader: true),
    );
  }
}
