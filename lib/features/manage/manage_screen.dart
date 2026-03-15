import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/portal_links.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/event_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import '../events/event_detail_screen.dart';
import '../events/event_editor_screen.dart';
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _ManageHero(
          organizerName: session.isGuest ? 'Guest mode' : repository.currentUserName,
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
              label: 'Managed events',
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
              label: 'Gross revenue',
              value: formatMoney(totalRevenue),
              icon: Icons.payments_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Your event stack',
          subtitle: session.isGuest
              ? 'Sign in to start an organizer application, then continue in Eventora Studio for approval and dashboard access.'
              : organizerReady
              ? 'Edit scheduling, ticket tiers, visibility, reminders, and promotion settings from one place.'
              : 'Organizer access is now approval-driven. Open Eventora Studio to apply, submit documents, and wait for superadmin review.',
          actionLabel: session.isGuest
              ? 'Create account'
              : organizerReady
              ? 'Create event'
              : 'Open Studio',
          onAction: () => session.isGuest
              ? _promptForAccess(context)
              : organizerReady
              ? _openEditor(context)
              : _openOrganizerPortal(context),
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          EmptyStateCard(
            title: 'Organizer tools are waiting for you',
            body: 'Guest access keeps discovery open. Sign in when you are ready to create events, manage ticketing, and promote launches.',
            icon: Icons.lock_outline,
            actionLabel: 'Sign in',
            onAction: () => _promptForAccess(context),
          )
        else if (!organizerReady && viewer.hasPendingOrganizerApplication)
          EmptyStateCard(
            title: 'Organizer application is in review',
            body: 'Your Eventora Studio application has been submitted. A superadmin will review it before organizer tools, publishing, and campaigns are unlocked in the app.',
            icon: Icons.pending_actions_outlined,
            actionLabel: 'Open Studio',
            onAction: () => _openOrganizerPortal(context),
          )
        else if (!organizerReady &&
            viewer.organizerApplicationStatus ==
                OrganizerApplicationStatus.rejected)
          EmptyStateCard(
            title: 'Organizer application needs changes',
            body: 'Open Eventora Studio to update your application and resubmit it for review.',
            icon: Icons.feedback_outlined,
            actionLabel: 'Fix in Studio',
            onAction: () => _openOrganizerPortal(context),
          )
        else if (!organizerReady)
          EmptyStateCard(
            title: 'Apply for organizer access',
            body: 'Eventora Studio is the organizer-facing web app for onboarding, verification, payouts, and approval. Once you are approved, this mobile workspace unlocks automatically.',
            icon: Icons.storefront_outlined,
            actionLabel: 'Open Studio',
            onAction: () => _openOrganizerPortal(context),
          )
        else if (events.isEmpty)
          EmptyStateCard(
            title: 'Your organizer workspace is empty',
            body: 'Create your first event and start with either open RSVPs, ticketed checkout, or a private invite-only rollout.',
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
    final campaign = await showCampaignComposerSheet(context, initialEvent: event);
    if (campaign != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Campaign "${campaign.name}" created.')),
      );
    }
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Organizer access starts with an account',
      body: 'Create an Eventora account to manage events, ticket tiers, and promotion settings.',
    );
  }

  Future<void> _openOrganizerPortal(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(eventoraStudioUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Eventora Studio right now.')),
      );
    }
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
        color: Colors.white.withValues(alpha: 0.84),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Organizer control room', style: context.text.titleLarge?.copyWith(fontSize: 20)),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Browse first, then turn on your organizer workspace when you are ready.'
                : !organizerReady
                ? 'Organizer approval is required before publishing events from the app.'
                : 'Run your calendar like a product, $organizerName.',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Guest access keeps public events open without forcing signup.'
                : !organizerReady
                ? 'Current organizer status: $organizerStatusLabel.'
                : 'Ticket revenue tracked so far: ${formatMoney(totalRevenue)}.',
            style: context.text.bodyLarge?.copyWith(color: palette.slate),
          ),
        ],
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
            _FooterPill(label: '$ticketCount tickets'),
            _FooterPill(label: formatMoney(revenue)),
            _FooterPill(label: event.allowSharing ? 'Share-ready' : 'Sharing off'),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(onPressed: onView, child: const Text('View')),
            OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
            ElevatedButton(onPressed: onPromote, child: const Text('Promote')),
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
      child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.ink)),
    );
  }
}
