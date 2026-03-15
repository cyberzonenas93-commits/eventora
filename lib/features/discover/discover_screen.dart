import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../events/event_detail_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final events = repository.discoverableEvents;
    final featured = events.isEmpty ? null : events.first;
    final recurringCount = events.where((event) => event.recurrence.isRecurring).length;
    final ticketedCount = events.where((event) => event.ticketing.enabled).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _DiscoverHero(featured: featured),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Upcoming public events',
              value: '${events.length}',
              icon: Icons.public_outlined,
            ),
            MetricTile(
              label: 'Ticketed experiences',
              value: '$ticketedCount',
              icon: Icons.confirmation_num_outlined,
            ),
            MetricTile(
              label: 'Recurring formats',
              value: '$recurringCount',
              icon: Icons.repeat_outlined,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Trending this week',
          subtitle: 'Public events only. Private and invite-only events stay out of discovery.',
        ),
        const SizedBox(height: 14),
        if (events.isEmpty)
          const EmptyStateCard(
            title: 'No public events yet',
            body: 'Once you publish an event, it will appear here with ticketing and sharing ready to go.',
            icon: Icons.event_busy_outlined,
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EventCard(
                event: event,
                onTap: () => _openEvent(context, event),
                footer: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _openEvent(context, event),
                        child: const Text('Open details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _openEvent(context, event),
                        child: Text(event.ticketing.enabled ? 'Get tickets' : 'View flow'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openEvent(BuildContext context, EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(eventId: event.id),
      ),
    );
  }
}

class _DiscoverHero extends StatelessWidget {
  const _DiscoverHero({required this.featured});

  final EventModel? featured;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [palette.ink, palette.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Eventora',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Build events with tickets, RSVPs, reminders, and promotion baked in.',
            style: context.text.headlineMedium?.copyWith(
              color: Colors.white,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            featured == null
                ? 'Your next event can start as a private invite and scale into a public campaign later.'
                : 'Featured now: ${featured!.title} in ${featured!.city}.',
            style: context.text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.86)),
          ),
        ],
      ),
    );
  }
}
