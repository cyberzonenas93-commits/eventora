import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import '../events/event_detail_screen.dart';
import '../events/event_editor_screen.dart';
import 'host_access_screen.dart';
import '../promotions/campaign_composer_sheet.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final session = context.watch<EventoraSessionController>();
    final events = repository.managedEvents;
    final totalRevenue = events.fold<double>(
      0,
      (sum, event) => sum + repository.revenueForEvent(event.id),
    );
    final totalSold = events.fold<int>(
      0,
      (sum, event) => sum + repository.soldForEvent(event.id),
    );
    final viewer = session.viewer;
    final organizerReady = viewer.hasOrganizerAccess;
    final campaigns = repository.campaigns;
    final featuredCount = campaigns
        .where(
          (campaign) => campaign.channels.contains(PromotionChannel.featured),
        )
        .length;
    final announcementCount = campaigns
        .where(
          (campaign) =>
              campaign.channels.contains(PromotionChannel.announcement),
        )
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _ManageHero(
          organizerName: session.isGuest
              ? 'Guest mode'
              : repository.currentUserName,
          totalRevenue: totalRevenue,
          isGuest: session.isGuest,
          organizerReady: organizerReady,
          organizerStatusLabel: viewer.organizerStatusLabel,
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Hosted events',
              value: '${events.length}',
              icon: Icons.calendar_month_outlined,
            ),
            MetricTile(
              label: 'Tickets sold',
              value: '$totalSold',
              icon: Icons.local_activity_outlined,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Sales so far',
              value: formatMoney(totalRevenue),
              icon: Icons.payments_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Premium placements',
          subtitle: session.isGuest
              ? 'Featured banners and full-screen announcements are paid placements available once you start hosting.'
              : organizerReady
              ? 'Use premium inventory when an event deserves extra attention in the attendee dashboard.'
              : 'Premium placements unlock once your hosting setup is approved.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _HostPlacementCard(
              title: 'Featured banner',
              body:
                  'Put an event into the Explore banner rail so it leads the dashboard instead of waiting inside the normal list.',
              stat: '$featuredCount campaigns',
              icon: Icons.workspace_premium_outlined,
              actionLabel: session.isGuest
                  ? 'Get started'
                  : organizerReady
                  ? 'Promote an event'
                  : 'Finish setup',
              onAction: () => session.isGuest
                  ? _promptForAccess(context)
                  : organizerReady
                  ? _launchGeneralCampaign(
                      context,
                      events.isNotEmpty ? events.first : null,
                    )
                  : _openHostAccess(context),
            ),
            _HostPlacementCard(
              title: 'Fullscreen announcement',
              body:
                  'Book a splash-like takeover that opens before attendees start scrolling through the event feed.',
              stat: '$announcementCount campaigns',
              icon: Icons.open_in_full_outlined,
              actionLabel: session.isGuest
                  ? 'Create account'
                  : organizerReady
                  ? 'Launch campaign'
                  : 'Finish setup',
              onAction: () => session.isGuest
                  ? _promptForAccess(context)
                  : organizerReady
                  ? _launchGeneralCampaign(
                      context,
                      events.isNotEmpty ? events.first : null,
                    )
                  : _openHostAccess(context),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Host tools',
          subtitle: session.isGuest
              ? 'Create an account to draft events, set ticket prices, and start building your host profile.'
              : organizerReady
              ? 'Update the essentials quickly: dates, tickets, sharing, reminders, and promotions.'
              : 'Finish your host access setup right here in the app, then publish and manage events from this workspace.',
          actionLabel: session.isGuest
              ? 'Get started'
              : organizerReady
              ? 'Create event'
              : 'Open setup',
          onAction: () => session.isGuest
              ? _promptForAccess(context)
              : organizerReady
              ? _openEditor(context)
              : _openHostAccess(context),
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          EmptyStateCard(
            title: 'Ready to host your first event?',
            body:
                'Create an account when you want to build an event page, sell tickets, and share updates with guests.',
            icon: Icons.lock_outline,
            actionLabel: 'Create account',
            onAction: () => _promptForAccess(context),
          )
        else if (!organizerReady && viewer.hasPendingOrganizerApplication)
          EmptyStateCard(
            title: 'Your host application is being reviewed',
            body:
                'You have already submitted your host access request. We will unlock publishing tools here as soon as approval is complete.',
            icon: Icons.pending_actions_outlined,
            actionLabel: 'Review status',
            onAction: () => _openHostAccess(context),
          )
        else if (!organizerReady &&
            viewer.organizerApplicationStatus ==
                OrganizerApplicationStatus.rejected)
          EmptyStateCard(
            title: 'Your host application needs an update',
            body:
                'Open your host access setup, fix the requested details, and send it back for review.',
            icon: Icons.feedback_outlined,
            actionLabel: 'Update now',
            onAction: () => _openHostAccess(context),
          )
        else if (!organizerReady)
          EmptyStateCard(
            title: 'Set up host access',
            body:
                'Complete your organizer profile and payout setup here in the app so the hosting tools are ready when you need them.',
            icon: Icons.storefront_outlined,
            actionLabel: 'Start setup',
            onAction: () => _openHostAccess(context),
          )
        else if (events.isEmpty)
          EmptyStateCard(
            title: 'You have not created an event yet',
            body:
                'Start with a public event, a ticketed launch, or a private guest list. You can edit everything later.',
            icon: Icons.add_circle_outline,
            actionLabel: 'Create event',
            onAction: () => _openEditor(context),
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: EventCard(
                event: event,
                onTap: () => _openEvent(context, event),
                footer: _ManageFooter(
                  event: event,
                  ticketCount: repository.soldForEvent(event.id),
                  revenue: repository.revenueForEvent(event.id),
                  onView: () => _openEvent(context, event),
                  onEdit: () => _openEditor(context, existing: event),
                  onPromote: () => _openPromoter(context, event),
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

  void _openEditor(BuildContext context, {EventModel? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventEditorScreen(existingEvent: existing),
      ),
    );
  }

  Future<void> _openPromoter(BuildContext context, EventModel event) async {
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

  Future<void> _launchGeneralCampaign(
    BuildContext context,
    EventModel? event,
  ) async {
    if (event == null) {
      _openEditor(context);
      return;
    }
    await _openPromoter(context, event);
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Hosting starts with an account',
      body:
          'Create an Eventora account to build events, set ticket options, and share updates with guests.',
    );
  }

  void _openHostAccess(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HostAccessScreen()));
  }
}

