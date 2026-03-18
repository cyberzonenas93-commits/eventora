import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';

class AdminFaceChooserScreen extends StatelessWidget {
  const AdminFaceChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();
    final viewer = session.viewer;
    final palette = context.palette;

    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.ink,
                  palette.ink.withValues(alpha: 0.95),
                  palette.coral.withValues(alpha: 0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: -40,
            right: -20,
            child: _GlowOrb(
              color: palette.gold.withValues(alpha: 0.24),
              size: 220,
            ),
          ),
          Positioned(
            bottom: -30,
            left: -10,
            child: _GlowOrb(
              color: palette.teal.withValues(alpha: 0.2),
              size: 260,
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: palette.canvas,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Choose your workspace',
                              style: context.text.bodyMedium?.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Welcome back, ${viewer.displayName}.',
                            style: context.text.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'This account can open both the attendee experience and the admin console. Pick the side you want right now.',
                            style: context.text.bodyLarge?.copyWith(
                              color: palette.slate,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _WorkspaceTile(
                            title: 'Eventora app',
                            subtitle:
                                'Open the main Eventora experience for discovery, RSVP, tickets, and organizer tools.',
                            icon: Icons.explore_outlined,
                            accent: palette.coral,
                            onTap: session.enterAttendeeWorkspace,
                          ),
                          const SizedBox(height: 14),
                          _WorkspaceTile(
                            title: viewer.hasSuperAdminAccess
                                ? 'Superadmin console'
                                : 'Admin console',
                            subtitle: viewer.hasSuperAdminAccess
                                ? 'Global oversight for events, gate operations, campaigns, admins, and platform-level settings.'
                                : 'Operations-first tools for event ops, ticket desks, campaigns, audience routing, and admin utilities.',
                            icon: viewer.hasSuperAdminAccess
                                ? Icons.shield_outlined
                                : Icons.admin_panel_settings_outlined,
                            accent: palette.teal,
                            onTap: session.enterAdminWorkspace,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1410212A),
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: context.text.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: accent),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
