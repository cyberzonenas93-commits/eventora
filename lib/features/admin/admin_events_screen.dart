import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../events/event_detail_screen.dart';
import '../events/event_editor_screen.dart';
import '../promotions/campaign_composer_sheet.dart';

class AdminEventsScreen extends StatelessWidget {
  const AdminEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final events = repository.adminVisibleEvents;
    final privateCount = events.where((event) => event.isPrivate).length;
    final ticketedCount = events
        .where((event) => event.ticketing.enabled)
        .length;
    final recurringCount = events
        .where((event) => event.recurrence.isRecurring)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        const _AdminEventsHero(),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'All events',
              value: '${events.length}',
              icon: Icons.event_note_outlined,
            ),
            MetricTile(
              label: 'Ticketed',
              value: '$ticketedCount',
              icon: Icons.local_activity_outlined,
              highlight: context.palette.gold,
            ),
            MetricTile(
              label: 'Private',
              value: '$privateCount',
              icon: Icons.lock_outline,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Recurring',
              value: '$recurringCount',
              icon: Icons.repeat_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Event operations',
          subtitle:
              'This is the Eventora equivalent of the GPlus event console: edit, inspect guest lists, check ticket pressure, and launch campaigns from one lane.',
        ),
        const SizedBox(height: 14),
        if (events.isEmpty)
          const EmptyStateCard(
            title: 'No events yet',
            body:
                'Once events are published, admin operations for RSVP lists, ticketing, and campaigns will show here.',
            icon: Icons.event_busy_outlined,
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EventCard(
                event: event,
                onTap: () => _openEvent(context, event),
                footer: _AdminEventFooter(event: event),
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

class _AdminEventsHero extends StatelessWidget {
  const _AdminEventsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.84),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Events hub',
            style: context.text.titleLarge?.copyWith(fontSize: 21),
          ),
          const SizedBox(height: 12),
          Text(
            'Manage publishing, recurrence, ticket tiers, privacy, guest lists, and event-specific campaigns from the admin side.',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'This surface leans into the stronger parts of the GPlus admin console without dragging over the club-specific complexity.',
            style: context.text.bodyLarge?.copyWith(
              color: context.palette.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEventFooter extends StatelessWidget {
  const _AdminEventFooter({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventoraRepository>();
    final rsvps = repository.rsvpsForEvent(event.id);
    final orders = repository.ordersForEvent(event.id);
    final outstanding = repository.outstandingTicketsForEvent(event.id).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AdminEventPill(label: '${rsvps.length} RSVPs'),
            _AdminEventPill(label: '${orders.length} orders'),
            _AdminEventPill(label: '$outstanding at gate'),
            _AdminEventPill(
              label: formatMoney(repository.revenueForEvent(event.id)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: () => _showGuestList(context, event),
              child: const Text('Guest list'),
            ),
            OutlinedButton(
              onPressed: () => _editEvent(context, event),
              child: const Text('Edit'),
            ),
            ElevatedButton(
              onPressed: () => _promoteEvent(context, event),
              child: const Text('Promote'),
            ),
          ],
        ),
      ],
    );
  }

  void _editEvent(BuildContext context, EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventEditorScreen(existingEvent: event),
      ),
    );
  }

  Future<void> _promoteEvent(BuildContext context, EventModel event) async {
    final campaign = await showCampaignComposerSheet(
      context,
      initialEvent: event,
    );
    if (campaign != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Campaign "${campaign.name}" created for ${event.title}.',
          ),
        ),
      );
    }
  }

  Future<void> _showGuestList(BuildContext context, EventModel event) async {
    final repository = context.read<EventoraRepository>();
    final rsvps = repository.rsvpsForEvent(event.id);
    final orders = repository.ordersForEvent(event.id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(event.title, style: context.text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'RSVPs, ticket buyers, and gate-ready counts in one admin sheet.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 20),
              SectionHeading(
                title: 'RSVPs',
                subtitle: rsvps.isEmpty
                    ? 'No RSVP records yet.'
                    : '${rsvps.length} RSVP records',
              ),
              const SizedBox(height: 12),
              if (rsvps.isEmpty)
                const EmptyStateCard(
                  title: 'No RSVPs yet',
                  body:
                      'RSVP-only events and hybrid events will start populating here.',
                  icon: Icons.person_add_alt_outlined,
                )
              else
                ...rsvps.map(
                  (rsvp) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        title: Text(rsvp.name),
                        subtitle: Text(
                          '${rsvp.phone} • ${rsvp.guestCount} guests',
                        ),
                        trailing: rsvp.bookTable
                            ? const Icon(Icons.table_restaurant_outlined)
                            : null,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              SectionHeading(
                title: 'Ticket buyers',
                subtitle: orders.isEmpty
                    ? 'No ticket orders yet.'
                    : '${orders.length} ticket orders',
              ),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const EmptyStateCard(
                  title: 'No ticket buyers yet',
                  body:
                      'Paid orders and pay-at-gate reservations will appear here.',
                  icon: Icons.receipt_long_outlined,
                )
              else
                ...orders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.buyerName,
                              style: context.text.titleLarge?.copyWith(
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${order.buyerPhone.isEmpty ? order.buyerEmail : order.buyerPhone} • ${order.ticketCount} tickets',
                              style: context.text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminEventPill extends StatelessWidget {
  const _AdminEventPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: context.palette.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
