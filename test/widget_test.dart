import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:vennuzo/app/vennuzo_app.dart';
import 'package:vennuzo/app/vennuzo_session_controller.dart';
import 'package:vennuzo/core/theme/vennuzo_theme.dart';
import 'package:vennuzo/core/art/event_art_widget.dart';
import 'package:vennuzo/data/mock/mock_seed.dart';
import 'package:vennuzo/data/repositories/vennuzo_repository.dart';
import 'package:vennuzo/domain/models/account_models.dart';
import 'package:vennuzo/domain/models/event_models.dart';
import 'package:vennuzo/features/admin/admin_face_chooser_screen.dart';
import 'package:vennuzo/features/discover/discover_screen.dart';
import 'package:vennuzo/features/onboarding/vennuzo_onboarding_screen.dart';
import 'package:vennuzo/features/places/places_screen.dart';
import 'package:vennuzo/features/shell/vennuzo_shell_screen.dart';
import 'package:vennuzo/widgets/event_card.dart';

void main() {
  testWidgets('Vennuzo shell renders the core navigation', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(
      const VennuzoApp(firebaseEnabled: false, skipLaunchOnboarding: true),
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

  testWidgets('Explore search keeps full typed query', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(
      const VennuzoApp(firebaseEnabled: false, skipLaunchOnboarding: true),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.enterText(find.byType(TextField).first, 'test');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Results for "test"'), findsOneWidget);
  });

  testWidgets('Calendar day tap scrolls selected events into view', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = VennuzoRepository.withFixtures(
      events: MockSeed.events(),
      creatorProfiles: MockSeed.creatorProfiles(),
      creatorPhotos: MockSeed.creatorPhotos(),
      campaigns: MockSeed.campaigns(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<VennuzoRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: VennuzoTheme.lightTheme,
          home: const Scaffold(body: DiscoverScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    final scrollable = find.byType(ListView).first;
    await tester.dragUntilVisible(
      find.text('Calendar'),
      scrollable,
      const Offset(0, -260),
    );
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    final targetEvent = MockSeed.events().firstWhere(
      (event) => event.id == 'event_after_dark',
    );
    await tester.tap(find.text('${targetEvent.startDate.day}').first);
    await tester.pumpAndSettle();

    final eventTitle = find.text('Pulse Summit After Dark').first;
    expect(eventTitle, findsOneWidget);
    final bounds = tester.getRect(eventTitle);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
  });

  testWidgets('Onboarding adapts to small screens without overflow', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: VennuzoTheme.lightTheme,
        home: VennuzoOnboardingScreen(onFinished: (_) async {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Workspace chooser uses readable text on its light card', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<VennuzoSessionController>.value(
        value: _TestWorkspaceSessionController(),
        child: MaterialApp(
          theme: VennuzoTheme.lightTheme,
          home: const AdminFaceChooserScreen(),
        ),
      ),
    );

    final heading = tester.widget<Text>(find.text('Welcome back, Dual Role.'));
    final appTile = tester.widget<Text>(find.text('Vennuzo app'));
    final organizerTile = tester.widget<Text>(find.text('Organizer portal'));
    final adminTile = tester.widget<Text>(find.text('Superadmin console'));

    expect(heading.style?.color, const Color(0xFF09111F));
    expect(appTile.style?.color, const Color(0xFF09111F));
    expect(organizerTile.style?.color, const Color(0xFF09111F));
    expect(adminTile.style?.color, const Color(0xFF09111F));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizer workspace adapts to small screens without overflow', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = _OrganizerWorkspaceSessionController();
    final repository = VennuzoRepository.seeded(firebaseEnabled: false)
      ..applyViewer(session.viewer);

    await tester.pumpWidget(
      ChangeNotifierProvider<VennuzoSessionController>.value(
        value: session,
        child: ChangeNotifierProvider<VennuzoRepository>.value(
          value: repository,
          child: MaterialApp(
            theme: VennuzoTheme.lightTheme,
            home: const VennuzoShellScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.text('Event Ops'),
      find.byType(ListView).first,
      const Offset(0, -180),
    );
    expect(find.text('Open Event Ops'), findsOneWidget);

    for (final tab in const ['Events', 'Promote']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Place events show flyers and expose RSVP ticket actions', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 920);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final baseEvent = MockSeed.events().first;
    final placeEvent = baseEvent.copyWith(
      id: 'gplus_place_event_test',
      title: 'G+ Nightclub Test Event',
      venue: 'G+ Nightclub',
      city: 'Accra',
      flyerAsset: 'assets/event_flyers/event_after_dark.png',
      location: const EventLocation(
        address: 'UPSA Road, Accra',
        latitude: 5.6503,
        longitude: -0.1602,
        placeId: MockSeed.gplusPlaceId,
      ),
      ticketing: baseEvent.ticketing.copyWith(
        enabled: true,
        requireTicket: true,
      ),
    );
    final repository = VennuzoRepository.withFixtures(
      events: [placeEvent],
      places: MockSeed.places(),
      placeMenuSections: MockSeed.placeMenuSections(),
      placeMenuItems: MockSeed.placeMenuItems(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<VennuzoSessionController>.value(
        value: VennuzoSessionController(firebaseEnabled: false),
        child: ChangeNotifierProvider<VennuzoRepository>.value(
          value: repository,
          child: MaterialApp(
            theme: VennuzoTheme.lightTheme,
            home: const PlaceDetailScreen(placeId: MockSeed.gplusPlaceId),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('G+ Nightclub Test Event'), findsOneWidget);
    expect(find.byType(EventArtwork), findsWidgets);
    expect(find.text('Get tickets'), findsOneWidget);

    final eventCard = tester.widget<EventCard>(find.byType(EventCard).first);
    final ticketButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Get tickets'),
    );

    expect(eventCard.onTap, isNotNull);
    expect(ticketButton.onPressed, isNotNull);
  });

  testWidgets('Sold-out place event shows a disabled Sold out action', (
    WidgetTester tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 920);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final baseEvent = MockSeed.events().first;
    final soldOutEvent = baseEvent.copyWith(
      id: 'gplus_place_event_soldout',
      title: 'Sold Out Night',
      venue: 'G+ Nightclub',
      city: 'Accra',
      flyerAsset: 'assets/event_flyers/event_after_dark.png',
      location: const EventLocation(
        address: 'UPSA Road, Accra',
        latitude: 5.6503,
        longitude: -0.1602,
        placeId: MockSeed.gplusPlaceId,
      ),
      ticketing: baseEvent.ticketing.copyWith(
        enabled: true,
        requireTicket: true,
        tiers: const [
          TicketTier(
            tierId: 'ga',
            name: 'General',
            price: 50,
            maxQuantity: 10,
            sold: 10,
          ),
        ],
      ),
    );
    final repository = VennuzoRepository.withFixtures(
      events: [soldOutEvent],
      places: MockSeed.places(),
      placeMenuSections: MockSeed.placeMenuSections(),
      placeMenuItems: MockSeed.placeMenuItems(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<VennuzoSessionController>.value(
        value: VennuzoSessionController(firebaseEnabled: false),
        child: ChangeNotifierProvider<VennuzoRepository>.value(
          value: repository,
          child: MaterialApp(
            theme: VennuzoTheme.lightTheme,
            home: const PlaceDetailScreen(placeId: MockSeed.gplusPlaceId),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Sold out'), findsOneWidget);
    expect(find.text('Get tickets'), findsNothing);

    final soldOutButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sold out'),
    );
    expect(soldOutButton.onPressed, isNull);
  });

  testWidgets(
    'Unknown place shows a recoverable not-found screen with an app bar',
    (WidgetTester tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;

      final repository = VennuzoRepository.withFixtures(
        events: const [],
        places: MockSeed.places(),
        placeMenuSections: MockSeed.placeMenuSections(),
        placeMenuItems: MockSeed.placeMenuItems(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<VennuzoSessionController>.value(
          value: VennuzoSessionController(firebaseEnabled: false),
          child: ChangeNotifierProvider<VennuzoRepository>.value(
            value: repository,
            child: MaterialApp(
              theme: VennuzoTheme.lightTheme,
              home: const PlaceDetailScreen(placeId: 'missing_place_id'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Place not found'), findsOneWidget);
    },
  );
}

class _TestWorkspaceSessionController extends VennuzoSessionController {
  _TestWorkspaceSessionController() : super(firebaseEnabled: false);

  @override
  VennuzoViewer get viewer => const VennuzoViewer(
    displayName: 'Dual Role',
    isAuthenticated: true,
    roles: ['admin', 'attendee', 'organizer'],
    hasCustomerProfile: true,
    hasAdminProfile: true,
    adminRole: 'superadmin',
    superAdminAllowed: true,
    organizerApplicationStatus: OrganizerApplicationStatus.active,
  );

  @override
  void enterAttendeeWorkspace() {}

  @override
  void enterOrganizerWorkspace() {}

  @override
  void enterAdminWorkspace() {}
}

class _OrganizerWorkspaceSessionController extends VennuzoSessionController {
  _OrganizerWorkspaceSessionController() : super(firebaseEnabled: false);

  @override
  VennuzoViewer get viewer => const VennuzoViewer(
    uid: 'organizer_angel',
    displayName: 'Organizer With A Long Workspace Name',
    email: 'organizer-with-a-very-long-email-address@vennuzo.test',
    phone: '+233 59 549 4113',
    isAuthenticated: true,
    roles: ['attendee', 'organizer'],
    activeFace: VennuzoWorkspaceFace.organizer,
    hasCustomerProfile: true,
    organizerApplicationStatus: OrganizerApplicationStatus.active,
    defaultOrganizationId: 'org_organizer_angel',
  );

  @override
  bool get isGuest => false;

  @override
  bool get isOrganizerWorkspace => true;

  @override
  bool get canChooseWorkspace => true;

  @override
  void openWorkspaceChooser() {}
}
