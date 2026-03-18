import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../widgets/eventora_motion.dart';
import '../account/account_screen.dart';
import '../discover/discover_screen.dart';
import '../manage/manage_screen.dart';
import '../promotions/promotions_screen.dart';
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
                _ShellTopBar(
                  badgeLabel: session.viewer.badgeLabel,
                  viewerName: session.viewer.displayName,
                  photoUrl: session.viewer.photoUrl,
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
                  label: 'Explore',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.edit_calendar_outlined),
                  activeIcon: Icon(Icons.edit_calendar),
                  label: 'Host',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.confirmation_num_outlined),
                  activeIcon: Icon(Icons.confirmation_num),
                  label: 'Passes',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.campaign_outlined),
                  activeIcon: Icon(Icons.campaign),
                  label: 'Reach',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.badgeLabel,
    required this.viewerName,
    required this.photoUrl,
    required this.isGuest,
    required this.isBusy,
    required this.canSwitchWorkspace,
    required this.onSwitchWorkspace,
  });

  final String badgeLabel;
  final String viewerName;
  final String? photoUrl;
  final bool isGuest;
  final bool isBusy;
  final bool canSwitchWorkspace;
  final VoidCallback onSwitchWorkspace;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: EventoraReveal(
        delay: const Duration(milliseconds: 50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x14FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12121E31),
                blurRadius: 20,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.gold.withValues(alpha: 0.22),
                      palette.coral.withValues(alpha: 0.14),
                    ],
                  ),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGuest ? 'Explore' : viewerName,
                      style: context.text.bodyLarge?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBusy)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              if (canSwitchWorkspace)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton.filledTonal(
                    onPressed: onSwitchWorkspace,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.swap_horiz_outlined),
                    tooltip: 'Switch workspace',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton.filledTonal(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    );
                  },
                  visualDensity: VisualDensity.compact,
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.transparent,
                    foregroundImage: photoUrl != null
                        ? NetworkImage(photoUrl!)
                        : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  tooltip: 'Account',
                ),
              ),
            ],
          ),
        ),
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
          right: -40,
          child: _Blob(
            size: 280,
            colors: [
              palette.coral.withValues(alpha: 0.18),
              palette.gold.withValues(alpha: 0.08),
            ],
          ),
        ),
        Positioned(
          top: 160,
          left: -70,
          child: _Blob(
            size: 190,
            colors: [
              palette.gold.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
        ),
        Positioned(
          bottom: 100,
          left: -90,
          child: _Blob(
            size: 240,
            colors: [
              palette.teal.withValues(alpha: 0.16),
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
