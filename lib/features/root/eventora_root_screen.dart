import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../admin/admin_face_chooser_screen.dart';
import '../admin/admin_shell_screen.dart';
import '../shell/eventora_shell_screen.dart';

class EventoraRootScreen extends StatelessWidget {
  const EventoraRootScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
    final palette = context.palette;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.ink,
              palette.ink.withValues(alpha: 0.9),
              palette.coral.withValues(alpha: 0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.white.withValues(alpha: 0.92),
                strokeWidth: 2.8,
              ),
              const SizedBox(height: 20),
              Text(
                'Loading Eventora',
                style: context.text.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Powered by GPLUS',
                style: context.text.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
