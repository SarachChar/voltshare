import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/reservation_confirmed_screen.dart';
import 'package:voltshare_app/screens/reserve_charger_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// Only the hours lookup is used by ReserveChargerScreen; anything else fails.
class _FakeChargerService implements ChargerService {
  @override
  Future<List<ChargerAvailability>> getChargerAvailability(
    String chargerId,
  ) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Only the taken-slots lookup is used by ReserveChargerScreen.
class _FakeReservationService implements ReservationService {
  @override
  Future<List<Reservation>> getConfirmedReservationsForChargerOnDate({
    required String chargerId,
    required DateTime date,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  const station = Station(
    id: 's1',
    name: 'Siam EV Hub',
    address: '1 Rama I Rd, Pathum Wan',
    latitude: 13.7,
    longitude: 100.5,
  );
  final charger =
      Charger('c1', 'Charger 2', 'DC', 'CCS2', 120, 8.5, 'available');

  testWidgets('Reserve screen card shows station, charger and address',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReserveChargerScreen(
          station: station,
          charger: charger,
          controller: ChargerController(_FakeChargerService()),
          reservationController:
              ReservationController(_FakeReservationService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Siam EV Hub'), findsOneWidget);
    expect(
      find.text('Charger 2 · 120 kW · DC · CCS2 · ฿8.50/kWh'),
      findsOneWidget,
    );
    expect(find.text('1 Rama I Rd, Pathum Wan'), findsOneWidget);
  });

  testWidgets('Confirmed screen shows station and charger rows',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReservationConfirmedScreen(
          stationName: 'Siam EV Hub',
          chargerName: 'Charger 2',
          dateLabel: 'November 3, 2026',
          timeLabel: '10:00 - 11:00',
          durationLabel: '1 hr',
        ),
      ),
    );

    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Siam EV Hub'), findsOneWidget);
    expect(find.text('Charger'), findsOneWidget);
    expect(find.text('Charger 2'), findsOneWidget);
    expect(find.text('10:00 - 11:00'), findsOneWidget);
  });
}
