import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../data/services/eventora_payment_service.dart';
import '../../data/services/event_safety_service.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import 'event_share_sheet.dart';
import '../tickets/eventora_ticket_payment_status_screen.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;
  static const _eventSafetyService = EventSafetyService();

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final session = context.watch<EventoraSessionController>();
    final event = repository.eventById(eventId);

    if (event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: EmptyStateCard(
            title: 'Event not found',
            icon: Icons.event_busy_outlined,
          ),
        ),
      );
    }

    final reminder = repository.reminderFor(event.id);
    final hasRsvp = repository.hasRsvp(event.id);
    final campaigns = repository.campaignsForEvent(event.id);
    PromotionCampaign? premiumCampaign;
    for (final campaign in campaigns) {
      if (campaign.channels.contains(PromotionChannel.featured) ||
          campaign.channels.contains(PromotionChannel.announcement)) {
        premiumCampaign = campaign;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
          IconButton(
            onPressed: () => _showShareSheet(context, event),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            onPressed: () => _showReportSheet(context, event, session),
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report event',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!event.ticketing.requireTicket)
                SizedBox(
                  width: event.ticketing.enabled ? 150 : double.infinity,
                  child: OutlinedButton(
                    onPressed: hasRsvp
                        ? null
                        : () => _openRsvpFlow(context, event),
                    child: Text(hasRsvp ? 'Spot reserved' : 'Reserve spot'),
                  ),
                ),
              if (event.ticketing.enabled)
                SizedBox(
                  width: event.ticketing.requireTicket ? double.infinity : 190,
                  child: ElevatedButton(
                    onPressed: () => _openCheckoutFlow(context, event),
                    child: Text(
                      event.ticketing.requireTicket
                          ? 'Get tickets'
                          : 'Buy support ticket',
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: hasRsvp
                        ? null
                        : () => _openRsvpFlow(context, event),
                    child: Text(hasRsvp ? 'Spot reserved' : 'Reserve spot'),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _HeroBanner(event: event, campaign: premiumCampaign),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              MetricTile(
                label: 'Likes',
                value: '${event.likesCount}',
                icon: Icons.favorite_outline,
                highlight: context.palette.coral,
              ),
              MetricTile(
                label: 'RSVPs',
                value: '${event.rsvpCount}',
                icon: Icons.people_outline,
                highlight: context.palette.teal,
              ),
              MetricTile(
                label: 'Tickets sold',
                value: '${repository.soldForEvent(event.id)}',
                icon: Icons.confirmation_num_outlined,
                highlight: context.palette.gold,
              ),
            ],
          ),
          if (premiumCampaign != null) ...[
            const SizedBox(height: 20),
            _PremiumPlacementPanel(event: event, campaign: premiumCampaign),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  context.read<EventoraRepository>().toggleLike(event.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved to your events.')),
                  );
                },
                icon: const Icon(Icons.favorite_border),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (session.isGuest) {
                    final authenticated = await showAuthPromptSheet(
                      context,
                      title: 'Sign in for reminders',
                      body: 'Reminders need an account.',
                    );
                    if (!context.mounted || !authenticated) {
                      return;
                    }
                  }
                  _showReminderSheet(context, event, reminder);
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(reminder == null ? 'Remind me' : reminder.label),
              ),
              OutlinedButton.icon(
                onPressed: event.allowSharing
                    ? () => _showShareSheet(context, event)
                    : null,
                icon: const Icon(Icons.link_outlined),
                label: Text(event.allowSharing ? 'Share' : 'Sharing off'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionHeading(title: 'Why people are showing up', subtitle: null),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(event.description, style: context.text.bodyLarge),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeading(title: 'Plan the night', subtitle: null),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(
                    icon: Icons.place_outlined,
                    title: 'Venue',
                    body: '${event.venue}, ${event.city}',
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.schedule_outlined,
                    title: 'Date and time',
                    body: formatEventWindow(event.startDate, event.endDate),
                  ),
                  if (event.recurrence.isRecurring) ...[
                    const SizedBox(height: 16),
                    _DetailRow(
                      icon: Icons.repeat_outlined,
                      title: 'Recurrence',
                      body: event.recurrence.description,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (event.location != null) ...[
            SectionHeading(title: 'Location and directions', subtitle: null),
            const SizedBox(height: 14),
            _EventMapCard(
              event: event,
              onOpenDirections: () => _openDirections(event),
            ),
            const SizedBox(height: 24),
          ],
          SectionHeading(title: 'Lineup and hosting', subtitle: null),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(
                    icon: Icons.music_note_outlined,
                    title: 'Performers',
                    body: event.performers,
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.queue_music_outlined,
                    title: 'DJs',
                    body: event.djs,
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.record_voice_over_outlined,
                    title: 'Hosts and MCs',
                    body: event.mcs,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeading(title: 'Entry options', subtitle: null),
          const SizedBox(height: 14),
          if (!event.ticketing.enabled)
            const EmptyStateCard(
              title: 'No tickets required',
              icon: Icons.event_available_outlined,
            )
          else
            ...event.ticketing.tiers.map(
              (tier) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TierCard(
                  tier: tier,
                  currency: event.ticketing.currency,
                ),
              ),
            ),
          const SizedBox(height: 24),
          SectionHeading(title: 'Guest settings', subtitle: null),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SettingPill(
                    label: event.sendPushNotification
                        ? 'Push reminders available'
                        : 'No push reminders',
                  ),
                  _SettingPill(
                    label: event.sendSmsNotification
                        ? 'SMS updates available'
                        : 'No SMS updates',
                  ),
                  _SettingPill(
                    label: event.allowSharing
                        ? 'Sharing is on'
                        : 'Sharing is off',
                  ),
                  _SettingPill(
                    label: event.isPrivate
                        ? 'Invite-only event'
                        : 'Public listing',
                  ),
                ],
              ),
            ),
          ),
          if (campaigns.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionHeading(title: 'Updates from the host', subtitle: null),
            const SizedBox(height: 14),
            ...campaigns.map(
              (campaign) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PromotionCard(campaign: campaign),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showReminderSheet(
    BuildContext context,
    EventModel event,
    ReminderTiming? currentReminder,
  ) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('When should we remind you?', style: context.text.titleLarge),
            const SizedBox(height: 12),
            ...ReminderTiming.values.map(
              (timing) => ListTile(
                leading: Icon(
                  currentReminder == timing
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(timing.label),
                onTap: () => Navigator.of(context).pop(timing),
              ),
            ),
            if (currentReminder != null)
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Turn reminder off'),
                onTap: () => Navigator.of(context).pop('clear'),
              ),
            const SizedBox(height: 12),
          ],
        );
      },
    );

    if (!context.mounted) return;
    final repository = context.read<EventoraRepository>();
    if (result == null) {
      return;
    }
    if (result == 'clear') {
      repository.clearReminder(event.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder removed.')));
      return;
    }
    if (result is! ReminderTiming) return;

    repository.setReminder(event.id, result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder set for ${result.label.toLowerCase()}.'),
      ),
    );
  }

  Future<void> _showShareSheet(BuildContext context, EventModel event) async {
    await showEventShareSheet(context, event: event);
  }

  Future<void> _openRsvpFlow(BuildContext context, EventModel event) async {
    final session = context.read<EventoraSessionController>();
    if (session.isGuest) {
      final authenticated = await showAuthPromptSheet(
        context,
        title: 'Sign in to save your RSVP',
        body: 'RSVPs need an account.',
      );
      if (!context.mounted || !authenticated) {
        return;
      }
    }

    final record = await showModalBottomSheet<RsvpRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RsvpSheet(event: event),
    );

    if (record != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your spot is saved for ${record.eventTitle}.')),
      );
    }
  }

  Future<void> _openCheckoutFlow(BuildContext context, EventModel event) async {
    final session = context.read<EventoraSessionController>();
    if (session.isGuest) {
      final authenticated = await showAuthPromptSheet(
        context,
        title: 'Sign in for checkout',
        body: 'Checkout needs an account.',
      );
      if (!context.mounted || !authenticated) {
        return;
      }
    }

    final result = await showModalBottomSheet<_CheckoutResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CheckoutSheet(event: event),
    );

    if (result == null || !context.mounted) return;

    if (result.opensPaymentStatus) {
      if (!result.launchSucceeded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hubtel did not open automatically. Use the payment status screen to reopen checkout.',
            ),
          ),
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventoraTicketPaymentStatusScreen(
            orderId: result.order.id,
            initialOrder: result.order,
            checkoutUrl: result.checkoutUrl ?? '',
          ),
        ),
      );
      return;
    }

    final order = result.order;
    final link = context.read<EventoraRepository>().buildPublicTicketLink(
      order.id,
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            order.totalAmount == 0 ? 'Reservation created' : 'Tickets issued',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.totalAmount == 0
                    ? 'Your reservation is saved and waiting for payment at the door.'
                    : 'Your order is paid and ready to use at entry.',
              ),
              const SizedBox(height: 12),
              Text('Order link', style: context.text.bodyMedium),
              const SizedBox(height: 6),
              Text(link, style: context.text.bodyLarge),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copy link'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showReportSheet(
    BuildContext context,
    EventModel event,
    EventoraSessionController session,
  ) async {
    final report = await showModalBottomSheet<_EventReportPayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportEventSheet(
        eventTitle: event.title,
        email: session.viewer.email,
      ),
    );

    if (report == null || !context.mounted) {
      return;
    }

    try {
      await _eventSafetyService.reportEvent(
        eventId: event.id,
        eventTitle: event.title,
        reason: report.reason,
        details: report.details,
        reporterUid: session.viewer.uid,
        reporterEmail: report.email,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks. Your report has been sent.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not send your report right now.'),
        ),
      );
    }
  }

  Future<void> _openDirections(EventModel event) async {
    final location = event.location;
    if (location == null) {
      return;
    }

    final mapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}',
    );
    await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.event, this.campaign});

  final EventModel event;
  final PromotionCampaign? campaign;

  @override
  Widget build(BuildContext context) {
    final minPrice = event.ticketing.minimumPrice;
    final priceLabel = minPrice == null
        ? 'Free entry'
        : 'From ${formatMoney(minPrice)}';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            context.palette.primaryStart,
            event.mood.colors.first.withValues(alpha: 0.92),
            context.palette.primaryEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: context.palette.primaryStart.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -32,
            right: -10,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroPill(
                    label: event.isPrivate ? 'Invite only' : 'Public event',
                  ),
                  if (event.ticketing.enabled)
                    _HeroPill(
                      label: event.ticketing.requireTicket
                          ? 'Ticket required'
                          : 'RSVP or optional ticket',
                    ),
                  if (campaign?.channels.contains(
                        PromotionChannel.announcement,
                      ) ??
                      false)
                    const _HeroPill(label: 'Live spotlight'),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                event.title,
                style: context.text.headlineMedium?.copyWith(
                  color: Colors.white,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                event.description,
                style: context.text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroMeta(label: '${event.venue}, ${event.city}'),
                  _HeroMeta(label: formatShortDate(event.startDate)),
                  _HeroMeta(label: priceLabel),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                formatEventWindow(event.startDate, event.endDate),
                style: context.text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PremiumPlacementPanel extends StatelessWidget {
  const _PremiumPlacementPanel({required this.event, required this.campaign});

  final EventModel event;
  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final placementLabels = <String>[
      if (campaign.channels.contains(PromotionChannel.featured))
        'Featured banner',
      if (campaign.channels.contains(PromotionChannel.announcement))
        'Fullscreen announcement',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: placementLabels
                  .map((label) => _SettingPill(label: label))
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text(
              'This event is currently in Eventora spotlight.',
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(campaign.message, style: context.text.bodyLarge),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SettingPill(label: 'Budget ${formatMoney(campaign.budget)}'),
                _SettingPill(label: '${event.likesCount} likes'),
                _SettingPill(label: '${event.rsvpCount} RSVPs'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final resolvedBody = body.trim().isEmpty ? 'To be announced.' : body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.palette.slate),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.text.titleLarge?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(resolvedBody, style: context.text.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.currency});

  final TicketTier tier;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tier.name,
                    style: context.text.titleLarge?.copyWith(fontSize: 21),
                  ),
                ),
                Text(
                  tier.price == 0
                      ? 'Free'
                      : '$currency ${tier.price.toStringAsFixed(2)}',
                  style: context.text.titleLarge?.copyWith(fontSize: 18),
                ),
              ],
            ),
            if (tier.description != null &&
                tier.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tier.description!, style: context.text.bodyMedium),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SettingPill(label: '${tier.sold} sold'),
                _SettingPill(label: '${tier.remaining} remaining'),
                if (tier.soldOut) _SettingPill(label: 'Sold out'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingPill extends StatelessWidget {
  const _SettingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.campaign});

  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              campaign.name,
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(campaign.message, style: context.text.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SettingPill(label: '${campaign.pushAudience} push'),
                _SettingPill(label: '${campaign.smsAudience} SMS'),
                _SettingPill(label: formatPromoTime(campaign.scheduledAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventMapCard extends StatelessWidget {
  const _EventMapCard({required this.event, required this.onOpenDirections});

  final EventModel event;
  final Future<void> Function() onOpenDirections;

  @override
  Widget build(BuildContext context) {
    final location = event.location;
    if (location == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: gmaps.GoogleMap(
                  initialCameraPosition: gmaps.CameraPosition(
                    target: gmaps.LatLng(location.latitude, location.longitude),
                    zoom: 15,
                  ),
                  markers: {
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('event_location'),
                      position: gmaps.LatLng(
                        location.latitude,
                        location.longitude,
                      ),
                      infoWindow: gmaps.InfoWindow(
                        title: event.venue,
                        snippet: event.city,
                      ),
                    ),
                  },
                  liteModeEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  myLocationButtonEnabled: false,
                  scrollGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              event.venue,
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(location.address, style: context.text.bodyMedium),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenDirections,
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Open directions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RsvpSheet extends StatefulWidget {
  const _RsvpSheet({required this.event});

  final EventModel event;

  @override
  State<_RsvpSheet> createState() => _RsvpSheetState();
}

class _RsvpSheetState extends State<_RsvpSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  int _guestCount = 1;
  bool _bookTable = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<EventoraRepository>();
    _nameController = TextEditingController(text: repository.currentUserName);
    _phoneController = TextEditingController(text: repository.currentUserPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Reserve your spot', style: context.text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Add your details so the host knows you are coming and can send event updates if needed.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 18),
                Text(
                  'Guest count',
                  style: context.text.titleLarge?.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: _guestCount > 1
                          ? () => setState(() => _guestCount -= 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$_guestCount', style: context.text.headlineSmall),
                    IconButton(
                      onPressed: () => setState(() => _guestCount += 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _bookTable,
                  onChanged: (value) => setState(() => _bookTable = value),
                  title: const Text('Book a table'),
                  subtitle: const Text(
                    'Use this when the event offers table reservations.',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = _nameController.text.trim();
                      final phone = _phoneController.text.trim();
                      if (name.isEmpty || phone.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Add your name and phone number.'),
                          ),
                        );
                        return;
                      }
                      final record = context
                          .read<EventoraRepository>()
                          .createRsvp(
                            eventId: widget.event.id,
                            eventTitle: widget.event.title,
                            name: name,
                            phone: phone,
                            guestCount: _guestCount,
                            bookTable: _bookTable,
                          );
                      Navigator.of(context).pop(record);
                    },
                    child: const Text('Save my RSVP'),
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

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.event});

  final EventModel event;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final Map<String, int> _selections;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selections = {
      for (final tier in widget.event.ticketing.tiers) tier.tierId: 0,
    };
  }

  int get _ticketCount =>
      _selections.values.fold(0, (sum, value) => sum + value);

  double get _total {
    var total = 0.0;
    for (final tier in widget.event.ticketing.tiers) {
      total += (_selections[tier.tierId] ?? 0) * tier.price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Checkout', style: context.text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Pick the ticket types you want. Free options become pay-at-door reservations.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: 20),
                ...widget.event.ticketing.tiers.map(
                  (tier) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0x1410212A)),
                      ),
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
                                      tier.name,
                                      style: context.text.titleLarge?.copyWith(
                                        fontSize: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      tier.price == 0
                                          ? 'Free or pay at door'
                                          : formatMoney(tier.price),
                                      style: context.text.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed:
                                        (_selections[tier.tierId] ?? 0) > 0
                                        ? () => setState(
                                            () => _selections[tier.tierId] =
                                                (_selections[tier.tierId] ??
                                                    0) -
                                                1,
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text(
                                    '${_selections[tier.tierId] ?? 0}',
                                    style: context.text.titleLarge,
                                  ),
                                  IconButton(
                                    onPressed:
                                        tier.soldOut ||
                                            (_selections[tier.tierId] ?? 0) >=
                                                tier.remaining
                                        ? null
                                        : () => setState(
                                            () => _selections[tier.tierId] =
                                                (_selections[tier.tierId] ??
                                                    0) +
                                                1,
                                          ),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (tier.description != null &&
                              tier.description!.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              tier.description!,
                              style: context.text.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            '${tier.remaining} remaining',
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.palette.canvas,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: context.text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tickets: $_ticketCount',
                        style: context.text.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total: ${formatMoney(_total)}',
                        style: context.text.bodyLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting
                        ? null
                        : () async {
                            if (_ticketCount == 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Choose at least one ticket option.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setState(() => _submitting = true);
                            try {
                              final repository = context
                                  .read<EventoraRepository>();
                              final session = context
                                  .read<EventoraSessionController>();

                              if (_total <= 0 || !session.firebaseEnabled) {
                                final order = repository.checkout(
                                  event: widget.event,
                                  selections: _selections,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                Navigator.of(
                                  context,
                                ).pop(_CheckoutResult.reservation(order));
                                return;
                              }

                              final checkoutSession =
                                  await EventoraPaymentService.startPaidCheckout(
                                    event: widget.event,
                                    selections: _selections,
                                    viewer: session.viewer,
                                  );
                              repository.upsertOrder(checkoutSession.order);
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.of(context).pop(
                                _CheckoutResult.payment(
                                  checkoutSession.order,
                                  checkoutSession.checkoutUrl,
                                  checkoutSession.launched,
                                ),
                              );
                            } on EventoraPaymentException catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            } on FirebaseFunctionsException catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error.message ??
                                        'Could not start Hubtel checkout.',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _submitting = false);
                              }
                            }
                          },
                    child: Text(
                      _submitting
                          ? 'Getting checkout ready...'
                          : _total == 0
                          ? 'Reserve now'
                          : 'Pay ${formatMoney(_total)}',
                    ),
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

class _CheckoutResult {
  const _CheckoutResult({
    required this.order,
    required this.opensPaymentStatus,
    required this.launchSucceeded,
    this.checkoutUrl,
  });

  factory _CheckoutResult.reservation(TicketOrder order) {
    return _CheckoutResult(
      order: order,
      opensPaymentStatus: false,
      launchSucceeded: true,
    );
  }

  factory _CheckoutResult.payment(
    TicketOrder order,
    String checkoutUrl,
    bool launchSucceeded,
  ) {
    return _CheckoutResult(
      order: order,
      opensPaymentStatus: true,
      launchSucceeded: launchSucceeded,
      checkoutUrl: checkoutUrl,
    );
  }

  final TicketOrder order;
  final bool opensPaymentStatus;
  final bool launchSucceeded;
  final String? checkoutUrl;
}

class _EventReportPayload {
  const _EventReportPayload({
    required this.reason,
    required this.details,
    required this.email,
  });

  final String reason;
  final String details;
  final String? email;
}

class _ReportEventSheet extends StatefulWidget {
  const _ReportEventSheet({required this.eventTitle, required this.email});

  final String eventTitle;
  final String? email;

  @override
  State<_ReportEventSheet> createState() => _ReportEventSheetState();
}

class _ReportEventSheetState extends State<_ReportEventSheet> {
  static const _reasons = [
    'Spam or scam',
    'Harassment or abuse',
    'False event information',
    'Hate or violent content',
    'Other safety concern',
  ];

  late final TextEditingController _detailsController;
  late final TextEditingController _emailController;
  String _selectedReason = _reasons.first;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Report event', style: context.text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Tell us what feels wrong about "${widget.eventTitle}".',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: _reasons
                      .map(
                        (reason) => DropdownMenuItem<String>(
                          value: reason,
                          child: Text(reason),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _selectedReason = value ?? _selectedReason,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _detailsController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Details',
                    hintText:
                        'Share any details that would help our team review this event.',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Contact email (optional)',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _EventReportPayload(
                          reason: _selectedReason,
                          details: _detailsController.text.trim(),
                          email: _emailController.text.trim(),
                        ),
                      );
                    },
                    child: const Text('Submit report'),
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
