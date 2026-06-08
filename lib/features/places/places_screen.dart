import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/place_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/place_verification_badge.dart';
import '../../widgets/section_heading.dart';
import 'place_fullscreen_gallery.dart';

part 'place_detail_screen.dart';
part 'place_reservation_sheet.dart';
part 'place_screen_widgets.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  String _query = '';
  String _selectedCategory = 'All';
  String _sortMode = 'Recommended';

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final allPlaces = repository.places;
    final categories = <String>{
      'All',
      for (final place in allPlaces)
        for (final category in place.categories)
          if (category.trim().isNotEmpty) category.trim(),
    }.take(8).toList();
    final places =
        repository.places.where((place) {
          if (_selectedCategory != 'All' &&
              !place.categories.contains(_selectedCategory)) {
            return false;
          }
          if (_query.isEmpty) return true;
          final text = [
            place.name,
            place.city,
            place.address,
            place.description,
            ...place.categories,
          ].join(' ').toLowerCase();
          return text.contains(_query.toLowerCase());
        }).toList()..sort((a, b) {
          if (_sortMode == 'Rating') {
            final rating = b.rating.compareTo(a.rating);
            if (rating != 0) return rating;
          }
          if (_sortMode == 'Followers') {
            final followers = b.subscriberCount.compareTo(a.subscriberCount);
            if (followers != 0) return followers;
          }
          if (a.featured != b.featured) return a.featured ? -1 : 1;
          return b.subscriberCount.compareTo(a.subscriberCount);
        });
    final featured = places.where((place) => place.featured).toList();
    final spotlight = featured.isNotEmpty
        ? featured.first
        : (places.isNotEmpty ? places.first : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        _PlacesHero(
          spotlight: spotlight,
          placeCount: allPlaces.length,
          featuredCount: allPlaces.where((place) => place.featured).length,
          subscriberCount: allPlaces.fold<int>(
            0,
            (sum, place) => sum + place.subscriberCount,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search places, menus, area',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 14),
        _PlacesCommandDeck(
          categories: categories,
          selectedCategory: _selectedCategory,
          sortMode: _sortMode,
          onCategoryChanged: (value) =>
              setState(() => _selectedCategory = value),
          onSortChanged: (value) => setState(() => _sortMode = value),
        ),
        if (categories.length > 1) ...[
          const SizedBox(height: 14),
          _CategoryRail(
            categories: categories,
            selected: _selectedCategory,
            onChanged: (value) => setState(() => _selectedCategory = value),
          ),
        ],
        const SizedBox(height: 18),
        if (featured.isNotEmpty) ...[
          SectionHeading(
            title: 'Featured places',
            subtitle:
                'Media-rich profiles with menus, events, and reservations.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 306,
                child: _FeaturedPlaceCard(place: featured[index]),
              ),
            ),
          ),
          const SizedBox(height: 26),
        ],
        SectionHeading(
          title: 'Places',
          subtitle: '${places.length} matching profiles',
        ),
        const SizedBox(height: 12),
        if (places.isEmpty)
          const EmptyStateCard(
            title: 'No places yet',
            icon: Icons.storefront_outlined,
            body:
                'Featured venues, menus, reservations, and location updates will appear here.',
          )
        else
          ...places.map(
            (place) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlaceRow(
                place: place,
                eventCount: repository.eventsForPlace(place.id).length,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlacesCommandDeck extends StatelessWidget {
  const _PlacesCommandDeck({
    required this.categories,
    required this.selectedCategory,
    required this.sortMode,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  final List<String> categories;
  final String selectedCategory;
  final String sortMode;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final activeCategories = categories.where((item) => item != 'All').length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: VennuzoTheme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CommandMetric(
                  icon: Icons.tune_rounded,
                  value: sortMode,
                  label: 'sort',
                ),
                const SizedBox(width: 10),
                _CommandMetric(
                  icon: Icons.category_outlined,
                  value: selectedCategory,
                  label: '$activeCategories categories',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Recommended',
                  label: Text('Best'),
                  icon: Icon(Icons.auto_awesome_rounded),
                ),
                ButtonSegment(
                  value: 'Rating',
                  label: Text('Rating'),
                  icon: Icon(Icons.star_rounded),
                ),
                ButtonSegment(
                  value: 'Followers',
                  label: Text('Reach'),
                  icon: Icon(Icons.groups_rounded),
                ),
              ],
              selected: {sortMode},
              showSelectedIcon: false,
              onSelectionChanged: (value) => onSortChanged(value.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandMetric extends StatelessWidget {
  const _CommandMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VennuzoTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VennuzoTheme.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: context.palette.teal, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                    Text(label, style: context.text.bodySmall),
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

class _PlacesHero extends StatelessWidget {
  const _PlacesHero({
    required this.spotlight,
    required this.placeCount,
    required this.featuredCount,
    required this.subscriberCount,
  });

  final PlaceProfile? spotlight;
  final int placeCount;
  final int featuredCount;
  final int subscriberCount;

  @override
  Widget build(BuildContext context) {
    final place = spotlight;
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minHeight: 360),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowElevated,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _PlaceImage(url: place?.coverUrl)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.22),
                    VennuzoTheme.surface.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Pill(label: 'Places'),
                const SizedBox(height: 52),
                Text(
                  place == null ? 'Discover places' : place.name,
                  style: context.text.headlineMedium?.copyWith(
                    color: Colors.white,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  place == null
                      ? 'Explore menus, reservations, events, and venue updates.'
                      : '${place.city} · ${place.subscriberCount} followers · ${place.rating.toStringAsFixed(1)} rating',
                  style: context.text.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                if (place != null && place.galleryUrls.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _HeroGalleryPreview(place: place),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PlaceStat(value: '$placeCount', label: 'places'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PlaceStat(
                        value: '$featuredCount',
                        label: 'featured',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PlaceStat(
                        value: '$subscriberCount',
                        label: 'followers',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGalleryPreview extends StatelessWidget {
  const _HeroGalleryPreview({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final gallery = _mediaForPlace(place).take(4).toList();
    if (gallery.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          for (final url in gallery) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _PlaceImage(url: url, thumbnail: true),
              ),
            ),
            if (url != gallery.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _PlaceStat extends StatelessWidget {
  const _PlaceStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.text.titleMedium),
            Text(label, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final category = categories[index];
          final active = category == selected;
          return FilterChip(
            selected: active,
            showCheckmark: false,
            label: Text(category),
            avatar: category == 'All'
                ? const Icon(Icons.explore_rounded, size: 16)
                : null,
            onSelected: (_) => onChanged(category),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: categories.length,
      ),
    );
  }
}

class _FeaturedPlaceCard extends StatelessWidget {
  const _FeaturedPlaceCard({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final gallery = _mediaForPlace(place).skip(1).take(3).toList();
    return Semantics(
      button: true,
      label: 'Open ${place.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        onTap: () => _openPlace(context, place),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
            border: Border.all(color: context.palette.border),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PlaceImage(url: place.coverUrl),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (gallery.isNotEmpty) ...[
                      SizedBox(
                        height: 46,
                        child: Row(
                          children: gallery
                              .map(
                                (url) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: url == gallery.last ? 0 : 7,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _PlaceImage(
                                        url: url,
                                        thumbnail: true,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const _Pill(label: 'Featured'),
                        PlaceVerificationBadge(place: place, compact: true),
                        _Pill(label: '${place.galleryUrls.length} photos'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      place.name,
                      style: context.text.titleLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${place.city} · ${place.subscriberCount} subscribers',
                      style: context.text.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
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

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.eventCount});

  final PlaceProfile place;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final subscribed = repository.isSubscribedToPlace(place.id);
    final menuCount = repository.menuItemsForPlace(place.id).length;
    final primaryCategory = place.categories.isEmpty
        ? 'Place'
        : place.categories.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Open ${place.name}',
        child: InkWell(
          onTap: () => _openPlace(context, place),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 172,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PlaceImage(url: place.coverUrl),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.70),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 16,
                      child: Row(
                        children: [
                          _Pill(label: primaryCategory),
                          const SizedBox(width: 8),
                          if (place.featured) const _Pill(label: 'Featured'),
                          const Spacer(),
                          PlaceVerificationBadge(place: place, compact: true),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              place.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: () => subscribed
                                ? repository.unsubscribeFromPlace(place.id)
                                : repository.subscribeToPlace(place.id),
                            icon: Icon(
                              subscribed
                                  ? Icons.notifications_active_rounded
                                  : Icons.notification_add_outlined,
                            ),
                            tooltip: subscribed ? 'Unsubscribe' : 'Subscribe',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _PlaceLogo(place: place),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                place.address.isEmpty
                                    ? place.city
                                    : place.address,
                                style: context.text.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                place.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.restaurant_menu_rounded,
                          color: context.palette.teal,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text('$menuCount menu'),
                        const SizedBox(width: 14),
                        Icon(
                          Icons.event_rounded,
                          color: context.palette.teal,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text('$eventCount events'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _openPlace(context, place),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(label: '${place.rating.toStringAsFixed(1)} ★'),
                        for (final amenity in place.amenities.take(3))
                          _Pill(label: amenity),
                        if (place.featured) const _Pill(label: 'Featured'),
                        if (subscribed) const _Pill(label: 'Subscribed'),
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
