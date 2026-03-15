import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/eventora_cloud_sync_service.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';
import '../mock/mock_seed.dart';

class EventoraRepository extends ChangeNotifier {
  EventoraRepository._({
    required List<EventModel> events,
    required List<TicketOrder> orders,
    required List<RsvpRecord> rsvps,
    required List<PromotionCampaign> campaigns,
    required EventoraCloudSyncService cloudSync,
  }) : _events = events,
       _orders = orders,
       _rsvps = rsvps,
       _campaigns = campaigns,
       _cloudSync = cloudSync {
    if (_cloudSync.isEnabled) {
      _bindEventStreams();
    }
  }

  factory EventoraRepository.seeded({required bool firebaseEnabled}) {
    return EventoraRepository._(
      events: MockSeed.events(),
      orders: MockSeed.orders(),
      rsvps: MockSeed.rsvps(),
      campaigns: MockSeed.campaigns(),
      cloudSync: EventoraCloudSyncService(firebaseEnabled: firebaseEnabled),
    );
  }

  final List<EventModel> _events;
  final List<TicketOrder> _orders;
  final List<RsvpRecord> _rsvps;
  final List<PromotionCampaign> _campaigns;
  final EventoraCloudSyncService _cloudSync;
  final List<EventModel> _livePublicEvents = <EventModel>[];
  final List<EventModel> _liveWorkspaceEvents = <EventModel>[];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _publicEventsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _workspaceEventsSubscription;
  EventoraViewer _viewer = const EventoraViewer.guest();
  final Map<String, ReminderTiming> _reminders = {
    'event_after_dark': ReminderTiming.oneDayBefore,
  };

  List<EventModel> get _effectiveEvents {
    final merged = <String, EventModel>{
      for (final event in _events) event.id: event,
    };
    for (final event in _livePublicEvents) {
      merged[event.id] = event;
    }
    for (final event in _liveWorkspaceEvents) {
      merged[event.id] = event;
    }
    return merged.values.toList();
  }

  String get currentUserId => _viewer.uid ?? '';
  String get currentUserName => _viewer.displayName;
  String get currentUserPhone => _viewer.phone ?? '';
  String get currentUserEmail => _viewer.email ?? '';
  bool get isGuest => _viewer.isGuest;

  void applyViewer(EventoraViewer viewer) {
    if (_viewer.uid == viewer.uid &&
        _viewer.displayName == viewer.displayName &&
        _viewer.email == viewer.email &&
        _viewer.phone == viewer.phone &&
        _viewer.isAuthenticated == viewer.isAuthenticated &&
        _viewer.activeFace == viewer.activeFace &&
      _viewer.organizerApplicationStatus == viewer.organizerApplicationStatus &&
      _viewer.organizerReviewNotes == viewer.organizerReviewNotes &&
      listEquals(_viewer.roles, viewer.roles)) {
      return;
    }

    _viewer = viewer;
    if (viewer.isAuthenticated && viewer.hasOrganizerAccess) {
      unawaited(_cloudSync.ensureOrganizerWorkspace(viewer));
    }
    if (_cloudSync.isEnabled) {
      _bindEventStreams();
    }
    notifyListeners();
  }

  List<EventModel> get discoverableEvents =>
      _effectiveEvents.where((event) => !event.isPrivate).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  List<EventModel> get managedEvents {
    if (isGuest || !_viewer.hasOrganizerAccess) {
      return const [];
    }
    return _managedEffectiveEvents;
  }

