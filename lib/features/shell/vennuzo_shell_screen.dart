import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/visuals/vennuzo_visuals.dart';
import '../../domain/models/account_models.dart';
import '../../widgets/vennuzo_motion.dart';
import '../account/account_screen.dart';
import '../admin/admin_tickets_screen.dart';
import '../discover/discover_screen.dart';
import '../manage/manage_screen.dart';
import '../organizer/organizer_business_screen.dart';
import '../organizer/organizer_overview_screen.dart';
import '../places/place_management_screen.dart';
import '../places/places_screen.dart';
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
  VennuzoWorkspaceFace? _faceForIndex;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    if (_faceForIndex != session.viewer.activeFace) {
      _faceForIndex = session.viewer.activeFace;
      _currentIndex = 0;
    }
    final tabs = session.viewer.isOrganizerWorkspace
        ? _organizerTabs()
        : _attendeeTabs;
    if (_currentIndex >= tabs.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      extendBody: false,
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ShellTopBar(
                  badgeLabel: session.viewer.badgeLabel,
                  title: tabs[_currentIndex].title,
                  photoUrl: session.viewer.photoUrl,
                  isBusy: session.isInitializing || session.isProcessing,
                  canSwitchWorkspace: session.canChooseWorkspace,
                  onSwitchWorkspace: session.openWorkspaceChooser,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: tabs.map((tab) => tab.screen).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _PremiumBottomNav(
        items: tabs.map((tab) => tab.item).toList(),
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }

  static const _attendeeTabs = [
    _ShellTab(
      title: 'Explore Vennuzo',
      screen: DiscoverScreen(),
      item: _NavItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: 'Explore',
      ),
    ),
    _ShellTab(
      title: 'Places',
      screen: PlacesScreen(),
      item: _NavItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront_rounded,
        label: 'Places',
      ),
    ),
    _ShellTab(
      title: 'Social',
      screen: SocialFeedScreen(),
      item: _NavItem(
        icon: Icons.people_outline_rounded,
        activeIcon: Icons.people_rounded,
        label: 'Social',
      ),
    ),
    _ShellTab(
      title: 'Host',
      screen: ManageScreen(),
      item: _NavItem(
        icon: Icons.edit_calendar_outlined,
        activeIcon: Icons.edit_calendar_rounded,
        label: 'Host',
      ),
    ),
    _ShellTab(
      title: 'Passes',
      screen: TicketsScreen(),
      item: _NavItem(
        icon: Icons.confirmation_num_outlined,
        activeIcon: Icons.confirmation_num_rounded,
        label: 'Passes',
      ),
    ),
    _ShellTab(
      title: 'Reach',
      screen: PromotionsScreen(),
      item: _NavItem(
        icon: Icons.campaign_outlined,
        activeIcon: Icons.campaign_rounded,
        label: 'Reach',
      ),
    ),
  ];

  List<_ShellTab> _organizerTabs() => [
    _ShellTab(
      title: 'Overview',
      screen: OrganizerOverviewScreen(
        onOpenEvents: () => setState(() => _currentIndex = 1),
        onOpenTickets: () => setState(() => _currentIndex = 2),
        onOpenPromote: () => setState(() => _currentIndex = 3),
        onOpenBusiness: () => setState(() => _currentIndex = 5),
      ),
      item: const _NavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Overview',
      ),
    ),
    const _ShellTab(
      title: 'Events',
      screen: ManageScreen(),
      item: _NavItem(
        icon: Icons.event_note_outlined,
        activeIcon: Icons.event_note_rounded,
        label: 'Events',
      ),
    ),
    const _ShellTab(
      title: 'Tickets',
      screen: AdminTicketsScreen(),
      item: _NavItem(
        icon: Icons.qr_code_scanner_outlined,
        activeIcon: Icons.qr_code_scanner_rounded,
        label: 'Tickets',
      ),
    ),
    const _ShellTab(
      title: 'Promote',
      screen: PromotionsScreen(),
      item: _NavItem(
        icon: Icons.campaign_outlined,
        activeIcon: Icons.campaign_rounded,
        label: 'Promote',
      ),
    ),
    const _ShellTab(
      title: 'Places',
      screen: PlaceManagementScreen(),
      item: _NavItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront_rounded,
        label: 'Places',
      ),
    ),
    const _ShellTab(
      title: 'Business',
      screen: OrganizerBusinessScreen(),
      item: _NavItem(
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet_rounded,
        label: 'Business',
      ),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// _PremiumBottomNav — frosted glass pill container, active item has glow pill
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumBottomNav extends StatelessWidget {
  const _PremiumBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

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
                color: VennuzoTheme.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
                border: Border.all(color: VennuzoTheme.borderBright),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: VennuzoTheme.primaryStart.withValues(alpha: 0.10),
                    blurRadius: 20,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: onTap,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: VennuzoTheme.primaryStart,
                unselectedItemColor: VennuzoTheme.textTertiary,
                showUnselectedLabels: true,
                type: BottomNavigationBarType.fixed,
                items: [
                  for (final item in items)
                    BottomNavigationBarItem(
                      icon: Icon(item.icon),
                      activeIcon: Icon(item.activeIcon),
                      label: item.label,
                      tooltip: item.label,
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

class _ShellTab {
  const _ShellTab({
    required this.title,
    required this.screen,
    required this.item,
  });

  final String title;
  final Widget screen;
  final _NavItem item;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShellTopBar — compact frosted header with Vennuzo branding
// ─────────────────────────────────────────────────────────────────────────────
class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.badgeLabel,
    required this.title,
    required this.photoUrl,
    required this.isBusy,
    required this.canSwitchWorkspace,
    required this.onSwitchWorkspace,
  });

  final String badgeLabel;
  final String title;
  final String? photoUrl;
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
                color: VennuzoTheme.surface.withValues(alpha: 0.80),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(color: VennuzoTheme.borderBright),
                boxShadow: VennuzoTheme.shadowElevated,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF080C1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: VennuzoTheme.primaryStart.withValues(
                          alpha: 0.30,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: VennuzoTheme.primaryStart.withValues(
                            alpha: 0.12,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo-transparent.png',
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 102),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          VennuzoTheme.primaryStart.withValues(alpha: 0.18),
                          VennuzoTheme.primaryEnd.withValues(alpha: 0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        VennuzoTheme.radiusFull,
                      ),
                      border: Border.all(
                        color: VennuzoTheme.primaryStart.withValues(
                          alpha: 0.18,
                        ),
                      ),
                    ),
                    child: Text(
                      badgeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: VennuzoTheme.primaryStart,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: context.text.titleSmall?.copyWith(
                        color: VennuzoTheme.textPrimary,
                        fontWeight: FontWeight.w800,
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
                  Tooltip(
                    excludeFromSemantics: true,
                    message: 'Account',
                    child: Semantics(
                      button: true,
                      label: 'Account',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AccountScreen(),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          // Keep the 34px avatar but a >=44px tap target.
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Ink(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: VennuzoTheme.borderBright,
                                  ),
                                  image: photoUrl != null
                                      ? DecorationImage(
                                          image: CachedNetworkImageProvider(
                                            photoUrl!,
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  gradient: photoUrl == null
                                      ? const LinearGradient(
                                          colors: [
                                            VennuzoTheme.surfaceElevated,
                                            VennuzoTheme.surface,
                                          ],
                                        )
                                      : null,
                                ),
                                child: photoUrl == null
                                    ? const Icon(
                                        Icons.person_outline_rounded,
                                        size: 16,
                                        color: VennuzoTheme.primaryStart,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
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
      excludeFromSemantics: true,
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            // Keep the 32px visual but a >=44px tap target for accessibility.
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Ink(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: VennuzoTheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: VennuzoTheme.border),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: VennuzoTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Backdrop — logo-inspired cosmic canvas.
// ─────────────────────────────────────────────────────────────────────────────
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          VennuzoVisuals.cosmicTexture,
          fit: BoxFit.cover,
          cacheWidth: 1400,
          opacity: const AlwaysStoppedAnimation(0.34),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF8030510), Color(0xDE070B1D), Color(0xEE130B2A)],
              stops: [0.0, 0.56, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ],
    );
  }
}
