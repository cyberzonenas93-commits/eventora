import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/section_heading.dart';
import 'admin_organizer_approvals_screen.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();
    final viewer = session.viewer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _AdminToolsHero(
          displayName: viewer.displayName,
          adminRole:
              viewer.adminRole ??
              (session.hasSuperAdminAccess ? 'superadmin' : 'admin'),
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Team access',
          subtitle:
              'Manage role-based access, ticket-desk permissions, and campaign control for the admin team.',
        ),
        const SizedBox(height: 14),
        const _RoleCard(
          title: 'Superadmin',
          subtitle:
              'Platform-wide oversight, report review, admin management, and high-trust controls.',
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: 12),
        const _RoleCard(
          title: 'Admin / Event manager',
          subtitle:
              'Manage event publishing, RSVP lists, ticket operations, and event analytics.',
          icon: Icons.manage_accounts_outlined,
        ),
        const SizedBox(height: 12),
        const _RoleCard(
          title: 'Check-in staff',
          subtitle:
              'Ticket lookup, QR validation, admission logs, and cash-at-gate collection.',
          icon: Icons.qr_code_scanner_outlined,
        ),
        const SizedBox(height: 12),
        const _RoleCard(
          title: 'Marketing manager',
          subtitle:
              'Push campaigns, SMS audiences, share links, and event promotion scheduling.',
          icon: Icons.campaign_outlined,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Admin utilities',
          subtitle:
              'These are the control-room features that matter most for the event-only product.',
        ),
        const SizedBox(height: 14),
        const _AdminUtilityCard(
          title: 'Notification jobs',
          body:
              'Inspect queued push and SMS jobs, reminder flow health, and campaign delivery history.',
          icon: Icons.notifications_active_outlined,
        ),
        const SizedBox(height: 12),
        const _AdminUtilityCard(
          title: 'Reports & moderation',
          body:
              'Review event reports, handle support escalations, and keep organizer content safe and store-compliant.',
          icon: Icons.flag_outlined,
        ),
        const SizedBox(height: 12),
        const _AdminUtilityCard(
          title: 'Admin settings',
          body:
              'Configure organization-level defaults, operator access, and future payment or check-in policies.',
          icon: Icons.settings_outlined,
        ),
        if (session.hasSuperAdminAccess) ...[
          const SizedBox(height: 28),
          SectionHeading(
            title: 'Platform layer',
            subtitle:
                'Reserved for multi-organization Eventora operations as the product grows.',
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Organizer approvals',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Review Eventora Studio applications, approve organizer teams, and provision organization access from one superadmin queue.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.palette.slate,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const AdminOrganizerApprovalsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.approval_outlined),
                      label: const Text('Open approval queue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 28),
          const EmptyStateCard(
            title: 'Superadmin tools are reserved',
            body:
                'Platform analytics, organizer approvals, payouts, and support governance stay behind superadmin access.',
            icon: Icons.admin_panel_settings_outlined,
          ),
        ],
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Workspace actions',
          subtitle:
              'Switch between the customer-facing Eventora experience and the admin console without signing out when your credentials allow both.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session.canChooseWorkspace) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        session.openWorkspaceChooser();
                      },
                      icon: const Icon(Icons.swap_horiz_outlined),
                      label: const Text('Switch workspace'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: session.isProcessing
                        ? null
                        : () => _signOut(context),
                    child: Text(
                      session.isProcessing ? 'Signing out...' : 'Sign out',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await context.read<EventoraSessionController>().signOut();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out of Eventora admin console.')),
      );
    } on EventoraAuthFailure catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _AdminToolsHero extends StatelessWidget {
  const _AdminToolsHero({required this.displayName, required this.adminRole});

  final String displayName;
  final String adminRole;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.84),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin tools',
            style: context.text.titleLarge?.copyWith(fontSize: 21),
          ),
          const SizedBox(height: 12),
          Text(
            '$displayName is signed in as ${adminRole.toUpperCase()}.',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Use this panel for access control, report-handling, notification oversight, and workspace switching.',
            style: context.text.bodyLarge?.copyWith(
              color: context.palette.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: context.palette.canvas,
          foregroundColor: context.palette.ink,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _AdminUtilityCard extends StatelessWidget {
  const _AdminUtilityCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: context.palette.canvas,
              foregroundColor: context.palette.ink,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleLarge?.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(body, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
