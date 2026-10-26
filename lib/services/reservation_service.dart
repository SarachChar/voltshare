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

  /// Fetches the latest copy of a single reservation by [id] (with the joined
  /// charger fields). Returns null when the row no longer exists.
  Future<Reservation?> getReservationById(String id);

  /// True when [chargerId] has a charging session in progress — a reservation
  /// that is confirmed and has a `started_at`. [excludeReservationId] is left
  /// out of the check (pass the driver's own booking).
  Future<bool> hasActiveSessionOnCharger({
    required String chargerId,
    String? excludeReservationId,
  });

  /// Deletes a reservation by [id]. Used to roll back a just-created booking
  /// when the payment step fails.
  Future<void> deleteReservation(String id);

  /// Cancels a reservation by setting its status to 'cancelled'. The booking
  /// fee is non-refundable, so no refund is issued.
  Future<void> cancelReservation(String id);
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
    // the charger name, address and power without a second query, plus the
    // driver's review (1-1) to pick "Review" vs "View Review", and the
    // charging session + bill for completed cards (actual times, cost).
    final List<dynamic> data = await _client
        .from('reservations')
        .select(
          '*, ${Reservation.chargerJoin}, reviews(*), '
          'charging_sessions(started_at, ended_at, '
          'session_payments(energy_amount)), booking_fee(status)',
        )
        .eq('user_id', userId)
        .order('start_time', ascending: false);

    return data
        .map((item) => Reservation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Reservation?> getReservationById(String id) async {
    final data = await _client
        .from('reservations')
        .select('*, ${Reservation.chargerJoin}')
        .eq('id', id)
        .maybeSingle();

    return data == null ? null : Reservation.fromJson(data);
  }

  @override
  Future<bool> hasActiveSessionOnCharger({
    required String chargerId,
    String? excludeReservationId,
  }) async {
    var query = _client
        .from('reservations')
        .select('id')
        .eq('charger_id', chargerId)
        .eq('status', 'confirmed')
        .not('started_at', 'is', null);
    if (excludeReservationId != null) {
      query = query.neq('id', excludeReservationId);
    }

    final List<dynamic> data = await query.limit(1);
    return data.isNotEmpty;
  }

  @override
  Future<void> deleteReservation(String id) async {
    await _client.from('reservations').delete().eq('id', id);
  }

  @override
  Future<void> cancelReservation(String id) async {
    await _client
        .from('reservations')
        .update({'status': 'cancelled'})
        .eq('id', id);
  }
}
