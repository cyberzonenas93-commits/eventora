import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../widgets/vennuzo_motion.dart';
import '../account/account_screen.dart';
import '../discover/discover_screen.dart';
import '../manage/manage_screen.dart';
import '../promotions/promotions_screen.dart';
import '../social/social_feed_screen.dart';
import '../tickets/tickets_screen.dart';

class VennuzoShellScreen extends StatefulWidget {
  const VennuzoShellScreen({super.key});

  @override
  State<VennuzoShellScreen> createState() => _VennuzoShellScreenState();
}

class _VennuzoShellScreenState extends State<VennuzoShellScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = const [
    DiscoverScreen(),
    SocialFeedScreen(),
    ManageScreen(),
    TicketsScreen(),
    PromotionsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();

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
      bottomNavigationBar: _FrostedBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}

/// Frosted glass bottom navigation — inspired by Apple + Ticketmaster.
class _FrostedBottomNav extends StatelessWidget {
  const _FrostedBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.3),
                ),
                boxShadow: VennuzoTheme.shadowFloating,
              ),
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: onTap,
                showUnselectedLabels: true,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.explore_outlined),
                    activeIcon: Icon(Icons.explore),
                    label: 'Explore',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people_outline),
                    activeIcon: Icon(Icons.people),
                    label: 'Social',
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
      ),
    );
  }
}

/// Top bar with frosted glass, compact profile, and workspace badge.
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: VennuzoReveal(
        delay: const Duration(milliseconds: 50),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.25),
                ),
                boxShadow: VennuzoTheme.shadowElevated,
              ),
              child: Row(
                children: [
                  // Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          palette.teal.withValues(alpha: 0.12),
                          palette.coral.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(VennuzoTheme.radiusFull),
                    ),
                    child: Text(
                      badgeLabel,
                      style: context.text.labelSmall?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name
                  Expanded(
                    child: Text(
                      isGuest ? 'Explore' : viewerName,
                      style: context.text.titleSmall?.copyWith(
                        color: palette.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (canSwitchWorkspace)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: IconButton(
                        onPressed: onSwitchWorkspace,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: palette.canvas,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          Icons.swap_horiz_outlined,
                          size: 20,
                          color: palette.ink,
                        ),
                        tooltip: 'Switch workspace',
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AccountScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: palette.border.withValues(alpha: 0.5),
                          ),
                          image: photoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(photoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          color: palette.canvas,
                        ),
                        child: photoUrl == null
                            ? Icon(
                                Icons.person_outline,
                                size: 18,
                                color: palette.slate,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Refined ambient backdrop with subtle gradients.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        // Base gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.teal.withValues(alpha: 0.03),
                  palette.canvas,
                  palette.coral.withValues(alpha: 0.02),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Top-right ambient glow
        Positioned(
          top: -80,
          right: -40,
          child: _AmbientOrb(
            size: 260,
            color: palette.coral.withValues(alpha: 0.08),
          ),
        ),
        // Top-left cool glow
        Positioned(
          top: -40,
          left: -60,
          child: _AmbientOrb(
            size: 200,
            color: palette.teal.withValues(alpha: 0.06),
          ),
        ),
        // Bottom ambient
        Positioned(
          bottom: 40,
          left: -40,
          child: _AmbientOrb(
            size: 220,
            color: palette.gold.withValues(alpha: 0.05),
          ),
        ),
      ],
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
