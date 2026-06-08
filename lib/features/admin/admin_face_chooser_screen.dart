import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';

class AdminFaceChooserScreen extends StatelessWidget {
  const AdminFaceChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final viewer = session.viewer;
    final palette = context.palette;
    const cardText = Color(0xFF09111F);
    const cardSubtleText = Color(0xFF42526A);
    final tiles = <Widget>[
      if (viewer.canUseAttendeeWorkspace)
        _WorkspaceTile(
          title: 'Vennuzo app',
          subtitle: 'Discover events, RSVP, tickets, saves, and your profile.',
          icon: Icons.explore_outlined,
          accent: const Color(0xFF0A7C86),
          textColor: cardText,
          subtitleColor: cardSubtleText,
          onTap: session.enterAttendeeWorkspace,
        ),
      if (viewer.hasOrganizerAccess)
        _WorkspaceTile(
          title: 'Organizer portal',
          subtitle:
              'Manage events, ticket sales, payouts, campaigns, creative, and audiences.',
          icon: Icons.storefront_outlined,
          accent: const Color(0xFF7C3AED),
          textColor: cardText,
          subtitleColor: cardSubtleText,
          onTap: session.enterOrganizerWorkspace,
        ),
      if (viewer.hasAdminAccess)
        _WorkspaceTile(
          title: viewer.hasSuperAdminAccess
              ? 'Superadmin console'
              : 'Admin console',
          subtitle: viewer.hasSuperAdminAccess
              ? 'Global oversight for events, gate ops, campaigns, admins, and platform settings.'
              : 'Operations tools for events, ticket desks, campaigns, and admin utilities.',
          icon: viewer.hasSuperAdminAccess
              ? Icons.shield_outlined
              : Icons.admin_panel_settings_outlined,
          accent: const Color(0xFFBE185D),
          textColor: cardText,
          subtitleColor: cardSubtleText,
          onTap: session.enterAdminWorkspace,
        ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.darkSurface,
                    palette.darkSurfaceMid,
                    palette.coral.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const SizedBox.expand(),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Card(
                            color: Colors.white.withValues(alpha: 0.94),
                            surfaceTintColor: Colors.transparent,
                            shadowColor: Colors.black.withValues(alpha: 0.28),
                            child: Padding(
                              padding: const EdgeInsets.all(22),
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
                                  const SizedBox(height: 14),
                                  Text(
                                    'Welcome back, ${viewer.displayName}.',
                                    style: context.text.headlineSmall?.copyWith(
                                      color: cardText,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'This account has more than one Vennuzo face. Pick your workspace.',
                                    style: context.text.bodyLarge?.copyWith(
                                      color: cardSubtleText,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  for (
                                    var index = 0;
                                    index < tiles.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(height: 10),
                                    tiles[index],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
    required this.textColor,
    required this.subtitleColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color textColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open $title workspace',
      hint: subtitle,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleLarge?.copyWith(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: subtitleColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
