import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final session = context.watch<EventoraSessionController>();
    final events = repository.adminVisibleEvents;
    final campaigns = repository.adminVisibleCampaigns;
    final liveCampaigns = campaigns
        .where((campaign) => campaign.status.name == 'live')
        .length;
    final privateCount = events.where((event) => event.isPrivate).length;
    final recurringCount = events
        .where((event) => event.recurrence.isRecurring)
        .length;
    final watchlist = events.take(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _DashboardHero(
          displayName: session.viewer.displayName,
          isSuperAdmin: session.hasSuperAdminAccess,
          grossRevenue: repository.grossRevenue,
          openGateCount: repository.openGateTicketCount,
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Events in system',
              value: '${events.length}',
              icon: Icons.calendar_month_outlined,
            ),
            MetricTile(
              label: 'Gross revenue',
              value: formatMoney(repository.grossRevenue),
              icon: Icons.payments_outlined,
              highlight: context.palette.gold,
            ),
            MetricTile(
              label: 'Live campaigns',
              value: '$liveCampaigns',
              icon: Icons.campaign_outlined,
              highlight: context.palette.teal,
            ),
            MetricTile(
              label: 'Gate queue',
              value: '${repository.openGateTicketCount}',
              icon: Icons.qr_code_scanner_outlined,
              highlight: context.palette.coral,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Today at a glance',
          subtitle:
              'A focused admin summary of revenue, validation pressure, private-event load, and upcoming recurring formats.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _AdminInsightCard(
              title: 'RSVP pressure',
              body:
                  '${repository.totalRsvps} attendee records are already in the system and ready for audience sync or gate prep.',
              accent: context.palette.teal,
              icon: Icons.groups_2_outlined,
            ),
            _AdminInsightCard(
              title: 'Private events',
              body:
                  '$privateCount private or invite-only events need tighter operator handling and limited sharing.',
              accent: context.palette.coral,
              icon: Icons.lock_outline,
            ),
            _AdminInsightCard(
              title: 'Recurring series',
              body:
                  '$recurringCount active recurring formats are ideal for reminder automation and repeat-audience SMS.',
              accent: context.palette.gold,
              icon: Icons.repeat_outlined,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Operations watchlist',
          subtitle:
              'These events are the closest to the door, campaign desk, or admin escalation path.',
        ),
        const SizedBox(height: 14),
        ...watchlist.map(
          (event) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _WatchlistCard(event: event),
          ),
        ),
        if (session.hasSuperAdminAccess) ...[
          const SizedBox(height: 28),
          SectionHeading(
            title: 'Superadmin layer',
            subtitle:
                'Platform-level visibility for admins, reports, moderation, and notification infrastructure.',
          ),
          const SizedBox(height: 14),
          _SuperAdminPanel(
            totalEvents: events.length,
            totalCampaigns: campaigns.length,
          ),
        ],
      ],
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.displayName,
    required this.isSuperAdmin,
    required this.grossRevenue,
    required this.openGateCount,
  });

  final String displayName;
  final bool isSuperAdmin;
  final double grossRevenue;
  final int openGateCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [context.palette.ink, context.palette.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSuperAdmin ? 'Superadmin command deck' : 'Admin command deck',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Run events, ticketing, and comms from one operations surface, $displayName.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            '${formatMoney(grossRevenue)} tracked so far, with $openGateCount tickets still waiting at the gate.',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminInsightCard extends StatelessWidget {
  const _AdminInsightCard({
    required this.title,
    required this.body,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String body;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 14),
          Text(title, style: context.text.titleLarge?.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text(body, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventoraRepository>();
    final orders = repository.ordersForEvent(event.id);
    final outstanding = repository.outstandingTicketsForEvent(event.id).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                        event.title,
                        style: context.text.titleLarge?.copyWith(fontSize: 21),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatEventWindow(event.startDate, event.endDate),
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _WatchlistPill(
                  label: event.isPrivate ? 'Private' : 'Public',
                  color: event.isPrivate
                      ? context.palette.coral
                      : context.palette.teal,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WatchlistPill(
                  label: '${repository.rsvpsForEvent(event.id).length} RSVPs',
                ),
                _WatchlistPill(label: '${orders.length} orders'),
                _WatchlistPill(label: '$outstanding at gate'),
                _WatchlistPill(
                  label: formatMoney(repository.revenueForEvent(event.id)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistPill extends StatelessWidget {
  const _WatchlistPill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.palette.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SuperAdminPanel extends StatelessWidget {
  const _SuperAdminPanel({
    required this.totalEvents,
    required this.totalCampaigns,
  });

  final int totalEvents;
  final int totalCampaigns;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform oversight',
              style: context.text.titleLarge?.copyWith(fontSize: 21),
            ),
            const SizedBox(height: 10),
            Text(
              'Use this layer for moderator queues, admin access, support escalation, and broadcast governance as Eventora grows beyond one organizer workspace.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WatchlistPill(
                  label: '$totalEvents total events',
                  color: context.palette.teal,
                ),
                _WatchlistPill(
                  label: '$totalCampaigns campaign records',
                  color: context.palette.gold,
                ),
                _WatchlistPill(
                  label: 'UGC reports ready',
                  color: context.palette.coral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
