import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/event_models.dart';
// EventMoodPalette extension provides `.colors` on EventMood
import '../../widgets/empty_state_card.dart';
import '../events/event_detail_screen.dart';
import 'social_service.dart';

class SavedEventsScreen extends StatelessWidget {
  const SavedEventsScreen({
    super.key,
    required this.userId,
  });

  final String userId;
  static final _socialService = SocialService();

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: EmptyStateCard(
            title: 'Sign in to see saved events',
            icon: Icons.bookmark_outline,
          ),
        ),
      );
    }

    return StreamBuilder<List<String>>(
      stream: _socialService.getSavedEvents(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final eventIds = snapshot.data ?? [];
        if (eventIds.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: EmptyStateCard(
                title: 'No saved events yet',
                body: 'Tap the bookmark icon on any event to save it here.',
                icon: Icons.bookmark_border_outlined,
              ),
            ),
          );
        }

        return _SavedEventsList(
          eventIds: eventIds,
          socialService: _socialService,
          userId: userId,
        );
      },
    );
  }
}

class _SavedEventsList extends StatelessWidget {
  const _SavedEventsList({
    required this.eventIds,
    required this.socialService,
    required this.userId,
  });

  final List<String> eventIds;
  final SocialService socialService;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final events = eventIds
        .map((id) => repository.eventById(id))
        .where((e) => e != null)
        .cast<EventModel>()
        .toList();

    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Loading saved events…',
          style: context.text.bodyMedium?.copyWith(color: context.palette.slate),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = events[index];
        return _SavedEventCard(
          event: event,
          userId: userId,
          socialService: socialService,
        );
      },
    );
  }
}

class _SavedEventCard extends StatelessWidget {
  const _SavedEventCard({
    required this.event,
    required this.userId,
    required this.socialService,
  });

  final EventModel event;
  final String userId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final moodColors = event.mood.colors;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(eventId: event.id),
        ),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Color swatch
            Container(
              width: 6,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: moodColors,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.venue,
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.slate,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // Unsave button
            IconButton(
              onPressed: () {
                socialService.unsaveEvent(userId, event.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Event removed from saved.')),
                );
              },
              icon: const Icon(Icons.bookmark),
              color: palette.coral,
              tooltip: 'Remove from saved',
            ),
          ],
        ),
      ),
    );
  }
}
