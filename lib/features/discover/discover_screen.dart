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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discover',
                    style: context.text.displayMedium?.copyWith(
                      color: VennuzoTheme.textPrimary,
                      letterSpacing: -1.5,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: 8),
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
            ),
            // Spotlight button
            if (featuredCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _SpotlightButton(onTap: onShowAnnouncement),
              ),
          ],
        ),
      ],
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
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
