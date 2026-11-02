import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/host_revenue_controller.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/host_station_screen.dart';

import '../fakes/fake_charger_service.dart';
import '../fakes/fake_station_service.dart';

void main() {
  const station = Station(
    id: 's1',
    name: 'Siam EV Hub',
    address: '1 Rama I Rd',
    latitude: 13.7,
    longitude: 100.5,
  );

  late FakeStationService service;
  late FakeChargerService chargerService;
  late FakeHostRevenueService revenueService;
  late StationController controller;
  late int changedCalls;

  setUp(() {
    service = FakeStationService()
      ..allChargers = [
        Charger('c1', 'Charger 1', 'DC', 'CCS2', 120, 8.5, 'available', 0, 0),
        Charger('c2', 'Charger 2', 'AC', 'Type 2', 7.4, 6.5, 'review', 0, 0),
        Charger('c3', 'Charger 3', 'AC', 'Type 2', 22, 7, 'unavailable', 0, 0),
      ]
      ..promotions = const [
        StationPromotion(
          id: 'p1',
          stationId: 's1',
          title: 'Free coffee',
          status: 'ACTIVE',
        ),
        StationPromotion(
          id: 'p2',
          stationId: 's1',
          title: 'Old deal',
          status: 'EXPIRED',
        ),
      ];
    chargerService = FakeChargerService();
    revenueService = FakeHostRevenueService(
      HostRevenue(
        month: DateTime(2026, 11),
        summary: const RevenueSummary(),
        byCharger: [
          ChargerRevenue(
            chargerId: 'c1',
            name: 'Charger 1',
            sessions: 4,
            gross: 1200,
            net: 1020,
          ),
        ],
        monthly: const [],
      ),
    );
    controller = StationController(service);
    changedCalls = 0;
  });

  tearDown(() => controller.dispose());

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<Station?> Function(BuildContext, Station)? openEdit,
    Future<Charger?> Function(BuildContext, Station, Charger?, int)?
        openChargerForm,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HostStationScreen(
          station: station,
          controller: controller,
          chargerController: ChargerController(chargerService),
          revenueController: HostRevenueController(revenueService),
          openEditStation: openEdit,
          openChargerForm: openChargerForm,
          onChanged: () => changedCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inCard(String chargerId, Finder f) => find.descendant(
        of: find.byKey(ValueKey('host-charger-$chargerId')),
        matching: f,
      );

  testWidgets('shows the station and every charger', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Siam EV Hub'), findsOneWidget);
    expect(find.text('1 Rama I Rd'), findsOneWidget);
    for (final id in ['c1', 'c2', 'c3']) {
      expect(find.byKey(ValueKey('host-charger-$id')), findsOneWidget);
    }
  });

  testWidgets('live chargers get a switch; pending ones a badge',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('charger-switch-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('charger-switch-c3')), findsOneWidget);
    expect(find.byKey(const ValueKey('charger-switch-c2')), findsNothing);
    expect(inCard('c2', find.text('In review')), findsOneWidget);

    Switch sw(String id) =>
        tester.widget<Switch>(find.byKey(ValueKey('charger-switch-$id')));
    expect(sw('c1').value, isTrue);
    expect(sw('c3').value, isFalse);
  });

  testWidgets('toggling a live charger saves its new status', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('charger-switch-c1')));
    await tester.pumpAndSettle();

    expect(chargerService.statusUpdates, ['c1 unavailable']);
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('charger-switch-c1')))
          .value,
      isFalse,
    );
    expect(changedCalls, 1);
  });

  testWidgets('a failed toggle rolls the switch back', (tester) async {
    chargerService.statusError = Exception('network');
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('charger-switch-c3')));
    await tester.pumpAndSettle();

    expect(chargerService.statusUpdates, ['c3 available']);
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('charger-switch-c3')))
          .value,
      isFalse,
    );
    expect(changedCalls, 0);
  });

  testWidgets('live cards show this month revenue; pending cards do not',
      (tester) async {
    await pumpScreen(tester);

    expect(inCard('c1', find.text('4')), findsOneWidget);
    expect(inCard('c1', find.text('฿1,200')), findsOneWidget);
    expect(inCard('c1', find.text('฿1,020')), findsOneWidget);
    // Live but no revenue this month: zeros.
    expect(inCard('c3', find.text('0')), findsOneWidget);
    // Pending: no metrics row at all.
    expect(inCard('c2', find.text('SESSIONS')), findsNothing);
    expect(find.text('Figures for Nov 2026'), findsOneWidget);
  });

  testWidgets('Add Charger opens the form with the current count, then '
      'reloads and reports the change', (tester) async {
    Charger? passedCharger;
    int? passedCount;
    await pumpScreen(
      tester,
      openChargerForm: (_, s, charger, count) async {
        passedCharger = charger;
        passedCount = count;
        return Charger('c4', 'Charger 4', 'AC', 'Type 2', 7, 7, 'review', 0, 0);
      },
    );

    service.allChargers = [
      ...service.allChargers,
      Charger('c4', 'Charger 4', 'AC', 'Type 2', 7, 7, 'review', 0, 0),
    ];
    await tester.tap(find.byKey(const ValueKey('add-charger')));
    await tester.pumpAndSettle();

    expect(passedCharger, isNull);
    expect(passedCount, 3);
    expect(find.byKey(const ValueKey('host-charger-c4')), findsOneWidget);
    expect(changedCalls, 1);
  });

  testWidgets('Edit on a charger opens the form for that charger',
      (tester) async {
    Charger? passedCharger;
    await pumpScreen(
      tester,
      openChargerForm: (_, s, charger, count) async {
        passedCharger = charger;
        return null; // cancelled
      },
    );

    await tester.tap(find.byKey(const ValueKey('edit-charger-c3')));
    await tester.pumpAndSettle();

    expect(passedCharger?.id, 'c3');
    expect(changedCalls, 0);
  });

  testWidgets('promotions: active has a switch, expired shows a badge',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Free coffee'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-switch-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-switch-p2')), findsNothing);
    expect(find.text('EXPIRED'), findsOneWidget);
  });

  testWidgets('turning a promotion off saves INACTIVE', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('promo-switch-p1')));
    await tester.pumpAndSettle();

    expect(service.writes, contains('updatePromotionStatus: p1 INACTIVE'));
    final sw =
        tester.widget<Switch>(find.byKey(const ValueKey('promo-switch-p1')));
    expect(sw.value, isFalse);
  });

  testWidgets('deleting a promotion asks first, then removes it',
      (tester) async {
    await pumpScreen(tester);

    final promoTile = find.byKey(const ValueKey('promo-p1'));
    await tester.tap(
      find.descendant(of: promoTile, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete promotion?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(service.writes, contains('deletePromotion: p1'));
    expect(find.text('Free coffee'), findsNothing);
  });

  testWidgets('edit updates the header with the saved station',
      (tester) async {
    await pumpScreen(
      tester,
      openEdit: (_, current) async =>
          current.copyWith(name: 'Siam EV Hub 2', address: '2 New Rd'),
    );

    await tester.tap(find.byKey(const ValueKey('edit-station')));
    await tester.pumpAndSettle();

    expect(find.text('Siam EV Hub 2'), findsOneWidget);
    expect(find.text('2 New Rd'), findsOneWidget);
    expect(changedCalls, 1);
  });
}
