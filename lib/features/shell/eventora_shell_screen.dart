import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../account/account_screen.dart';
import '../account/auth_prompt_sheet.dart';
import '../events/event_editor_screen.dart';
import '../promotions/campaign_composer_sheet.dart';
import '../promotions/promotions_screen.dart';
import '../discover/discover_screen.dart';
import '../manage/manage_screen.dart';
import '../tickets/tickets_screen.dart';

class EventoraShellScreen extends StatefulWidget {
  const EventoraShellScreen({super.key});

  @override
  State<EventoraShellScreen> createState() => _EventoraShellScreenState();
}

class _EventoraShellScreenState extends State<EventoraShellScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = const [
    DiscoverScreen(),
    ManageScreen(),
    TicketsScreen(),
    PromotionsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ShellHeader(
                  badgeLabel: session.viewer.badgeLabel,
                  viewerName: session.viewer.displayName,
                  isGuest: session.isGuest,
                  isBusy: session.isInitializing || session.isProcessing,
                  canSwitchWorkspace: session.canChooseWorkspace,
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
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A10212A),
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
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.explore_outlined),
                  activeIcon: Icon(Icons.explore),
                  label: 'Discover',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.edit_calendar_outlined),
                  activeIcon: Icon(Icons.edit_calendar),
                  label: 'Manage',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.confirmation_num_outlined),
                  activeIcon: Icon(Icons.confirmation_num),
                  label: 'Tickets',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.campaign_outlined),
                  activeIcon: Icon(Icons.campaign),
                  label: 'Promote',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildFab(BuildContext context) {
    final palette = context.palette;
    final session = context.read<EventoraSessionController>();

    if (_currentIndex == 1) {
      return FloatingActionButton.extended(
        onPressed: () {
          if (session.isGuest) {
            showAuthPromptSheet(
              context,
              title: 'Create events with an account',
              body:
                  'Guest mode is perfect for discovery. Sign in when you are ready to publish events and manage ticketing.',
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const EventEditorScreen()),
          );
        },
        backgroundColor: palette.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      );
    }

    if (_currentIndex == 3) {
      return FloatingActionButton.extended(
        onPressed: () async {
          if (session.isGuest) {
            await showAuthPromptSheet(
              context,
              title: 'Campaign tools need an account',
              body:
                  'Sign in to launch push, SMS, and share-link campaigns from your Eventora workspace.',
            );
            return;
          }
          final campaign = await showCampaignComposerSheet(context);
          if (campaign != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Campaign "${campaign.name}" launched.')),
            );
          }
        },
        backgroundColor: palette.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_graph_outlined),
        label: const Text('Campaign'),
      );
    }

    return null;
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.badgeLabel,
    required this.viewerName,
    required this.isGuest,
    required this.isBusy,
    required this.canSwitchWorkspace,
    required this.onSwitchWorkspace,
  });

  final String badgeLabel;
  final String viewerName;
  final bool isGuest;
  final bool isBusy;
  final bool canSwitchWorkspace;
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
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeLabel,
                    style: context.text.bodyMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Eventora', style: context.text.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  isGuest
                      ? 'Browse live events without signing up.'
                      : 'Welcome back, $viewerName.',
                  style: context.text.bodyMedium?.copyWith(
                    color: palette.slate,
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                onPressed: onSwitchWorkspace,
                icon: const Icon(Icons.swap_horiz_outlined),
                tooltip: 'Switch workspace',
              ),
            ),
          IconButton.filledTonal(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              );
            },
            icon: const Icon(Icons.person_outline),
            tooltip: 'Account',
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -50,
          child: _Blob(
            size: 260,
            colors: [
              palette.coral.withValues(alpha: 0.14),
              palette.gold.withValues(alpha: 0.06),
            ],
          ),
        ),
        Positioned(
          bottom: 100,
          left: -90,
          child: _Blob(
            size: 220,
            colors: [
              palette.teal.withValues(alpha: 0.14),
              palette.canvas.withValues(alpha: 0.04),
            ],
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.colors});

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
