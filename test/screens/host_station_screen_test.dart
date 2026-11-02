import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/host_station_screen.dart';

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
  late StationController controller;

  setUp(() {
    service = FakeStationService()
      ..allChargers = [
        Charger('c1', 'Charger 1', 'DC', 'CCS2', 120, 8.5, 'available', 0, 0),
        Charger('c2', 'Charger 2', 'AC', 'Type 2', 7.4, 6.5, 'review', 0, 0),
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
    controller = StationController(service);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<Station?> Function(BuildContext, Station)? openEdit,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HostStationScreen(
          station: station,
          controller: controller,
          openEditStation: openEdit,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the station, every charger with its status',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Siam EV Hub'), findsOneWidget);
    expect(find.text('1 Rama I Rd'), findsOneWidget);
    expect(find.byKey(const ValueKey('host-charger-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('host-charger-c2')), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget);
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
  });
}
