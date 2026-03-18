import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../data/services/eventora_launch_preferences.dart';
import '../../data/services/eventora_location_service.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
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
        await EventoraLaunchPreferences.shouldAllowAnnouncementTakeover();
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
    final repository = context.watch<EventoraRepository>();
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
        _DashboardHero(
          eventCount: events.length,
          featuredCount: featuredCampaigns.length,
          onShowAnnouncement: () => _showCurrentAnnouncement(repository),
        ),
        const SizedBox(height: 22),
        _AroundYouCard(
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
        const SizedBox(height: 22),
        _SearchPanel(
          controller: _searchController,
          query: _searchQuery,
          resultCount: filteredEvents.length,
          onChanged: (value) => setState(() => _searchQuery = value.trim()),
          onClear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
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
        SectionHeading(
          title: 'Featured this week',
          subtitle: _searchQuery.isEmpty
              ? 'The biggest launches and standout nights stay pinned here so you can scan what matters first.'
              : 'Featured events that match your search stay visible here.',
        ),
        const SizedBox(height: 14),
        if (featuredCampaigns.isEmpty)
          EmptyStateCard(
            title: _searchQuery.isEmpty
                ? 'No featured placements are live right now'
                : 'No featured events match your search',
            body: _searchQuery.isEmpty
                ? 'As new spotlight events go live, they will appear here for faster discovery.'
                : 'Try another event name, venue, city, or tag to see matching spotlight events.',
            icon: Icons.star_outline,
          )
        else
          SizedBox(
            height: 360,
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
        SectionHeading(
          title: 'Browse by vibe',
          subtitle: _searchQuery.isEmpty
              ? 'Tap one filter to strip away the noise and get to the kind of event you actually want.'
              : 'Use a vibe filter to narrow the search results even further.',
        ),
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
          subtitle: _resultsSubtitle(filteredEvents.length),
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
                : 'Nothing matches that vibe yet',
            body: _searchQuery.isNotEmpty
                ? 'Try a different name, venue, city, performer, or tag. You can also clear filters to browse everything again.'
                : 'Try another filter or come back later. The feed will update as new public events go live.',
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
    EventoraRepository repository,
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

  String _resultsSubtitle(int resultCount) {
    if (_searchQuery.isNotEmpty && _selectedTag != null) {
      return '$resultCount events match your search and the $_selectedTag vibe.';
    }
    if (_searchQuery.isNotEmpty) {
      return '$resultCount events match your search right now.';
    }
    if (_selectedTag != null) {
      return 'Only the listings tagged with $_selectedTag are shown below.';
    }
    return 'A cleaner feed of public events with the details that matter before you commit.';
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
      final position = await EventoraLocationService.instance
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
    final repository = context.read<EventoraRepository>();
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

  Future<void> _showCurrentAnnouncement(EventoraRepository repository) async {
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search Eventora',
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Look up an event by name, city, venue, host, performer, or tag.',
              style: context.text.bodyMedium?.copyWith(color: palette.slate),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText:
                    'Search by event name, venue, city, rooftop, music...',
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SearchHintChip(
                  icon: Icons.location_on_outlined,
                  label: 'City, venue, or host',
                ),
                _SearchHintChip(
                  icon: Icons.sell_outlined,
                  label: query.isEmpty
                      ? 'Try Music or Community'
                      : '$resultCount matches right now',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            palette.primaryStart,
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.06),
              palette.primaryStart,
            ),
            palette.primaryEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primaryStart.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -14,
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
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
              const SizedBox(height: 18),
              Text(
                'Find what is worth showing up for.',
                style: context.text.headlineMedium?.copyWith(
                  color: Colors.white,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Discover standout events, browse what is trending nearby, and move from curiosity to tickets without friction.',
                style: context.text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: onShowAnnouncement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: palette.ink,
                    ),
                    icon: const Icon(Icons.local_fire_department_outlined),
                    label: const Text('See spotlight'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(
                          Icons.swipe_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        Text(
                          'Curated picks below',
                          style: context.text.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHintChip extends StatelessWidget {
  const _SearchHintChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 16, color: palette.slate),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

    return SizedBox(
      width: 308,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              context.palette.primaryStart,
              event.mood.colors.first.withValues(alpha: 0.92),
              context.palette.primaryEnd,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: context.palette.primaryStart.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(18),
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
                      Text(
                        formatShortDate(event.startDate),
                        style: context.text.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    event.title,
                    style: context.text.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    campaign.message,
                    style: context.text.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 12),
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
      ),
    );
  }
}

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
              child: const Text('See details'),
            ),
          ),
          const SizedBox(width: 12),
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
    if (isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                  'Finding events around you...',
                  style: context.text.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (currentPosition == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Around you',
                style: context.text.titleLarge?.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                error ??
                    'Turn on location once so Eventora can highlight events close to you.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.my_location_outlined),
                label: const Text('Enable nearby events'),
              ),
            ],
          ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        style: context.text.titleLarge?.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        events.isEmpty
                            ? 'We have your location, but there are no mapped public events close by yet.'
                            : 'These are the closest public events with confirmed map locations.',
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Refresh nearby events',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
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
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => onOpenEvent(event),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.palette.canvas,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.palette.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: context.text.titleLarge?.copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${event.venue}, ${event.city}',
                                  style: context.text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(distanceForEvent(event) ?? 0).toStringAsFixed(1)} km',
                            style: context.text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: palette.primaryStart,
      side: BorderSide(color: palette.border),
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? Colors.white : palette.ink,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}

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
        padding: const EdgeInsets.all(20),
        child: Material(
          color: Colors.transparent,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: LinearGradient(
                colors: event.mood.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned(
                      top: -50,
                      right: -20,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 52,
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
                                  IconButton.filled(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                'Now spotlighting',
                                style: context.text.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.84),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                event.title,
                                style: context.text.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  height: 0.98,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                campaign.message,
                                style: context.text.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                              const SizedBox(height: 18),
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
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: context.palette.ink,
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
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Not now'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'This placement is part of Eventora premium promotion inventory for organizers.',
                                style: context.text.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
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

class _PlacementBadge extends StatelessWidget {
  const _PlacementBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacementStat extends StatelessWidget {
  const _PlacementStat({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
