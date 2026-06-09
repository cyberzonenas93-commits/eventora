import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../mock/mock_seed.dart';
import '../services/vennuzo_cloud_sync_service.dart';
import '../services/vennuzo_payment_service.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/creator_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/place_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';

class VennuzoRepository extends ChangeNotifier {
  VennuzoRepository._({
    required List<EventModel> events,
    required List<TicketOrder> orders,
    required List<RsvpRecord> rsvps,
    required List<PromotionCampaign> campaigns,
    required List<CreatorProfile> creatorProfiles,
    required List<CreatorEventPhoto> creatorPhotos,
    required List<PlaceProfile> places,
    required List<PlaceMenuSection> placeMenuSections,
    required List<PlaceMenuItem> placeMenuItems,
    required List<PlaceReservation> placeReservations,
    required VennuzoCloudSyncService cloudSync,
  }) : _events = events,
       _orders = orders,
       _rsvps = rsvps,
       _campaigns = campaigns,
       _creatorProfiles = creatorProfiles,
       _creatorPhotos = creatorPhotos,
       _places = places,
       _placeMenuSections = placeMenuSections,
       _placeMenuItems = placeMenuItems,
       _placeReservations = placeReservations,
       _cloudSync = cloudSync {
    if (_cloudSync.isEnabled) {
      _bindEventStreams();
      _bindCreatorStreams();
      _bindPlaceStreams();
    }
  }

  factory VennuzoRepository.seeded({required bool firebaseEnabled}) {
    // App Store compliance (Guideline 2.3.1/4.0): demo/QA fixtures must never
    // reach production users. Release builds start with empty base lists so
    // only live Firestore data is shown; debug/profile builds keep the mock
    // seed for local development. The `_effective*` getters merge these base
    // lists with the live cloud overlay, so an empty base + live overlay is a
    // fully functional release experience.
    return VennuzoRepository._(
      events: kReleaseMode ? <EventModel>[] : MockSeed.events(),
      orders: kReleaseMode ? <TicketOrder>[] : MockSeed.orders(),
      rsvps: kReleaseMode ? <RsvpRecord>[] : MockSeed.rsvps(),
      campaigns: kReleaseMode ? <PromotionCampaign>[] : MockSeed.campaigns(),
      creatorProfiles: kReleaseMode
          ? <CreatorProfile>[]
          : MockSeed.creatorProfiles(),
      creatorPhotos: kReleaseMode
          ? <CreatorEventPhoto>[]
          : MockSeed.creatorPhotos(),
      places: kReleaseMode ? <PlaceProfile>[] : MockSeed.places(),
      placeMenuSections: kReleaseMode
          ? <PlaceMenuSection>[]
          : MockSeed.placeMenuSections(),
      placeMenuItems: kReleaseMode
          ? <PlaceMenuItem>[]
          : MockSeed.placeMenuItems(),
      placeReservations: kReleaseMode
          ? <PlaceReservation>[]
          : MockSeed.placeReservations(),
      cloudSync: VennuzoCloudSyncService(firebaseEnabled: firebaseEnabled),
    );
  }

  @visibleForTesting
  factory VennuzoRepository.withFixtures({
    List<EventModel> events = const <EventModel>[],
    List<TicketOrder> orders = const <TicketOrder>[],
    List<RsvpRecord> rsvps = const <RsvpRecord>[],
    List<PromotionCampaign> campaigns = const <PromotionCampaign>[],
    List<CreatorProfile> creatorProfiles = const <CreatorProfile>[],
    List<CreatorEventPhoto> creatorPhotos = const <CreatorEventPhoto>[],
    List<PlaceProfile> places = const <PlaceProfile>[],
    List<PlaceMenuSection> placeMenuSections = const <PlaceMenuSection>[],
    List<PlaceMenuItem> placeMenuItems = const <PlaceMenuItem>[],
    List<PlaceReservation> placeReservations = const <PlaceReservation>[],
    bool firebaseEnabled = false,
  }) {
    return VennuzoRepository._(
      events: List<EventModel>.of(events),
      orders: List<TicketOrder>.of(orders),
      rsvps: List<RsvpRecord>.of(rsvps),
      campaigns: List<PromotionCampaign>.of(campaigns),
      creatorProfiles: List<CreatorProfile>.of(creatorProfiles),
      creatorPhotos: List<CreatorEventPhoto>.of(creatorPhotos),
      places: List<PlaceProfile>.of(places),
      placeMenuSections: List<PlaceMenuSection>.of(placeMenuSections),
      placeMenuItems: List<PlaceMenuItem>.of(placeMenuItems),
      placeReservations: List<PlaceReservation>.of(placeReservations),
      cloudSync: VennuzoCloudSyncService(firebaseEnabled: firebaseEnabled),
    );
  }

  final List<EventModel> _events;
  final List<TicketOrder> _orders;
  final List<RsvpRecord> _rsvps;
  final List<PromotionCampaign> _campaigns;
  final List<CreatorProfile> _creatorProfiles;
  final List<CreatorEventPhoto> _creatorPhotos;
  final List<PlaceProfile> _places;
  final List<PlaceMenuSection> _placeMenuSections;
  final List<PlaceMenuItem> _placeMenuItems;
  final List<PlaceReservation> _placeReservations;
  final VennuzoCloudSyncService _cloudSync;
  final Set<String> _followedCreatorIds = <String>{};
  final Set<String> _subscribedPlaceIds = <String>{};
  String? _lastPlaceSyncError;
  final List<EventModel> _livePublicEvents = <EventModel>[];
  final List<EventModel> _liveWorkspaceEvents = <EventModel>[];
  final List<TicketOrder> _liveOrders = <TicketOrder>[];
  final List<RsvpRecord> _liveRsvps = <RsvpRecord>[];
  final List<PromotionCampaign> _liveCampaigns = <PromotionCampaign>[];
  final List<CreatorProfile> _liveCreatorProfiles = <CreatorProfile>[];
  final List<CreatorEventPhoto> _liveCreatorPhotos = <CreatorEventPhoto>[];
  final List<PlaceProfile> _livePlaces = <PlaceProfile>[];
  final List<PlaceMenuSection> _livePlaceMenuSections = <PlaceMenuSection>[];
  final List<PlaceMenuItem> _livePlaceMenuItems = <PlaceMenuItem>[];
  final List<PlaceReservation> _livePlaceReservations = <PlaceReservation>[];
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _creatorFollowsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _creatorProfilesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _creatorPhotosSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _placesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _placeMenuSectionsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _placeMenuItemsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _placeReservationsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _placeSubscriptionsSubscription;
  VennuzoViewer _viewer = const VennuzoViewer.guest();
  final Map<String, ReminderTiming> _reminders = <String, ReminderTiming>{};
  final Set<String> _likedEventIds = <String>{};
  bool _ordersHydrated = false;
  bool _rsvpsHydrated = false;
  bool _campaignsHydrated = false;
  bool _remindersHydrated = false;
  bool _placesHydrated = false;
  bool _eventsHydrated = false;

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

  List<CreatorProfile> get _effectiveCreatorProfiles {
    final merged = <String, CreatorProfile>{
      for (final profile in _creatorProfiles) profile.creatorId: profile,
    };
    for (final profile in _liveCreatorProfiles) {
      merged[profile.creatorId] = profile;
    }
    return merged.values.toList();
  }

  List<CreatorEventPhoto> get _effectiveCreatorPhotos {
    final merged = <String, CreatorEventPhoto>{
      for (final photo in _creatorPhotos) photo.id: photo,
    };
    for (final photo in _liveCreatorPhotos) {
      merged[photo.id] = photo;
    }
    return merged.values.toList();
  }

