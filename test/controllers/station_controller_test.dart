import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/services/station_service.dart';

class _FakeStationService implements StationService {
  List<Station> stations = const [];
  List<Charger> chargers = const [];
  Object? error;

  Map<String, Object?>? lastBoundsCall;
  String? lastChargersStationId;

  @override
  Future<List<Station>> getStationsInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit = 200,
  }) async {
    lastBoundsCall = {
      'userLat': userLat,
      'userLng': userLng,
      'minLat': minLat,
      'minLng': minLng,
      'maxLat': maxLat,
      'maxLng': maxLng,
      'limit': limit,
    };
    if (error != null) throw error!;
    return stations;
  }

  @override
  Future<List<Charger>> getStationChargers(String stationId) async {
    lastChargersStationId = stationId;
    return chargers;
  }
}

void main() {
  late _FakeStationService service;
  late StationController controller;

  setUp(() {
    service = _FakeStationService();
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
}
