import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/portal_links.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../creative/creative_services_screen.dart';
import '../events/event_editor_screen.dart';
import '../promotions/campaign_composer_sheet.dart';

class OrganizerOverviewScreen extends StatelessWidget {
  const OrganizerOverviewScreen({
    super.key,
    required this.onOpenEvents,
    required this.onOpenTickets,
    required this.onOpenPromote,
    required this.onOpenBusiness,
  });

  final VoidCallback onOpenEvents;
  final VoidCallback onOpenTickets;
  final VoidCallback onOpenPromote;
  final VoidCallback onOpenBusiness;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final repository = context.watch<VennuzoRepository>();
    final events = repository.managedEvents;
    final orders = repository.orders;
    final rsvps = repository.rsvps;
    final campaigns = repository.campaigns;
    final totalRevenue = events.fold<double>(
      0,
      (sum, event) => sum + repository.revenueForEvent(event.id),
    );
    final ticketsSold = events.fold<int>(
      0,
      (sum, event) => sum + repository.soldForEvent(event.id),
    );
    final openGateTickets = orders.fold<int>(
      0,
      (sum, order) =>
          sum +
          order.tickets
              .where((ticket) => ticket.status != TicketStatus.admitted)
              .length,
    );
    final nextEvent = events.isEmpty ? null : events.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        _OrganizerHero(
          organizerName: session.viewer.displayName,
          totalRevenue: totalRevenue,
          eventCount: events.length,
          nextEvent: nextEvent,
          onCreateEvent: () => _openCreateEvent(context),
          onPromote: () => _launchCampaign(context, nextEvent),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Events',
              value: '${events.length}',
              icon: Icons.calendar_month_outlined,
            ),
            MetricTile(
              label: 'Tickets sold',
              value: '$ticketsSold',
              icon: Icons.local_activity_outlined,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Revenue',
              value: formatMoney(totalRevenue),
              icon: Icons.payments_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Creator toolkit',
          subtitle: 'Everything an event organizer needs in one workspace.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _ToolCard(
              title: 'Events',
              body:
                  'Create, edit, publish, ticket, schedule, and share public event pages.',
              icon: Icons.event_note_outlined,
              actionLabel: 'Manage events',
              onTap: onOpenEvents,
            ),
            _ToolCard(
              title: 'Ticket desk',
              body:
                  'Inspect orders, scan QR tokens, admit guests, and handle cash-at-gate tickets.',
              icon: Icons.qr_code_scanner_outlined,
              actionLabel: 'Open tickets',
              onTap: onOpenTickets,
            ),
            _ToolCard(
              title: 'Promotions',
              body:
                  'Run paid push, SMS, share-link, featured banner, and announcement campaigns.',
              icon: Icons.campaign_outlined,
              actionLabel: 'Promote event',
              onTap: onOpenPromote,
            ),
            _ToolCard(
              title: 'Creative services',
              body:
                  'Generate event flyers and table-package flyers from your own brand.',
              icon: Icons.auto_awesome_outlined,
              actionLabel: 'Create flyer',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CreativeServicesScreen(),
                ),
              ),
            ),
            _ToolCard(
              title: 'Event Ops',
              body:
                  'Set up inventory, waiter credentials, paid tabs, and end-of-event reports.',
              icon: Icons.point_of_sale_outlined,
              actionLabel: 'Open Event Ops',
              onTap: () => _openEventOpsStudio(context, nextEvent),
            ),
            _ToolCard(
              title: 'Contacts / CRM',
              body:
                  'View RSVP guests and ticket buyers, spend summary, and contact history.',
              icon: Icons.groups_2_outlined,
              actionLabel: 'Open CRM',
              onTap: onOpenBusiness,
            ),
            _ToolCard(
              title: 'Business',
              body:
                  'Wallet, payouts, partners, referral tracking, and readiness.',
              icon: Icons.account_balance_wallet_outlined,
              actionLabel: 'Open business',
              onTap: onOpenBusiness,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Current operating status',
          subtitle:
              'Quick read on audience, campaigns, and gate pressure for this organizer workspace.',
        ),
        const SizedBox(height: 14),
        _OperationsCard(
          eventCount: events.length,
          rsvpCount: rsvps.length,
          campaignCount: campaigns.length,
          openGateTickets: openGateTickets,
        ),
        const SizedBox(height: 20),
        if (events.isNotEmpty) ...[
          SectionHeading(title: 'Public event presence', subtitle: null),
          const SizedBox(height: 14),
          ...events
              .take(4)
              .map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PublicPresenceCard(event: event),
                ),
              ),
        ],
      ],
    );
  }

  void _openCreateEvent(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const EventEditorScreen()));
  }

  Future<void> _launchCampaign(BuildContext context, EventModel? event) async {
    final campaign = await showCampaignComposerSheet(
      context,
      initialEvent: event,
    );
    if (campaign != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Campaign "${campaign.name}" created.')),
      );
    }
  }

  Future<void> _openEventOpsStudio(
    BuildContext context,
    EventModel? event,
  ) async {
    final url = event == null
        ? '$vennuzoStudioUrl/studio/operations'
        : '$vennuzoStudioUrl/studio/operations?eventId=${Uri.encodeComponent(event.id)}';
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Event Ops Studio.')),
      );
    }
  }
}

class _OrganizerHero extends StatelessWidget {
  const _OrganizerHero({
    required this.organizerName,
    required this.totalRevenue,
    required this.eventCount,
    required this.nextEvent,
    required this.onCreateEvent,
    required this.onPromote,
  });

  final String organizerName;
  final double totalRevenue;
  final int eventCount;
  final EventModel? nextEvent;
  final VoidCallback onCreateEvent;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            VennuzoTheme.surface,
            VennuzoTheme.surfaceBright,
            VennuzoTheme.primaryMid,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organizer portal',
            style: context.text.bodyLarge?.copyWith(
              color: VennuzoTheme.primaryStart,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Run every event workflow, $organizerName.',
            style: context.text.headlineSmall?.copyWith(
              color: VennuzoTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$eventCount events, ${formatMoney(totalRevenue)} tracked. ${nextEvent == null ? 'Create your next event to begin.' : 'Next up: ${nextEvent!.title}.'}',
            style: context.text.bodyLarge?.copyWith(
              color: VennuzoTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: onCreateEvent,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create event'),
              ),
              OutlinedButton.icon(
                onPressed: onPromote,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Launch promo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 40;
    final cardWidth = availableWidth < 330 ? availableWidth : 330.0;

    return SizedBox(
      width: cardWidth,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.palette.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: context.palette.teal),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: context.text.titleLarge?.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(body, style: context.text.bodyMedium),
                const SizedBox(height: 14),
                Text(
                  actionLabel,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.palette.teal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationsCard extends StatelessWidget {
  const _OperationsCard({
    required this.eventCount,
    required this.rsvpCount,
    required this.campaignCount,
    required this.openGateTickets,
  });

  final int eventCount;
  final int rsvpCount;
  final int campaignCount;
  final int openGateTickets;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusPill(label: '$eventCount managed events'),
            _StatusPill(label: '$rsvpCount RSVP contacts'),
            _StatusPill(label: '$campaignCount campaigns'),
            _StatusPill(label: '$openGateTickets gate tickets'),
          ],
        ),
      ),
    );
  }
}

class _PublicPresenceCard extends StatelessWidget {
  const _PublicPresenceCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<VennuzoRepository>();
    final link = repository.buildShareLink(event.id);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(event.title),
        subtitle: Text(event.visibility.name == 'public' ? link : 'Private'),
        trailing: IconButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Event share link copied.')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Copy event link',
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

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
