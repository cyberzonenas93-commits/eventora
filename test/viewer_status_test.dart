import 'package:eventora_app/domain/models/account_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventoraViewer organizer state', () {
    test('draft and rejected viewers can keep editing host access', () {
      const draftViewer = EventoraViewer(
        displayName: 'Draft Host',
        isAuthenticated: true,
        organizerApplicationStatus: OrganizerApplicationStatus.draft,
      );
      const rejectedViewer = EventoraViewer(
        displayName: 'Rejected Host',
        isAuthenticated: true,
        organizerApplicationStatus: OrganizerApplicationStatus.rejected,
      );

      expect(draftViewer.canStartOrganizerApplication, isTrue);
      expect(rejectedViewer.canStartOrganizerApplication, isTrue);
    });

    test('submitted and under-review viewers are treated as pending', () {
      const submittedViewer = EventoraViewer(
        displayName: 'Submitted Host',
        isAuthenticated: true,
        organizerApplicationStatus: OrganizerApplicationStatus.submitted,
      );
      const reviewingViewer = EventoraViewer(
        displayName: 'Reviewing Host',
        isAuthenticated: true,
        organizerApplicationStatus: OrganizerApplicationStatus.underReview,
      );

      expect(submittedViewer.hasPendingOrganizerApplication, isTrue);
      expect(reviewingViewer.hasPendingOrganizerApplication, isTrue);
      expect(submittedViewer.canStartOrganizerApplication, isFalse);
      expect(reviewingViewer.canStartOrganizerApplication, isFalse);
    });

    test('approved viewers gain organizer access', () {
      const approvedViewer = EventoraViewer(
        displayName: 'Approved Host',
        isAuthenticated: true,
        organizerApplicationStatus: OrganizerApplicationStatus.approved,
      );

      expect(approvedViewer.hasOrganizerAccess, isTrue);
      expect(approvedViewer.canStartOrganizerApplication, isFalse);
    });
  });
}
