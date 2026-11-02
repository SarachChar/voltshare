import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/review_controller.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/station_detail_screen.dart';

import '../fakes/fake_review_service.dart';
import '../fakes/fake_station_service.dart';

void main() {
  const station = Station(
    id: 's1',
    name: 'Siam EV Hub',
    address: '1 Rama I Rd',
    latitude: 13.7,
    longitude: 100.5,
  );

  late FakeStationService stationService;
  late FakeReviewService reviewService;
  late StationController stationController;
  late List<Charger> booked;

  setUp(() {
    stationService = FakeStationService()
      ..chargers = [
        Charger('c1', 'Charger 1', 'DC', 'CCS2', 120, 8.5, 'available', 0, 0),
        Charger('c2', 'Charger 2', 'AC', 'Type 2', 7.4, 6.5, 'unavailable', 0,
            0),
      ]
      ..availability = {
        'c1': [
          for (var d = 0; d < 7; d++)
            ChargerAvailability(
              id: 'a$d',
              chargerId: 'c1',
              dayOfWeek: d,
              startTime: '08:00:00',
              endTime: '20:00:00',
            ),
        ],
      };
    reviewService = FakeReviewService()
      ..summary = const ChargerReviewSummary(averageRating: 4.5, reviewCount: 2);
    stationController = StationController(stationService);
    booked = [];
  });

  tearDown(() => stationController.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    // Tall surface so the whole Station info tab is laid out.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          station: station,
          controller: stationController,
          reviewController: ReviewController(reviewService),
          onBookCharger: (_, charger) => booked.add(charger),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every charger of the station with its specs',
      (tester) async {
    await pumpScreen(tester);

    expect(stationService.lastChargersStationId, 's1');
    expect(stationService.lastAvailabilityIds, ['c1', 'c2']);
    expect(reviewService.lastStationId, 's1');

    expect(find.text('Siam EV Hub'), findsOneWidget);
    expect(find.text('Charger 1'), findsOneWidget);
    expect(find.text('Charger 2'), findsOneWidget);
    expect(find.text('DC · CCS2 · 120 kW'), findsOneWidget);
    expect(find.text('AC · Type 2 · 7.4 kW'), findsOneWidget);
    expect(find.text('฿8.50/kWh'), findsOneWidget);
    // Stat chips are computed from the available chargers only.
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('120 kW'), findsOneWidget);
    expect(find.text('฿8.50'), findsOneWidget);
    // Station rating badge.
    expect(find.text('4.5'), findsOneWidget);
  });

  testWidgets('only available chargers can be booked', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('book-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-c2')), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('book-c1')));
    await tester.pump();

    expect(booked.map((c) => c.id), ['c1']);
  });

  testWidgets('hours show today, and the full week when expanded',
      (tester) async {
    await pumpScreen(tester);

    final c1Card = find.byKey(const ValueKey('charger-card-c1'));
    Finder inC1(Finder f) => find.descendant(of: c1Card, matching: f);

    expect(inC1(find.text('Today')), findsOneWidget);
    expect(inC1(find.text('08:00 - 20:00')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hours-toggle-c1')));
    await tester.pumpAndSettle();

    expect(inC1(find.text('08:00 - 20:00')), findsNWidgets(7));
    expect(inC1(find.text('Show less')), findsOneWidget);

    // Charger 2 has no rows: today shows as Closed and it stays collapsed.
    final c2Card = find.byKey(const ValueKey('charger-card-c2'));
    expect(
      find.descendant(of: c2Card, matching: find.text('Closed')),
      findsOneWidget,
    );
  });

  testWidgets('shows a retry message when chargers fail to load',
      (tester) async {
    stationService.error = Exception('network');
    await pumpScreen(tester);

    expect(find.text('Could not load the chargers.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
