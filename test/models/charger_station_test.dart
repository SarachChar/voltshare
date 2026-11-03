import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';

void main() {
  group('Charger.fromJson station fields', () {
    test('reads station_id and the embedded station name', () {
      final c = Charger.fromJson({
        'id': 'c1',
        'name': 'Charger 1',
        'status': 'review',
        'station_id': 's1',
        'stations': {'name': 'Siam EV Hub', 'host_id': 'h1'},
      });
      expect(c.stationId, 's1');
      expect(c.stationName, 'Siam EV Hub');
    });

    test('tolerates a list embed and a missing station', () {
      final listed = Charger.fromJson({
        'id': 'c1',
        'stations': [
          {'name': 'Ari Hub'},
        ],
      });
      expect(listed.stationName, 'Ari Hub');

      final bare = Charger.fromJson({'id': 'c2'});
      expect(bare.stationId, '');
      expect(bare.stationName, '');
    });

    test('isLive only for available / unavailable', () {
      Charger withStatus(String s) => Charger('c', 'n', 'AC', 'T', 7, 7, s);
      expect(withStatus('available').isLive, isTrue);
      expect(withStatus('unavailable').isLive, isTrue);
      for (final s in Charger.pendingStatuses) {
        expect(withStatus(s).isLive, isFalse, reason: s);
      }
    });
  });

  group('ChargerRevenue', () {
    test('fromJson reads station fields', () {
      final r = ChargerRevenue.fromJson({
        'charger_id': 'c1',
        'name': 'Charger 2',
        'station_id': 's1',
        'station_name': 'Siam EV Hub',
        'sessions': 3,
        'gross': 900,
        'net': 765,
      });
      expect(r.stationId, 's1');
      expect(r.stationName, 'Siam EV Hub');
      expect(r.sessions, 3);
      expect(r.displayName, 'Siam EV Hub · Charger 2');
    });

    test('displayName without a station or a name', () {
      expect(
        ChargerRevenue(chargerId: 'c', name: 'Charger 1').displayName,
        'Charger 1',
      );
      expect(ChargerRevenue(chargerId: 'c', name: '').displayName, 'Charger');
    });

    test('HostRevenue.forCharger returns zeros for unknown chargers', () {
      final revenue = HostRevenue.fromJson({
        'month': '2026-11-01',
        'summary': {},
        'by_charger': [
          {'charger_id': 'c1', 'name': 'Charger 1', 'sessions': 2},
        ],
        'monthly': [],
      });
      expect(revenue.forCharger('c1').sessions, 2);
      expect(revenue.forCharger('zz').sessions, 0);
      expect(revenue.forCharger('zz').net, 0);
    });
  });
}
