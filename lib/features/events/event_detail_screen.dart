import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

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
            body:
                'This event may have been removed or is no longer available in the local workspace.',
            icon: Icons.event_busy_outlined,
          ),
        ),
      );
    }

    final reminder = repository.reminderFor(event.id);
    final hasRsvp = repository.hasRsvp(event.id);
    final campaigns = repository.campaignsForEvent(event.id);

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
                    child: Text(hasRsvp ? 'RSVP saved' : 'RSVP'),
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
                          : 'Support with ticket',
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
                    child: Text(hasRsvp ? 'RSVP saved' : 'RSVP to event'),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _HeroBanner(event: event),
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
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  context.read<EventoraRepository>().toggleLike(event.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Added to your saved events.'),
                    ),
                  );
                },
                icon: const Icon(Icons.favorite_border),
                label: const Text('Like'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  if (session.isGuest) {
                    showAuthPromptSheet(
                      context,
                      title: 'Reminders need an account',
                      body:
                          'Sign in to save event reminders and keep them attached to your Eventora profile.',
                    );
                    return;
                  }
                  _showReminderSheet(context, event, reminder);
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(reminder == null ? 'Set reminder' : reminder.label),
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
          SectionHeading(
            title: 'About',
            subtitle: 'Everything your attendees need to know.',
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(event.description, style: context.text.bodyLarge),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeading(title: 'Schedule & Venue'),
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
          SectionHeading(title: 'Lineup & Hosting'),
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
          SectionHeading(
            title: 'Tickets & Entry',
            subtitle: event.ticketing.enabled
                ? (event.ticketing.requireTicket
                      ? 'This event requires a ticket to enter.'
                      : 'This event supports both RSVPs and optional tickets.')
                : 'This event uses RSVP flow only.',
          ),
          const SizedBox(height: 14),
          if (!event.ticketing.enabled)
            const EmptyStateCard(
              title: 'No ticketing enabled',
              body:
                  'This event can still collect RSVPs and reminder opt-ins even without paid checkout.',
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
          SectionHeading(title: 'Distribution settings'),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SettingPill(
                    label: event.sendPushNotification ? 'Push on' : 'Push off',
                  ),
                  _SettingPill(
                    label: event.sendSmsNotification ? 'SMS on' : 'SMS off',
                  ),
                  _SettingPill(
                    label: event.allowSharing
                        ? 'Share links on'
                        : 'Share links off',
                  ),
                  _SettingPill(
                    label: event.isPrivate
                        ? 'Private visibility'
                        : 'Public visibility',
                  ),
                ],
              ),
            ),
          ),
          if (campaigns.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionHeading(
              title: 'Promotion history',
              subtitle:
                  'This event already has campaign activity attached to it.',
            ),
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
            Text('Choose reminder timing', style: context.text.titleLarge),
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
                title: const Text('Remove reminder'),
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
    final repository = context.read<EventoraRepository>();
    final shareLink = repository.buildShareLink(event.id);

    final copied = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share event', style: context.text.titleLarge),
              const SizedBox(height: 10),
              Text(
                event.allowSharing
                    ? 'This share link can route guests into your event detail and ticket flow.'
                    : 'Sharing is disabled for this event.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.palette.canvas,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(shareLink, style: context.text.bodyLarge),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: event.allowSharing
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: shareLink),
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
                        }
                      : null,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy share link'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (context.mounted && copied == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Share link copied.')));
    }
  }

  Future<void> _openRsvpFlow(BuildContext context, EventModel event) async {
    final session = context.read<EventoraSessionController>();
    if (session.isGuest) {
      await showAuthPromptSheet(
        context,
        title: 'RSVPs need an account',
        body:
            'Create an Eventora account to save your RSVP, guest count, and table requests.',
      );
      return;
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
        SnackBar(content: Text('RSVP saved for ${record.eventTitle}.')),
      );
    }
  }

  Future<void> _openCheckoutFlow(BuildContext context, EventModel event) async {
    final session = context.read<EventoraSessionController>();
    if (session.isGuest) {
      await showAuthPromptSheet(
        context,
        title: 'Ticket checkout starts after sign-in',
        body:
            'Sign in to reserve tickets, pay at the gate, and keep order links in your Eventora wallet.',
      );
      return;
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
                    ? 'Your order is reserved for payment at the gate.'
                    : 'Your order is marked paid and ready for entry.',
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
        const SnackBar(content: Text('Thanks. The report was submitted.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not submit the report right now.'),
        ),
      );
    }
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: event.mood.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(
                label: event.isPrivate ? 'Private event' : 'Public event',
              ),
              if (event.ticketing.enabled)
                _HeroPill(
                  label: event.ticketing.requireTicket
                      ? 'Ticket required'
                      : 'Optional ticket',
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            event.title,
            style: context.text.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            '${event.venue}, ${event.city}',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatEventWindow(event.startDate, event.endDate),
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
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
              Text(body, style: context.text.bodyMedium),
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RSVP to ${widget.event.title}',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'RSVPs can also feed your future SMS audience and reminder flow.',
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
                  child: const Text('Confirm RSVP'),
                ),
              ),
            ],
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Checkout', style: context.text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Choose ticket tiers. Free reservations become pay-at-gate holds.',
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
                                        ? 'Free / at gate'
                                        : formatMoney(tier.price),
                                    style: context.text.bodyLarge,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: (_selections[tier.tierId] ?? 0) > 0
                                      ? () => setState(
                                          () => _selections[tier.tierId] =
                                              (_selections[tier.tierId] ?? 0) -
                                              1,
                                        )
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
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
                                              (_selections[tier.tierId] ?? 0) +
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
                                  'Select at least one ticket tier.',
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
                        ? 'Starting checkout...'
                        : _total == 0
                        ? 'Reserve tickets'
                        : 'Pay ${formatMoney(_total)}',
                  ),
                ),
              ),
            ],
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Report event', style: context.text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tell us what looks wrong about "${widget.eventTitle}".',
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
                onChanged: (value) =>
                    setState(() => _selectedReason = value ?? _selectedReason),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _detailsController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText:
                      'Share any context that would help a moderator review this event.',
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
    );
  }
}
