import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../account/account_screen.dart';
import '../events/event_editor_screen.dart';
import '../promotions/campaign_composer_sheet.dart';
import 'admin_campaigns_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_events_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_tickets_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = const [
    AdminDashboardScreen(),
    AdminEventsScreen(),
    AdminTicketsScreen(),
    AdminCampaignsScreen(),
    AdminSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();

    return Scaffold(
      body: Stack(
        children: [
          const _AdminBackdrop(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _AdminHeader(
                  badgeLabel: session.viewer.badgeLabel,
                  viewerName: session.viewer.displayName,
                  canSwitchWorkspace: session.canChooseWorkspace,
                  isBusy: session.isProcessing || session.isInitializing,
                  onSwitchWorkspace: session.openWorkspaceChooser,
                ),
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: _screens),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF12242D),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3B000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              showUnselectedLabels: true,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white.withValues(alpha: 0.58),
              backgroundColor: Colors.transparent,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.space_dashboard_outlined),
                  activeIcon: Icon(Icons.space_dashboard),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.event_note_outlined),
                  activeIcon: Icon(Icons.event_note),
                  label: 'Events',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  activeIcon: Icon(Icons.qr_code_scanner),
                  label: 'Tickets',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.campaign_outlined),
                  activeIcon: Icon(Icons.campaign),
                  label: 'Campaigns',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  activeIcon: Icon(Icons.admin_panel_settings),
                  label: 'Admin',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildFab(BuildContext context) {
    if (_currentIndex == 1) {
      return FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const EventEditorScreen()),
          );
        },
        backgroundColor: context.palette.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      );
    }

    if (_currentIndex == 3) {
      return FloatingActionButton.extended(
        onPressed: () async {
          final campaign = await showCampaignComposerSheet(context);
          if (campaign != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Campaign "${campaign.name}" launched.')),
            );
          }
        },
        backgroundColor: context.palette.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.send_outlined),
        label: const Text('Launch'),
      );
    }

    return null;
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({
    required this.badgeLabel,
    required this.viewerName,
    required this.canSwitchWorkspace,
    required this.isBusy,
    required this.onSwitchWorkspace,
  });

  final String badgeLabel;
  final String viewerName;
  final bool canSwitchWorkspace;
  final bool isBusy;
  final VoidCallback onSwitchWorkspace;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeLabel,
                    style: context.text.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Vennuzo Admin',
                  style: context.text.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Operations console for $viewerName.',
                  style: context.text.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          if (canSwitchWorkspace)
            IconButton.filledTonal(
              onPressed: onSwitchWorkspace,
              style: IconButton.styleFrom(
                backgroundColor: palette.teal.withValues(alpha: 0.24),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.swap_horiz_outlined),
              tooltip: 'Switch workspace',
            ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.person_outline),
            tooltip: 'Account',
          ),
        ],
      ),
    );
  }
}

class _AdminBackdrop extends StatelessWidget {
  const _AdminBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF081319)),
        Positioned(
          top: -90,
          right: -40,
          child: _BlurBlob(
            size: 240,
            colors: [
              context.palette.teal.withValues(alpha: 0.22),
              context.palette.teal.withValues(alpha: 0),
            ],
          ),
        ),
        Positioned(
          bottom: -120,
          left: -40,
          child: _BlurBlob(
            size: 300,
            colors: [
              context.palette.coral.withValues(alpha: 0.2),
              context.palette.coral.withValues(alpha: 0),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlurBlob extends StatelessWidget {
  const _BlurBlob({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
