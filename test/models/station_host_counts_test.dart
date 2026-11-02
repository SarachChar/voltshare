import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/models/station_model.dart';

void main() {
  test('counts an embedded chargers(id, status) list', () {
    final station = Station.fromJson({
      'id': 's1',
      'name': 'Siam EV Hub',
      'latitude': 13.7,
      'longitude': 100.5,
      'chargers': [
        {'id': 'a', 'status': 'available'},
        {'id': 'b', 'status': 'available'},
        {'id': 'c', 'status': 'unavailable'},
        {'id': 'd', 'status': 'review'},
        {'id': 'e', 'status': 'setup'},
        {'id': 'f', 'status': 'rejected'},
      ],
    });

    expect(station.chargerCount, 3); // available + unavailable
    expect(station.availableCount, 2);
    expect(station.pendingCount, 3); // review + setup + rejected
    expect(station.name, 'Siam EV Hub');
    expect(station.hostCountsLabel, '3 live · 3 pending');
  });

  test('RPC summary columns win over an embedded list', () {
    final station = Station.fromJson({
      'id': 's1',
      'name': 'x',
      'latitude': 0,
      'longitude': 0,
      'charger_count': 4,
      'available_count': 1,
      'chargers': [
        {'id': 'a', 'status': 'available'},
      ],
    });
    expect(station.chargerCount, 4);
    expect(station.availableCount, 1);
  });

  test('hostCountsLabel variants', () {
    Station make(int live, int pending) => Station(
          id: 's',
          name: 'n',
          latitude: 0,
          longitude: 0,
          chargerCount: live,
          pendingCount: pending,
        );
    expect(make(0, 0).hostCountsLabel, 'No chargers yet');
    expect(make(2, 0).hostCountsLabel, '2 live');
    expect(make(0, 1).hostCountsLabel, '1 pending');
  });

  test('copyWith keeps untouched fields', () {
    const station = Station(
      id: 's',
      hostId: 'h',
      name: 'Old',
      address: 'A',
      latitude: 1,
      longitude: 2,
      chargerCount: 3,
      pendingCount: 1,
    );
    final copy = station.copyWith(name: 'New', latitude: 9);
    expect(copy.id, 's');
    expect(copy.hostId, 'h');
    expect(copy.name, 'New');
    expect(copy.address, 'A');
    expect(copy.latitude, 9);
    expect(copy.longitude, 2);
    expect(copy.chargerCount, 3);
    expect(copy.pendingCount, 1);
  });
}
