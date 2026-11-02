import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';

import '../fakes/fake_station_service.dart';

void main() {
  late FakeStationService service;
  late StationController controller;

  setUp(() {
    service = FakeStationService();
    controller = StationController(service);
  });

  tearDown(() => controller.dispose());

  test('fetchStationsInBounds forwards the bounds and caches the result',
      () async {
    service.stations = const [
      Station(id: 's1', name: 'A', latitude: 1, longitude: 1),
    ];

    final result = await controller.fetchStationsInBounds(
      userLat: 13.7,
      userLng: 100.5,
      minLat: 13.6,
      minLng: 100.4,
      maxLat: 13.9,
      maxLng: 100.7,
      limit: 201,
    );

    expect(result.map((s) => s.id), ['s1']);
    expect(controller.stations, same(result));
    expect(service.lastBoundsCall, {
      'userLat': 13.7,
      'userLng': 100.5,
      'minLat': 13.6,
      'minLng': 100.4,
      'maxLat': 13.9,
      'maxLng': 100.7,
      'limit': 201,
    });
  });

  test('onSync emits true then false around a load', () async {
    final events = <bool>[];
    final sub = controller.onSync.listen(events.add);

    await controller.fetchStationsInBounds(
      userLat: 0,
      userLng: 0,
      minLat: 0,
      minLng: 0,
      maxLat: 1,
      maxLng: 1,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, [true, false]);
    await sub.cancel();
  });

  test('onSync still emits false when the load fails', () async {
    service.error = Exception('network');
    final events = <bool>[];
    final sub = controller.onSync.listen(events.add);

    await expectLater(
      controller.fetchStationsInBounds(
        userLat: 0,
        userLng: 0,
        minLat: 0,
        minLng: 0,
        maxLat: 1,
        maxLng: 1,
      ),
      throwsException,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, [true, false]);
    await sub.cancel();
  });

  test('fetchStationChargers forwards the station id', () async {
    service.chargers = [
      Charger('c1', 'Charger 1', 'AC', 'Type 2', 7.4, 7.0, 'available', 0, 0),
    ];

    final result = await controller.fetchStationChargers('s9');

    expect(service.lastChargersStationId, 's9');
    expect(result.map((c) => c.id), ['c1']);
  });

  test('togglePromotionStatus maps the switch to ACTIVE / INACTIVE', () async {
    service.promotions = const [
      StationPromotion(id: 'p1', stationId: 's1', title: 't'),
    ];

    final off = await controller.togglePromotionStatus('p1', false);
    final on = await controller.togglePromotionStatus('p1', true);

    expect(off.status, 'INACTIVE');
    expect(on.status, 'ACTIVE');
    expect(service.writes, [
      'updatePromotionStatus: p1 INACTIVE',
      'updatePromotionStatus: p1 ACTIVE',
    ]);
  });

  test('createStation / updateStation / createPromotion forward their fields',
      () async {
    final created = await controller.createStation(
      hostId: 'h1',
      name: 'Hub',
      latitude: 1,
      longitude: 2,
    );
    await controller.updateStation(
      stationId: created.id,
      name: 'Hub 2',
      latitude: 1,
      longitude: 2,
    );
    await controller.createPromotion(
      stationId: created.id,
      title: 'Deal',
      status: 'INACTIVE',
    );

    expect(service.writes, [
      'createStation: h1 Hub',
      'updateStation: ${created.id} Hub 2',
      'createPromotion: ${created.id} Deal INACTIVE',
    ]);
  });

  test('fetchChargersWeek returns a full week for every charger', () async {
    service.availability = {
      'c1': [
        ChargerAvailability(
          id: 'a1',
          chargerId: 'c1',
          dayOfWeek: 1,
          startTime: '08:00:00',
          endTime: '20:00:00',
        ),
      ],
    };

    final weeks = await controller.fetchChargersWeek(['c1', 'c2']);

    expect(service.lastAvailabilityIds, ['c1', 'c2']);
    expect(weeks.keys, ['c1', 'c2']);
    expect(weeks['c1']!.length, 7);
    expect(weeks['c1']![1].timeRangeLabel, '08:00 - 20:00');
    expect(weeks['c1']![0].isClosed, isTrue);
    // A charger with no rows is a fully closed week, not missing.
    expect(weeks['c2']!.length, 7);
    expect(weeks['c2']!.every((d) => d.isClosed), isTrue);
  });
}
