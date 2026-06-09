import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/art/event_art_widget.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../data/services/vennuzo_payment_service.dart';
import '../../data/services/event_safety_service.dart';
import '../../domain/models/creator_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import '../creators/creator_profile_screen.dart';
import 'event_share_sheet.dart';
import '../tickets/vennuzo_ticket_payment_status_screen.dart';
import '../social/event_posts_grid.dart';
import '../social/social_moderation_service.dart';
import '../social/social_service.dart';

enum EventDetailInitialAction { none, rsvp, checkout }

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.initialAction = EventDetailInitialAction.none,
  });

  final String eventId;
  final EventDetailInitialAction initialAction;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  static const _eventSafetyService = EventSafetyService();
  static final _socialModerationService = SocialModerationService();
  static final _socialService = SocialService();

  bool _handledInitialAction = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runInitialActionOnce();
  }

  void _runInitialActionOnce() {
    if (_handledInitialAction ||
        widget.initialAction == EventDetailInitialAction.none) {
      return;
    }
    _handledInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final event = context.read<VennuzoRepository>().eventById(widget.eventId);
      if (event == null) return;
      switch (widget.initialAction) {
        case EventDetailInitialAction.none:
          break;
        case EventDetailInitialAction.rsvp:
          _openRsvpFlow(context, event);
        case EventDetailInitialAction.checkout:
          _openCheckoutFlow(context, event);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final session = context.watch<VennuzoSessionController>();
    final event = repository.eventById(widget.eventId);

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
    final creatorProfile = repository.creatorProfileFor(event.createdBy);
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
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor.withValues(alpha: 0.96),
        foregroundColor: VennuzoTheme.textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: context.text.titleLarge?.copyWith(
          color: VennuzoTheme.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: const IconThemeData(color: VennuzoTheme.textPrimary),
        title: Text(event.title),
        actions: [
          if (!session.isGuest)
            StreamBuilder<bool>(
              stream: _socialService.isEventSaved(
                session.viewer.uid ?? '',
                widget.eventId,
              ),
              builder: (context, snapshot) {
                final saved = snapshot.data ?? false;
                return IconButton(
                  onPressed: () {
                    final uid = session.viewer.uid ?? '';
                    if (saved) {
                      _socialService.unsaveEvent(uid, event.id);
                    } else {
                      _socialService.saveEvent(uid, event.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Event saved.')),
                      );
                    }
                  },
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border_outlined,
                  ),
                  tooltip: saved ? 'Unsave event' : 'Save event',
                );
              },
            ),
          IconButton(
            onPressed: () => _showShareSheet(context, event),
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Share event',
          ),
          IconButton(
            onPressed: () => _showReportSheet(context, event, session),
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report event',
          ),
        ],
      ),
      bottomNavigationBar: _EventBottomBar(
        event: event,
        hasRsvp: hasRsvp,
        onReserve: hasRsvp ? null : () => _openRsvpFlow(context, event),
        onCheckout: event.ticketing.enabled
            ? () => _openCheckoutFlow(context, event)
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
        children: [
          _HeroBanner(event: event, campaign: premiumCampaign),
          const SizedBox(height: 28),
          _AboutEventCard(event: event),
          const SizedBox(height: 18),
          _CreatorProfileCard(
            profile: creatorProfile,
            isOwnProfile: session.viewer.uid == event.createdBy,
            isFollowing: repository.isFollowingCreator(event.createdBy),
            onOpen: () => _openCreatorProfile(context, event.createdBy),
            onFollow: () => _toggleFollowCreator(context, creatorProfile),
          ),
          const SizedBox(height: 18),
          _RatingRow(eventId: widget.eventId, socialService: _socialService),
          if (premiumCampaign != null) ...[
            const SizedBox(height: 28),
            _PremiumPlacementPanel(event: event, campaign: premiumCampaign),
          ],
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionPillButton(
                onPressed: () async {
                  if (session.isGuest) {
                    final authenticated = await showAuthPromptSheet(
                      context,
                      title: 'Sign in to like events',
                      body: 'Save the events you love.',
                    );
                    if (!context.mounted || !authenticated) {
                      return;
                    }
                  }
                  final nowLiked = context.read<VennuzoRepository>().toggleLike(
                    event.id,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        nowLiked
                            ? 'Added to your likes.'
                            : 'Removed from your likes.',
                      ),
                    ),
                  );
                },
                icon: repository.isEventLiked(event.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: repository.isEventLiked(event.id) ? 'Liked' : 'Like',
              ),
              _ActionPillButton(
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
                icon: Icons.notifications_active_outlined,
                label: reminder == null ? 'Remind me' : reminder.label,
              ),
              _ActionPillButton(
                onPressed: event.allowSharing
                    ? () => _showShareSheet(context, event)
                    : null,
                icon: Icons.link_outlined,
                label: event.allowSharing ? 'Share' : 'Sharing off',
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionHeading(title: 'Plan the night', subtitle: null),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
              border: Border.all(
                color: context.palette.border.withValues(alpha: 0.6),
              ),
              boxShadow: VennuzoTheme.shadowResting,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  icon: Icons.place_outlined,
                  title: 'Venue',
                  body: '${event.venue}, ${event.city}',
                ),
                const SizedBox(height: 18),
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  title: 'Date and time',
                  body: formatEventWindow(event.startDate, event.endDate),
                ),
                if (event.recurrence.isRecurring) ...[
                  const SizedBox(height: 18),
                  _DetailRow(
                    icon: Icons.repeat_outlined,
                    title: 'Recurrence',
                    body: event.recurrence.description,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (event.location != null) ...[
            SectionHeading(title: 'Location and directions', subtitle: null),
            const SizedBox(height: 14),
            _EventMapCard(
              event: event,
              onOpenDirections: () => _openDirections(event),
            ),
            const SizedBox(height: 28),
          ],
          SectionHeading(title: 'Lineup and hosting', subtitle: null),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
              border: Border.all(
                color: context.palette.border.withValues(alpha: 0.6),
              ),
              boxShadow: VennuzoTheme.shadowResting,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  icon: Icons.music_note_outlined,
                  title: 'Performers',
                  body: event.performers,
                ),
                const SizedBox(height: 18),
                _DetailRow(
                  icon: Icons.queue_music_outlined,
                  title: 'DJs',
                  body: event.djs,
                ),
                const SizedBox(height: 18),
                _DetailRow(
                  icon: Icons.record_voice_over_outlined,
                  title: 'Hosts and MCs',
                  body: event.mcs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
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
          const SizedBox(height: 28),
          SectionHeading(title: 'Guest settings', subtitle: null),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
              border: Border.all(
                color: context.palette.border.withValues(alpha: 0.6),
              ),
              boxShadow: VennuzoTheme.shadowResting,
            ),
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
          if (campaigns.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(title: 'Updates from the host', subtitle: null),
            const SizedBox(height: 14),
            ...campaigns.map(
              (campaign) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PromotionCard(campaign: campaign),
              ),
            ),
          ],
          const SizedBox(height: 28),
          SectionHeading(title: 'Photos from this event', subtitle: null),
          const SizedBox(height: 14),
          EventPostsGrid(
            eventId: widget.eventId,
            socialService: _socialService,
            moderationService: _socialModerationService,
            currentUserId: session.viewer.uid ?? '',
          ),
        ],
      ),
    );
  }

  void _openCreatorProfile(BuildContext context, String creatorId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreatorProfileScreen(creatorId: creatorId),
      ),
    );
  }

  Future<void> _toggleFollowCreator(
    BuildContext context,
    CreatorProfile profile,
  ) async {
    final session = context.read<VennuzoSessionController>();
    if (session.viewer.uid == profile.creatorId) {
      _openCreatorProfile(context, profile.creatorId);
      return;
    }
    if (session.isGuest) {
      final authenticated = await showAuthPromptSheet(
        context,
        title: 'Sign in to follow creators',
        body: 'Follow creators to see their new events on Explore.',
      );
      if (!context.mounted || !authenticated) {
        return;
      }
    }
    final repository = context.read<VennuzoRepository>();
    if (repository.isFollowingCreator(profile.creatorId)) {
      repository.unfollowCreator(profile.creatorId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unfollowed ${profile.displayName}.')),
      );
    } else {
      repository.followCreator(profile.creatorId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Following ${profile.displayName}.')),
      );
    }
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
    final repository = context.read<VennuzoRepository>();
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

    final session = context.read<VennuzoSessionController>();
    if (!session.viewer.notificationPrefs.pushEnabled && context.mounted) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Get reminders on your device'),
          content: const Text(
            'Enable push notifications to receive this reminder when it\'s time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (enable == true && context.mounted) {
        final pushActive = await session.updateNotificationPrefs(
          pushEnabled: true,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                pushActive
                    ? 'Push notifications enabled.'
                    : 'Allow notifications in Settings to get this reminder.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _showShareSheet(BuildContext context, EventModel event) async {
    await showEventShareSheet(context, event: event);
  }

  Future<void> _openRsvpFlow(BuildContext context, EventModel event) async {
    final session = context.read<VennuzoSessionController>();
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
    if (event.ticketing.isSoldOut) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This event is sold out.')));
      return;
    }
    final session = context.read<VennuzoSessionController>();
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
          builder: (_) => VennuzoTicketPaymentStatusScreen(
            orderId: result.order.id,
            initialOrder: result.order,
            checkoutUrl: result.checkoutUrl ?? '',
          ),
        ),
      );
      return;
    }

    final order = result.order;
    final link = context.read<VennuzoRepository>().buildPublicTicketLink(
      order.id,
    );
    final isComplimentary =
        order.paymentStatus == TicketPaymentStatus.complimentary;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            order.totalAmount == 0 && !isComplimentary
                ? 'Reservation created'
                : 'Tickets issued',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.totalAmount == 0 && !isComplimentary
                    ? 'Your reservation is saved and waiting for payment at the door.'
                    : isComplimentary
                    ? 'Your voucher covered the order and your tickets are ready to use at entry.'
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
    VennuzoSessionController session,
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

