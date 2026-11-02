import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/models/station_model.dart';

void main() {
  group('Station.fromJson', () {
    test('parses a full stations_in_bounds row', () {
      final station = Station.fromJson({
        'id': 's1',
        'host_id': 'h1',
        'name': 'Siam EV Hub',
        'description': 'Near BTS',
        'address': '1 Rama I Rd',
        'latitude': 13.746,
        'longitude': 100.534,
        'created_at': '2026-11-01T10:00:00Z',
        'distance_m': 420.4,
        'charger_count': 3,
        'available_count': 2,
        'connector_types': ['CCS2', 'Type 2'],
        'charger_types': ['AC', 'DC'],
        'min_price': 7.5,
        'max_power_kw': 120,
      });

      expect(station.id, 's1');
      expect(station.hostId, 'h1');
      expect(station.name, 'Siam EV Hub');
      expect(station.address, '1 Rama I Rd');
      expect(station.latitude, 13.746);
      expect(station.longitude, 100.534);
      expect(station.createdAt, isNotNull);
      expect(station.distanceMeters, 420.4);
      expect(station.chargerCount, 3);
      expect(station.availableCount, 2);
      expect(station.connectorTypes, ['CCS2', 'Type 2']);
      expect(station.chargerTypes, ['AC', 'DC']);
      expect(station.minPrice, 7.5);
      expect(station.maxPowerKw, 120.0);
    });

    test('tolerates nulls and missing summary columns', () {
      final station = Station.fromJson({
        'id': 's2',
        'name': null,
        'latitude': null,
        'longitude': null,
        'connector_types': null,
      });

      expect(station.name, '');
      expect(station.hostId, '');
      expect(station.latitude, 0.0);
      expect(station.longitude, 0.0);
      expect(station.createdAt, isNull);
      expect(station.distanceMeters, isNull);
      expect(station.chargerCount, 0);
      expect(station.availableCount, 0);
      expect(station.connectorTypes, isEmpty);
      expect(station.chargerTypes, isEmpty);
      expect(station.minPrice, isNull);
      expect(station.maxPowerKw, isNull);
    });

    test('drops empty and non-string entries from type arrays', () {
      final station = Station.fromJson({
        'id': 's3',
        'name': 'x',
        'latitude': 1,
        'longitude': 2,
        'connector_types': ['CCS2', '', null, 5],
        'charger_types': [],
      });

      expect(station.connectorTypes, ['CCS2']);
      expect(station.chargerTypes, isEmpty);
    });

    test('listFromJson maps every row', () {
      final stations = Station.listFromJson([
        {'id': 'a', 'name': 'A', 'latitude': 1, 'longitude': 1},
        {'id': 'b', 'name': 'B', 'latitude': 2, 'longitude': 2},
      ]);
      expect(stations.map((s) => s.id), ['a', 'b']);
    });
  });

  group('Station labels', () {
    Station make({
      double? distance,
      int count = 0,
      int available = 0,
      double? price,
      double? power,
    }) {
      return Station(
        id: 'id',
        name: 'n',
        latitude: 0,
        longitude: 0,
        distanceMeters: distance,
        chargerCount: count,
        availableCount: available,
        minPrice: price,
        maxPowerKw: power,
      );
    }

    test('distanceLabel', () {
      expect(make().distanceLabel, '');
      expect(make(distance: 850.4).distanceLabel, '850 m');
      expect(make(distance: 1234).distanceLabel, '1.2 km');
    });

    test('availabilityLabel', () {
      expect(make(count: 3, available: 2).availabilityLabel, '2/3 available');
      expect(make(count: 0, available: 2).availabilityLabel, '2 available');
      expect(make(count: 1, available: 2).availabilityLabel, '2 available');
    });

    test('priceFromLabel', () {
      expect(make().priceFromLabel, '');
      expect(make(price: 7.5).priceFromLabel, 'from ฿7.50/kWh');
    });

    test('maxPowerLabel', () {
      expect(make().maxPowerLabel, '');
      expect(make(power: 120).maxPowerLabel, 'up to 120 kW');
      expect(make(power: 7.4).maxPowerLabel, 'up to 7.4 kW');
    });
  });
}