  List<PlaceProfile> get _effectivePlaces {
    final merged = <String, PlaceProfile>{
      for (final place in _places) place.id: place,
    };
    for (final place in _livePlaces) {
      merged[place.id] = place;
    }
    return merged.values.where((place) => place.isActive).toList();
  }

  List<PlaceMenuSection> get _effectivePlaceMenuSections {
    final merged = <String, PlaceMenuSection>{
      for (final section in _placeMenuSections) section.id: section,
    };
    for (final section in _livePlaceMenuSections) {
      merged[section.id] = section;
    }
    return merged.values.where((section) => section.visible).toList();
  }

  List<PlaceMenuItem> get _effectivePlaceMenuItems {
    final merged = <String, PlaceMenuItem>{
      for (final item in _placeMenuItems) item.id: item,
    };
    for (final item in _livePlaceMenuItems) {
      merged[item.id] = item;
    }
    return merged.values.where((item) => item.isVisible).toList();
  }

  List<PlaceReservation> get _effectivePlaceReservations {
    final merged = <String, PlaceReservation>{
      for (final reservation in _placeReservations) reservation.id: reservation,
    };
    for (final reservation in _livePlaceReservations) {
      merged[reservation.id] = reservation;
    }
    return merged.values.toList();
  }

  String get currentUserId => _viewer.uid ?? '';
  String get currentUserName => _viewer.displayName;
  String get currentUserPhone => _viewer.phone ?? '';
  String get currentUserEmail => _viewer.email ?? '';
  bool get isGuest => _viewer.isGuest;

