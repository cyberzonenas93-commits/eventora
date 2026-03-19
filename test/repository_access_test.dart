import 'package:vennuzo/data/mock/mock_seed.dart';
import 'package:vennuzo/data/repositories/vennuzo_repository.dart';
import 'package:vennuzo/domain/models/account_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VennuzoRepository access scoping', () {
    test('guests do not see wallet or campaign data', () {
      final repository = VennuzoRepository.seeded(firebaseEnabled: false);

      expect(repository.orders, isEmpty);
      expect(repository.rsvps, isEmpty);
      expect(repository.campaigns, isEmpty);
    });

    test('attendees only see records explicitly owned by them', () {
      final repository = VennuzoRepository.seeded(firebaseEnabled: false);
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
      final repository = VennuzoRepository.seeded(firebaseEnabled: false);
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

    test('admins retain full visibility', () {
      final repository = VennuzoRepository.seeded(firebaseEnabled: false);
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
  });
}
