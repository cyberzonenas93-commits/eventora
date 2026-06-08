import 'package:vennuzo/domain/models/account_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin-only account does not need workspace choice', () {
    const viewer = VennuzoViewer(
      displayName: 'Admin Only',
      isAuthenticated: true,
      roles: ['admin'],
      hasCustomerProfile: true,
      hasAdminProfile: true,
      adminRole: 'admin',
    );

    expect(viewer.hasAdminAccess, isTrue);
    expect(viewer.hasMainAppAccess, isFalse);
    expect(viewer.canChooseWorkspace, isFalse);
  });

  test('dual-role admin organizer account can choose a workspace', () {
    const viewer = VennuzoViewer(
      displayName: 'Dual Role',
      isAuthenticated: true,
      roles: ['admin', 'organizer'],
      hasCustomerProfile: true,
      hasAdminProfile: true,
      adminRole: 'superadmin',
      organizerApplicationStatus: OrganizerApplicationStatus.active,
    );

    expect(viewer.hasAdminAccess, isTrue);
    expect(viewer.hasOrganizerAccess, isTrue);
    expect(viewer.hasMainAppAccess, isTrue);
    expect(viewer.canChooseWorkspace, isTrue);
  });

  test('attendee organizer account can choose app or organizer portal', () {
    const viewer = VennuzoViewer(
      displayName: 'Host Guest',
      isAuthenticated: true,
      roles: ['attendee', 'organizer'],
      hasCustomerProfile: true,
      organizerApplicationStatus: OrganizerApplicationStatus.active,
    );

    expect(viewer.canUseAttendeeWorkspace, isTrue);
    expect(viewer.hasOrganizerAccess, isTrue);
    expect(viewer.hasAdminAccess, isFalse);
    expect(viewer.canChooseWorkspace, isTrue);
  });

  test('superadmin label requires explicit owner allow-list approval', () {
    const blocked = VennuzoViewer(
      displayName: 'Blocked',
      isAuthenticated: true,
      roles: ['admin', 'superadmin'],
      hasAdminProfile: true,
      adminRole: 'superadmin',
    );
    const allowed = VennuzoViewer(
      displayName: 'Allowed',
      isAuthenticated: true,
      roles: ['admin', 'superadmin'],
      hasAdminProfile: true,
      adminRole: 'superadmin',
      superAdminAllowed: true,
    );

    expect(blocked.hasAdminAccess, isTrue);
    expect(blocked.hasSuperAdminAccess, isFalse);
    expect(allowed.hasSuperAdminAccess, isTrue);
  });
}