  List<EventModel> get _managedEffectiveEvents {
    return _effectiveEvents
        .where(
          (event) =>
              event.createdBy == MockSeed.organizerId ||
              (currentUserId.isNotEmpty && event.createdBy == currentUserId),
        )
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<EventModel> get adminVisibleEvents {
    if (isGuest) {
      return const [];
    }
    if (_viewer.hasAdminAccess) {
      return _effectiveEvents.toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
    }
    return _managedEffectiveEvents;
  }

  List<TicketOrder> get orders {
    if (isGuest) {
      return const [];
    }
    return _orders.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<TicketOrder> get adminVisibleOrders => orders;

  List<RsvpRecord> get rsvps {
    if (isGuest) {
      return const [];
    }
    return _rsvps.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<RsvpRecord> get adminVisibleRsvps => rsvps;

  List<PromotionCampaign> get campaigns {
    if (isGuest) {
      return const [];
    }
    return _campaigns.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<PromotionCampaign> get adminVisibleCampaigns => campaigns;

  int get totalAdmittedTickets => _orders.fold<int>(
    0,
    (total, order) =>
        total +
        order.tickets
            .where((ticket) => ticket.status == TicketStatus.admitted)
            .length,
  );

  int get openGateTicketCount => _orders.fold<int>(
    0,
    (total, order) =>
        total +
        order.tickets
            .where((ticket) => ticket.status != TicketStatus.admitted)
            .length,
  );

  int get totalRsvps => _rsvps.length;

  double get grossRevenue => _orders
      .where((order) => order.status == TicketOrderStatus.paid)
      .fold<double>(0, (total, order) => total + order.totalAmount);

  int get liveCampaignCount => _campaigns
      .where((campaign) => campaign.status == PromotionStatus.live)
      .length;

  int get scheduledCampaignCount => _campaigns
      .where((campaign) => campaign.status == PromotionStatus.scheduled)
      .length;

  List<RsvpRecord> rsvpsForEvent(String eventId) =>
      _rsvps.where((rsvp) => rsvp.eventId == eventId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<TicketOrder> ordersForEvent(String eventId) =>
      _orders.where((order) => order.eventId == eventId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  TicketOrder? orderById(String orderId) {
    for (final order in _orders) {
      if (order.id == orderId) {
        return order;
      }
    }
    return null;
  }

  List<EventTicket> outstandingTicketsForEvent(String eventId) {
    return [
      for (final order in ordersForEvent(eventId))
        for (final ticket in order.tickets)
          if (ticket.status != TicketStatus.admitted) ticket,
    ];
  }

  EventModel? eventById(String id) {
    for (final event in _effectiveEvents) {
      if (event.id == id) return event;
    }
    return null;
  }

  ReminderTiming? reminderFor(String eventId) => _reminders[eventId];

  String buildShareLink(String eventId) => 'https://eventora.app/e/$eventId';

  String buildPublicTicketLink(String orderId) =>
      'https://eventora.app/ticket/$orderId';

  bool hasRsvp(String eventId) {
    if (isGuest) {
      return false;
    }
    return _rsvps.any((rsvp) => rsvp.eventId == eventId);
  }

  List<PromotionCampaign> campaignsForEvent(String eventId) =>
      _campaigns.where((campaign) => campaign.eventId == eventId).toList();

  int pushAudienceFor(String eventId) {
    final event = eventById(eventId);
    if (event == null) return 0;
    return 700 + (event.likesCount * 6) + (event.rsvpCount * 3);
  }

  int smsAudienceFor(String eventId) {
    final event = eventById(eventId);
    if (event == null) return 0;
    return 120 + (event.rsvpCount * 2) + soldForEvent(eventId);
  }

  int soldForEvent(String eventId) {
    return _orders
        .where(
          (order) =>
              order.eventId == eventId &&
              order.status == TicketOrderStatus.paid,
        )
        .fold<int>(0, (total, order) => total + order.ticketCount);
  }

  double revenueForEvent(String eventId) {
    return _orders
        .where(
          (order) =>
              order.eventId == eventId &&
              order.status == TicketOrderStatus.paid,
        )
        .fold<double>(0, (total, order) => total + order.totalAmount);
  }

  void setReminder(String eventId, ReminderTiming timing) {
    _reminders[eventId] = timing;
    final event = eventById(eventId);
    if (event != null && _viewer.isAuthenticated) {
      unawaited(() async {
        await _cloudSync.upsertEvent(
          event: event,
          viewer: _viewer,
          grossRevenue: revenueForEvent(event.id),
        );
        await _cloudSync.saveReminder(
          event: event,
          viewer: _viewer,
          timing: timing,
        );
      }());
    }
    notifyListeners();
  }

  void clearReminder(String eventId) {
    _reminders.remove(eventId);
    if (_viewer.isAuthenticated) {
      unawaited(_cloudSync.clearReminder(eventId: eventId, viewer: _viewer));
    }
    notifyListeners();
  }

  void toggleLike(String eventId) {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index == -1) return;
    final event = _events[index];
    _events[index] = event.copyWith(likesCount: event.likesCount + 1);
    notifyListeners();
  }

  void createEvent(EventDraft draft) {
    if (isGuest || currentUserId.isEmpty || !_viewer.hasOrganizerAccess) {
      return;
    }
    final event = EventModel(
      id: _generateId('event'),
      title: draft.title,
      description: draft.description,
      venue: draft.venue,
      city: draft.city,
      startDate: draft.startDate,
      endDate: draft.endDate,
      visibility: draft.visibility,
      createdBy: currentUserId,
      createdAt: DateTime.now(),
      ticketing: draft.ticketing,
      recurrence: draft.recurrence,
      sendPushNotification: draft.sendPushNotification,
      sendSmsNotification: draft.sendSmsNotification,
      allowSharing: draft.allowSharing,
      djs: draft.djs,
      mcs: draft.mcs,
      performers: draft.performers,
      likesCount: 0,
      rsvpCount: 0,
      mood: draft.mood,
      tags: draft.tags,
    );
    _events.add(event);
    unawaited(
      _cloudSync.upsertEvent(
        event: event,
        viewer: _viewer,
        grossRevenue: revenueForEvent(event.id),
      ),
    );
    notifyListeners();
  }

  void updateEvent(String eventId, EventDraft draft) {
    if (!_viewer.hasOrganizerAccess) {
      return;
    }
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index == -1) return;
    final updated = _events[index].copyWith(
      title: draft.title,
      description: draft.description,
      venue: draft.venue,
      city: draft.city,
      startDate: draft.startDate,
      endDate: draft.endDate,
      visibility: draft.visibility,
      ticketing: draft.ticketing,
      recurrence: draft.recurrence,
      sendPushNotification: draft.sendPushNotification,
      sendSmsNotification: draft.sendSmsNotification,
      allowSharing: draft.allowSharing,
      djs: draft.djs,
      mcs: draft.mcs,
      performers: draft.performers,
      mood: draft.mood,
      tags: draft.tags,
    );
    _events[index] = updated;
    if (_viewer.isAuthenticated) {
      unawaited(
        _cloudSync.upsertEvent(
          event: updated,
          viewer: _viewer,
          grossRevenue: revenueForEvent(updated.id),
        ),
      );
    }
    notifyListeners();
  }

  RsvpRecord createRsvp({
    required String eventId,
    required String eventTitle,
    required String name,
    required String phone,
    required int guestCount,
    required bool bookTable,
  }) {
    if (isGuest) {
      throw StateError('Guests need an account before saving RSVPs.');
    }
    final record = RsvpRecord(
      id: _generateId('rsvp'),
      eventId: eventId,
      eventTitle: eventTitle,
      name: name,
      phone: phone,
      guestCount: guestCount,
      bookTable: bookTable,
      createdAt: DateTime.now(),
    );
    _rsvps.add(record);
    _mutateEvent(
      eventId,
      (event) => event.copyWith(rsvpCount: event.rsvpCount + 1),
    );
    final event = eventById(eventId);
    if (event != null) {
      unawaited(() async {
        await _cloudSync.upsertEvent(
          event: event,
          viewer: _viewer,
          grossRevenue: revenueForEvent(event.id),
        );
        await _cloudSync.upsertRsvp(
          event: event,
          record: record,
          viewer: _viewer,
        );
      }());
    }
    notifyListeners();
    return record;
  }

  TicketOrder checkout({
    required EventModel event,
    required Map<String, int> selections,
  }) {
    if (isGuest) {
      throw StateError('Guests need an account before checking out.');
    }
    final chosenSelections = <TicketSelection>[];
    final tickets = <EventTicket>[];
    final now = DateTime.now();
    double total = 0;

    var updatedTiers = event.ticketing.tiers;
    for (final tier in event.ticketing.tiers) {
      final quantity = selections[tier.tierId] ?? 0;
      if (quantity <= 0) continue;
      chosenSelections.add(
        TicketSelection(
          tierId: tier.tierId,
          name: tier.name,
          price: tier.price,
          quantity: quantity,
        ),
      );
      total += tier.price * quantity;
      updatedTiers = updatedTiers
          .map(
            (value) => value.tierId == tier.tierId
                ? value.copyWith(sold: value.sold + quantity)
                : value,
          )
          .toList();
    }

    final orderId = _generateId('order');
    var ticketNumber = 1;
    final unpaidReservation = total == 0;
    for (final selection in chosenSelections) {
      for (var index = 0; index < selection.quantity; index++) {
        tickets.add(
          EventTicket(
            ticketId: '${orderId}_${selection.tierId}_$ticketNumber',
            orderId: orderId,
            eventId: event.id,
            tierId: selection.tierId,
            tierName: selection.name,
            qrToken: _generateId('qr'),
            status: unpaidReservation
                ? TicketStatus.unpaid
                : TicketStatus.issued,
            attendeeName: currentUserName,
            price: selection.price,
            issuedAt: now,
          ),
        );
        ticketNumber += 1;
      }
    }

    final order = TicketOrder(
      id: orderId,
      eventId: event.id,
      eventTitle: event.title,
      buyerName: currentUserName,
      buyerPhone: currentUserPhone,
      buyerEmail: currentUserEmail,
      selectedTiers: chosenSelections,
      totalAmount: total,
      status: unpaidReservation
          ? TicketOrderStatus.reserved
          : TicketOrderStatus.paid,
      paymentStatus: unpaidReservation
          ? TicketPaymentStatus.cashAtGate
          : TicketPaymentStatus.paid,
      source: 'app',
      createdAt: now,
      updatedAt: now,
      tickets: tickets,
    );

    _orders.add(order);
    _mutateEvent(
      event.id,
      (current) => current.copyWith(
        ticketing: current.ticketing.copyWith(tiers: updatedTiers),
      ),
    );
    final updatedEvent = eventById(event.id) ?? event;
    unawaited(() async {
      await _cloudSync.upsertEvent(
        event: updatedEvent,
        viewer: _viewer,
        grossRevenue: revenueForEvent(updatedEvent.id),
      );
      await _cloudSync.upsertOrder(
        event: updatedEvent,
        order: order,
        viewer: _viewer,
      );
    }());
    notifyListeners();
    return order;
  }

  void admitTicket(String orderId, String ticketId) {
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    if (orderIndex == -1) return;
    final order = _orders[orderIndex];
    final updatedTickets = order.tickets
        .map(
          (ticket) => ticket.ticketId == ticketId
              ? ticket.copyWith(
                  status: TicketStatus.admitted,
                  admittedAt: DateTime.now(),
                )
              : ticket,
        )
        .toList();
    _orders[orderIndex] = order.copyWith(
      tickets: updatedTickets,
      updatedAt: DateTime.now(),
      paymentStatus: order.paymentStatus == TicketPaymentStatus.cashAtGate
          ? TicketPaymentStatus.cashAtGatePaid
          : order.paymentStatus,
      status: TicketOrderStatus.paid,
    );
    final updatedOrder = _orders[orderIndex];
    final updatedTicket = updatedTickets.firstWhere(
      (ticket) => ticket.ticketId == ticketId,
    );
    unawaited(
      _cloudSync.admitTicket(order: updatedOrder, ticket: updatedTicket),
    );
    notifyListeners();
  }

  void upsertOrder(TicketOrder order) {
    final index = _orders.indexWhere((existing) => existing.id == order.id);
    if (index == -1) {
      _orders.add(order);
    } else {
      _orders[index] = order;
    }
    notifyListeners();
  }

  PromotionCampaign scheduleCampaign({
    required EventModel event,
    required String name,
    required DateTime? scheduledAt,
    required List<PromotionChannel> channels,
    required double budget,
    required String message,
  }) {
    if (!_viewer.hasOrganizerAccess && !_viewer.hasAdminAccess) {
      throw StateError(
        'Organizer or admin access is required before launching campaigns.',
      );
    }
    final campaign = PromotionCampaign(
      id: _generateId('promo'),
      eventId: event.id,
      eventTitle: event.title,
      name: name,
      status: scheduledAt == null
          ? PromotionStatus.live
          : PromotionStatus.scheduled,
      channels: channels,
      scheduledAt: scheduledAt,
      pushAudience: channels.contains(PromotionChannel.push)
          ? pushAudienceFor(event.id)
          : 0,
      smsAudience: channels.contains(PromotionChannel.sms)
          ? smsAudienceFor(event.id)
          : 0,
      shareLinkEnabled: channels.contains(PromotionChannel.shareLink),
      budget: budget,
      message: message,
      createdAt: DateTime.now(),
    );
    _campaigns.add(campaign);
    unawaited(() async {
      await _cloudSync.upsertEvent(
        event: event,
        viewer: _viewer,
        grossRevenue: revenueForEvent(event.id),
      );
      await _cloudSync.launchCampaign(
        campaign: campaign,
        event: event,
        viewer: _viewer,
      );
    }());
    notifyListeners();
    return campaign;
  }

  void _mutateEvent(
    String eventId,
    EventModel Function(EventModel event) mapper,
  ) {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index == -1) return;
    _events[index] = mapper(_events[index]);
  }

  String _generateId(String prefix) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999).toString().padLeft(5, '0');
    return '${prefix}_${now}_$random';
  }

  void _bindEventStreams() {
    _publicEventsSubscription?.cancel();
    _workspaceEventsSubscription?.cancel();
    _livePublicEvents.clear();
    _liveWorkspaceEvents.clear();

    final firestore = FirebaseFirestore.instance;
    _publicEventsSubscription = firestore
        .collection('events')
        .where('visibility', isEqualTo: 'public')
        .snapshots()
        .listen((snapshot) {
          _livePublicEvents
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => _eventFromFirestore(doc))
                  .whereType<EventModel>(),
            );
          notifyListeners();
        });