// ─── Floating Event CTA ──────────────────────────────────────────────────────

class _EventBottomBar extends StatelessWidget {
  const _EventBottomBar({
    required this.event,
    required this.hasRsvp,
    required this.onReserve,
    required this.onCheckout,
  });

  final EventModel event;
  final bool hasRsvp;
  final VoidCallback? onReserve;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final hasOptionalTickets =
        event.ticketing.enabled && !event.ticketing.requireTicket;
    final isSoldOut = event.ticketing.isSoldOut;
    final priceLabel = _priceLabel(event);
    final primaryLabel = isSoldOut
        ? 'Sold out'
        : event.ticketing.enabled
        ? event.ticketing.requireTicket
              ? 'Get tickets'
              : 'Buy ticket'
        : hasRsvp
        ? 'Reserved'
        : 'RSVP';
    final primaryAction = isSoldOut
        ? null
        : event.ticketing.enabled
        ? onCheckout
        : onReserve;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
              border: Border.all(color: VennuzoTheme.borderBright),
              boxShadow: VennuzoTheme.shadowFloating,
            ),
            padding: const EdgeInsets.all(6),
            child: hasOptionalTickets
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onReserve,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                VennuzoTheme.radiusFull,
                              ),
                            ),
                          ),
                          child: Text(hasRsvp ? 'Reserved' : 'RSVP'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FloatingCtaPill(
                          priceLabel: priceLabel,
                          actionLabel: primaryLabel,
                          compact: true,
                          onPressed: primaryAction,
                        ),
                      ),
                    ],
                  )
                : _FloatingCtaPill(
                    priceLabel: priceLabel,
                    actionLabel: primaryLabel,
                    onPressed: primaryAction,
                  ),
          ),
        ),
      ),
    );
  }

  String _priceLabel(EventModel event) {
    final minimumPrice = event.ticketing.minimumPrice;
    if (minimumPrice != null) {
      return 'From ${formatMoney(minimumPrice)}';
    }
    return event.ticketing.enabled ? 'Free entry' : 'Free RSVP';
  }
}

