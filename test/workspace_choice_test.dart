import 'package:eventora_app/domain/models/account_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin-only account does not need workspace choice', () {
    const viewer = EventoraViewer(
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
    const viewer = EventoraViewer(
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
}
