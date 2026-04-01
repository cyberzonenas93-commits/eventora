import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
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
import '../../widgets/metric_tile.dart';
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
  Position? _currentPosition;
  String? _locationError;
  bool _isLoadingNearby = false;
  bool _announcementEligible = false;

  TextEditingController get _searchController =>
      _searchControllerInstance ??= TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) {
          _loadNearbyEvents();
        }
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
    if (!mounted) {
      return;
    }
    setState(() {
      _announcementEligible = shouldAllow;
    });
    if (shouldAllow) {
      _maybeShowAnnouncement();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final events = repository.discoverableEvents;
    final searchFilteredEvents = _searchQuery.isEmpty
        ? events
        : events.where((event) => _matchesSearch(event, _searchQuery)).toList();
    final featuredCampaigns = repository.featuredCampaigns.where((campaign) {
      final event = repository.eventById(campaign.eventId);
      if (event == null) {
        return false;
      }
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
              .where((event) => event.tags.contains(_selectedTag))
              .toList();
    final nearbyEvents = _nearbyEventsFor(repository, filteredEvents);
    final recurringCount = events
        .where((event) => event.recurrence.isRecurring)
        .length;
    final ticketedCount = events
        .where((event) => event.ticketing.enabled)
        .length;
    final freeCount = events
        .where((event) => event.ticketing.minimumPrice == null)
        .length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        VennuzoReveal(
          child: _DashboardHero(
            eventCount: events.length,
            featuredCount: featuredCampaigns.length,
            onShowAnnouncement: () => _showCurrentAnnouncement(repository),
          ),
        ),
        const SizedBox(height: 22),
        VennuzoReveal(
          delay: const Duration(milliseconds: 70),
          child: _AroundYouCard(
            currentPosition: _currentPosition,
            events: nearbyEvents,
            distanceForEvent: (event) {
              final position = _currentPosition;
              if (position == null) {
                return null;
              }
              return repository.distanceKmForEvent(
                event,
                latitude: position.latitude,
                longitude: position.longitude,
              );
            },
            isLoading: _isLoadingNearby,
            error: _locationError,
            onRefresh: _loadNearbyEvents,
            onOpenEvent: (event) => _openEvent(context, event),
          ),
        ),
        const SizedBox(height: 22),
        VennuzoReveal(
          delay: const Duration(milliseconds: 120),
          child: _SearchPanel(
            controller: _searchController,
            query: _searchQuery,
            resultCount: filteredEvents.length,
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Live listings',
              value: '${events.length}',
              icon: Icons.public_outlined,
            ),
            MetricTile(
              label: 'Ticketed nights',
              value: '$ticketedCount',
              icon: Icons.confirmation_num_outlined,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Free plans',
              value: '$freeCount',
              icon: Icons.celebration_outlined,
              highlight: context.palette.teal,
            ),
            MetricTile(
              label: 'Recurring picks',
              value: '$recurringCount',
              icon: Icons.repeat_outlined,
              highlight: context.palette.gold,
            ),
          ],
        ),
        const SizedBox(height: 30),
        SectionHeading(title: 'Featured this week', subtitle: null),
        const SizedBox(height: 14),
        if (featuredCampaigns.isEmpty)
          EmptyStateCard(
            title: _searchQuery.isEmpty
                ? 'No featured events right now'
                : 'No featured matches',
            body: _searchQuery.isEmpty ? null : 'Try another search or tag.',
            icon: Icons.star_outline,
          )
        else
          SizedBox(
            height: 380,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featuredCampaigns.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final campaign = featuredCampaigns[index];
                final event = repository.eventById(campaign.eventId);
                if (event == null) {
                  return const SizedBox.shrink();
                }
                return _FeaturedBannerCard(
                  event: event,
                  campaign: campaign,
                  onTap: () => _openEvent(context, event),
                );
              },
            ),
          ),
        const SizedBox(height: 30),
        SectionHeading(title: 'Browse by vibe', subtitle: null),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _VibeFilterChip(
                label: 'All events',
                selected: _selectedTag == null,
                onTap: () => setState(() => _selectedTag = null),
              ),
              for (final tag in tags) ...[
                const SizedBox(width: 10),
                _VibeFilterChip(
                  label: tag,
                  selected: _selectedTag == tag,
                  onTap: () => setState(() => _selectedTag = tag),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 30),
        SectionHeading(
          title: _resultsTitle,
          subtitle: null,
          actionLabel: (_selectedTag != null || _searchQuery.isNotEmpty)
              ? 'Clear all'
              : null,
          onAction: (_selectedTag != null || _searchQuery.isNotEmpty)
              ? _clearAllFilters
              : null,
        ),
        const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          ...filteredEvents
              .skip(1)
              .map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: EventCard(
                    event: event,
                    onTap: () => _openEvent(context, event),
                    compact: true,
                    footer: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _openEvent(context, event),
                            child: const Text('See details'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _openEvent(context, event),
                            child: Text(
                              event.ticketing.enabled
                                  ? 'Get tickets'
                                  : 'Reserve spot',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  List<EventModel> _nearbyEventsFor(
    VennuzoRepository repository,
    List<EventModel> candidateEvents,
  ) {
    final position = _currentPosition;
    if (position == null) {
      return const <EventModel>[];
    }

    final nearby =
        candidateEvents.where((event) {
          final distance = repository.distanceKmForEvent(
            event,
            latitude: position.latitude,
            longitude: position.longitude,
          );
          return distance != null && distance <= 25;
        }).toList()..sort((a, b) {
          final aDistance =
              repository.distanceKmForEvent(
                a,
                latitude: position.latitude,
                longitude: position.longitude,
              ) ??
              double.infinity;
          final bDistance =
              repository.distanceKmForEvent(
                b,
                latitude: position.latitude,
                longitude: position.longitude,
              ) ??
              double.infinity;
          return aDistance.compareTo(bDistance);
        });

    return nearby.take(5).toList();
  }

  List<String> _discoverTags(List<EventModel> events) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final event in events) {
      for (final tag in event.tags) {
        if (seen.add(tag)) {
          ordered.add(tag);
        }
      }
    }
    return ordered.take(8).toList();
  }

  bool _matchesSearch(EventModel event, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final searchableFields = [
      event.title,
      event.description,
      event.venue,
      event.city,
      event.performers,
      event.djs,
      event.mcs,
      ...event.tags,
    ];

    return searchableFields.any(
      (value) => value.toLowerCase().contains(normalizedQuery),
    );
  }

  String get _resultsTitle {
    if (_searchQuery.isNotEmpty && _selectedTag != null) {
      return 'Results for "$_searchQuery" in $_selectedTag';
    }
    if (_searchQuery.isNotEmpty) {
      return 'Results for "$_searchQuery"';
    }
    if (_selectedTag != null) {
      return 'Showing $_selectedTag';
    }
    return 'Upcoming around you';
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedTag = null;
    });
  }

  Future<void> _loadNearbyEvents() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingNearby = true;
      _locationError = null;
    });

    try {
      final position = await VennuzoLocationService.instance
          .getCurrentPosition();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentPosition = position;
        _isLoadingNearby = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingNearby = false;
        _locationError = '$error';
      });
    }
  }

  void _maybeShowAnnouncement() {
    if (!_announcementEligible) {
      return;
    }
    final repository = context.read<VennuzoRepository>();
    final campaign = repository.primaryAnnouncementCampaign;
    if (campaign == null || campaign.id == _lastAnnouncementId) {
      return;
    }

    _lastAnnouncementId = campaign.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _showCurrentAnnouncement(repository);
    });
  }

  Future<void> _showCurrentAnnouncement(VennuzoRepository repository) async {
    final campaign = repository.primaryAnnouncementCampaign;
    if (campaign == null || !mounted) {
      return;
    }
    final event = repository.eventById(campaign.eventId);
    if (event == null) {
      return;
    }

    final openEvent = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      barrierLabel: 'Featured announcement',
      pageBuilder: (_, _, _) =>
          _AnnouncementTakeover(event: event, campaign: campaign),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (openEvent == true && mounted) {
      _openEvent(context, event);
    }
  }

  void _openEvent(BuildContext context, EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(eventId: event.id),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SearchPanel - Cleaner, card-free search with subtle hint
// ---------------------------------------------------------------------------
class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.query,
    required this.resultCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final int resultCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
            border: Border.all(color: palette.borderSubtle),
            boxShadow: VennuzoTheme.shadowResting,
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Event, venue, city, or tag',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Icon(
                  Icons.search_outlined,
                  color: palette.muted,
                  size: 22,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClear,
                      icon: Icon(Icons.close, color: palette.slate, size: 20),
                      tooltip: 'Clear search',
                    ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SearchHintChip(
          icon: Icons.sell_outlined,
          label: query.isEmpty ? 'Try Music' : '$resultCount matches',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _DashboardHero - Immersive dark gradient, larger type, glass tags
// ---------------------------------------------------------------------------
class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.eventCount,
    required this.featuredCount,
    required this.onShowAnnouncement,
  });

  final int eventCount;
  final int featuredCount;
  final VoidCallback onShowAnnouncement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0A0A12),
            Color(0xFF1A0F3A),
            Color(0xFF12101E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A0F3A).withValues(alpha: 0.32),
            blurRadius: 48,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative glow orb
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    VennuzoTheme.primaryStart.withValues(alpha: 0.18),
                    VennuzoTheme.primaryStart.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Secondary glow
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    VennuzoTheme.primaryEnd.withValues(alpha: 0.12),
                    VennuzoTheme.primaryEnd.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroTag(
                    icon: Icons.bolt_outlined,
                    label: '$eventCount public events',
                  ),
                  _HeroTag(
                    icon: Icons.auto_awesome_outlined,
                    label: '$featuredCount featured',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Find what\nmatters.',
                style: context.text.displayMedium?.copyWith(
                  color: Colors.white,
                  height: 0.98,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Trending, nearby, and ready to book.',
                style: context.text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: onShowAnnouncement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: palette.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          VennuzoTheme.radiusMd,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.local_fire_department_outlined),
                    label: const Text('Spotlight'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        VennuzoTheme.radiusMd,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(
                          Icons.swipe_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                        Text(
                          'Curated',
                          style: context.text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HeroTag - Glass-morphism pill on dark hero
// ---------------------------------------------------------------------------
class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.7)),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SearchHintChip - Subtle, labelSmall style
// ---------------------------------------------------------------------------
class _SearchHintChip extends StatelessWidget {
  const _SearchHintChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: palette.slate,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FeaturedBannerCard - Taller, deeper scrim, glass badges, letter-spacing
// ---------------------------------------------------------------------------
class _FeaturedBannerCard extends StatelessWidget {
  const _FeaturedBannerCard({
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
    final priceLabel = minPrice == null
        ? 'Free entry'
        : 'From ${formatMoney(minPrice)}';
    final moodPal = MoodArtPalette.fromMood(event.mood);

    return SizedBox(
      width: 320,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          boxShadow: [
            BoxShadow(
              color: moodPal.base.withValues(alpha: 0.26),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: Stack(
            children: [
              Positioned.fill(
                child: EventArtwork(
                  event: event,
                  height: 380,
                ),
              ),
              // Deeper scrim gradient
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.35, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _PlacementBadge(
                              label: 'Featured',
                              icon: Icons.workspace_premium_outlined,
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(
                                  VennuzoTheme.radiusFull,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                formatShortDate(event.startDate),
                                style: context.text.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          event.title,
                          style: context.text.headlineMedium?.copyWith(
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          campaign.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PlacementStat(label: event.city),
                            _PlacementStat(label: priceLabel),
                            _PlacementStat(label: '${event.rsvpCount} RSVPs'),
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

// ---------------------------------------------------------------------------
// _LeadEventCard - Footer buttons with radiusMd
// ---------------------------------------------------------------------------
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
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                ),
              ),
              child: const Text('See details'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                ),
              ),
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

// ---------------------------------------------------------------------------
// _AroundYouCard - Cleaner layout, VennuzoTheme.radiusLg map corners
// ---------------------------------------------------------------------------
class _AroundYouCard extends StatelessWidget {
  const _AroundYouCard({
    required this.currentPosition,
    required this.events,
    required this.distanceForEvent,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onOpenEvent,
  });

  final Position? currentPosition;
  final List<EventModel> events;
  final double? Function(EventModel event) distanceForEvent;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<EventModel> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          border: Border.all(color: palette.borderSubtle),
          boxShadow: VennuzoTheme.shadowResting,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Finding nearby events...',
                style: context.text.bodyLarge,
              ),
            ),
          ],
        ),
      );
    }

    if (currentPosition == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          border: Border.all(color: palette.borderSubtle),
          boxShadow: VennuzoTheme.shadowResting,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Around you',
              style: context.text.titleLarge?.copyWith(
                fontSize: 22,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error ?? 'Turn on location to see nearby events.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                ),
              ),
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Enable nearby events'),
            ),
          ],
        ),
      );
    }

    final markers = <gmaps.Marker>{
      gmaps.Marker(
        markerId: const gmaps.MarkerId('current_location'),
        position: gmaps.LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        ),
        infoWindow: const gmaps.InfoWindow(title: 'You are here'),
      ),
      ...events
          .where((event) => event.location != null)
          .map(
            (event) => gmaps.Marker(
              markerId: gmaps.MarkerId(event.id),
              position: gmaps.LatLng(
                event.location!.latitude,
                event.location!.longitude,
              ),
              infoWindow: gmaps.InfoWindow(
                title: event.title,
                snippet: event.venue,
              ),
            ),
          ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Around you',
                      style: context.text.titleLarge?.copyWith(
                        fontSize: 22,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      events.isEmpty
                          ? 'No nearby events yet.'
                          : 'Closest public events.',
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Refresh nearby events',
                  icon: Icon(Icons.refresh, color: palette.slate, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: IgnorePointer(
                child: gmaps.GoogleMap(
                  initialCameraPosition: gmaps.CameraPosition(
                    target: gmaps.LatLng(
                      currentPosition!.latitude,
                      currentPosition!.longitude,
                    ),
                    zoom: events.isEmpty ? 12 : 13,
                  ),
                  markers: markers,
                  liteModeEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  myLocationButtonEnabled: false,
                  scrollGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                ),
              ),
            ),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...events.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                  child: InkWell(
                    onTap: () => onOpenEvent(event),
                    borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(
                          VennuzoTheme.radiusMd,
                        ),
                        border: Border.all(color: palette.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          EventArtwork(
                            event: event,
                            height: 48,
                            width: 48,
                            borderRadius: BorderRadius.circular(
                              VennuzoTheme.radiusSm,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: context.text.titleSmall?.copyWith(
                                    fontSize: 15,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${event.venue}, ${event.city}',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.canvas,
                              borderRadius: BorderRadius.circular(
                                VennuzoTheme.radiusFull,
                              ),
                              border: Border.all(color: palette.border),
                            ),
                            child: Text(
                              '${(distanceForEvent(event) ?? 0).toStringAsFixed(1)} km',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _VibeFilterChip - Pill-shaped with gradient fill when selected
// ---------------------------------------------------------------------------
class _VibeFilterChip extends StatelessWidget {
  const _VibeFilterChip({
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
          color: selected ? null : palette.card,
          border: selected
              ? null
              : Border.all(color: palette.border),
          boxShadow: selected ? VennuzoTheme.shadowElevated : null,
        ),
        child: Text(
          label,
          style: context.text.bodyMedium?.copyWith(
            color: selected ? Colors.white : palette.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AnnouncementTakeover - Cinematic, deeper scrims, larger type
// ---------------------------------------------------------------------------
class _AnnouncementTakeover extends StatelessWidget {
  const _AnnouncementTakeover({required this.event, required this.campaign});

  final EventModel event;
  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final minPrice = event.ticketing.minimumPrice;
    final priceLabel = minPrice == null
        ? 'Free entry'
        : 'From ${formatMoney(minPrice)}';

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
                    // Full-bleed generative art background
                    Positioned.fill(
                      child: EventArtwork(
                        event: event,
                        height: constraints.maxHeight,
                      ),
                    ),
                    // Deep cinematic scrim
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.3, 0.65, 1.0],
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.45),
                              Colors.black.withValues(alpha: 0.78),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 60,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: _PlacementBadge(
                                      label: 'Fullscreen announcement',
                                      icon: Icons.open_in_full_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                    child: IconButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      style: IconButton.styleFrom(
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(Icons.close, size: 22),
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                'NOW SPOTLIGHTING',
                                style: context.text.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                event.title,
                                style: context.text.headlineLarge?.copyWith(
                                  color: Colors.white,
                                  height: 0.96,
                                  letterSpacing: -0.8,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                campaign.message,
                                style: context.text.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _PlacementStat(
                                    label: formatShortDate(event.startDate),
                                  ),
                                  _PlacementStat(
                                    label: '${event.venue}, ${event.city}',
                                  ),
                                  _PlacementStat(label: priceLabel),
                                ],
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: context.palette.ink,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        VennuzoTheme.radiusMd,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_forward_outlined,
                                  ),
                                  label: const Text('View event'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        VennuzoTheme.radiusMd,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Not now'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'This placement is part of Vennuzo premium promotion inventory for organizers.',
                                style: context.text.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
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

// ---------------------------------------------------------------------------
// _PlacementBadge - Glass-morphism style
// ---------------------------------------------------------------------------
class _PlacementBadge extends StatelessWidget {
  const _PlacementBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PlacementStat - Glass-morphism chip
// ---------------------------------------------------------------------------
class _PlacementStat extends StatelessWidget {
  const _PlacementStat({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