class _FloatingCtaPill extends StatelessWidget {
  const _FloatingCtaPill({
    required this.priceLabel,
    required this.actionLabel,
    required this.onPressed,
    this.compact = false,
  });

  final String priceLabel;
  final String actionLabel;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    const activeForeground = Color(0xFF031018);
    final foreground = disabled ? VennuzoTheme.textTertiary : activeForeground;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: '$priceLabel, $actionLabel',
      child: GestureDetector(
        onTap: onPressed,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
              color: disabled
                  ? VennuzoTheme.surfaceElevated
                  : VennuzoTheme.primaryStart,
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: VennuzoTheme.primaryStart.withValues(
                          alpha: 0.18,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!compact) ...[
                  Flexible(
                    child: Text(
                      priceLabel,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: foreground.withValues(alpha: disabled ? 0.2 : 0.28),
                  ),
                ],
                Flexible(
                  child: Text(
                    actionLabel,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: foreground,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── About Event Card ────────────────────────────────────────────────────────

class _AboutEventCard extends StatefulWidget {
  const _AboutEventCard({required this.event});

  final EventModel event;

  @override
  State<_AboutEventCard> createState() => _AboutEventCardState();
}

class _AboutEventCardState extends State<_AboutEventCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.6),
        ),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About this event', style: context.text.titleLarge),
          const SizedBox(height: 10),
          Text(
            event.description,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: context.text.bodyLarge,
          ),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? 'Show less' : 'Read more'),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: VennuzoTheme.primaryStart,
                  boxShadow: VennuzoTheme.shadowResting,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verified organizer',
                      style: context.text.titleSmall?.copyWith(
                        color: VennuzoTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Hosted on Vennuzo',
                      style: context.text.bodySmall?.copyWith(
                        color: VennuzoTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreatorProfileCard extends StatelessWidget {
  const _CreatorProfileCard({
    required this.profile,
    required this.isOwnProfile,
    required this.isFollowing,
    required this.onOpen,
    required this.onFollow,
  });

  final CreatorProfile profile;
  final bool isOwnProfile;
  final bool isFollowing;
  final VoidCallback onOpen;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.6),
        ),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: VennuzoTheme.primaryStart.withValues(
                  alpha: 0.12,
                ),
                foregroundImage:
                    profile.avatarUrl != null &&
                        profile.avatarUrl!.startsWith('http')
                    ? CachedNetworkImageProvider(profile.avatarUrl!)
                    : null,
                child:
                    profile.avatarUrl != null &&
                        !profile.avatarUrl!.startsWith('http')
                    ? null
                    : Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName.characters.first.toUpperCase()
                            : 'V',
                        style: context.text.titleLarge?.copyWith(
                          color: VennuzoTheme.primaryStart,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: context.text.titleMedium?.copyWith(
                        color: VennuzoTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${profile.followerCount} followers · ${profile.eventCount} events',
                      style: context.text.bodySmall?.copyWith(
                        color: VennuzoTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(profile.bio, style: context.text.bodyMedium),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('View creator'),
              ),
              if (!isOwnProfile)
                ElevatedButton.icon(
                  onPressed: onFollow,
                  icon: Icon(
                    isFollowing
                        ? Icons.check_circle_rounded
                        : Icons.person_add_alt_1_outlined,
                  ),
                  label: Text(isFollowing ? 'Following' : 'Follow'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Action Pill Button ──────────────────────────────────────────────────────

class _ActionPillButton extends StatelessWidget {
  const _ActionPillButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            border: Border.all(
              color: onPressed != null
                  ? context.palette.border
                  : context.palette.border.withValues(alpha: 0.4),
            ),
            color: context.palette.card,
            boxShadow: VennuzoTheme.shadowResting,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: onPressed != null
                    ? context.palette.slate
                    : context.palette.muted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  color: onPressed != null
                      ? context.palette.ink
                      : context.palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero Banner ─────────────────────────────────────────────────────────────

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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        border: Border.all(color: VennuzoTheme.borderSubtle),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        child: SizedBox(
          height: 280,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Generative art background
              EventArtwork(event: event, height: 280),
              // Deep cinematic scrim for text legibility
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.3, 0.65, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.38),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),
              // Campaign badge overlay with glass-morphism
              if (campaign?.channels.contains(PromotionChannel.announcement) ??
                  false)
                Positioned(
                  top: 16,
                  right: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            VennuzoTheme.radiusMd,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Spotlight',
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Content
              Positioned(
                left: 22,
                right: 22,
                bottom: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(
                          label: event.isPrivate
                              ? 'Invite only'
                              : 'Public event',
                        ),
                        if (event.ticketing.enabled)
                          _HeroPill(
                            label: event.ticketing.requireTicket
                                ? 'Ticket required'
                                : 'RSVP or optional ticket',
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      event.title,
                      style: context.text.headlineMedium?.copyWith(
                        color: Colors.white,
                        height: 1.05,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroMeta(label: '${event.venue}, ${event.city}'),
                        _HeroMeta(label: formatShortDate(event.startDate)),
                        _HeroMeta(label: priceLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 84,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.92),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Premium Placement Panel ─────────────────────────────────────────────────

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

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.palette.darkSurface,
            context.palette.darkSurfaceMid,
            context.palette.darkSurface.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: VennuzoTheme.shadowElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: VennuzoTheme.primaryMid.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: VennuzoTheme.primaryMid,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Vennuzo Spotlight',
                  style: context.text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: placementLabels
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        VennuzoTheme.radiusFull,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      label,
                      style: context.text.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'This event is currently in Vennuzo spotlight.',
            style: context.text.titleLarge?.copyWith(
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            campaign.message,
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DarkPill(label: 'Budget ${formatMoney(campaign.budget)}'),
              _DarkPill(label: '${event.likesCount} likes'),
              _DarkPill(label: '${event.rsvpCount} RSVPs'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Detail Row ──────────────────────────────────────────────────────────────

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
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: context.palette.teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
          ),
          child: Icon(icon, size: 20, color: context.palette.teal),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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

// ─── Tier Card ───────────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.currency});

  final TicketTier tier;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.6),
        ),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tier.name,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      VennuzoTheme.radiusFull,
                    ),
                  ),
                  child: Text(
                    tier.price == 0
                        ? 'Free'
                        : '$currency ${tier.price.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      color: context.palette.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (tier.description != null &&
              tier.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
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
    );
  }
}

// ─── Setting Pill ────────────────────────────────────────────────────────────

class _SettingPill extends StatelessWidget {
  const _SettingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.palette.canvas,
            context.palette.canvas.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.palette.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Promotion Card ──────────────────────────────────────────────────────────

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.campaign});

  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.6),
        ),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accent gradient strip
          Container(
            width: 4,
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [context.palette.teal, context.palette.coral],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.name,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(campaign.message, style: context.text.bodyMedium),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SettingPill(label: '${campaign.pushAudience} push'),
                      _SettingPill(label: '${campaign.smsAudience} SMS'),
                      _SettingPill(
                        label: formatPromoTime(campaign.scheduledAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Event Map Card ──────────────────────────────────────────────────────────

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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.6),
        ),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(VennuzoTheme.radiusLg - 1),
            ),
            child: SizedBox(
              height: 200,
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.venue,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(location.address, style: context.text.bodyMedium),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenDirections,
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Open directions'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          VennuzoTheme.radiusMd,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── RSVP Sheet ──────────────────────────────────────────────────────────────

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
    final repository = context.read<VennuzoRepository>();
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(VennuzoTheme.radiusXl),
        ),
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
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                      onPressed: _guestCount < 20
                          ? () => setState(() => _guestCount += 1)
                          : null,
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
                          .read<VennuzoRepository>()
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

// ─── Checkout Sheet ──────────────────────────────────────────────────────────

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.event});

