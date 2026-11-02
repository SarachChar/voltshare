import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/models/reservation_model.dart';

Map<String, dynamic> _base({Object? chargers}) => {
      'id': 'r1',
      'user_id': 'u1',
      'charger_id': 'c1',
      'start_time': '2026-11-03T03:00:00Z',
      'end_time': '2026-11-03T04:00:00Z',
      'duration_minutes': 60,
      'status': 'confirmed',
      'chargers': chargers,
    };

void main() {
  test('chargerJoin embeds the station through the charger', () {
    expect(Reservation.chargerJoin, contains('stations('));
    expect(Reservation.chargerJoin, contains('station_id'));
    expect(Reservation.chargerJoin, isNot(contains('address, power_kw')));
  });

  test('parses charger + nested station', () {
    final r = Reservation.fromJson(_base(chargers: {
      'name': 'Charger 2',
      'power_kw': 22,
      'charger_type': 'AC',
      'connector_type': 'Type 2',
      'price_per_kwh': 7.5,
      'station_id': 's1',
      'stations': {
        'id': 's1',
        'name': 'Siam EV Hub',
        'address': '1 Rama I Rd',
        'latitude': 13.746,
        'longitude': 100.534,
      },
    }));

    expect(r.chargerName, 'Charger 2');
    expect(r.chargerConnectorType, 'Type 2');
    expect(r.chargerPricePerKwh, 7.5);
    expect(r.stationId, 's1');
    expect(r.stationName, 'Siam EV Hub');
    expect(r.stationAddress, '1 Rama I Rd');
    expect(r.stationLatitude, 13.746);
    expect(r.stationLongitude, 100.534);

    expect(r.stationTitle, 'Siam EV Hub');
    expect(r.chargerLine, 'Charger 2 · 22 kW AC');
  });

  test('tolerates the station embed arriving as a list', () {
    final r = Reservation.fromJson(_base(chargers: {
      'name': 'Charger 1',
      'stations': [
        {'id': 's9', 'name': 'Ari Hub', 'address': 'Soi 7'},
      ],
    }));
    expect(r.stationId, 's9');
    expect(r.stationName, 'Ari Hub');
    expect(r.stationAddress, 'Soi 7');
  });

  test('charger without a station falls back to the charger name', () {
    final r = Reservation.fromJson(_base(chargers: {
      'name': 'Charger 1',
      'power_kw': 7.4,
      'charger_type': 'AC',
      'station_id': 's2',
      'stations': null,
    }));

    expect(r.stationName, '');
    expect(r.stationId, 's2'); // from chargers.station_id
    expect(r.stationTitle, 'Charger 1');
    // Name is already the title, so the second line is only the spec.
    expect(r.chargerLine, '7.4 kW AC');
  });

  test('no charger join gives empty fields and a generic title', () {
    final r = Reservation.fromJson(_base());

    expect(r.chargerName, '');
    expect(r.stationId, '');
    expect(r.stationName, '');
    expect(r.stationAddress, '');
    expect(r.stationLatitude, isNull);
    expect(r.stationTitle, 'Charger');
    expect(r.chargerLine, '');
  });
}
