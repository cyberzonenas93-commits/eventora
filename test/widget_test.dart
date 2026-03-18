import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:eventora_app/app/eventora_app.dart';

void main() {
  testWidgets('Eventora shell renders the core navigation', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(
      const EventoraApp(
        firebaseEnabled: false,
        skipLaunchOnboarding: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final navigationBar = find.byType(BottomNavigationBar);

    expect(
      find.descendant(of: navigationBar, matching: find.text('Explore')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('Host')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('Passes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigationBar, matching: find.text('Reach')),
      findsOneWidget,
    );
  });
}