class _ManageHero extends StatelessWidget {
  const _ManageHero({
    required this.organizerName,
    required this.totalRevenue,
    required this.isGuest,
    required this.organizerReady,
    required this.organizerStatusLabel,
  });

  final String organizerName;
  final double totalRevenue;
  final bool isGuest;
  final bool organizerReady;
  final String organizerStatusLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            palette.gold.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hosting hub',
            style: context.text.titleLarge?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Start hosting when you are ready.'
                : !organizerReady
                ? 'Finish your host access setup before you publish from the app.'
                : 'Everything you need to keep your events moving, $organizerName.',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'You can keep browsing as a guest. Sign in later to build an event page, sell tickets, and promote it.'
                : !organizerReady
                ? 'Current setup status: $organizerStatusLabel.'
                : 'You have tracked ${formatMoney(totalRevenue)} in ticket sales so far.',
            style: context.text.bodyLarge?.copyWith(color: palette.slate),
          ),
        ],
      ),
    );
  }
}

class _HostPlacementCard extends StatelessWidget {
  const _HostPlacementCard({
    required this.title,
    required this.body,
    required this.stat,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String stat;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.teal.withValues(alpha: 0.18),
                      palette.gold.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: palette.ink),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: context.text.titleLarge?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(body, style: context.text.bodyMedium),
              const SizedBox(height: 14),
              _FooterPill(label: stat),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageFooter extends StatelessWidget {
  const _ManageFooter({
    required this.event,
    required this.ticketCount,
    required this.revenue,
    required this.onView,
    required this.onEdit,
    required this.onPromote,
  });

  final EventModel event;
  final int ticketCount;
  final double revenue;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FooterPill(label: '$ticketCount sold'),
            _FooterPill(label: formatMoney(revenue)),
            _FooterPill(
              label: event.allowSharing ? 'Sharing on' : 'Sharing off',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(onPressed: onView, child: const Text('Preview')),
            OutlinedButton(
              onPressed: onEdit,
              child: const Text('Edit details'),
            ),
            ElevatedButton(onPressed: onPromote, child: const Text('Share it')),
          ],
        ),
      ],
    );
  }
}

class _FooterPill extends StatelessWidget {
  const _FooterPill({required this.label});

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
        style: context.text.bodyMedium?.copyWith(color: context.palette.ink),
      ),
    );
  }
}