  final EventModel event;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

// ── Step enum for the multi-step checkout sheet ──────────────────────────────
enum _CheckoutStep { tierSelect, buyerDetails }

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final Map<String, int> _selections;
  _CheckoutStep _step = _CheckoutStep.tierSelect;
  bool _submitting = false;
  String? _checkoutError;
  String? _appliedVoucherCode;

  // Buyer-details controllers — pre-filled in _initBuyerControllers()
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _voucherCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selections = {
      for (final tier in widget.event.ticketing.tiers) tier.tierId: 0,
    };
    _nameCtrl.addListener(_rebuildBuyerFooter);
    _emailCtrl.addListener(_rebuildBuyerFooter);
    _phoneCtrl.addListener(_rebuildBuyerFooter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-fill buyer fields from the signed-in viewer profile (once only).
    if (_nameCtrl.text.isEmpty) {
      final viewer = context.read<VennuzoSessionController>().viewer;
      final user = FirebaseAuth.instance.currentUser;
      _nameCtrl.text =
          (viewer.displayName.isNotEmpty ? viewer.displayName : null) ??
          user?.displayName ??
          '';
      _emailCtrl.text = viewer.email ?? user?.email ?? '';
      _phoneCtrl.text = viewer.phone ?? user?.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_rebuildBuyerFooter);
    _emailCtrl.removeListener(_rebuildBuyerFooter);
    _phoneCtrl.removeListener(_rebuildBuyerFooter);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _voucherCtrl.dispose();
    super.dispose();
  }

