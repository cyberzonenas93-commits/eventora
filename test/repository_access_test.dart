import 'package:vennuzo/data/mock/mock_seed.dart';
import 'package:vennuzo/data/repositories/vennuzo_repository.dart';
import 'package:vennuzo/domain/models/account_models.dart';
import 'package:vennuzo/domain/models/place_models.dart';
import 'package:vennuzo/domain/models/promotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

VennuzoRepository fixtureRepository() => VennuzoRepository.withFixtures(
  events: MockSeed.events(),
  orders: MockSeed.orders(),
  rsvps: MockSeed.rsvps(),
  campaigns: MockSeed.campaigns(),
  creatorProfiles: MockSeed.creatorProfiles(),
  creatorPhotos: MockSeed.creatorPhotos(),
  places: MockSeed.places(),
  placeMenuSections: MockSeed.placeMenuSections(),
  placeMenuItems: MockSeed.placeMenuItems(),
  placeReservations: MockSeed.placeReservations(),
);

void main() {
  group('VennuzoRepository access scoping', () {
    test('guests do not see wallet or campaign data', () {
      final repository = fixtureRepository();

      expect(repository.orders, isEmpty);
      expect(repository.rsvps, isEmpty);
      expect(repository.campaigns, isEmpty);
    });

    test('attendees only see records explicitly owned by them', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: 'attendee_001',
        displayName: 'Ama Owusu',
        email: 'ama@example.com',
        phone: '+23350111222',
        isAuthenticated: true,
        roles: ['attendee'],
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);

      expect(repository.orders, isEmpty);
      expect(repository.rsvps, isEmpty);
      expect(repository.campaigns, isEmpty);

      final event = repository.discoverableEvents.first;
      repository.createRsvp(
        eventId: event.id,
        eventTitle: event.title,
        name: viewer.displayName,
        phone: viewer.phone!,
        guestCount: 2,
        bookTable: false,
      );
      repository.checkout(
        event: event,
        selections: {event.ticketing.tiers.first.tierId: 1},
      );

      expect(repository.rsvps, hasLength(1));
      expect(repository.rsvps.single.attendeeUserId, viewer.uid);
      expect(repository.orders, hasLength(1));
      expect(repository.orders.single.buyerUserId, viewer.uid);
    });

    test('organizers see hosted event commerce and campaign data', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: MockSeed.organizerId,
        displayName: MockSeed.organizerName,
        email: MockSeed.organizerEmail,
        phone: MockSeed.organizerPhone,
        isAuthenticated: true,
        roles: ['attendee', 'organizer'],
        organizerApplicationStatus: OrganizerApplicationStatus.approved,
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);

      expect(repository.orders, hasLength(2));
      expect(repository.rsvps, hasLength(1));
      expect(repository.campaigns, hasLength(3));
    });

    test('organizers can schedule featured place campaigns', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: MockSeed.organizerId,
        displayName: MockSeed.organizerName,
        email: MockSeed.organizerEmail,
        phone: MockSeed.organizerPhone,
        isAuthenticated: true,
        roles: ['attendee', 'organizer'],
        organizerApplicationStatus: OrganizerApplicationStatus.approved,
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);

      final campaign = repository.schedulePlaceCampaign(
        placeId: 'gplus_nightclub',
        placeTitle: 'G+Nightclub',
        name: 'G+Nightclub featured place',
        scheduledAt: null,
        channels: const [PromotionChannel.featured, PromotionChannel.shareLink],
        budget: 150,
        message: 'Feature G+Nightclub in Places.',
      );

      expect(campaign.targetType, PromotionTargetType.place);
      expect(campaign.targetLabel, 'Place: G+Nightclub');
      expect(repository.featuredPlaceCampaigns, contains(campaign));
    });

    test('attendees can subscribe to places and create reservations', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: 'attendee_places_001',
        displayName: 'Places Tester',
        email: 'places@example.com',
        phone: '+233501112233',
        isAuthenticated: true,
        roles: ['attendee'],
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);

      final place = repository.placeById(MockSeed.gplusPlaceId);
      expect(place, isNotNull);
      expect(repository.menuItemsForPlace(MockSeed.gplusPlaceId), isNotEmpty);

      repository.subscribeToPlace(MockSeed.gplusPlaceId);
      expect(repository.isSubscribedToPlace(MockSeed.gplusPlaceId), isTrue);

      final reservation = repository.createPlaceReservation(
        PlaceReservationRequest(
          placeId: MockSeed.gplusPlaceId,
          placeName: 'G+Nightclub',
          reservationType: PlaceReservationType.vipTable,
          guestName: viewer.displayName,
          phone: viewer.phone!,
          partySize: 4,
          requestedAt: DateTime.now().add(const Duration(days: 1)),
          selectedMenuItemIds: const ['gplus_hennessy_vip'],
        ),
      );

      expect(reservation.status, PlaceReservationStatus.pending);
      expect(repository.myPlaceReservations, contains(reservation));
    });

    test('admins retain full visibility', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: 'admin_001',
        displayName: 'Console Admin',
        email: 'admin@vennuzo.app',
        isAuthenticated: true,
        roles: ['admin'],
        hasAdminProfile: true,
      );
      repository.applyViewer(viewer);

      expect(repository.orders, hasLength(2));
      expect(repository.rsvps, hasLength(1));
      expect(repository.campaigns, hasLength(3));
    });

    test('attendees see events from creators they follow', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: 'attendee_follow_001',
        displayName: 'Follow Tester',
        email: 'follow@example.com',
        isAuthenticated: true,
        roles: ['attendee'],
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);

      expect(repository.followedCreatorEvents, isEmpty);

      repository.followCreator(MockSeed.cultureCreatorId);

      expect(
        repository.followedCreatorEvents.map((event) => event.id),
        contains('event_market'),
      );

      repository.unfollowCreator(MockSeed.cultureCreatorId);

      expect(repository.followedCreatorEvents, isEmpty);
    });

    test('G+ creator fallback uses G+ branding', () {
      final repository = VennuzoRepository.withFixtures();

      final profile = repository.creatorProfileFor('gplus');

      expect(profile.displayName, 'G+ Nightclub');
      expect(profile.bio, contains('G+ Nightclub events'));
    });

    test('checkout applies discount vouchers and redeems the code', () {
      final repository = fixtureRepository();
      const viewer = VennuzoViewer(
        uid: 'attendee_discount_001',
        displayName: 'Discount Tester',
        email: 'discount@example.com',
        phone: '+233501234567',
        isAuthenticated: true,
        roles: ['attendee'],
        hasCustomerProfile: true,
      );
      repository.applyViewer(viewer);
      final event = repository.eventById('event_after_dark')!;

      final order = repository.checkout(
        event: event,
        selections: const {'early': 1},
        discountCode: 'pulse25',
      );

      expect(order.discount?.code, 'PULSE25');
      expect(order.discountAmount, 25);
      expect(order.totalAmount, 95);

      final updatedEvent = repository.eventById('event_after_dark')!;
      final redeemedVoucher = updatedEvent.ticketing.voucherByCode('PULSE25')!;
      expect(redeemedVoucher.redeemedCount, 1);
    });
  });
}
