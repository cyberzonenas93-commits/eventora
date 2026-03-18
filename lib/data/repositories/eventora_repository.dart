import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/eventora_cloud_sync_service.dart';
import '../services/eventora_payment_service.dart';
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
  final List<TicketOrder> _liveOrders = <TicketOrder>[];
  final List<RsvpRecord> _liveRsvps = <RsvpRecord>[];
  final List<PromotionCampaign> _liveCampaigns = <PromotionCampaign>[];
  final Map<String, ReminderTiming> _liveReminders = <String, ReminderTiming>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _publicEventsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _workspaceEventsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rsvpsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _campaignsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _remindersSubscription;
  EventoraViewer _viewer = const EventoraViewer.guest();
  final Map<String, ReminderTiming> _reminders = {
    'event_after_dark': ReminderTiming.oneDayBefore,
  };
  bool _ordersHydrated = false;
  bool _rsvpsHydrated = false;
  bool _campaignsHydrated = false;
  bool _remindersHydrated = false;

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
        _viewer.organizerApplicationStatus ==
            viewer.organizerApplicationStatus &&
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
      _bindCommerceStreams();
    }
    notifyListeners();
  }

  List<EventModel> get discoverableEvents =>
      _effectiveEvents.where((event) => !event.isPrivate).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  List<EventModel> nearbyEvents({
    required double latitude,
    required double longitude,
    double radiusKm = 25,
    int limit = 8,
  }) {
    final matches =
        discoverableEvents.where((event) {
          final distance = distanceKmForEvent(
            event,
            latitude: latitude,
            longitude: longitude,
          );
          return distance != null && distance <= radiusKm;
        }).toList()..sort((a, b) {
          final aDistance =
              distanceKmForEvent(a, latitude: latitude, longitude: longitude) ??
              double.infinity;
          final bDistance =
              distanceKmForEvent(b, latitude: latitude, longitude: longitude) ??
              double.infinity;
          final compareDistance = aDistance.compareTo(bDistance);
          if (compareDistance != 0) {
            return compareDistance;
          }
          return a.startDate.compareTo(b.startDate);
        });
    return matches.take(limit).toList();
  }

  double? distanceKmForEvent(
    EventModel event, {
    required double latitude,
    required double longitude,
  }) {
    final location = event.location;
    if (location == null) {
      return null;
    }
    return _distanceKm(
      latitude,
      longitude,
      location.latitude,
      location.longitude,
    );
  }

  List<PromotionCampaign> get featuredCampaigns {
    return _campaigns
        .where(
          (campaign) =>
              campaign.status == PromotionStatus.live &&
              campaign.channels.contains(PromotionChannel.featured) &&
              !(eventById(campaign.eventId)?.isPrivate ?? true),
        )
        .toList()
      ..sort((a, b) {
        final aEvent = eventById(a.eventId);
        final bEvent = eventById(b.eventId);
        if (aEvent == null || bEvent == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        return aEvent.startDate.compareTo(bEvent.startDate);
      });
  }

  List<PromotionCampaign> get announcementCampaigns {
    return _campaigns
        .where(
          (campaign) =>
              campaign.status == PromotionStatus.live &&
              campaign.channels.contains(PromotionChannel.announcement) &&
              !(eventById(campaign.eventId)?.isPrivate ?? true),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  PromotionCampaign? get primaryAnnouncementCampaign {
    final campaigns = announcementCampaigns;
    return campaigns.isEmpty ? null : campaigns.first;
  }

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
    final visibleOrders = _shouldUseLiveOrders
        ? _liveOrders.toList()
        : _visibleOrders();
    return visibleOrders..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<TicketOrder> get adminVisibleOrders => orders;

  List<RsvpRecord> get rsvps {
    if (isGuest) {
      return const [];
    }
    final visibleRsvps = _shouldUseLiveRsvps
        ? _liveRsvps.toList()
        : _visibleRsvps();
    return visibleRsvps..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<RsvpRecord> get adminVisibleRsvps => rsvps;

  List<PromotionCampaign> get campaigns {
    if (isGuest) {
      return const [];
    }
    return (_shouldUseLiveCampaigns
          ? _liveCampaigns.toList()
          : _visibleCampaigns().toList())
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
      rsvps.where((rsvp) => rsvp.eventId == eventId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<TicketOrder> ordersForEvent(String eventId) =>
      orders.where((order) => order.eventId == eventId).toList()
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

  ReminderTiming? reminderFor(String eventId) {
    if (_shouldUseLiveReminders) {
      return _liveReminders[eventId];
    }
    return _reminders[eventId];
  }

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
      campaigns.where((campaign) => campaign.eventId == eventId).toList();

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
      location: draft.location,
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
      location: draft.location,
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
      attendeeUserId: currentUserId,
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
      buyerUserId: currentUserId,
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
      createdByUserId: currentUserId,
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

  List<TicketOrder> _visibleOrders() {
    if (_viewer.hasAdminAccess) {
      return _orders.toList();
    }

    if (_viewer.hasOrganizerAccess) {
      final managedEventIds = _managedEffectiveEvents
          .map((event) => event.id)
          .toSet();
      return _orders
          .where((order) => managedEventIds.contains(order.eventId))
          .toList();
    }

    final email = currentUserEmail.trim().toLowerCase();
    final phone = currentUserPhone.trim();
    final name = currentUserName.trim().toLowerCase();
    return _orders.where((order) {
      final buyerUserId = order.buyerUserId?.trim();
      if (buyerUserId != null &&
          buyerUserId.isNotEmpty &&
          buyerUserId == currentUserId) {
        return true;
      }
      if (email.isNotEmpty && order.buyerEmail.trim().toLowerCase() == email) {
        return true;
      }
      if (phone.isNotEmpty && order.buyerPhone.trim() == phone) {
        return true;
      }
      return name.isNotEmpty && order.buyerName.trim().toLowerCase() == name;
    }).toList();
  }

  List<RsvpRecord> _visibleRsvps() {
    if (_viewer.hasAdminAccess) {
      return _rsvps.toList();
    }

    if (_viewer.hasOrganizerAccess) {
      final managedEventIds = _managedEffectiveEvents
          .map((event) => event.id)
          .toSet();
      return _rsvps
          .where((rsvp) => managedEventIds.contains(rsvp.eventId))
          .toList();
    }

    final phone = currentUserPhone.trim();
    final name = currentUserName.trim().toLowerCase();
    return _rsvps.where((rsvp) {
      final attendeeUserId = rsvp.attendeeUserId?.trim();
      if (attendeeUserId != null &&
          attendeeUserId.isNotEmpty &&
          attendeeUserId == currentUserId) {
        return true;
      }
      if (phone.isNotEmpty && rsvp.phone.trim() == phone) {
        return true;
      }
      return name.isNotEmpty && rsvp.name.trim().toLowerCase() == name;
    }).toList();
  }

  List<PromotionCampaign> _visibleCampaigns() {
    if (_viewer.hasAdminAccess) {
      return _campaigns.toList();
    }

    if (_viewer.hasOrganizerAccess) {
      final currentUid = currentUserId.trim();
      final ownedCampaigns = currentUid.isEmpty
          ? const <PromotionCampaign>[]
          : _campaigns
                .where(
                  (campaign) => campaign.createdByUserId?.trim() == currentUid,
                )
                .toList();
      if (ownedCampaigns.isNotEmpty) {
        return ownedCampaigns;
      }
      final managedEventIds = _managedEffectiveEvents
          .map((event) => event.id)
          .toSet();
      return _campaigns
          .where((campaign) => managedEventIds.contains(campaign.eventId))
          .toList();
    }

    return const <PromotionCampaign>[];
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

  void _bindCommerceStreams() {
    _ordersSubscription?.cancel();
    _rsvpsSubscription?.cancel();
    _campaignsSubscription?.cancel();
    _remindersSubscription?.cancel();
    _liveOrders.clear();
    _liveRsvps.clear();
    _liveCampaigns.clear();
    _liveReminders.clear();
    _ordersHydrated = false;
    _rsvpsHydrated = false;
    _campaignsHydrated = false;
    _remindersHydrated = false;

    if (!_viewer.isAuthenticated || _viewer.uid == null) {
      notifyListeners();
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final uid = _viewer.uid!;
    final organizationId = _viewer.defaultOrganizationId?.trim();

    Query<Map<String, dynamic>>? ordersQuery;
    Query<Map<String, dynamic>>? rsvpsQuery;
    Query<Map<String, dynamic>>? campaignsQuery;
    Query<Map<String, dynamic>> remindersQuery = firestore
        .collection('event_reminders')
        .where('userId', isEqualTo: uid);

    if (_viewer.hasAdminAccess) {
      ordersQuery = firestore.collection('event_ticket_orders');
      rsvpsQuery = firestore.collection('event_rsvps');
      campaignsQuery = firestore.collection('promotion_campaigns');
    } else if (organizationId != null &&
        organizationId.isNotEmpty &&
        _viewer.hasOrganizerAccess) {
      ordersQuery = firestore
          .collection('event_ticket_orders')
          .where('organizationId', isEqualTo: organizationId);
      rsvpsQuery = firestore
          .collection('event_rsvps')
          .where('organizationId', isEqualTo: organizationId);
      campaignsQuery = firestore
          .collection('promotion_campaigns')
          .where('organizationId', isEqualTo: organizationId);
    } else {
      ordersQuery = firestore
          .collection('event_ticket_orders')
          .where('buyerId', isEqualTo: uid);
      rsvpsQuery = firestore
          .collection('event_rsvps')
          .where('userId', isEqualTo: uid);
    }

    _ordersSubscription = ordersQuery.snapshots().listen((snapshot) {
      _ordersHydrated = true;
      _liveOrders
        ..clear()
        ..addAll(
          snapshot.docs
              .map(EventoraPaymentService.orderFromDocument)
              .whereType<TicketOrder>(),
        );
      notifyListeners();
    });

    _rsvpsSubscription = rsvpsQuery.snapshots().listen((snapshot) {
      _rsvpsHydrated = true;
      _liveRsvps
        ..clear()
        ..addAll(
          snapshot.docs
              .map((doc) => _rsvpFromFirestore(doc))
              .whereType<RsvpRecord>(),
        );
      notifyListeners();
    });

    if (campaignsQuery != null) {
      _campaignsSubscription = campaignsQuery.snapshots().listen((snapshot) {
        _campaignsHydrated = true;
        _liveCampaigns
          ..clear()
          ..addAll(
            snapshot.docs
                .map((doc) => _campaignFromFirestore(doc))
                .whereType<PromotionCampaign>(),
          );
        notifyListeners();
      });
    } else {
      _campaignsHydrated = true;
    }

    _remindersSubscription = remindersQuery.snapshots().listen((snapshot) {
      _remindersHydrated = true;
      _liveReminders
        ..clear()
        ..addEntries(
          snapshot.docs
              .map(
                (doc) => MapEntry(
                  '${doc.data()['eventId'] ?? ''}'.trim(),
                  _reminderTimingFromValue(doc.data()['timing']),
                ),
              )
              .where((entry) => entry.key.isNotEmpty),
        );
      notifyListeners();
    });
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
    final rawLocation = data['location'];
    final latitude = _latitudeFromValue(rawLocation, data['latitude']);
    final longitude = _longitudeFromValue(rawLocation, data['longitude']);
    final addressText = '${data['addressText'] ?? ''}'.trim();
    final placeId = '${data['placeId'] ?? ''}'.trim();

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
        requireTicket: ticketing is Map
            ? ticketing['requireTicket'] == true
            : false,
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
      tags:
          (data['tags'] as Iterable?)
              ?.map((value) => '$value')
              .where((value) => value.trim().isNotEmpty)
              .toList() ??
          const <String>[],
      location: latitude == null || longitude == null
          ? null
          : EventLocation(
              address: addressText.isEmpty
                  ? '${data['venue'] ?? 'Venue TBA'}, ${data['city'] ?? 'Accra'}'
                  : addressText,
              latitude: latitude,
              longitude: longitude,
              placeId: placeId.isEmpty ? null : placeId,
            ),
    );
  }

  RsvpRecord? _rsvpFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    return RsvpRecord(
      id: doc.id,
      eventId: '${data['eventId'] ?? ''}'.trim(),
      eventTitle: '${data['eventTitle'] ?? ''}'.trim(),
      attendeeUserId: '${data['userId'] ?? ''}'.trim().isEmpty
          ? null
          : '${data['userId'] ?? ''}'.trim(),
      name: '${data['name'] ?? ''}'.trim(),
      phone: '${data['phone'] ?? ''}'.trim(),
      guestCount: (data['guestCount'] as num?)?.toInt() ?? 1,
      bookTable: data['bookTable'] == true,
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
    );
  }

  PromotionCampaign? _campaignFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final rawChannels = data['channels'];
    final channels = rawChannels is Iterable
        ? rawChannels
              .map((channel) => _promotionChannelFromValue(channel))
              .whereType<PromotionChannel>()
              .toList()
        : const <PromotionChannel>[];

    return PromotionCampaign(
      id: doc.id,
      eventId: '${data['eventId'] ?? ''}'.trim(),
      eventTitle: '${data['eventTitle'] ?? ''}'.trim(),
      name: '${data['name'] ?? ''}'.trim(),
      createdByUserId: '${data['createdBy'] ?? ''}'.trim().isEmpty
          ? null
          : '${data['createdBy'] ?? ''}'.trim(),
      status: _promotionStatusFromValue(data['status']),
      channels: channels,
      scheduledAt: _dateFromValue(data['scheduledAt']),
      pushAudience: (data['pushAudience'] as num?)?.toInt() ?? 0,
      smsAudience: (data['smsAudience'] as num?)?.toInt() ?? 0,
      shareLinkEnabled: data['shareLinkEnabled'] == true,
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      message: '${data['message'] ?? ''}'.trim(),
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
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

  double? _latitudeFromValue(Object? location, Object? fallback) {
    if (location is GeoPoint) {
      return location.latitude;
    }
    if (location is Map) {
      final raw = location['latitude'] ?? location['lat'];
      if (raw is num) {
        return raw.toDouble();
      }
    }
    if (fallback is num) {
      return fallback.toDouble();
    }
    if (fallback is String && fallback.trim().isNotEmpty) {
      return double.tryParse(fallback);
    }
    return null;
  }

  double? _longitudeFromValue(Object? location, Object? fallback) {
    if (location is GeoPoint) {
      return location.longitude;
    }
    if (location is Map) {
      final raw = location['longitude'] ?? location['lng'];
      if (raw is num) {
        return raw.toDouble();
      }
    }
    if (fallback is num) {
      return fallback.toDouble();
    }
    if (fallback is String && fallback.trim().isNotEmpty) {
      return double.tryParse(fallback);
    }
    return null;
  }

  double _distanceKm(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _degreesToRadians(endLatitude - startLatitude);
    final longitudeDelta = _degreesToRadians(endLongitude - startLongitude);
    final originLatitude = _degreesToRadians(startLatitude);
    final destinationLatitude = _degreesToRadians(endLatitude);

    final haversine =
        sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
        cos(originLatitude) *
            cos(destinationLatitude) *
            sin(longitudeDelta / 2) *
            sin(longitudeDelta / 2);
    final angularDistance = 2 * atan2(sqrt(haversine), sqrt(1 - haversine));
    return earthRadiusKm * angularDistance;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180.0;

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

  PromotionStatus _promotionStatusFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'draft' => PromotionStatus.draft,
      'scheduled' => PromotionStatus.scheduled,
      'completed' => PromotionStatus.completed,
      _ => PromotionStatus.live,
    };
  }

  PromotionChannel? _promotionChannelFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'push' => PromotionChannel.push,
      'sms' => PromotionChannel.sms,
      'sharelink' => PromotionChannel.shareLink,
      'featured' => PromotionChannel.featured,
      'announcement' => PromotionChannel.announcement,
      _ => null,
    };
  }

  ReminderTiming _reminderTimingFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'onday' => ReminderTiming.onDay,
      'twodaysbefore' => ReminderTiming.twoDaysBefore,
      'oneweekbefore' => ReminderTiming.oneWeekBefore,
      'custom' => ReminderTiming.custom,
      _ => ReminderTiming.oneDayBefore,
    };
  }

  bool get _shouldUseLiveOrders =>
      _cloudSync.isEnabled && _viewer.isAuthenticated && _ordersHydrated;

  bool get _shouldUseLiveRsvps =>
      _cloudSync.isEnabled && _viewer.isAuthenticated && _rsvpsHydrated;

  bool get _shouldUseLiveCampaigns =>
      _cloudSync.isEnabled && _viewer.isAuthenticated && _campaignsHydrated;

  bool get _shouldUseLiveReminders =>
      _cloudSync.isEnabled && _viewer.isAuthenticated && _remindersHydrated;

  @override
  void dispose() {
    _publicEventsSubscription?.cancel();
    _workspaceEventsSubscription?.cancel();
    _ordersSubscription?.cancel();
    _rsvpsSubscription?.cancel();
    _campaignsSubscription?.cancel();
    _remindersSubscription?.cancel();
    super.dispose();
  }
}
