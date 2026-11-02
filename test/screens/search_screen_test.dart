import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/search_screen.dart';

import '../fakes/fake_station_service.dart';

Station _station(int i) => Station(
      id: 's$i',
      name: 'Station $i',
      address: '$i Test Rd',
      latitude: 13.7,
      longitude: 100.5,
      distanceMeters: 100.0 * i,
      chargerCount: 3,
      availableCount: 2,
      connectorTypes: const ['CCS2', 'Type 2'],
      minPrice: 7.5,
      maxPowerKw: 120,
    );

void main() {
  late FakeStationService service;
  late StationController controller;
  final userLocation = ValueNotifier<LatLng?>(const LatLng(13.75, 100.53));

  setUp(() {
    service = FakeStationService();
    controller = StationController(service);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(controller: controller, userLocation: userLocation),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first query uses the user location and no filters',
      (tester) async {
    service.searchPages = {0: [_station(1)]};
    await pumpSearch(tester);

    expect(service.searchCalls, hasLength(1));
    expect(service.searchCalls.single, {
      'userLat': 13.75,
      'userLng': 100.53,
      'query': null,
      'chargerType': null,
      'connectorType': null,
      'powerMin': null,
      'powerMax': null,
      'limit': 20,
      'offset': 0,
    });
  });

  testWidgets('renders a station card with its summary', (tester) async {
    service.searchPages = {0: [_station(1)]};
    await pumpSearch(tester);

    expect(find.text('Find Stations'), findsOneWidget);
    expect(find.text('Station 1'), findsOneWidget);
    expect(find.text('1 Test Rd · 100 m'), findsOneWidget);
    expect(find.text('CCS2'), findsOneWidget);
    expect(find.text('Type 2'), findsOneWidget);
    expect(find.text('2/3 available · up to 120 kW'), findsOneWidget);
    expect(find.text('from ฿7.50/kWh'), findsOneWidget);
    expect(find.text('1 station found', findRichText: true), findsOneWidget);
  });

  testWidgets('applying filters sends them to the search', (tester) async {
    service.searchPages = {0: [_station(1)]};
    await pumpSearch(tester);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DC'));
    await tester.tap(find.text('CCS2').last);
    await tester.tap(find.text('> 50 kW'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final last = service.searchCalls.last;
    expect(last['chargerType'], 'DC');
    expect(last['connectorType'], 'CCS2');
    expect(last['powerMin'], 50);
    expect(last['powerMax'], isNull);
    expect(last['offset'], 0);
  });

  testWidgets('typing a name sends a trimmed query after the debounce',
      (tester) async {
    await pumpSearch(tester);

    await tester.enterText(find.byType(TextField), '  Siam ');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(service.searchCalls.last['query'], 'Siam');
  });

  testWidgets('scrolling to the end loads the next page at offset 20',
      (tester) async {
    service.searchPages = {
      0: [for (var i = 1; i <= 20; i++) _station(i)],
      20: [_station(21)],
    };
    await pumpSearch(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    expect(service.searchCalls.map((c) => c['offset']), [0, 20]);
    // The second page is appended below; scroll to it.
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('Station 21'), findsOneWidget);
    // That page was short (1 < 20), so no third page is requested.
    expect(service.searchCalls, hasLength(2));
  });

  testWidgets('shows the empty state when nothing matches', (tester) async {
    await pumpSearch(tester);
    expect(find.text('No stations found'), findsOneWidget);
  });
}
