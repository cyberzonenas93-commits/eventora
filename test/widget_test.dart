import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:eventora_app/app/eventora_app.dart';

void main() {
  testWidgets('Eventora shell renders the core navigation', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(const EventoraApp(firebaseEnabled: false));
    await tester.pumpAndSettle();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Promote'), findsOneWidget);
  });
}
