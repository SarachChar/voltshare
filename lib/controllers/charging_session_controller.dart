import 'package:flutter/foundation.dart';

import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/session_payment_model.dart';
import 'package:voltshare_app/models/session_stream_model.dart';
import 'package:voltshare_app/services/charging_session_service.dart';

/// Thin controller over [ChargingSessionService], following the project's
/// Model → Service → Controller pattern.
class ChargingSessionController {
  final ChargingSessionService service;

  ChargingSessionController(this.service);

  /// Bumped whenever a session starts, stops or is paid, so screens that list
  /// reservations (Bookings) can refresh even though the charging flow
  /// replaced routes instead of popping back to them.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void notifyChanged() => changes.value++;

  Future<String> startCharging(String reservationId) async {
    final id = await service.startCharging(reservationId);
    notifyChanged();
    return id;
  }

  Future<ChargingStopResult> stopCharging(String reservationId) async {
    final result = await service.stopCharging(reservationId);
    notifyChanged();
    return result;
  }

  Future<void> payForSession({
    required String sessionId,
    required String paymentMethodId,
    required double amount,
  }) async {
    await service.payForSession(
      sessionId: sessionId,
      paymentMethodId: paymentMethodId,
      amount: amount,
    );
    notifyChanged();
  }

  Future<ChargingSession?> fetchSessionByReservation(String reservationId) =>
      service.getSessionByReservation(reservationId);

  Future<ChargingSession?> fetchSession(String sessionId) =>
      service.getSession(sessionId);

  Stream<SessionStream?> watchLatestReading(String sessionId) =>
      service.watchLatestReading(sessionId);

  Stream<ChargingSession?> watchSession(String sessionId) =>
      service.watchSession(sessionId);

  Future<SessionPayment?> fetchPayment(String sessionId) =>
      service.getPayment(sessionId);

  Future<PendingChargingSession?> findPendingSession() =>
      service.findPendingSession();
}
