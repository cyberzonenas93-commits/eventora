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
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _PremiumBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PremiumBottomNav — frosted glass pill container, active item has glow pill
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumBottomNav extends StatelessWidget {
  const _PremiumBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    _NavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: 'Explore'),
    _NavItem(icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'Social'),
    _NavItem(icon: Icons.edit_calendar_outlined, activeIcon: Icons.edit_calendar_rounded, label: 'Host'),
    _NavItem(icon: Icons.confirmation_num_outlined, activeIcon: Icons.confirmation_num_rounded, label: 'Passes'),
    _NavItem(icon: Icons.campaign_outlined, activeIcon: Icons.campaign_rounded, label: 'Reach'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C1A).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_items.length, (index) {
                  return _NavButton(
                    item: _items[index],
                    selected: currentIndex == index,
                    onTap: () => onTap(index),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
          gradient: selected
              ? LinearGradient(
                  colors: [
                    VennuzoTheme.primaryStart.withValues(alpha: 0.20),
                    VennuzoTheme.primaryMid.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: selected
              ? Border.all(
                  color: VennuzoTheme.primaryStart.withValues(alpha: 0.22),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                key: ValueKey(selected),
                size: 22,
                color: selected
                    ? VennuzoTheme.primaryStart
                    : const Color(0xFF5A5A78),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? VennuzoTheme.primaryStart
                    : const Color(0xFF5A5A78),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShellTopBar — compact frosted header with Vennuzo branding
// ─────────────────────────────────────────────────────────────────────────────
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: VennuzoReveal(
        delay: const Duration(milliseconds: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C1A).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                children: [
                  // Role badge with gradient
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          VennuzoTheme.primaryStart.withValues(alpha: 0.18),
                          VennuzoTheme.primaryMid.withValues(alpha: 0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        VennuzoTheme.radiusFull,
                      ),
                      border: Border.all(
                        color: VennuzoTheme.primaryStart.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      badgeLabel,
                      style: context.text.labelSmall?.copyWith(
                        color: VennuzoTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isGuest ? 'Explore Vennuzo' : viewerName,
                      style: context.text.titleSmall?.copyWith(
                        color: VennuzoTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isBusy)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: VennuzoTheme.primaryStart,
                        ),
                      ),
                    ),
                  if (canSwitchWorkspace)
                    _TopBarIconBtn(
                      icon: Icons.swap_horiz_rounded,
                      onTap: onSwitchWorkspace,
                      tooltip: 'Switch workspace',
                    ),
                  const SizedBox(width: 6),
                  // Avatar button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        gradient: photoUrl == null
                            ? LinearGradient(
                                colors: [
                                  VennuzoTheme.surfaceElevated,
                                  VennuzoTheme.surfaceBright,
                                ],
                              )
                            : null,
                      ),
                      child: photoUrl == null
                          ? const Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: Color(0xFF8E8EA8),
                            )
                          : null,
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

class _TopBarIconBtn extends StatelessWidget {
  const _TopBarIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: VennuzoTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: VennuzoTheme.border),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF8E8EA8)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Backdrop — ambient dark canvas with iridescent glow orbs
// ─────────────────────────────────────────────────────────────────────────────
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: VennuzoTheme.background),
          ),
        ),
        // Top-right: rose glow
        Positioned(
          top: -60,
          right: -30,
          child: _Orb(
            size: 240,
            color: VennuzoTheme.primaryEnd.withValues(alpha: 0.055),
          ),
        ),
        // Top-left: blue glow
        Positioned(
          top: -30,
          left: -50,
          child: _Orb(
            size: 180,
            color: VennuzoTheme.primaryStart.withValues(alpha: 0.045),
          ),
        ),
        // Bottom-left: purple glow
        Positioned(
          bottom: 60,
          left: -30,
          child: _Orb(
            size: 200,
            color: VennuzoTheme.primaryMid.withValues(alpha: 0.035),
          ),
        ),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
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
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
