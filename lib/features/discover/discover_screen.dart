import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/art/event_art_widget.dart';
import '../../core/art/mood_art_palette.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../data/services/vennuzo_launch_preferences.dart';
import '../../data/services/vennuzo_location_service.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/vennuzo_motion.dart';
import '../../widgets/section_heading.dart';
import '../events/event_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  TextEditingController? _searchControllerInstance;
  String? _selectedTag;
  String? _lastAnnouncementId;
  String _searchQuery = '';
  bool _announcementEligible = false;
  final ScrollController _scroll = ScrollController();

  TextEditingController get _searchController =>
      _searchControllerInstance ??= TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _loadNearbyEvents();
      });
    });
    _prepareAnnouncementGate();
  }

  @override
  void dispose() {
    _searchControllerInstance?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeShowAnnouncement();
  }

  Future<void> _prepareAnnouncementGate() async {
    final shouldAllow =
        await VennuzoLaunchPreferences.shouldAllowAnnouncementTakeover();
    if (!mounted) return;
    setState(() => _announcementEligible = shouldAllow);
    if (shouldAllow) _maybeShowAnnouncement();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final events = repository.discoverableEvents;
    final searchFilteredEvents = _searchQuery.isEmpty
        ? events
        : events.where((e) => _matchesSearch(e, _searchQuery)).toList();
    final featuredCampaigns = repository.featuredCampaigns.where((campaign) {
      final event = repository.eventById(campaign.eventId);
      if (event == null) return false;
      if (_searchQuery.isNotEmpty && !_matchesSearch(event, _searchQuery)) {
        return false;
      }
      if (_selectedTag != null && !event.tags.contains(_selectedTag)) {
        return false;
      }
      return true;
    }).toList();

    final tags = _discoverTags(searchFilteredEvents);
    final filteredEvents = _selectedTag == null
        ? searchFilteredEvents
        : searchFilteredEvents
            .where((e) => e.tags.contains(_selectedTag))
            .toList();

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // ── Compact hero ─────────────────────────────────────────
        VennuzoReveal(
          child: _DiscoverHero(
            eventCount: events.length,
            featuredCount: featuredCampaigns.length,
            onShowAnnouncement: () => _showCurrentAnnouncement(repository),
          ),
        ),
        const SizedBox(height: 18),
        // ── Search bar ───────────────────────────────────────────
        VennuzoReveal(
          delay: const Duration(milliseconds: 60),
          child: _SearchBar(
            controller: _searchController,
            query: _searchQuery,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
        ),
        const SizedBox(height: 14),
        // ── Vibe filter chips ────────────────────────────────────
        VennuzoReveal(
          delay: const Duration(milliseconds: 100),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                _VibeChip(
                  label: 'All',
                  selected: _selectedTag == null,
                  onTap: () => setState(() => _selectedTag = null),
                ),
                for (final tag in tags) ...[
                  const SizedBox(width: 8),
                  _VibeChip(
                    label: tag,
                    selected: _selectedTag == tag,
                    onTap: () => setState(() => _selectedTag = tag),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // ── Tonight on Vennuzo — cinematic film strip ────────────
        VennuzoReveal(
          delay: const Duration(milliseconds: 140),
          child: const _FilmStrip(assets: _filmStripPhotos),
        ),
        const SizedBox(height: 28),
        // ── Featured this week ───────────────────────────────────
        if (featuredCampaigns.isNotEmpty) ...[
          SectionHeading(title: 'Featured', subtitle: null),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featuredCampaigns.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final campaign = featuredCampaigns[index];
                final event = repository.eventById(campaign.eventId);
                if (event == null) return const SizedBox.shrink();
                return _FeaturedCard(
                  event: event,
                  campaign: campaign,
                  onTap: () => _openEvent(context, event),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
        ],
        // ── Events list ──────────────────────────────────────────
        SectionHeading(
          title: _resultsTitle,
          subtitle: null,
          actionLabel: (_selectedTag != null || _searchQuery.isNotEmpty)
              ? 'Clear'
              : null,
          onAction: (_selectedTag != null || _searchQuery.isNotEmpty)
              ? _clearAllFilters
              : null,
        ),
        const SizedBox(height: 12),
        if (filteredEvents.isEmpty)
          EmptyStateCard(
            title: _searchQuery.isNotEmpty
                ? 'No events match "$_searchQuery"'
                : 'No events for that vibe yet',
            body: _searchQuery.isNotEmpty ? 'Try another name or tag.' : null,
            icon: _searchQuery.isNotEmpty
                ? Icons.search_off_outlined
                : Icons.filter_alt_off_outlined,
            actionLabel: 'Show all events',
            onAction: _clearAllFilters,
          )
        else ...[
          _LeadEventCard(
            event: filteredEvents.first,
            onTap: () => _openEvent(context, filteredEvents.first),
          ),
          const SizedBox(height: 14),
          ...filteredEvents.skip(1).map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: EventCard(
                    event: event,
                    onTap: () => _openEvent(context, event),
                    compact: true,
                    footer: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _openEvent(context, event),
                          child: const Text('Details'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _openEvent(context, event),
                          child: Text(event.ticketing.enabled
                              ? 'Get tickets'
                              : 'Reserve spot'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
        ],
        // ── Editorial showcase — every kind of night ─────────────
        const SizedBox(height: 34),
        VennuzoReveal(
          child: const SectionHeading(
            title: 'Every kind of night',
            subtitle: 'One app, from doors to dancefloor',
          ),
        ),
        const SizedBox(height: 16),
        const _ShowcaseMoments(),
        // ── Closing CTA band ─────────────────────────────────────
        const SizedBox(height: 28),
        VennuzoReveal(
          child: _CtaBand(onBrowseAll: _browseAll),
        ),
      ],
    );
  }

  List<String> _discoverTags(List<EventModel> events) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final event in events) {
      for (final tag in event.tags) {
        if (seen.add(tag)) ordered.add(tag);
      }
    }
    return ordered.take(8).toList();
  }

  bool _matchesSearch(EventModel event, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      event.title, event.description, event.venue, event.city,
      event.performers, event.djs, event.mcs, ...event.tags,
    ].any((v) => v.toLowerCase().contains(q));
  }

  String get _resultsTitle {
    if (_searchQuery.isNotEmpty && _selectedTag != null) {
      return '"$_searchQuery" in $_selectedTag';
    }
    if (_searchQuery.isNotEmpty) return 'Results for "$_searchQuery"';
    if (_selectedTag != null) return '$_selectedTag events';
    return 'Events for you';
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() { _searchQuery = ''; _selectedTag = null; });
  }

  void _browseAll() {
    _clearAllFilters();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _loadNearbyEvents() async {
    if (!mounted) return;
    try {
      await VennuzoLocationService.instance.getCurrentPosition();
    } catch (_) {}
  }

  void _maybeShowAnnouncement() {
    if (!_announcementEligible) return;
    final repository = context.read<VennuzoRepository>();
    final campaign = repository.primaryAnnouncementCampaign;
    if (campaign == null || campaign.id == _lastAnnouncementId) return;
    _lastAnnouncementId = campaign.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showCurrentAnnouncement(repository);
    });
  }

  Future<void> _showCurrentAnnouncement(VennuzoRepository repository) async {
    final campaign = repository.primaryAnnouncementCampaign;
    if (campaign == null || !mounted) return;
    final event = repository.eventById(campaign.eventId);
    if (event == null) return;
    final openEvent = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      barrierLabel: 'Announcement',
      pageBuilder: (ctx, anim, secAnim) =>
          _AnnouncementTakeover(event: event, campaign: campaign),
      transitionBuilder: (context, animation, secAnim, child) {
        final curved = CurvedAnimation(
          parent: animation, curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (openEvent == true && mounted) _openEvent(context, event);
  }

  void _openEvent(BuildContext context, EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(eventId: event.id),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DiscoverHero — compact, text-only, no giant card
// ─────────────────────────────────────────────────────────────────────────────
class _DiscoverHero extends StatelessWidget {
  const _DiscoverHero({
    required this.eventCount,
    required this.featuredCount,
    required this.onShowAnnouncement,
  });

  final int eventCount;
  final int featuredCount;
  final VoidCallback onShowAnnouncement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        boxShadow: VennuzoTheme.glowShadow(VennuzoTheme.primaryMid),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        child: SizedBox(
          height: 344,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cinematic photo with slow Ken Burns drift
              const _KenBurnsImage(
                asset: 'assets/photos/01_hero_concert_crowd.jpg',
                cacheWidth: 1080,
              ),
              // Legibility scrim — darkest toward the bottom-left copy
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      stops: const [0.0, 0.45, 1.0],
                      colors: [
                        VennuzoTheme.background.withValues(alpha: 0.10),
                        VennuzoTheme.background.withValues(alpha: 0.55),
                        VennuzoTheme.background.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
              // Iridescent sheen in the top-left corner
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [
                        VennuzoTheme.primaryStart.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const _HeroEyebrow(),
                        const Spacer(),
                        if (featuredCount > 0)
                          _SpotlightButton(onTap: onShowAnnouncement),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover what’s\nhappening tonight',
                          style: context.text.headlineLarge?.copyWith(
                            color: Colors.white,
                            height: 1.04,
                            letterSpacing: -0.8,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _StatPill(
                              icon: Icons.bolt_rounded,
                              label: '$eventCount events',
                              color: VennuzoTheme.primaryStart,
                            ),
                            if (featuredCount > 0) ...[
                              const SizedBox(width: 8),
                              _StatPill(
                                icon: Icons.auto_awesome_rounded,
                                label: '$featuredCount featured',
                                color: VennuzoTheme.primaryEnd,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeroEyebrow — frosted "live tonight" pill with a pulse dot
// ─────────────────────────────────────────────────────────────────────────────
class _HeroEyebrow extends StatelessWidget {
  const _HeroEyebrow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: VennuzoTheme.accentMint,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'LIVE TONIGHT',
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightButton extends StatelessWidget {
  const _SpotlightButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [VennuzoTheme.primaryStart, VennuzoTheme.primaryMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
          boxShadow: VennuzoTheme.glowShadow(VennuzoTheme.primaryStart),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Spotlight',
              style: context.text.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchBar — clean, prominent, full-width
// ─────────────────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
        border: Border.all(color: VennuzoTheme.border),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: context.text.bodyLarge?.copyWith(
          color: VennuzoTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search events, venues, cities…',
          hintStyle: context.text.bodyLarge?.copyWith(
            color: VennuzoTheme.textTertiary,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 10),
            child: Icon(
              Icons.search_rounded,
              color: palette.slate,
              size: 22,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    color: palette.slate,
                    size: 20,
                  ),
                ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VibeChip — compact pill, gradient when selected
// ─────────────────────────────────────────────────────────────────────────────
class _VibeChip extends StatelessWidget {
  const _VibeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
          gradient: selected
              ? const LinearGradient(
                  colors: [
                    VennuzoTheme.primaryStart,
                    VennuzoTheme.primaryMid,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : VennuzoTheme.surfaceElevated,
          border: selected
              ? null
              : Border.all(color: VennuzoTheme.border),
        ),
        child: Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: selected ? Colors.white : palette.slate,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeaturedCard — slim horizontal-scroll card (260px tall)
// ─────────────────────────────────────────────────────────────────────────────
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.event,
    required this.campaign,
    required this.onTap,
  });

  final EventModel event;
  final PromotionCampaign campaign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minPrice = event.ticketing.minimumPrice;
    final priceLabel =
        minPrice == null ? 'Free' : formatMoney(minPrice);
    final moodPal = MoodArtPalette.fromMood(event.mood);

    return SizedBox(
      width: 240,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          boxShadow: [
            BoxShadow(
              color: moodPal.base.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: Stack(
            fit: StackFit.expand,
            children: [
              EventArtwork(event: event, height: 260),
              // Scrim
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Featured badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              VennuzoTheme.radiusFull,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.workspace_premium_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Featured',
                                style: context.text.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleLarge?.copyWith(
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.place_rounded,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.city,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                priceLabel,
                                style: context.text.labelSmall?.copyWith(
                                  color: VennuzoTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeadEventCard — first event in the list, with action buttons
// ─────────────────────────────────────────────────────────────────────────────
class _LeadEventCard extends StatelessWidget {
  const _LeadEventCard({required this.event, required this.onTap});

  final EventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EventCard(
      event: event,
      onTap: onTap,
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onTap,
              child: const Text('Details'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: onTap,
              child: Text(
                event.ticketing.enabled ? 'Get tickets' : 'Reserve spot',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AnnouncementTakeover — fullscreen spotlight modal (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────
class _AnnouncementTakeover extends StatelessWidget {
  const _AnnouncementTakeover({
    required this.event,
    required this.campaign,
  });

  final EventModel event;
  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final minPrice = event.ticketing.minimumPrice;
    final priceLabel =
        minPrice == null ? 'Free entry' : 'From ${formatMoney(minPrice)}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl + 8),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Background artwork
                    Positioned.fill(
                      child: EventArtwork(
                        event: event,
                        height: constraints.maxHeight,
                      ),
                    ),
                    // Dark scrim
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      VennuzoTheme.radiusFull,
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    'NOW SPOTLIGHTING',
                                    style: context.text.labelSmall?.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 1.0,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.15),
                                    shape: const CircleBorder(),
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              event.title,
                              style: context.text.displayMedium?.copyWith(
                                color: Colors.white,
                                letterSpacing: -1.0,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              campaign.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoPill(label: formatShortDate(event.startDate)),
                                _InfoPill(label: event.city),
                                _InfoPill(label: priceLabel),
                              ],
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: VennuzoTheme.background,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      VennuzoTheme.radiusMd,
                                    ),
                                  ),
                                ),
                                child: const Text('See full event'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      Colors.white.withValues(alpha: 0.7),
                                ),
                                child: const Text('Not now'),
                              ),
                            ),
                            Text(
                              'This placement is part of Vennuzo premium promotion inventory for organizers.',
                              style: context.text.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: context.text.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cinematic photo layer — Ken Burns hero, film strip, editorial moments, CTA.
// Photos bundled in assets/photos/ (see pubspec). Harmonized to the iridescent
// brand palette, in the app's inset rounded-card design language.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _filmStripPhotos = [
  'assets/photos/02_dj_booth_night.jpg',
  'assets/photos/03_festival_dusk.jpg',
  'assets/photos/07_dancefloor_silhouettes.jpg',
  'assets/photos/08_live_band_intimate.jpg',
  'assets/photos/10_gallery_culture_event.jpg',
];

const double _kFilmItemW = 172;
const double _kFilmItemH = 108;
const double _kFilmGap = 10;

// Slowly drifting + scaling photo (Ken Burns). Fills its parent constraints.
class _KenBurnsImage extends StatefulWidget {
  const _KenBurnsImage({
    required this.asset,
    this.cacheWidth = 900,
  });

  final String asset;
  final int cacheWidth;

  static const Alignment _alignmentBegin = Alignment(-0.55, -0.35);
  static const Alignment _alignmentEnd = Alignment(0.5, 0.4);
  static const double _scaleBegin = 1.04;
  static const double _scaleEnd = 1.16;
  static const Duration _duration = Duration(seconds: 22);

  @override
  State<_KenBurnsImage> createState() => _KenBurnsImageState();
}

class _KenBurnsImageState extends State<_KenBurnsImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _KenBurnsImage._duration,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;
        final scale =
            lerpDouble(_KenBurnsImage._scaleBegin, _KenBurnsImage._scaleEnd, t)!;
        final align = Alignment.lerp(
            _KenBurnsImage._alignmentBegin, _KenBurnsImage._alignmentEnd, t)!;
        return Transform.scale(
          scale: scale,
          alignment: align,
          child: Image.asset(
            widget.asset,
            fit: BoxFit.cover,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

// Auto-scrolling marquee of show photos, with faded edges.
class _FilmStrip extends StatefulWidget {
  const _FilmStrip({required this.assets});
  final List<String> assets;

  @override
  State<_FilmStrip> createState() => _FilmStripState();
}

class _FilmStripState extends State<_FilmStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.assets.length * 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setWidth = widget.assets.length * (_kFilmItemW + _kFilmGap);
    return SizedBox(
      height: _kFilmItemH,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.06, 0.94, 1.0],
        ).createShader(rect),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-_controller.value * setWidth, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.assets.length * 2; i++) ...[
                        _FilmFrame(
                          asset: widget.assets[i % widget.assets.length],
                        ),
                        const SizedBox(width: _kFilmGap),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FilmFrame extends StatelessWidget {
  const _FilmFrame({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kFilmItemW,
      height: _kFilmItemH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset, fit: BoxFit.cover, cacheWidth: 360),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  VennuzoTheme.background.withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Editorial "every kind of night" — three photo moments with numbered captions.
class _Moment {
  const _Moment({
    required this.number,
    required this.title,
    required this.sub,
    required this.asset,
    required this.accent,
  });
  final String number;
  final String title;
  final String sub;
  final String asset;
  final Color accent;
}

class _ShowcaseMoments extends StatelessWidget {
  const _ShowcaseMoments();

  static const _moments = [
    _Moment(
      number: '01',
      title: 'Find the nights\nworth showing up for',
      sub: 'Browse what’s on near you — filter by vibe, venue or date.',
      asset: 'assets/photos/04_friends_arriving.jpg',
      accent: VennuzoTheme.primaryStart,
    ),
    _Moment(
      number: '02',
      title: 'Tap in.\nSkip the line.',
      sub: 'Secure checkout, tickets in your pocket, QR entry at the door.',
      asset: 'assets/photos/05_qr_entry.jpg',
      accent: VennuzoTheme.primaryMid,
    ),
    _Moment(
      number: '03',
      title: 'Bring the crew,\nrelive the moment',
      sub: 'Share events, roll deep, keep the memories after the lights go up.',
      asset: 'assets/photos/06_rooftop_party.jpg',
      accent: VennuzoTheme.primaryEnd,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _moments.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          VennuzoReveal(
            delay: Duration(milliseconds: 60 * i),
            child: _MomentCard(moment: _moments[i]),
          ),
        ],
      ],
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment});
  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
      child: SizedBox(
        height: 188,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(moment.asset, fit: BoxFit.cover, cacheWidth: 900),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  stops: const [0.0, 0.5, 1.0],
                  colors: [
                    VennuzoTheme.background.withValues(alpha: 0.14),
                    VennuzoTheme.background.withValues(alpha: 0.62),
                    VennuzoTheme.background.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    moment.number,
                    style: context.text.titleMedium?.copyWith(
                      color: moment.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      moment.title,
                      style: context.text.titleLarge?.copyWith(
                        color: Colors.white,
                        height: 1.12,
                        letterSpacing: -0.4,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 252),
                    child: Text(
                      moment.sub,
                      style: context.text.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Closing call-to-action over a celebratory photo.
class _CtaBand extends StatelessWidget {
  const _CtaBand({required this.onBrowseAll});
  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        boxShadow: VennuzoTheme.glowShadow(VennuzoTheme.primaryEnd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/photos/09_confetti_celebration.jpg',
                fit: BoxFit.cover,
                cacheWidth: 1000,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      VennuzoTheme.background.withValues(alpha: 0.55),
                      VennuzoTheme.background.withValues(alpha: 0.86),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'YOUR NEXT NIGHT OUT',
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(
                      color: VennuzoTheme.accentMint,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ready to find\nwhat’s next?',
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium?.copyWith(
                      color: Colors.white,
                      height: 1.05,
                      letterSpacing: -0.6,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Discover events near you and grab tickets in seconds.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _GradientButton(
                    label: 'Browse all events',
                    icon: Icons.explore_rounded,
                    onTap: onBrowseAll,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          gradient: VennuzoTheme.brandGradient,
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
          boxShadow: VennuzoTheme.glowShadow(VennuzoTheme.primaryMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
