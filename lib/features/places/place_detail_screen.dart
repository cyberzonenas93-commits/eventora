part of 'places_screen.dart';

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
