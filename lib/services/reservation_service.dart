import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/reservation_model.dart';

abstract class ReservationService {
  /// Returns the CONFIRMED reservations for [chargerId] that overlap the local
  /// calendar day [date] — i.e. the slots already taken on that day. Cancelled
  /// and completed bookings are excluded so they don't block new bookings.
  Future<List<Reservation>> getConfirmedReservationsForChargerOnDate({
    required String chargerId,
    required DateTime date,
  });

  /// Inserts a new reservation and returns the saved row (with its db id).
  ///
  /// [startTime]/[endTime] are local device times; they're converted to UTC
  /// before being stored in the `timestamptz` columns.
  Future<Reservation> createReservation({
    required String userId,
    required String chargerId,
    required DateTime startTime,
    required DateTime endTime,
    required int durationMinutes,
  });

  /// Returns the reservations made by [userId], most recent first.
  Future<List<Reservation>> getReservationsByUser(String userId);
}

/// Supabase-backed implementation that reads from the `reservations` table.
class ReservationSupabaseService implements ReservationService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<Reservation>> getConfirmedReservationsForChargerOnDate({
    required String chargerId,
    required DateTime date,
  }) async {
    // Build the local day's [start, end) window, then convert to UTC for the
    // query since the DB stores timestamptz. A reservation counts as "on this
    // day" when it overlaps the window: start_time < dayEnd AND end_time >
    // dayStart.
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final List<dynamic> data = await _client
        .from('reservations')
        .select()
        .eq('charger_id', chargerId)
        .eq('status', 'confirmed')
        .lt('start_time', dayEnd.toUtc().toIso8601String())
        .gt('end_time', dayStart.toUtc().toIso8601String())
        .order('start_time', ascending: true);

    return data
        .map((item) => Reservation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Reservation> createReservation({
    required String userId,
    required String chargerId,
    required DateTime startTime,
    required DateTime endTime,
    required int durationMinutes,
  }) async {
    final data = await _client
        .from('reservations')
        .insert({
          'user_id': userId,
          'charger_id': chargerId,
          'start_time': startTime.toUtc().toIso8601String(),
          'end_time': endTime.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          'status': 'confirmed',
        })
        .select()
        .single();

    return Reservation.fromJson(data);
  }

  @override
  Future<List<Reservation>> getReservationsByUser(String userId) async {
    // Embed the related charger's display fields so the Bookings list can show
    // the charger name, address and power without a second query.
    final List<dynamic> data = await _client
        .from('reservations')
        .select('*, chargers(name, address, power_kw)')
        .eq('user_id', userId)
        .order('start_time', ascending: false);

    return data
        .map((item) => Reservation.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
