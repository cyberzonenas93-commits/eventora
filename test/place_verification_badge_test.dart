import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vennuzo/core/theme/vennuzo_theme.dart';
import 'package:vennuzo/domain/models/place_models.dart';
import 'package:vennuzo/widgets/place_verification_badge.dart';

PlaceProfile _place({
  required String verificationStatus,
  required bool verified,
}) {
  final now = DateTime(2026, 1, 1);
  return PlaceProfile(
    id: 'place_1',
    name: 'Test Venue',
    description: '',
    city: 'Accra',
    address: 'Somewhere',
    verificationStatus: verificationStatus,
    verified: verified,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpBadge(WidgetTester tester, PlaceProfile place) {
  return tester.pumpWidget(
    MaterialApp(
      theme: VennuzoTheme.lightTheme,
      home: Scaffold(body: Center(child: PlaceVerificationBadge(place: place))),
    ),
  );
}

void main() {
  group('PlaceVerificationBadge', () {
    testWidgets('shows Verified for a verified place', (tester) async {
      await _pumpBadge(
        tester,
        _place(verificationStatus: 'verified', verified: true),
      );

      expect(find.text('Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('shows In review for a pending place', (tester) async {
      await _pumpBadge(
        tester,
        _place(verificationStatus: 'pending_review', verified: false),
      );

      expect(find.text('In review'), findsOneWidget);
    });

    testWidgets('shows Unverified otherwise', (tester) async {
      await _pumpBadge(
        tester,
        _place(verificationStatus: 'unverified', verified: false),
      );

      expect(find.text('Unverified'), findsOneWidget);
    });

    testWidgets('treats verified flag as verified even when status lags', (
      tester,
    ) async {
      await _pumpBadge(
        tester,
        _place(verificationStatus: 'unverified', verified: true),
      );

      expect(find.text('Verified'), findsOneWidget);
    });
  });
}
