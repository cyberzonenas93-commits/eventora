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

class PlaceDetailScreen extends StatelessWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final place = repository.placeById(placeId);
    if (place == null) {
      return const Scaffold(body: Center(child: Text('Place not found')));
    }
    final subscribed = repository.isSubscribedToPlace(place.id);
    final sections = repository.menuSectionsForPlace(place.id);
    final menuItems = repository.menuItemsForPlace(place.id);
    final events = repository.eventsForPlace(place.id);
    final gallery = _mediaForPlace(place).take(12).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        bottomNavigationBar: _PlaceActionBar(
          place: place,
          subscribed: subscribed,
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 380,
              pinned: true,
              title: Text(place.name),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Material(
                  color: VennuzoTheme.background.withValues(alpha: 0.94),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(
                        child: Semantics(
                          button: true,
                          label: 'Profile tab',
                          child: const Text('Profile'),
                        ),
                      ),
                      Tab(
                        child: Semantics(
                          button: true,
                          label: 'Menu tab',
                          child: const Text('Menu'),
                        ),
                      ),
                      Tab(
                        child: Semantics(
                          button: true,
                          label: 'Events tab',
                          child: const Text('Events'),
                        ),
                      ),
                      Tab(
                        child: Semantics(
                          button: true,
                          label: 'Media tab',
                          child: const Text('Media'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PlaceHeaderMedia(place: place),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.10),
                            Colors.black.withValues(alpha: 0.86),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              PlaceVerificationBadge(place: place),
                              if (place.featured)
                                const _Pill(label: 'Featured'),
                              _Pill(
                                label: '${place.rating.toStringAsFixed(1)} ★',
                              ),
                              _Pill(label: '${menuItems.length} menu items'),
                              _Pill(
                                label: '${place.galleryUrls.length} photos',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            place.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.headlineMedium?.copyWith(
                              color: Colors.white,
                              height: 1.02,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            place.address.isEmpty ? place.city : place.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.86),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _PlaceAboutTab(
                place: place,
                gallery: gallery,
                eventsCount: events.length,
              ),
              _PlaceMenuTab(sections: sections),
              _PlaceEventsTab(events: events),
              _PlaceMediaTab(place: place, gallery: gallery),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceHeaderMedia extends StatelessWidget {
  const _PlaceHeaderMedia({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final media = _mediaForPlace(place);
    return Stack(
      fit: StackFit.expand,
      children: [
        _PlaceImage(url: media.isEmpty ? place.coverUrl : media.first),
        if (media.length > 2)
          Positioned(
            right: 18,
            top: 96,
            width: 92,
            child: Column(
              children: media
                  .skip(1)
                  .take(3)
                  .map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _PlaceImage(url: url, thumbnail: true),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _PlaceAboutTab extends StatelessWidget {
  const _PlaceAboutTab({
    required this.place,
    required this.gallery,
    required this.eventsCount,
  });

  final PlaceProfile place;
  final List<String> gallery;
  final int eventsCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        _PlaceProfileSummary(place: place),
        const SizedBox(height: 18),
        Text(place.description, style: context.text.bodyLarge),
        const SizedBox(height: 16),
        _DetailMetricGrid(
          rating: place.rating.toStringAsFixed(1),
          reviews: place.reviewCount,
          subscribers: place.subscriberCount,
          events: eventsCount,
        ),
        const SizedBox(height: 26),
        if (gallery.length > 1) ...[
          _GalleryStrip(urls: gallery),
          const SizedBox(height: 26),
        ],
        _InfoPanel(place: place),
      ],
    );
  }
}

class _PlaceProfileSummary extends StatelessWidget {
  const _PlaceProfileSummary({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: VennuzoTheme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _PlaceLogo(place: place, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, style: context.text.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    place.categories.take(3).join(' · '),
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlaceVerificationBadge(place: place, compact: true),
                      _Pill(label: place.city),
                      if (place.featured) const _Pill(label: 'Featured'),
                      _Pill(label: '${place.galleryUrls.length} media'),
                    ],
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

class _PlaceMenuTab extends StatelessWidget {
  const _PlaceMenuTab({required this.sections});

  final List<PlaceMenuSection> sections;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        SectionHeading(title: 'Menu', subtitle: null),
        const SizedBox(height: 12),
        if (sections.isEmpty)
          const EmptyStateCard(
            title: 'No menu published',
            icon: Icons.restaurant_menu_outlined,
            body: 'This place has not published its public menu yet.',
          )
        else
          for (final section in sections) ...[
            _MenuSection(section: section),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

class _PlaceEventsTab extends StatelessWidget {
  const _PlaceEventsTab({required this.events});

  final List<EventModel> events;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        SectionHeading(title: 'Upcoming events', subtitle: null),
        const SizedBox(height: 12),
        if (events.isEmpty)
          const EmptyStateCard(
            title: 'No upcoming events',
            icon: Icons.event_outlined,
            body: 'Events hosted at this location will appear here.',
          )
        else
          for (final event in events)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.event_outlined,
                  color: context.palette.teal,
                ),
                title: Text(event.title),
                subtitle: Text(
                  formatEventWindow(event.startDate, event.endDate),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
      ],
    );
  }
}

class _PlaceMediaTab extends StatelessWidget {
  const _PlaceMediaTab({required this.place, required this.gallery});

  final PlaceProfile place;
  final List<String> gallery;

  @override
  Widget build(BuildContext context) {
    final media = gallery.isEmpty ? _mediaForPlace(place) : gallery;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        SectionHeading(
          title: 'Media gallery',
          subtitle: '${media.length} photos from the place profile',
        ),
        const SizedBox(height: 12),
        if (media.isEmpty)
          const EmptyStateCard(
            title: 'No media yet',
            icon: Icons.photo_library_outlined,
            body: 'Photos and gallery imports from G+ will appear here.',
          )
        else
          _PlaceMediaMosaic(urls: media),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: context.palette.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Media from G+ gallery imports is used to keep this profile fresh across Vennuzo discovery, events, and featured placements.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceMediaMosaic extends StatelessWidget {
  const _PlaceMediaMosaic({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final restCount = (urls.length - 1).clamp(0, 8);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.35,
          child: _TappableGalleryImage(
            urls: urls,
            index: 0,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          ),
        ),
        if (restCount > 0) ...[
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: restCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) => _TappableGalleryImage(
              urls: urls,
              index: index + 1,
              thumbnail: true,
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaceActionBar extends StatelessWidget {
  const _PlaceActionBar({required this.place, required this.subscribed});

  final PlaceProfile place;
  final bool subscribed;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<VennuzoRepository>();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(
          color: VennuzoTheme.background.withValues(alpha: 0.96),
          border: const Border(top: BorderSide(color: VennuzoTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _reserve(context, place),
                icon: const Icon(Icons.event_seat_outlined),
                label: const Text('Reserve'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => subscribed
                    ? repository.unsubscribeFromPlace(place.id)
                    : repository.subscribeToPlace(place.id),
                icon: Icon(
                  subscribed
                      ? Icons.notifications_active_rounded
                      : Icons.notification_add_outlined,
                ),
                label: Text(subscribed ? 'Subscribed' : 'Subscribe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailMetricGrid extends StatelessWidget {
  const _DetailMetricGrid({
    required this.rating,
    required this.reviews,
    required this.subscribers,
    required this.events,
  });

  final String rating;
  final int reviews;
  final int subscribers;
  final int events;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DetailMetric(
            icon: Icons.star_rounded,
            value: rating,
            label: 'rating',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DetailMetric(
            icon: Icons.reviews_outlined,
            value: '$reviews',
            label: 'reviews',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DetailMetric(
            icon: Icons.notifications_active_outlined,
            value: '$subscribers',
            label: 'followers',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DetailMetric(
            icon: Icons.event_outlined,
            value: '$events',
            label: 'events',
          ),
        ),
      ],
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VennuzoTheme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: context.palette.teal, size: 18),
            const SizedBox(height: 7),
            Text(value, style: context.text.titleSmall),
            Text(label, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GalleryStrip extends StatelessWidget {
  const _GalleryStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title: 'Photos', subtitle: null),
        const SizedBox(height: 12),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) => AspectRatio(
              aspectRatio: 1.2,
              child: _TappableGalleryImage(
                urls: urls,
                index: index,
                thumbnail: true,
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
              ),
            ),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemCount: urls.length,
          ),
        ),
      ],
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.section});

  final PlaceMenuSection section;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final items = repository.menuItemsForPlace(
      section.placeId,
      sectionId: section.id,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.name,
          style: context.text.titleLarge?.copyWith(fontSize: 20),
        ),
        if (section.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(section.description, style: context.text.bodyMedium),
        ],
        const SizedBox(height: 10),
        for (final item in items)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: item.imageUrl == null
                      ? DecoratedBox(
                          decoration: const BoxDecoration(
                            color: VennuzoTheme.surfaceElevated,
                          ),
                          child: Icon(
                            item.featured
                                ? Icons.star_rounded
                                : Icons.restaurant_menu_rounded,
                            color: item.featured
                                ? context.palette.gold
                                : context.palette.teal,
                          ),
                        )
                      : _PlaceImage(url: item.imageUrl, thumbnail: true),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: context.text.titleMedium,
                              ),
                            ),
                            Text(
                              formatMoney(item.price),
                              style: context.text.titleSmall,
                            ),
                          ],
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ],
                        if (item.featured) ...[
                          const SizedBox(height: 8),
                          const _Pill(label: 'Popular'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Text(place.address.isEmpty ? place.city : place.address),
            if (place.openingHours.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Hours', style: context.text.titleMedium),
              const SizedBox(height: 8),
              for (final line in place.openingHours) Text(line),
            ],
            if (place.amenities.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: place.amenities
                    .map((item) => _Pill(label: item))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _reserve(BuildContext context, PlaceProfile place) async {
  final repository = context.read<VennuzoRepository>();
  final result = await showModalBottomSheet<PlaceReservationRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReservationSheet(place: place),
  );
  if (result == null || !context.mounted) return;
  repository.createPlaceReservation(result);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Reservation request sent to ${place.name}.')),
  );
}

class _ReservationSheet extends StatefulWidget {
  const _ReservationSheet({required this.place});

  final PlaceProfile place;

  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  PlaceReservationType _type = PlaceReservationType.table;
  int _partySize = 4;
  DateTime _requestedAt = DateTime.now().add(const Duration(days: 1, hours: 3));
  final Set<String> _selectedMenuItems = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final featuredItems = repository
        .menuItemsForPlace(widget.place.id)
        .where((item) => item.featured && item.isAvailable)
        .toList();
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Container(
      decoration: const BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reserve ${widget.place.name}',
              style: context.text.headlineSmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PlaceReservationType>(
              initialValue: _type,
              items: PlaceReservationType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
              decoration: const InputDecoration(labelText: 'Reservation type'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _partySize,
              items: [1, 2, 3, 4, 5, 6, 8, 10, 12]
                  .map(
                    (count) => DropdownMenuItem(
                      value: count,
                      child: Text('$count guests'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _partySize = value ?? 4),
              decoration: const InputDecoration(labelText: 'Party size'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _requestedAt,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_requestedAt),
                );
                if (time == null) return;
                setState(() {
                  _requestedAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    time.hour,
                    time.minute,
                  );
                });
              },
              icon: const Icon(Icons.schedule_outlined),
              label: Text(formatPromoTime(_requestedAt)),
            ),
            if (featuredItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Add package interest', style: context.text.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: featuredItems
                    .map(
                      (item) => FilterChip(
                        label: Text(
                          '${item.name} · ${formatMoney(item.price)}',
                        ),
                        selected: _selectedMenuItems.contains(item.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selectedMenuItems.add(item.id);
                          } else {
                            _selectedMenuItems.remove(item.id);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = _name.text.trim();
                  final phone = _phone.text.trim();
                  if (name.isEmpty || phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Add a name and phone number.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop(
                    PlaceReservationRequest(
                      placeId: widget.place.id,
                      placeName: widget.place.name,
                      reservationType: _type,
                      guestName: name,
                      phone: phone,
                      partySize: _partySize,
                      requestedAt: _requestedAt,
                      note: _note.text.trim(),
                      selectedMenuItemIds: _selectedMenuItems.toList(),
                    ),
                  );
                },
                child: const Text('Send reservation request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({required this.url, this.thumbnail = false});

  final String? url;

  /// When true, the network image is decoded/cached at a reduced width to keep
  /// memory low for small thumbnails (gallery tiles, logos, list covers).
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final raw = url ?? '';
    final value = raw.startsWith('/assets/') ? raw.substring(1) : raw;
    if (value.startsWith('http')) {
      final cacheWidth = thumbnail ? 320 : null;
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        placeholder: (_, _) => const _PlaceImageLoading(),
        errorWidget: (_, _, _) => const _PlaceImageFallback(),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        cacheWidth: thumbnail ? 320 : null,
        errorBuilder: (_, _, _) => const _PlaceImageFallback(),
      );
    }
    return const _PlaceImageFallback();
  }
}

class _PlaceImageLoading extends StatelessWidget {
  const _PlaceImageLoading();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: VennuzoTheme.surfaceElevated),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// A gallery thumbnail that opens the full-screen, zoomable viewer on tap.
class _TappableGalleryImage extends StatelessWidget {
  const _TappableGalleryImage({
    required this.urls,
    required this.index,
    required this.borderRadius,
    this.thumbnail = false,
  });

  final List<String> urls;
  final int index;
  final BorderRadius borderRadius;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View photo ${index + 1} of ${urls.length}',
      child: GestureDetector(
        onTap: () => showPlaceFullscreenGallery(
          context,
          urls: urls,
          initialIndex: index,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: _PlaceImage(
            url: index < urls.length ? urls[index] : null,
            thumbnail: thumbnail,
          ),
        ),
      ),
    );
  }
}

class _PlaceImageFallback extends StatelessWidget {
  const _PlaceImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [VennuzoTheme.surfaceElevated, VennuzoTheme.surfaceBright],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.storefront_rounded, size: 34)),
    );
  }
}

class _PlaceLogo extends StatelessWidget {
  const _PlaceLogo({required this.place, this.size = 48});

  final PlaceProfile place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = place.logoUrl ?? place.coverUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: VennuzoTheme.borderBright),
        color: VennuzoTheme.surfaceElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Icon(place.icon, color: context.palette.teal)
          : _PlaceImage(url: url, thumbnail: true),
    );
  }
}

List<String> _mediaForPlace(PlaceProfile place) {
  final seen = <String>{};
  final media = <String>[];
  void add(String? value) {
    final cleaned = (value ?? '').trim();
    if (cleaned.isEmpty || !seen.add(cleaned)) return;
    media.add(cleaned);
  }

  add(place.coverUrl);
  for (final url in place.galleryUrls) {
    add(url);
  }
  return media;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label, style: context.text.bodySmall)],
      ),
    );
  }
}

String _typeLabel(PlaceReservationType type) => switch (type) {
  PlaceReservationType.table => 'Table',
  PlaceReservationType.vipTable => 'VIP table',
  PlaceReservationType.guestlist => 'Guestlist',
  PlaceReservationType.bottleService => 'Bottle service',
  PlaceReservationType.privateBooking => 'Private booking',
};

void _openPlace(BuildContext context, PlaceProfile place) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaceDetailScreen(placeId: place.id),
    ),
  );
}