  void _rebuildBuyerFooter() {
    if (mounted && _step == _CheckoutStep.buyerDetails) {
      setState(() => _checkoutError = null);
    }
  }

  int get _ticketCount =>
      _selections.values.fold(0, (sum, value) => sum + value);

  double get _subtotal {
    var total = 0.0;
    for (final tier in widget.event.ticketing.tiers) {
      total += (_selections[tier.tierId] ?? 0) * tier.price;
    }
    return total;
  }

  EventDiscountVoucher? get _appliedVoucher {
    return widget.event.ticketing.voucherByCode(_appliedVoucherCode);
  }

  double get _discountAmount => _appliedVoucher?.discountFor(_subtotal) ?? 0;

  double get _total {
    return (_subtotal - _discountAmount).clamp(0, _subtotal).toDouble();
  }

  String? get _checkoutDiscountCode =>
      _discountAmount > 0 ? _appliedVoucher?.normalizedCode : null;

  void _applyVoucher() {
    final code = EventDiscountVoucher.normalizeCode(_voucherCtrl.text);
    if (code.isEmpty) {
      setState(() => _checkoutError = 'Enter a voucher code first.');
      return;
    }
    final voucher = widget.event.ticketing.voucherByCode(code);
    if (voucher == null) {
      setState(() => _checkoutError = 'That voucher code was not found.');
      return;
    }
    final discount = voucher.discountFor(_subtotal);
    if (discount <= 0) {
      setState(() {
        _appliedVoucherCode = null;
        _checkoutError = 'That voucher is not available for this order.';
      });
      return;
    }
    setState(() {
      _appliedVoucherCode = voucher.normalizedCode;
      _voucherCtrl.text = voucher.normalizedCode;
      _checkoutError = null;
    });
  }