  void applyViewer(VennuzoViewer viewer) {
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
      _ensureLocalCreatorProfile(viewer);
      unawaited(_cloudSync.ensureOrganizerWorkspace(viewer));
      if (viewer.uid != null) {
        unawaited(
          _cloudSync.upsertCreatorProfile(creatorProfileFor(viewer.uid!)),
        );
      }
    }
    if (_cloudSync.isEnabled) {
      _bindEventStreams();
      _bindCreatorStreams();
      _bindPlaceStreams();
      _bindCommerceStreams();
      _bindCreatorFollowStream();
      _bindPlaceSubscriptionStream();
    }
    notifyListeners();
  }

  bool _isCurrentEvent(EventModel event) {
    final visibleUntil = event.endDate ?? event.startDate;
    return visibleUntil.isAfter(DateTime.now());
  }

  List<EventModel> get discoverableEvents =>
      _effectiveEvents
          .where((event) => !event.isPrivate && _isCurrentEvent(event))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  List<EventModel> discoverableEventsForPreferences(
    Iterable<String> categoryIds,
  ) {
    final wanted = categoryIds
        .map(EventTaxonomy.canonicalCategoryId)
        .where((id) => id.isNotEmpty && id != 'all')
        .toSet();
    final events = discoverableEvents;
    return events..sort((a, b) {
      final aMatch = EventTaxonomy.eventMatchesAny(a, wanted);
      final bMatch = EventTaxonomy.eventMatchesAny(b, wanted);
      if (aMatch != bMatch) return aMatch ? -1 : 1;
      final scoreCompare = _discoverySpotlightScore(
        b,
      ).compareTo(_discoverySpotlightScore(a));
      if (scoreCompare != 0) return scoreCompare;
      return a.startDate.compareTo(b.startDate);
    });
  }

  List<PlaceProfile> get places {
    return _effectivePlaces..sort((a, b) {
      if (a.featured != b.featured) return a.featured ? -1 : 1;
      final aSubscribed = isSubscribedToPlace(a.id) ? 1 : 0;
      final bSubscribed = isSubscribedToPlace(b.id) ? 1 : 0;
      final subscribedCompare = bSubscribed.compareTo(aSubscribed);
      if (subscribedCompare != 0) return subscribedCompare;
      return b.subscriberCount.compareTo(a.subscriberCount);
    });
  }

  List<PlaceProfile> get featuredPlaces =>
      places.where((place) => place.featured).toList();

  /// True while the first Firestore places snapshot is still pending, so the UI
  /// can show a loading state instead of flashing an empty/"not found" view.
  /// Always false when cloud sync is disabled (data is available synchronously).
  bool get placesLoading => _cloudSync.isEnabled && !_placesHydrated;

  /// True while the first Firestore public-events snapshot is still pending.
  bool get eventsLoading => _cloudSync.isEnabled && !_eventsHydrated;

  PlaceProfile? placeById(String id) {
    for (final place in _effectivePlaces) {
      if (place.id == id) return place;
    }
    return null;
  }

  List<PlaceMenuSection> menuSectionsForPlace(String placeId) {
    return _effectivePlaceMenuSections
        .where((section) => section.placeId == placeId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<PlaceMenuItem> menuItemsForPlace(String placeId, {String? sectionId}) {
    return _effectivePlaceMenuItems
        .where(
          (item) =>
              item.placeId == placeId &&
              (sectionId == null || item.sectionId == sectionId),
        )
        .toList()
      ..sort((a, b) {
        if (a.featured != b.featured) return a.featured ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
  }

  List<PlaceReservation> reservationsForPlace(String placeId) {
    return _effectivePlaceReservations
        .where((reservation) => reservation.placeId == placeId)
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  }

  List<PlaceReservation> get myPlaceReservations {
    if (isGuest || currentUserId.isEmpty) return const <PlaceReservation>[];
    return _effectivePlaceReservations
        .where((reservation) => reservation.userId == currentUserId)
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  }

  List<EventModel> eventsForPlace(String placeId) {
    return discoverableEvents
        .where((event) => event.location?.placeId == placeId)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  bool isSubscribedToPlace(String placeId) {
    return _subscribedPlaceIds.contains(placeId);
  }

  /// Set when an optimistic place mutation was rolled back because its cloud
  /// write failed. The UI can surface this and call [clearPlaceSyncError].
  String? get lastPlaceSyncError => _lastPlaceSyncError;

  void clearPlaceSyncError() {
    if (_lastPlaceSyncError != null) {
      _lastPlaceSyncError = null;
      notifyListeners();
    }
  }

  void _reportPlaceSyncError(String message) {
    _lastPlaceSyncError = message;
    notifyListeners();
  }

  void subscribeToPlace(
    String placeId, {
    PlaceSubscriptionPrefs prefs = const PlaceSubscriptionPrefs(),
  }) {
    if (isGuest || currentUserId.isEmpty) return;
    final added = _subscribedPlaceIds.add(placeId);
    unawaited(
      _cloudSync
          .subscribeToPlace(placeId: placeId, viewer: _viewer, prefs: prefs)
          .then((ok) {
            // Roll back the optimistic subscription if the cloud write failed.
            if (!ok && added) {
              _subscribedPlaceIds.remove(placeId);
              _reportPlaceSyncError(
                'Could not subscribe to this place. Please try again.',
              );
            }
          }),
    );
    if (added) notifyListeners();
  }

  void unsubscribeFromPlace(String placeId) {
    if (currentUserId.isEmpty) return;
    final removed = _subscribedPlaceIds.remove(placeId);
    unawaited(
      _cloudSync.unsubscribeFromPlace(placeId: placeId, viewer: _viewer).then((
        ok,
      ) {
        if (!ok && removed) {
          _subscribedPlaceIds.add(placeId);
          _reportPlaceSyncError(
            'Could not update your subscription. Please try again.',
          );
        }
      }),
    );
    if (removed) notifyListeners();
  }

  /// Optimistically records the reservation, then awaits the cloud write.
  /// Adds locally first for an instant UI, but rolls back and throws if the
  /// cloud write fails so callers can surface a truthful result. Cloud sync
  /// disabled is treated as accepted (offline/local).
  Future<PlaceReservation> createPlaceReservation(
    PlaceReservationRequest request,
  ) async {
    if (isGuest || currentUserId.isEmpty) {
      throw StateError('Sign in before reserving a place.');
    }
    final now = DateTime.now();
    final reservation = PlaceReservation(
      id: _generateId('place_reservation'),
      placeId: request.placeId,
      placeName: request.placeName,
      userId: currentUserId,
      guestName: request.guestName,
      phone: request.phone,
      partySize: request.partySize,
      requestedAt: request.requestedAt,
      reservationType: request.reservationType,
      status: PlaceReservationStatus.pending,
      note: request.note,
      selectedMenuItemIds: request.selectedMenuItemIds,
      createdAt: now,
      updatedAt: now,
    );
    _placeReservations.add(reservation);
    notifyListeners();
    final ok = await _cloudSync.createPlaceReservation(
      reservation: reservation,
    );
    if (!ok) {
      _placeReservations.removeWhere((r) => r.id == reservation.id);
      _reportPlaceSyncError(
        'Could not submit your reservation. Please try again.',
      );
      notifyListeners();
      throw StateError('Could not submit your reservation. Please try again.');
    }
    return reservation;
  }

  PlaceMenuItem createPlaceMenuItem({
    required String placeId,
    required String sectionId,
    required String name,
    required String description,
    required double price,
    bool featured = false,
  }) {
    if (!_viewer.hasOrganizerAccess && !_viewer.hasAdminAccess) {
      throw StateError('Place management access is required.');
    }
    final item = PlaceMenuItem(
      id: _generateId('place_menu_item'),
      placeId: placeId,
      sectionId: sectionId,
      name: name,
      description: description,
      price: price,
      featured: featured,
      sortOrder: _effectivePlaceMenuItems
          .where((existing) => existing.placeId == placeId)
          .length,
    );
    _placeMenuItems.add(item);
    unawaited(
      _cloudSync.upsertPlaceMenuItem(item: item, viewer: _viewer).then((ok) {
        if (!ok) {
          _placeMenuItems.removeWhere((i) => i.id == item.id);
          _reportPlaceSyncError(
            'Could not save the menu item. Please try again.',
          );
        }
      }),
    );
    notifyListeners();
    return item;
  }

  void updatePlaceReservationStatus(
    String reservationId,
    PlaceReservationStatus status,
  ) {
    if (!_viewer.hasOrganizerAccess && !_viewer.hasAdminAccess) return;
    final index = _placeReservations.indexWhere(
      (reservation) => reservation.id == reservationId,
    );
    PlaceReservation? previous;
    if (index != -1) {
      final current = _placeReservations[index];
      previous = current;
      _placeReservations[index] = PlaceReservation(
        id: current.id,
        placeId: current.placeId,
        placeName: current.placeName,
        userId: current.userId,
        guestName: current.guestName,
        phone: current.phone,
        partySize: current.partySize,
        requestedAt: current.requestedAt,
        reservationType: current.reservationType,
        status: status,
        note: current.note,
        internalNote: current.internalNote,
        selectedMenuItemIds: current.selectedMenuItemIds,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
    }
    final rollbackTo = previous;
    unawaited(
      _cloudSync
          .updatePlaceReservationStatus(
            reservationId: reservationId,
            status: status,
          )
          .then((ok) {
            if (!ok && rollbackTo != null) {
              final i = _placeReservations.indexWhere(
                (r) => r.id == reservationId,
              );
              if (i != -1) {
                _placeReservations[i] = rollbackTo;
                _reportPlaceSyncError(
                  'Could not update the reservation. Please try again.',
                );
              }
            }
          }),
    );
    notifyListeners();
  }

  void launchPlacePushCampaign({
    required PlaceProfile place,
    required String title,
    required String message,
  }) {
    if (!_viewer.hasOrganizerAccess && !_viewer.hasAdminAccess) {
      throw StateError('Place management access is required.');
    }
    final estimatedCost = place.subscriberCount * 0.02;
    final campaign = PromotionCampaign(
      id: _generateId('promo'),
      eventId: '',
      eventTitle: '',
      targetType: PromotionTargetType.place,
      targetId: place.id,
      targetTitle: place.name,
      name: '${place.name} subscriber push',
      createdByUserId: currentUserId,
      status: PromotionStatus.live,
      channels: const [PromotionChannel.push],
      scheduledAt: null,
      pushAudience: place.subscriberCount,
      smsAudience: 0,
      shareLinkEnabled: false,
      audienceSources: const ['place_subscribers'],
      budget: estimatedCost,
      message: message,
      createdAt: DateTime.now(),
      objective: CampaignObjective.boostAwareness,
      audienceStrategy: AudienceStrategy.ownedCrm,
      optimizationGoal: OptimizationGoal.reach,
      bidStrategy: BidStrategy.balanced,
      creativeMode: CreativeMode.single,
      frequencyCap: 1,
      budgetCapGhs: estimatedCost,
    );
    _campaigns.add(campaign);
    unawaited(
      _cloudSync.launchPlacePushCampaign(
        place: place,
        title: title,
        message: message,
      ),
    );
    notifyListeners();
  }

  List<CreatorProfile> get creatorProfiles {
    final creatorIds = <String>{
      ..._effectiveCreatorProfiles.map((profile) => profile.creatorId),
      ..._effectiveEvents.map((event) => event.createdBy),
    };
    return creatorIds.map(creatorProfileFor).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  CreatorProfile creatorProfileFor(String creatorId) {
    final base = _effectiveCreatorProfiles.firstWhere(
      (profile) => profile.creatorId == creatorId,
      orElse: () {
        if (creatorId == 'gplus') {
          return CreatorProfile(
            creatorId: creatorId,
            displayName: 'G+ Nightclub',
            bio:
                'G+ Nightclub events, nightlife, culture, and community moments synced into Vennuzo.',
            city: 'Accra',
            updatedAt: DateTime.now(),
          );
        }
        return CreatorProfile(
          creatorId: creatorId,
          displayName: creatorId == currentUserId && currentUserName.isNotEmpty
              ? currentUserName
              : 'Vennuzo creator',
          bio: 'Events, tickets, updates, and photos hosted on Vennuzo.',
          updatedAt: DateTime.now(),
        );
      },
    );
    final followsBoost = isFollowingCreator(creatorId) ? 1 : 0;
    return base.copyWith(
      followerCount: base.followerCount + followsBoost,
      eventCount: eventsForCreator(creatorId).length,
      photoCount: photosForCreator(creatorId).length,
    );
  }

  List<CreatorEventPhoto> photosForCreator(String creatorId) {
    return _effectiveCreatorPhotos
        .where((photo) => photo.creatorId == creatorId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<EventModel> eventsForCreator(String creatorId) {
    return discoverableEvents
        .where((event) => event.createdBy == creatorId)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<EventModel> get followedCreatorEvents {
    if (_followedCreatorIds.isEmpty) {
      return const [];
    }
    return discoverableEvents
        .where((event) => _followedCreatorIds.contains(event.createdBy))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  bool isFollowingCreator(String creatorId) {
    return _followedCreatorIds.contains(creatorId);
  }

  void followCreator(String creatorId) {
    if (isGuest || currentUserId.isEmpty || creatorId == currentUserId) {
      return;
    }
    if (!_followedCreatorIds.add(creatorId)) {
      return;
    }
    unawaited(
      _cloudSync.followCreator(followerId: currentUserId, creatorId: creatorId),
    );
    notifyListeners();
  }

  void unfollowCreator(String creatorId) {
    if (currentUserId.isEmpty || !_followedCreatorIds.remove(creatorId)) {
      return;
    }
    unawaited(
      _cloudSync.unfollowCreator(
        followerId: currentUserId,
        creatorId: creatorId,
      ),
    );
    notifyListeners();
  }

  void saveCreatorProfile(CreatorProfile profile) {
    if (isGuest ||
        currentUserId.isEmpty ||
        profile.creatorId != currentUserId) {
      return;
    }
    final updated = profile.copyWith(updatedAt: DateTime.now());
    final index = _creatorProfiles.indexWhere(
      (existing) => existing.creatorId == updated.creatorId,
    );
    if (index == -1) {
      _creatorProfiles.add(updated);
    } else {
      _creatorProfiles[index] = updated;
    }
    final liveIndex = _liveCreatorProfiles.indexWhere(
      (existing) => existing.creatorId == updated.creatorId,
    );
    if (liveIndex != -1) {
      _liveCreatorProfiles[liveIndex] = updated;
    }
    unawaited(_cloudSync.upsertCreatorProfile(updated));
    notifyListeners();
  }

  CreatorEventPhoto addCreatorEventPhoto({
    required String creatorId,
    required EventModel event,
    required String imageUrl,
    required String caption,
  }) {
    if (isGuest || currentUserId.isEmpty || creatorId != currentUserId) {
      throw StateError('Only the creator can add photos to this profile.');
    }
    final photo = CreatorEventPhoto(
      id: _generateId('creator_photo'),
      creatorId: creatorId,
      eventId: event.id,
      eventTitle: event.title,
      imageUrl: imageUrl,
      caption: caption,
      createdAt: DateTime.now(),
    );
    _creatorPhotos.add(photo);
    unawaited(_cloudSync.upsertCreatorEventPhoto(photo));
    notifyListeners();
    return photo;
  }

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

  List<PromotionCampaign> featuredCampaignsForPreferences(
    Iterable<String> categoryIds,
  ) {
    return _publicVisibleCampaigns
        .where(
          (campaign) =>
              campaign.status == PromotionStatus.live &&
              campaign.channels.contains(PromotionChannel.featured) &&
              _campaignMatchesPreferences(campaign, categoryIds),
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

  List<PromotionCampaign> get featuredCampaigns =>
      featuredCampaignsForPreferences(const <String>[]);

  List<PromotionCampaign> announcementCampaignsForPreferences(
    Iterable<String> categoryIds,
  ) {
    return _livePublicVisibleCampaigns
        .where(
          (campaign) =>
              campaign.status == PromotionStatus.live &&
              (campaign.channels.contains(PromotionChannel.announcement) ||
                  campaign.channels.contains(PromotionChannel.featured)) &&
              _campaignMatchesPreferences(campaign, categoryIds),
        )
        .toList()
      ..sort((a, b) {
        final aEvent = eventById(a.eventId);
        final bEvent = eventById(b.eventId);
        if (aEvent == null || bEvent == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        final scoreCompare = _discoverySpotlightScore(
          bEvent,
        ).compareTo(_discoverySpotlightScore(aEvent));
        if (scoreCompare != 0) return scoreCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  List<PromotionCampaign> get announcementCampaigns =>
      announcementCampaignsForPreferences(const <String>[]);

  List<PromotionCampaign> get featuredPlaceCampaigns =>
      _publicVisibleCampaigns
          .where(
            (campaign) =>
                campaign.targetType == PromotionTargetType.place &&
                campaign.status == PromotionStatus.live &&
                campaign.channels.contains(PromotionChannel.featured),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  PromotionCampaign? get primaryAnnouncementCampaign {
    final campaigns = announcementCampaigns;
    return campaigns.isEmpty ? null : campaigns.first;
  }

  PromotionCampaign? primaryAnnouncementCampaignForPreferences(
    Iterable<String> categoryIds,
  ) {
    final campaigns = announcementCampaignsForPreferences(categoryIds);
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
              currentUserId.isNotEmpty && event.createdBy == currentUserId,
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

  String buildShareLink(String eventId) =>
      'https://vennuzo.web.app/events/${Uri.encodeComponent(eventId)}';

  String buildPublicTicketLink(String orderId) =>
      'https://vennuzo.web.app/tickets/${Uri.encodeComponent(orderId)}';

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

  bool isEventLiked(String eventId) => _likedEventIds.contains(eventId);

  /// Toggles the viewer's like for an event and returns the new liked state.
  /// Likes are tracked per session (not yet synced server-side), so this
  /// records membership rather than mutating shared like counts — the old
  /// behavior only ever incremented and could never be undone.
  bool toggleLike(String eventId) {
    final nowLiked = !_likedEventIds.contains(eventId);
    if (nowLiked) {
      _likedEventIds.add(eventId);
    } else {
      _likedEventIds.remove(eventId);
    }
    notifyListeners();
    return nowLiked;
  }

  void createEvent(EventDraft draft) {
    if (isGuest || currentUserId.isEmpty || !_viewer.hasOrganizerAccess) {
      return;
    }
    _ensureLocalCreatorProfile(_viewer);
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
      categoryId: draft.categoryId,
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
      categoryId: draft.categoryId,
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
    String? discountCode,
  }) {
    if (isGuest) {
      throw StateError('Guests need an account before checking out.');
    }
    final chosenSelections = <TicketSelection>[];
    final tickets = <EventTicket>[];
    final now = DateTime.now();
    double grossTotal = 0;

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
      grossTotal += tier.price * quantity;
      updatedTiers = updatedTiers
          .map(
            (value) => value.tierId == tier.tierId
                ? value.copyWith(sold: value.sold + quantity)
                : value,
          )
          .toList();
    }

    final voucher = event.ticketing.voucherByCode(discountCode);
    final discountAmount = voucher?.discountFor(grossTotal) ?? 0;
    final total = (grossTotal - discountAmount).clamp(0, grossTotal).toDouble();
    final discount = voucher != null && discountAmount > 0
        ? TicketDiscount(
            code: voucher.normalizedCode,
            label: voucher.label,
            amount: discountAmount,
            type: voucher.type.name,
            value: voucher.value,
          )
        : null;
    final updatedVouchers = discount == null
        ? event.ticketing.discountVouchers
        : event.ticketing.discountVouchers
              .map(
                (current) => current.normalizedCode == discount.code
                    ? current.copyWith(redeemedCount: current.redeemedCount + 1)
                    : current,
              )
              .toList();

    final orderId = _generateId('order');
    var ticketNumber = 1;
    final unpaidReservation = grossTotal == 0;
    final complimentaryDiscount = grossTotal > 0 && total == 0;
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
      discount: discount,
      status: unpaidReservation
          ? TicketOrderStatus.reserved
          : TicketOrderStatus.paid,
      paymentStatus: unpaidReservation
          ? TicketPaymentStatus.cashAtGate
          : complimentaryDiscount
          ? TicketPaymentStatus.complimentary
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
        ticketing: current.ticketing.copyWith(
          tiers: updatedTiers,
          discountVouchers: updatedVouchers,
        ),
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
    CampaignObjective objective = CampaignObjective.sellTickets,
    AudienceStrategy audienceStrategy = AudienceStrategy.recommended,
    OptimizationGoal optimizationGoal = OptimizationGoal.conversions,
    BidStrategy bidStrategy = BidStrategy.balanced,
    CreativeMode creativeMode = CreativeMode.single,
    int frequencyCap = 2,
    double? budgetCapGhs,
    List<String> audienceSources = const <String>[
      'event_rsvps',
      'ticket_buyers',
      'uploaded_contacts',
    ],
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
      targetType: PromotionTargetType.event,
      targetId: event.id,
      targetTitle: event.title,
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
      audienceSources: audienceSources,
      budget: budget,
      message: message,
      createdAt: DateTime.now(),
      objective: objective,
      audienceStrategy: audienceStrategy,
      optimizationGoal: optimizationGoal,
      bidStrategy: bidStrategy,
      creativeMode: creativeMode,
      frequencyCap: frequencyCap,
      budgetCapGhs: budgetCapGhs,
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

  PromotionCampaign schedulePlaceCampaign({
    required String placeId,
    required String placeTitle,
    required String name,
    required DateTime? scheduledAt,
    required List<PromotionChannel> channels,
    required double budget,
    required String message,
    CampaignObjective objective = CampaignObjective.boostAwareness,
    AudienceStrategy audienceStrategy = AudienceStrategy.broadDiscovery,
    OptimizationGoal optimizationGoal = OptimizationGoal.reach,
    BidStrategy bidStrategy = BidStrategy.balanced,
    CreativeMode creativeMode = CreativeMode.single,
    int frequencyCap = 2,
    double? budgetCapGhs,
    List<String> audienceSources = const <String>['places_discovery'],
  }) {
    if (!_viewer.hasOrganizerAccess && !_viewer.hasAdminAccess) {
      throw StateError(
        'Organizer or admin access is required before launching campaigns.',
      );
    }
    final campaign = PromotionCampaign(
      id: _generateId('promo'),
      eventId: '',
      eventTitle: '',
      targetType: PromotionTargetType.place,
      targetId: placeId,
      targetTitle: placeTitle,
      name: name,
      createdByUserId: currentUserId,
      status: scheduledAt == null
          ? PromotionStatus.live
          : PromotionStatus.scheduled,
      channels: channels,
      scheduledAt: scheduledAt,
      pushAudience: 0,
      smsAudience: 0,
      shareLinkEnabled: channels.contains(PromotionChannel.shareLink),
      audienceSources: audienceSources,
      budget: budget,
      message: message,
      createdAt: DateTime.now(),
      objective: objective,
      audienceStrategy: audienceStrategy,
      optimizationGoal: optimizationGoal,
      bidStrategy: bidStrategy,
      creativeMode: creativeMode,
      frequencyCap: frequencyCap,
      budgetCapGhs: budgetCapGhs,
    );
    _campaigns.add(campaign);
    unawaited(
      _cloudSync.launchPlaceCampaign(campaign: campaign, viewer: _viewer),
    );
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

  void _ensureLocalCreatorProfile(VennuzoViewer viewer) {
    final uid = viewer.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    final exists = _creatorProfiles.any((profile) => profile.creatorId == uid);
    if (exists) {
      return;
    }
    _creatorProfiles.add(
      CreatorProfile(
        creatorId: uid,
        displayName: viewer.displayName.isEmpty
            ? 'Vennuzo creator'
            : viewer.displayName,
        bio: 'Events, updates, and guest photos hosted on Vennuzo.',
        city: 'Accra',
        avatarUrl: viewer.photoUrl,
        updatedAt: DateTime.now(),
      ),
    );
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
          .where(
            (campaign) =>
                campaign.targetType == PromotionTargetType.event &&
                managedEventIds.contains(campaign.eventId),
          )
          .toList();
    }

    return const <PromotionCampaign>[];
  }

  List<PromotionCampaign> get _publicVisibleCampaigns {
    if (_cloudSync.isEnabled && !_campaignsHydrated) return const [];
    final merged = <String, PromotionCampaign>{
      if (!_cloudSync.isEnabled)
        for (final campaign in _campaigns) campaign.id: campaign,
    };
    for (final campaign in _liveCampaigns) {
      merged[campaign.id] = campaign;
    }
    return merged.values.where((campaign) {
      if (campaign.targetType == PromotionTargetType.place) {
        return campaign.status == PromotionStatus.live &&
            (campaign.channels.contains(PromotionChannel.featured) ||
                campaign.channels.contains(PromotionChannel.announcement));
      }
      final event = eventById(campaign.eventId);
      return event != null && !event.isPrivate && _isCurrentEvent(event);
    }).toList();
  }

  List<PromotionCampaign> get _livePublicVisibleCampaigns =>
      _liveCampaigns.where((campaign) {
        if (campaign.targetType == PromotionTargetType.place) {
          return campaign.status == PromotionStatus.live &&
              (campaign.channels.contains(PromotionChannel.featured) ||
                  campaign.channels.contains(PromotionChannel.announcement));
        }
        final event = eventById(campaign.eventId);
        return event != null && !event.isPrivate && _isCurrentEvent(event);
      }).toList();

  int _promotionWeightForEvent(String eventId) {
    var weight = 0;
    for (final campaign in _publicVisibleCampaigns) {
      if (campaign.eventId != eventId ||
          campaign.status != PromotionStatus.live) {
        continue;
      }
      if (campaign.channels.contains(PromotionChannel.announcement)) {
        weight += 90000;
      }
      if (campaign.channels.contains(PromotionChannel.featured)) {
        weight += 65000;
      }
      if (campaign.channels.contains(PromotionChannel.push)) {
        weight += 18000;
      }
      if (campaign.channels.contains(PromotionChannel.sms)) {
        weight += 18000;
      }
      if (campaign.channels.contains(PromotionChannel.shareLink)) {
        weight += 5000;
      }
      weight += campaign.budget.clamp(0, 5000).round();
    }
    return weight;
  }

  int _discoverySpotlightScore(EventModel event) {
    final ticketsSold = event.ticketing.totalSold;
    final revenueSignal = event.ticketing.tiers.fold<double>(
      0,
      (total, tier) => total + (tier.price * tier.sold),
    );
    final popularitySignal = (event.rsvpCount * 35) + (event.likesCount * 10);
    final ticketSignal = ticketsSold * 140;
    final revenueWeight = revenueSignal.clamp(0, 20000).round();
    return _promotionWeightForEvent(event.id) +
        ticketSignal +
        popularitySignal +
        revenueWeight;
  }

  bool _campaignMatchesPreferences(
    PromotionCampaign campaign,
    Iterable<String> categoryIds,
  ) {
    final event = eventById(campaign.eventId);
    if (event == null || event.isPrivate || !_isCurrentEvent(event)) {
      return false;
    }
    return EventTaxonomy.eventMatchesAny(event, categoryIds);
  }

  void _bindEventStreams() {
    _publicEventsSubscription?.cancel();
    _workspaceEventsSubscription?.cancel();
    _livePublicEvents.clear();
    _liveWorkspaceEvents.clear();
    _eventsHydrated = false;

    final firestore = FirebaseFirestore.instance;
    _publicEventsSubscription = firestore
        .collection('events')
        .where('visibility', isEqualTo: 'public')
        .where('status', isEqualTo: 'published')
        .where(
          'startAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 12)),
          ),
        )
        .orderBy('startAt')
        // Bound realtime reads/memory as the collection grows; the client ranks
        // and filters over this set. 500 is generous for the discover feed.
        .limit(500)
        .snapshots()
        .listen(
          (snapshot) {
            _livePublicEvents
              ..clear()
              ..addAll(
                snapshot.docs
                    .map((doc) => _eventFromFirestore(doc))
                    .whereType<EventModel>(),
              );
            _eventsHydrated = true;
            notifyListeners();
          },
          onError: (_) {
            // Surface an empty state rather than spinning forever on error.
            _eventsHydrated = true;
            notifyListeners();
          },
        );

    if (_viewer.hasAdminAccess) {
      _workspaceEventsSubscription = firestore
          .collection('events')
          .limit(500)
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
          .limit(500)
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

  void _bindCreatorStreams() {
    _creatorProfilesSubscription?.cancel();
    _creatorPhotosSubscription?.cancel();
    _liveCreatorProfiles.clear();
    _liveCreatorPhotos.clear();

    final firestore = FirebaseFirestore.instance;
    _creatorProfilesSubscription = firestore
        .collection('creator_profiles')
        .limit(500)
        .snapshots()
        .listen((snapshot) {
          _liveCreatorProfiles
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => _creatorProfileFromFirestore(doc))
                  .whereType<CreatorProfile>(),
            );
          notifyListeners();
        });

    _creatorPhotosSubscription = firestore
        .collection('creator_event_photos')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .listen((snapshot) {
          _liveCreatorPhotos
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => _creatorPhotoFromFirestore(doc))
                  .whereType<CreatorEventPhoto>(),
            );
          notifyListeners();
        });
  }

  void _bindPlaceStreams() {
    _placesSubscription?.cancel();
    _placeMenuSectionsSubscription?.cancel();
    _placeMenuItemsSubscription?.cancel();
    _placeReservationsSubscription?.cancel();
    _livePlaces.clear();
    _livePlaceMenuSections.clear();
    _livePlaceMenuItems.clear();
    _livePlaceReservations.clear();
    _placesHydrated = false;

    final firestore = FirebaseFirestore.instance;
    Query<Map<String, dynamic>> placesQuery = firestore
        .collection('places')
        .where('status', isEqualTo: 'active')
        .limit(500);
    if (_viewer.hasAdminAccess && _viewer.isAdminWorkspace) {
      placesQuery = firestore.collection('places').limit(500);
    } else if (_viewer.hasOrganizerAccess &&
        _viewer.isOrganizerWorkspace &&
        _viewer.defaultOrganizationId != null &&
        _viewer.defaultOrganizationId!.trim().isNotEmpty) {
      placesQuery = firestore
          .collection('places')
          .where('organizationId', isEqualTo: _viewer.defaultOrganizationId)
          .limit(500);
    }
    _placesSubscription = placesQuery.snapshots().listen(
      (snapshot) {
        _livePlaces
          ..clear()
          ..addAll(
            snapshot.docs
                .map((doc) => _placeFromFirestore(doc))
                .whereType<PlaceProfile>(),
          );
        _placesHydrated = true;
        notifyListeners();
      },
      onError: (_) {
        _placesHydrated = true;
        notifyListeners();
      },
    );

    _placeMenuSectionsSubscription = firestore
        .collection('place_menu_sections')
        .where('visible', isEqualTo: true)
        .limit(1000)
        .snapshots()
        .listen((snapshot) {
          _livePlaceMenuSections
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => _placeMenuSectionFromFirestore(doc))
                  .whereType<PlaceMenuSection>(),
            );
          notifyListeners();
        });

    _placeMenuItemsSubscription = firestore
        .collection('place_menu_items')
        .where('status', isEqualTo: 'available')
        .limit(2000)
        .snapshots()
        .listen((snapshot) {
          _livePlaceMenuItems
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => _placeMenuItemFromFirestore(doc))
                  .whereType<PlaceMenuItem>(),
            );
          notifyListeners();
        });

    if (!_viewer.isAuthenticated || _viewer.uid == null) {
      return;
    }

    final uid = _viewer.uid!;
    final organizationId = _viewer.defaultOrganizationId?.trim();
    Query<Map<String, dynamic>> reservationsQuery = firestore
        .collection('place_reservations')
        .where('userId', isEqualTo: uid)
        .limit(500);
    if (_viewer.hasAdminAccess && _viewer.isAdminWorkspace) {
      reservationsQuery = firestore.collection('place_reservations').limit(500);
    } else if (_viewer.hasOrganizerAccess &&
        _viewer.isOrganizerWorkspace &&
        organizationId != null &&
        organizationId.isNotEmpty) {
      reservationsQuery = firestore
          .collection('place_reservations')
          .where('organizationId', isEqualTo: organizationId)
          .limit(500);
    }

    _placeReservationsSubscription = reservationsQuery.snapshots().listen((
      snapshot,
    ) {
      _livePlaceReservations
        ..clear()
        ..addAll(
          snapshot.docs
              .map((doc) => _placeReservationFromFirestore(doc))
              .whereType<PlaceReservation>(),
        );
      notifyListeners();
    });
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

    final firestore = FirebaseFirestore.instance;
    final publicCampaignsQuery = firestore
        .collection('promotion_campaigns')
        .where('status', isEqualTo: 'live')
        .where('channels', arrayContainsAny: ['featured', 'announcement'])
        .limit(500);

    if (!_viewer.isAuthenticated || _viewer.uid == null) {
      _ordersHydrated = true;
      _rsvpsHydrated = true;
      _remindersHydrated = true;
      _campaignsSubscription = publicCampaignsQuery.snapshots().listen((
        snapshot,
      ) {
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
      notifyListeners();
      return;
    }

    final uid = _viewer.uid!;
    final organizationId = _viewer.defaultOrganizationId?.trim();

    Query<Map<String, dynamic>>? ordersQuery;
    Query<Map<String, dynamic>>? rsvpsQuery;
    Query<Map<String, dynamic>>? campaignsQuery;
    Query<Map<String, dynamic>> remindersQuery = firestore
        .collection('event_reminders')
        .where('userId', isEqualTo: uid)
        .limit(500);

    if (_viewer.isAdminWorkspace && _viewer.hasAdminAccess) {
      ordersQuery = firestore.collection('event_ticket_orders');
      rsvpsQuery = firestore.collection('event_rsvps');
      campaignsQuery = firestore.collection('promotion_campaigns');
    } else if (organizationId != null &&
        organizationId.isNotEmpty &&
        _viewer.isOrganizerWorkspace &&
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
      campaignsQuery = publicCampaignsQuery;
    }

    _ordersSubscription = ordersQuery.limit(500).snapshots().listen((snapshot) {
      _ordersHydrated = true;
      _liveOrders
        ..clear()
        ..addAll(
          snapshot.docs
              .map(VennuzoPaymentService.orderFromDocument)
              .whereType<TicketOrder>(),
        );
      notifyListeners();
    });

    _rsvpsSubscription = rsvpsQuery.limit(500).snapshots().listen((snapshot) {
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

    _campaignsSubscription = campaignsQuery.limit(500).snapshots().listen((
      snapshot,
    ) {
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

  void _bindCreatorFollowStream() {
    _creatorFollowsSubscription?.cancel();
    if (!_viewer.isAuthenticated || _viewer.uid == null) {
      _followedCreatorIds.clear();
      notifyListeners();
      return;
    }

    _creatorFollowsSubscription = FirebaseFirestore.instance
        .collection('creator_follows')
        .where('followerId', isEqualTo: _viewer.uid)
        .snapshots()
        .listen((snapshot) {
          _followedCreatorIds
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => '${doc.data()['creatorId'] ?? ''}'.trim())
                  .where((creatorId) => creatorId.isNotEmpty),
            );
          notifyListeners();
        });
  }

  void _bindPlaceSubscriptionStream() {
    _placeSubscriptionsSubscription?.cancel();
    if (!_viewer.isAuthenticated || _viewer.uid == null) {
      _subscribedPlaceIds.clear();
      notifyListeners();
      return;
    }

    _placeSubscriptionsSubscription = FirebaseFirestore.instance
        .collection('place_subscriptions')
        .where('userId', isEqualTo: _viewer.uid)
        .snapshots()
        .listen((snapshot) {
          _subscribedPlaceIds
            ..clear()
            ..addAll(
              snapshot.docs
                  .map((doc) => '${doc.data()['placeId'] ?? ''}'.trim())
                  .where((placeId) => placeId.isNotEmpty),
            );
          notifyListeners();
        });
  }

  PlaceProfile? _placeFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final metrics = data['metrics'];
    final location = data['location'];
    final latitude = _latitudeFromValue(location, data['latitude']);
    final longitude = _longitudeFromValue(location, data['longitude']);
    final name = _normalizedPlaceName(doc.id, data['name']);
    return PlaceProfile(
      id: doc.id,
      name: name,
      description: '${data['description'] ?? ''}'.trim(),
      city: '${data['city'] ?? 'Accra'}'.trim(),
      address:
          '${data['address'] ?? data['formattedAddress'] ?? data['addressText'] ?? ''}'
              .trim(),
      googlePlaceId: _nullableTrim(data['googlePlaceId'] ?? data['placeId']),
      mapsUrl: _nullableTrim(data['mapsUrl'] ?? data['googleMapsUrl']),
      latitude: latitude,
      longitude: longitude,
      phone: _nullableTrim(data['phone']),
      website: _nullableTrim(data['website']),
      logoUrl: _nullableTrim(data['logoUrl'] ?? data['avatarUrl']),
      coverUrl: _nullableTrim(data['coverUrl'] ?? data['imageUrl']),
      galleryUrls: _stringList(data['galleryUrls'] ?? data['photos']),
      categories: _stringList(data['categories']),
      amenities: _stringList(data['amenities']),
      openingHours: _stringList(data['openingHours'] ?? data['hours']),
      rating: metrics is Map
          ? (metrics['rating'] as num?)?.toDouble() ?? 0
          : (data['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: metrics is Map
          ? (metrics['reviewCount'] as num?)?.toInt() ?? 0
          : (data['reviewCount'] as num?)?.toInt() ?? 0,
      subscriberCount: metrics is Map
          ? (metrics['subscriberCount'] as num?)?.toInt() ?? 0
          : (data['subscriberCount'] as num?)?.toInt() ?? 0,
      featured: data['featured'] == true,
      status: '${data['status'] ?? 'active'}'.trim(),
      verificationStatus: '${data['verificationStatus'] ?? 'unverified'}'
          .trim(),
      verified: data['verified'] == true,
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
      updatedAt: _dateFromValue(data['updatedAt']) ?? DateTime.now(),
    );
  }

  String _normalizedPlaceName(String placeId, Object? value) {
    final raw = '${value ?? 'Vennuzo place'}'.trim();
    final compact = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (placeId == 'gplus_nightclub' ||
        compact == 'g+' ||
        compact == 'gplus' ||
        compact == 'g+nightclub' ||
        compact == 'gplusnightclub') {
      return 'G+ Nightclub';
    }
    return raw.isEmpty ? 'Vennuzo place' : raw;
  }

  String _normalizedCreatorDisplayName(String creatorId, Object? value) {
    final raw = '${value ?? 'Vennuzo creator'}'.trim();
    final compact = raw.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (creatorId == 'gplus' ||
        compact == 'g+' ||
        compact == 'gplus' ||
        compact == 'g+nightclub' ||
        compact == 'gplusnightclub') {
      return 'G+ Nightclub';
    }
    return raw.isEmpty ? 'Vennuzo creator' : raw;
  }

  PlaceMenuSection? _placeMenuSectionFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final placeId = '${data['placeId'] ?? ''}'.trim();
    if (placeId.isEmpty) return null;
    return PlaceMenuSection(
      id: doc.id,
      placeId: placeId,
      name: '${data['name'] ?? 'Menu'}'.trim(),
      description: '${data['description'] ?? ''}'.trim(),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      visible: data['visible'] != false,
    );
  }

  PlaceMenuItem? _placeMenuItemFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final placeId = '${data['placeId'] ?? ''}'.trim();
    final sectionId = '${data['sectionId'] ?? ''}'.trim();
    if (placeId.isEmpty || sectionId.isEmpty) return null;
    return PlaceMenuItem(
      id: doc.id,
      placeId: placeId,
      sectionId: sectionId,
      name: '${data['name'] ?? 'Menu item'}'.trim(),
      description: '${data['description'] ?? ''}'.trim(),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      currency: '${data['currency'] ?? 'GHS'}'.trim(),
      imageUrl: _nullableTrim(data['imageUrl']),
      featured: data['featured'] == true,
      status: _placeMenuItemStatusFromValue(data['status']),
      options: _stringList(data['options']),
      tags: _stringList(data['tags']),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  PlaceReservation? _placeReservationFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final placeId = '${data['placeId'] ?? ''}'.trim();
    if (placeId.isEmpty) return null;
    return PlaceReservation(
      id: doc.id,
      placeId: placeId,
      placeName: '${data['placeName'] ?? data['targetTitle'] ?? 'Place'}'
          .trim(),
      userId: '${data['userId'] ?? ''}'.trim(),
      guestName: '${data['guestName'] ?? data['name'] ?? ''}'.trim(),
      phone: '${data['phone'] ?? ''}'.trim(),
      partySize: (data['partySize'] as num?)?.toInt() ?? 1,
      requestedAt: _dateFromValue(data['requestedAt']) ?? DateTime.now(),
      reservationType: _placeReservationTypeFromValue(data['reservationType']),
      status: _placeReservationStatusFromValue(data['status']),
      note: '${data['note'] ?? ''}'.trim(),
      internalNote: '${data['internalNote'] ?? ''}'.trim(),
      selectedMenuItemIds: _stringList(data['selectedMenuItemIds']),
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
      updatedAt: _dateFromValue(data['updatedAt']) ?? DateTime.now(),
    );
  }

  CreatorProfile? _creatorProfileFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }
    final metrics = data['metrics'];
    final creatorId = '${data['creatorId'] ?? doc.id}'.trim();
    return CreatorProfile(
      creatorId: creatorId,
      displayName: _normalizedCreatorDisplayName(
        creatorId,
        data['displayName'],
      ),
      bio: '${data['bio'] ?? ''}'.trim(),
      city: '${data['city'] ?? 'Accra'}'.trim(),
      avatarUrl: (data['avatarUrl'] as String?)?.trim(),
      coverUrl: (data['coverUrl'] as String?)?.trim(),
      followerCount: metrics is Map
          ? (metrics['followerCount'] as num?)?.toInt() ?? 0
          : 0,
      eventCount: metrics is Map
          ? (metrics['eventCount'] as num?)?.toInt() ?? 0
          : 0,
      photoCount: metrics is Map
          ? (metrics['photoCount'] as num?)?.toInt() ?? 0
          : 0,
      updatedAt: _dateFromValue(data['updatedAt']) ?? DateTime.now(),
    );
  }

  CreatorEventPhoto? _creatorPhotoFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      return null;
    }
    final creatorId = '${data['creatorId'] ?? ''}'.trim();
    final eventId = '${data['eventId'] ?? ''}'.trim();
    final imageUrl = '${data['imageUrl'] ?? ''}'.trim();
    if (creatorId.isEmpty || eventId.isEmpty || imageUrl.isEmpty) {
      return null;
    }
    return CreatorEventPhoto(
      id: doc.id,
      creatorId: creatorId,
      eventId: eventId,
      eventTitle: '${data['eventTitle'] ?? 'Event'}'.trim(),
      imageUrl: imageUrl,
      caption: '${data['caption'] ?? ''}'.trim(),
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
    );
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
    final discountVouchers =
        ticketing is Map && ticketing['discountVouchers'] is Iterable
        ? (ticketing['discountVouchers'] as Iterable)
              .whereType<Map>()
              .map(_discountVoucherFromMap)
              .whereType<EventDiscountVoucher>()
              .toList()
        : const <EventDiscountVoucher>[];
    final recurrence = data['recurrence'];
    final lineup = data['lineup'];
    final metrics = data['metrics'];
    final distribution = data['distribution'];
    final rawLocation = data['location'];
    final locationMap = rawLocation is Map ? rawLocation : const {};
    final latitude = _latitudeFromValue(rawLocation, data['latitude']);
    final longitude = _longitudeFromValue(rawLocation, data['longitude']);
    final addressText = '${data['addressText'] ?? locationMap['address'] ?? ''}'
        .trim();
    final placeId = '${data['placeId'] ?? locationMap['placeId'] ?? ''}'.trim();
    final tags =
        (data['tags'] as Iterable?)
            ?.map((value) => '$value')
            .where((value) => value.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final categoryId = EventTaxonomy.inferCategoryId(
      categoryId:
          '${data['categoryId'] ?? data['category'] ?? data['type'] ?? ''}',
      title: '${data['title'] ?? ''}',
      description: '${data['description'] ?? ''}',
      mood: '${data['mood'] ?? ''}',
      tags: tags,
    );
    final flyerAsset =
        '${data['flyerAsset'] ?? data['imageUrl'] ?? data['coverUrl'] ?? ''}'
            .trim();

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
        discountVouchers: discountVouchers,
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
      tags: tags,
      categoryId: categoryId,
      flyerAsset: flyerAsset.isEmpty ? null : flyerAsset,
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
    final rawAudienceSources = data['audienceSources'];
    final audienceSources = rawAudienceSources is Iterable
        ? rawAudienceSources
              .map((source) => '$source'.trim())
              .where((source) => source.isNotEmpty)
              .toList()
        : const <String>['event_rsvps', 'ticket_buyers'];

    return PromotionCampaign(
      id: doc.id,
      eventId: '${data['eventId'] ?? ''}'.trim(),
      eventTitle: '${data['eventTitle'] ?? ''}'.trim(),
      targetType: _promotionTargetTypeFromValue(data['targetType']),
      targetId: '${data['targetId'] ?? data['eventId'] ?? ''}'.trim(),
      targetTitle: '${data['targetTitle'] ?? data['eventTitle'] ?? ''}'.trim(),
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
      audienceSources: audienceSources,
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      message: '${data['message'] ?? ''}'.trim(),
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
      objective: _campaignObjectiveFromValue(data['objective']),
      audienceStrategy: _audienceStrategyFromValue(data['audienceStrategy']),
      optimizationGoal: _optimizationGoalFromValue(data['optimizationGoal']),
      bidStrategy: _bidStrategyFromValue(data['bidStrategy']),
      creativeMode: _creativeModeFromValue(data['creativeMode']),
      frequencyCap: (data['frequencyCap'] as num?)?.toInt() ?? 2,
      budgetCapGhs: (data['budgetCapGhs'] as num?)?.toDouble(),
    );
  }

  EventDiscountVoucher? _discountVoucherFromMap(Map<dynamic, dynamic> data) {
    final code = '${data['code'] ?? ''}'.trim();
    final value = (data['value'] as num?)?.toDouble() ?? 0;
    if (code.isEmpty || value <= 0) {
      return null;
    }
    return EventDiscountVoucher(
      code: code,
      type: _discountVoucherTypeFromValue(data['type']),
      value: value,
      maxRedemptions: (data['maxRedemptions'] as num?)?.toInt(),
      redeemedCount: (data['redeemedCount'] as num?)?.toInt() ?? 0,
      active: data['active'] != false,
      expiresAt: _dateFromValue(data['expiresAt']),
      note: (data['note'] as String?)?.trim(),
    );
  }

  String? _nullableTrim(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
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

  EventDiscountVoucherType _discountVoucherTypeFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'fixedamount' ||
      'fixed_amount' ||
      'amount' => EventDiscountVoucherType.fixedAmount,
      _ => EventDiscountVoucherType.percentage,
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

  PromotionTargetType _promotionTargetTypeFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'place' || 'venue' || 'location' => PromotionTargetType.place,
      _ => PromotionTargetType.event,
    };
  }

  CampaignObjective _campaignObjectiveFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'driversvps' || 'drive_rsvps' => CampaignObjective.driveRsvps,
      'filltables' || 'fill_tables' => CampaignObjective.fillTables,
      'boostawareness' || 'boost_awareness' => CampaignObjective.boostAwareness,
      'retargetinterest' ||
      'retarget_interest' => CampaignObjective.retargetInterest,
      'lastcall' || 'last_call' => CampaignObjective.lastCall,
      _ => CampaignObjective.sellTickets,
    };
  }

  AudienceStrategy _audienceStrategyFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'highintent' || 'high_intent' => AudienceStrategy.highIntent,
      'ownedcrm' || 'owned_crm' => AudienceStrategy.ownedCrm,
      'broaddiscovery' || 'broad_discovery' => AudienceStrategy.broadDiscovery,
      'retargeting' => AudienceStrategy.retargeting,
      _ => AudienceStrategy.recommended,
    };
  }

  OptimizationGoal _optimizationGoalFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'reach' => OptimizationGoal.reach,
      'clicks' => OptimizationGoal.clicks,
      'rsvps' => OptimizationGoal.rsvps,
      'tables' => OptimizationGoal.tables,
      _ => OptimizationGoal.conversions,
    };
  }

  BidStrategy _bidStrategyFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'lowestcost' || 'lowest_cost' => BidStrategy.lowestCost,
      'premiumattention' || 'premium_attention' => BidStrategy.premiumAttention,
      _ => BidStrategy.balanced,
    };
  }

  CreativeMode _creativeModeFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'abtest' || 'ab_test' => CreativeMode.abTest,
      _ => CreativeMode.single,
    };
  }

  PlaceMenuItemStatus _placeMenuItemStatusFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'soldout' || 'sold_out' => PlaceMenuItemStatus.soldOut,
      'hidden' => PlaceMenuItemStatus.hidden,
      _ => PlaceMenuItemStatus.available,
    };
  }

  PlaceReservationStatus _placeReservationStatusFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'confirmed' => PlaceReservationStatus.confirmed,
      'changerequested' ||
      'change_requested' => PlaceReservationStatus.changeRequested,
      'seated' => PlaceReservationStatus.seated,
      'cancelled' || 'canceled' => PlaceReservationStatus.cancelled,
      'noshow' || 'no_show' => PlaceReservationStatus.noShow,
      _ => PlaceReservationStatus.pending,
    };
  }

  PlaceReservationType _placeReservationTypeFromValue(Object? value) {
    return switch ('$value'.trim().toLowerCase()) {
      'viptable' || 'vip_table' => PlaceReservationType.vipTable,
      'guestlist' || 'guest_list' => PlaceReservationType.guestlist,
      'bottleservice' || 'bottle_service' => PlaceReservationType.bottleService,
      'privatebooking' ||
      'private_booking' => PlaceReservationType.privateBooking,
      _ => PlaceReservationType.table,
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
    _creatorFollowsSubscription?.cancel();
    _creatorProfilesSubscription?.cancel();
    _creatorPhotosSubscription?.cancel();
    _placesSubscription?.cancel();
    _placeMenuSectionsSubscription?.cancel();
    _placeMenuItemsSubscription?.cancel();
    _placeReservationsSubscription?.cancel();
    _placeSubscriptionsSubscription?.cancel();
    super.dispose();
  }
}