    if (_viewer.hasAdminAccess) {
      _workspaceEventsSubscription = firestore
          .collection('events')
          .snapshots()
          .listen((snapshot) {
            _liveWorkspaceEvents
              ..clear()
              ..addAll(
                snapshot.docs
                    .map((doc) => _eventFromFirestore(doc))
                    .whereType<EventModel>(),
              );
            notifyListeners();
          });
      return;
    }

    final organizationId = _viewer.defaultOrganizationId?.trim();
    if (_viewer.hasOrganizerAccess &&
        organizationId != null &&
        organizationId.isNotEmpty) {
      _workspaceEventsSubscription = firestore
          .collection('events')
          .where('organizationId', isEqualTo: organizationId)
          .snapshots()
          .listen((snapshot) {
            _liveWorkspaceEvents
              ..clear()
              ..addAll(
                snapshot.docs
                    .map((doc) => _eventFromFirestore(doc))
                    .whereType<EventModel>(),
              );
            notifyListeners();
          });
    }
  }

  EventModel? _eventFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final ticketing = data['ticketing'];
    final tiers = ticketing is Map && ticketing['tiers'] is Iterable
        ? (ticketing['tiers'] as Iterable)
              .whereType<Map>()
              .map(
                (tier) => TicketTier(
                  tierId: '${tier['tierId'] ?? ''}'.trim(),
                  name: '${tier['name'] ?? 'General'}',
                  price: (tier['price'] as num?)?.toDouble() ?? 0,
                  maxQuantity: (tier['maxQuantity'] as num?)?.toInt() ?? 0,
                  sold: (tier['sold'] as num?)?.toInt() ?? 0,
                  description: (tier['description'] as String?)?.trim(),
                ),
              )
              .toList()
        : const <TicketTier>[];
    final recurrence = data['recurrence'];
    final lineup = data['lineup'];
    final metrics = data['metrics'];
    final distribution = data['distribution'];

    return EventModel(
      id: doc.id,
      title: '${data['title'] ?? 'Event'}',
      description: '${data['description'] ?? ''}',
      venue: '${data['venue'] ?? data['addressText'] ?? 'Venue TBA'}',
      city: '${data['city'] ?? 'Accra'}',
      startDate: _dateFromValue(data['startAt']) ?? DateTime.now(),
      endDate: _dateFromValue(data['endAt']),
      visibility: '${data['visibility'] ?? 'public'}' == 'private'
          ? EventVisibility.privateEvent
          : EventVisibility.publicEvent,
      createdBy: '${data['createdBy'] ?? ''}',
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
      ticketing: EventTicketing(
        enabled: ticketing is Map ? ticketing['enabled'] != false : false,
        requireTicket:
            ticketing is Map ? ticketing['requireTicket'] == true : false,
        currency: ticketing is Map
            ? '${ticketing['currency'] ?? 'GHS'}'
            : 'GHS',
        tiers: tiers,
      ),
      recurrence: RecurrenceRule(
        frequency: _recurrenceFrequencyFromValue(
          recurrence is Map ? recurrence['frequency'] : null,
        ),
        interval: recurrence is Map
            ? (recurrence['interval'] as num?)?.toInt() ?? 1
            : 1,
        endType: _recurrenceEndTypeFromValue(
          recurrence is Map ? recurrence['endType'] : null,
        ),
        endDate: _dateFromValue(
          recurrence is Map ? recurrence['endDate'] : null,
        ),
        endAfterOccurrences: recurrence is Map
            ? (recurrence['endAfterOccurrences'] as num?)?.toInt()
            : null,
      ),
      sendPushNotification: distribution is Map
          ? distribution['sendPushNotification'] != false
          : true,
      sendSmsNotification: distribution is Map
          ? distribution['sendSmsNotification'] != false
          : true,
      allowSharing: distribution is Map
          ? distribution['allowSharing'] != false
          : true,
      djs: lineup is Map ? '${lineup['djs'] ?? ''}' : '',
      mcs: lineup is Map ? '${lineup['mcs'] ?? ''}' : '',
      performers: lineup is Map ? '${lineup['performers'] ?? ''}' : '',
      likesCount: metrics is Map
          ? (metrics['likesCount'] as num?)?.toInt() ?? 0
          : 0,
      rsvpCount: metrics is Map
          ? (metrics['rsvpCount'] as num?)?.toInt() ?? 0
          : 0,
      mood: _eventMoodFromValue(data['mood']),
      tags: (data['tags'] as Iterable?)
              ?.map((value) => '$value')
              .where((value) => value.trim().isNotEmpty)
              .toList() ??
          const <String>[],
    );
  }

  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  RecurrenceFrequency _recurrenceFrequencyFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'daily' => RecurrenceFrequency.daily,
      'weekly' => RecurrenceFrequency.weekly,
      'monthly' => RecurrenceFrequency.monthly,
      _ => RecurrenceFrequency.none,
    };
  }

  RecurrenceEndType _recurrenceEndTypeFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'ondate' => RecurrenceEndType.onDate,
      'afteroccurrences' => RecurrenceEndType.afterOccurrences,
      _ => RecurrenceEndType.never,
    };
  }

  EventMood _eventMoodFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'sunrise' => EventMood.sunrise,
      'electric' => EventMood.electric,
      'garden' => EventMood.garden,
      _ => EventMood.night,
    };
  }

  @override
  void dispose() {
    _publicEventsSubscription?.cancel();
    _workspaceEventsSubscription?.cancel();
    super.dispose();
  }
}