  void _clearVoucher() {
    setState(() {
      _appliedVoucherCode = null;
      _voucherCtrl.clear();
      _checkoutError = null;
    });
  }

  void _advanceToBuyerDetails() {
    if (_ticketCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one ticket option.')),
      );
      return;
    }
    setState(() {
      _checkoutError = null;
      _step = _CheckoutStep.buyerDetails;
    });
  }

  Future<void> _submitPayment() async {
    if (_submitting) return;
    if (_step == _CheckoutStep.buyerDetails) {
      final validationError = _buyerDetailsError();
      if (validationError != null) {
        setState(() => _checkoutError = validationError);
        return;
      }
    }
    setState(() {
      _checkoutError = null;
      _submitting = true;
    });

    // Capture context-dependent objects before any await.
    final repository = context.read<VennuzoRepository>();
    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Free / offline path — no Hubtel
      if (_total <= 0 || !session.firebaseEnabled) {
        final order = repository.checkout(
          event: widget.event,
          selections: _selections,
          discountCode: _checkoutDiscountCode,
        );
        navigator.pop(_CheckoutResult.reservation(order));
        return;
      }

      final checkoutSession = await VennuzoPaymentService.startPaidCheckout(
        event: widget.event,
        selections: _selections,
        viewer: session.viewer,
        buyerNameOverride: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : null,
        buyerEmailOverride: _emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : null,
        buyerPhoneOverride: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        discountCode: _checkoutDiscountCode,
      );
      repository.upsertOrder(checkoutSession.order);
      if (!mounted) return;
      navigator.pop(
        _CheckoutResult.payment(
          checkoutSession.order,
          checkoutSession.checkoutUrl,
          checkoutSession.launched,
        ),
      );
    } on VennuzoPaymentException catch (error) {
      if (!mounted) return;
      setState(() => _checkoutError = error.message);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _checkoutError =
            error.message ?? 'Could not start Hubtel checkout.',
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not start Hubtel checkout.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      const message = 'Could not start checkout. Please try again.';
      setState(() => _checkoutError = message);
      messenger.showSnackBar(const SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _buyerDetailsError() {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.length < 2) {
      return 'Add the full name for this order.';
    }
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (!_isValidGhanaPhone(phone)) {
      return 'Enter a valid Ghana mobile money number.';
    }
    return null;
  }

  bool _isValidGhanaPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      return digits.length == 10;
    }
    if (digits.startsWith('233')) {
      return digits.length == 12;
    }
    return digits.length == 9;
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SizedBox(
      height: maxHeight,
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(VennuzoTheme.radiusXl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close checkout',
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _step == _CheckoutStep.tierSelect
                            ? _buildTierSelectStep(context)
                            : _buildBuyerDetailsStep(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildCheckoutFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Tier selection ─────────────────────────────────────────────────

  Widget _buildTierSelectStep(BuildContext context) {
    return Column(
      key: const ValueKey('tiers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step indicator
        _StepIndicator(current: 1, total: 2, label: 'Select tickets'),
        const SizedBox(height: 16),
        Text(
          'Pick the ticket types you want. Free options become pay-at-door reservations.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: 20),
        ...widget.event.ticketing.tiers.map(
          (tier) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(
                  color: context.palette.border.withValues(alpha: 0.6),
                ),
                boxShadow: VennuzoTheme.shadowResting,
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
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tier.price == 0
                                  ? 'Free or pay at door'
                                  : formatMoney(tier.price),
                              style: context.text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease ${tier.name} quantity',
                            onPressed: (_selections[tier.tierId] ?? 0) > 0
                                ? () => setState(
                                    () => _selections[tier.tierId] =
                                        (_selections[tier.tierId] ?? 0) - 1,
                                  )
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${_selections[tier.tierId] ?? 0}',
                            style: context.text.titleLarge,
                          ),
                          IconButton(
                            tooltip: 'Increase ${tier.name} quantity',
                            onPressed:
                                tier.soldOut ||
                                    (_selections[tier.tierId] ?? 0) >=
                                        tier.remaining
                                ? null
                                : () => setState(
                                    () => _selections[tier.tierId] =
                                        (_selections[tier.tierId] ?? 0) + 1,
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
                    Text(tier.description!, style: context.text.bodyMedium),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    '${tier.remaining} remaining',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.event.ticketing.discountVouchers.isNotEmpty) ...[
          _VoucherCodeBox(
            controller: _voucherCtrl,
            appliedCode: _appliedVoucher?.normalizedCode,
            discountAmount: _discountAmount,
            onApply: _applyVoucher,
            onClear: _clearVoucher,
          ),
          const SizedBox(height: 12),
        ],
        // Summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.palette.canvas,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text('Tickets: $_ticketCount', style: context.text.bodyLarge),
              const SizedBox(height: 4),
              Text(
                'Subtotal: ${formatMoney(_subtotal)}',
                style: context.text.bodyLarge,
              ),
              if (_discountAmount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Voucher: -${formatMoney(_discountAmount)}',
                  style: context.text.bodyLarge?.copyWith(
                    color: VennuzoTheme.primaryStart,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Total: ${formatMoney(_total)}',
                style: context.text.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: Buyer details ──────────────────────────────────────────────────

  Widget _buildBuyerDetailsStep(BuildContext context) {
    final palette = context.palette;
    return Column(
      key: const ValueKey('details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepIndicator(current: 2, total: 2, label: 'Your details'),
        const SizedBox(height: 16),
        // Order summary pill row
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.event.ticketing.tiers
                  .where((t) => (_selections[t.tierId] ?? 0) > 0)
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${t.name} × ${_selections[t.tierId]}',
                            style: context.text.bodyMedium,
                          ),
                          Text(
                            formatMoney(t.price * (_selections[t.tierId] ?? 0)),
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              const Divider(height: 16),
              if (_discountAmount > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _appliedVoucher?.normalizedCode ?? 'Voucher',
                      style: context.text.bodyMedium?.copyWith(
                        color: VennuzoTheme.primaryStart,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '-${formatMoney(_discountAmount)}',
                      style: context.text.bodyMedium?.copyWith(
                        color: VennuzoTheme.primaryStart,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: context.text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatMoney(_total),
                    style: context.text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Confirm the details for this order. Mobile money payments will use the phone number below.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: 18),
        _LabeledField(
          label: 'Full name',
          controller: _nameCtrl,
          keyboardType: TextInputType.name,
          hint: 'e.g. Kwame Mensah',
          autofocus: true,
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Email address',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          hint: 'you@example.com',
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Phone number',
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          hint: '+233 XX XXX XXXX',
          helperText: 'Used for mobile money and ticket delivery',
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCheckoutFooter(BuildContext context) {
    if (_step == _CheckoutStep.tierSelect) {
      final canContinue = _ticketCount > 0 && !_submitting;
      final isPaid = _total > 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_checkoutError != null) ...[
            _CheckoutErrorBanner(message: _checkoutError!),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: !canContinue
                  ? null
                  : isPaid
                  ? _advanceToBuyerDetails
                  : _submitPayment,
              child: Text(
                _ticketCount == 0
                    ? 'Select tickets'
                    : isPaid
                    ? 'Continue'
                    : _subtotal > 0
                    ? 'Claim discounted tickets'
                    : _submitting
                    ? 'Saving reservation...'
                    : 'Reserve (free / pay at door)',
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_checkoutError != null) ...[
          _CheckoutErrorBanner(message: _checkoutError!),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submitPayment,
            child: Text(
              _submitting ? 'Opening payment...' : 'Pay ${formatMoney(_total)}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() => _step = _CheckoutStep.tierSelect),
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }
}

class _CheckoutErrorBanner extends StatelessWidget {
  const _CheckoutErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
        border: Border.all(color: context.palette.coral.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: context.text.bodySmall?.copyWith(
          color: context.palette.coral,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VoucherCodeBox extends StatelessWidget {
  const _VoucherCodeBox({
    required this.controller,
    required this.appliedCode,
    required this.discountAmount,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController controller;
  final String? appliedCode;
  final double discountAmount;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasAppliedCode = appliedCode != null && discountAmount > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: hasAppliedCode
              ? VennuzoTheme.primaryStart.withValues(alpha: 0.28)
              : context.palette.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voucher code',
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Enter code',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (hasAppliedCode)
                TextButton(onPressed: onClear, child: const Text('Clear'))
              else
                ElevatedButton(onPressed: onApply, child: const Text('Apply')),
            ],
          ),
          if (hasAppliedCode) ...[
            const SizedBox(height: 10),
            Text(
              '$appliedCode applied: -${formatMoney(discountAmount)}',
              style: context.text.bodyMedium?.copyWith(
                color: VennuzoTheme.primaryStart,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Reusable helpers ──────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.palette.primaryStart,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$current',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: context.text.titleLarge)),
        Text('Step $current of $total', style: context.text.bodySmall),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.helperText,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final String? helperText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofocus: autofocus,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Checkout Result ─────────────────────────────────────────────────────────

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

// ─── Report Payload ──────────────────────────────────────────────────────────

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

// ─── Report Event Sheet ──────────────────────────────────────────────────────

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

  bool get _hasReportDetails => _detailsController.text.trim().length >= 8;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    _detailsController.addListener(_refreshDetailsState);
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  @override
  void dispose() {
    _detailsController.removeListener(_refreshDetailsState);
    _detailsController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _refreshDetailsState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(VennuzoTheme.radiusXl),
        ),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Report event',
                        style: context.text.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close report sheet',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us what feels wrong about "${widget.eventTitle}". Add a short detail so the safety team has something to review.',
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
                    helperText: 'Minimum 8 characters',
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
                    onPressed: _hasReportDetails
                        ? () {
                            Navigator.of(context).pop(
                              _EventReportPayload(
                                reason: _selectedReason,
                                details: _detailsController.text.trim(),
                                email: _emailController.text.trim(),
                              ),
                            );
                          }
                        : null,
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

// ─── Rating Row ──────────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.eventId, required this.socialService});

  final String eventId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: socialService.getAverageRating(eventId),
      builder: (context, snapshot) {
        final avg = snapshot.data ?? 0.0;
        final hasRatings = avg > 0;
        return StreamBuilder<int>(
          stream: socialService
              .getEventReviews(eventId)
              .map((list) => list.length),
          builder: (context, reviewSnap) {
            final count = reviewSnap.data ?? 0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
                border: Border.all(
                  color: context.palette.border.withValues(alpha: 0.6),
                ),
                boxShadow: VennuzoTheme.shadowResting,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        VennuzoTheme.radiusSm,
                      ),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFD700),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    hasRatings ? avg.toStringAsFixed(1) : 'No reviews yet',
                    style: context.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasRatings) ...[
                    const SizedBox(width: 6),
                    Text(
                      '($count review${count != 1 ? 's' : ''})',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.slate,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
