import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/add_charger_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// Records create / update / hours calls; anything else throws.
class _FakeChargerService implements ChargerService {
  final List<Map<String, Object?>> creates = [];
  final List<Map<String, Object?>> updates = [];
  int hourWrites = 0;

  @override
  Future<List<ChargerAvailability>> getChargerAvailability(
    String chargerId,
  ) async =>
      const [];

  @override
  Future<Charger> createCharger({
    required String stationId,
    required String name,
    String chargerType = '',
    String connectorType = '',
    double powerKw = 0.0,
    double pricePerKwh = 0.0,
    String status = 'review',
  }) async {
    creates.add({
      'stationId': stationId,
      'name': name,
      'chargerType': chargerType,
      'connectorType': connectorType,
      'powerKw': powerKw,
      'pricePerKwh': pricePerKwh,
      'status': status,
    });
    return Charger('new', name, chargerType, connectorType, powerKw,
        pricePerKwh, status);
  }

  @override
  Future<Charger> updateCharger({
    required String chargerId,
    required String name,
    required double pricePerKwh,
    String? chargerType,
    String? connectorType,
    double? powerKw,
  }) async {
    updates.add({
      'chargerId': chargerId,
      'name': name,
      'pricePerKwh': pricePerKwh,
      'chargerType': chargerType,
      'connectorType': connectorType,
      'powerKw': powerKw,
    });
    return Charger(chargerId, name, 'DC', 'CCS2', 120, pricePerKwh,
        'available');
  }

  @override
  Future<void> insertChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) async =>
      hourWrites++;

  @override
  Future<void> replaceChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) async =>
      hourWrites++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  const station = Station(
    id: 's1',
    name: 'Siam EV Hub',
    latitude: 13.7,
    longitude: 100.5,
  );

  late _FakeChargerService service;

  setUp(() => service = _FakeChargerService());

  Future<void> pump(WidgetTester tester, {Charger? initial}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AddChargerScreen(
          station: station,
          controller: ChargerController(service),
          initialCharger: initial,
          existingChargerCount: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Info -> Pricing -> Hours -> submit -> confirm.
  Future<void> continueToEndAndConfirm(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('charger-continue')));
      await tester.pumpAndSettle();
    }
    // The confirm dialog's primary button ("Submit" / "Save").
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('has 3 steps and no location / photo fields', (tester) async {
    await pump(tester);

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Pricing'), findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
    expect(find.text('Business'), findsNothing);
    expect(find.text('PIN LOCATION'), findsNothing);
    expect(find.text('PHOTOS'), findsNothing);
    expect(find.text('ADDRESS'), findsNothing);
    expect(find.textContaining('Siam EV Hub'), findsOneWidget);
  });

  testWidgets('create with a blank name uses "Charger N" in the station',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('DC'));
    await tester.tap(find.text('CCS2'));
    await tester.enterText(find.byKey(const ValueKey('charger-power')), '60');
    await tester.pumpAndSettle();
    await continueToEndAndConfirm(tester);

    expect(service.creates, hasLength(1));
    expect(service.creates.single, {
      'stationId': 's1',
      'name': 'Charger 3',
      'chargerType': 'DC',
      'connectorType': 'CCS2',
      'powerKw': 60.0,
      'pricePerKwh': 8.0,
      'status': 'review',
    });
    expect(service.hourWrites, 1);
  });

  testWidgets('a live charger has locked specs and saves them as null',
      (tester) async {
    await pump(
      tester,
      initial:
          Charger('c1', 'Charger 1', 'DC', 'CCS2', 120, 8.5, 'available'),
    );

    expect(find.byKey(const ValueKey('specs-locked')), findsOneWidget);
    final power =
        tester.widget<TextField>(find.byKey(const ValueKey('charger-power')));
    expect(power.enabled, isFalse);

    // Tapping another type does nothing while locked.
    await tester.tap(find.text('AC'));
    await tester.enterText(find.byKey(const ValueKey('charger-name')), 'Fast A');
    await tester.pumpAndSettle();
    await continueToEndAndConfirm(tester);

    expect(service.updates.single, {
      'chargerId': 'c1',
      'name': 'Fast A',
      'pricePerKwh': 8.5,
      'chargerType': null,
      'connectorType': null,
      'powerKw': null,
    });
    expect(service.hourWrites, 1);
  });

  testWidgets('a pending charger can still change its specs', (tester) async {
    await pump(
      tester,
      initial:
          Charger('c2', 'Charger 2', 'AC', 'Type 2', 7.4, 6.5, 'review'),
    );

    expect(find.byKey(const ValueKey('specs-locked')), findsNothing);
    await tester.tap(find.text('DC'));
    await tester.pumpAndSettle();
    await continueToEndAndConfirm(tester);

    final update = service.updates.single;
    expect(update['chargerType'], 'DC');
    expect(update['connectorType'], 'Type 2');
    expect(update['powerKw'], 7.4);
    expect(update['name'], 'Charger 2'); // blank field keeps the old name
  });
}
