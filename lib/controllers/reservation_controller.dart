import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// Thin controller over [ReservationService], mirroring the project's
/// Model → Service → Controller pattern. Kept separate from the charger
/// controller so reservations don't share state with charger browsing.
class ReservationController {
  final ReservationService service;

  ReservationController(this.service);

  /// Fetches the CONFIRMED reservations for a charger on a given local day —
  /// the slots already taken — so the booking grid can disable them.
  Future<List<Reservation>> fetchConfirmedReservationsForChargerOnDate({
    required String chargerId,
    required DateTime date,
  }) {
    return service.getConfirmedReservationsForChargerOnDate(
      chargerId: chargerId,
      date: date,
    );
  }

  /// Creates a new reservation for the signed-in driver.
  Future<Reservation> createReservation({
    required String userId,
    required String chargerId,
    required DateTime startTime,
    required DateTime endTime,
    required int durationMinutes,
  }) {
    return service.createReservation(
      userId: userId,
      chargerId: chargerId,
      startTime: startTime,
      endTime: endTime,
      durationMinutes: durationMinutes,
    );
  }

  /// Fetches the reservations made by a user, most recent first.
  Future<List<Reservation>> fetchReservationsByUser(String userId) {
    return service.getReservationsByUser(userId);
  }
}
