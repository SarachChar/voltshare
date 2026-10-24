import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/session_payment_model.dart';
import 'package:voltshare_app/models/session_stream_model.dart';

/// Error returned by a charging edge function, e.g. errorCode "TOO_EARLY".
class ChargingException implements Exception {
  final String code;
  final String message;

  ChargingException(this.code, this.message);

  @override
  String toString() => 'ChargingException($code): $message';

  /// Friendly text for the app's error popups.
  String get userMessage {
    switch (code) {
      case 'RESERVATION_CANCELLED':
        return 'This booking was cancelled because charging wasn\'t started '
            'within 15 minutes of the booked start time. The booking fee is '
            'non-refundable.';
      case 'RESERVATION_EXPIRED':
        return 'Charging must start within 15 minutes of the booked start '
            'time. This booking can no longer be started.';
      case 'TOO_EARLY':
        return 'It\'s not time yet. You can start up to 30 minutes early if '
            'the charger is free.';
      case 'CHARGER_IN_USE':
        return 'The charger is still in use by another driver. Please wait '
            'until your booking starts.';
      case 'RESERVATION_NOT_ACTIVE':
      case 'SESSION_ALREADY_STARTED':
        return 'Charging has already been started for this booking.';
      case 'NO_ACTIVE_TRANSACTION':
        return 'This charging session has already ended.';
      case 'PAYMENT_DECLINED':
        return 'Payment declined: insufficient funds. Try another card.';
      case 'INVALID_PAYMENT_METHOD':
        return 'That card is no longer available. Please choose another.';
      case 'ALREADY_PAID':
        return 'This charging session has already been paid.';
      case 'NETWORK_ERROR':
        return 'Couldn\'t connect. Please check your connection and try again.';
      default:
        return message.isNotEmpty
            ? message
            : 'Something went wrong. Please try again.';
    }
  }
}

/// Result of a successful stop.
class ChargingStopResult {
  final String sessionId;
  final String paymentStatus;
  final double totalAmount;

  ChargingStopResult({
    required this.sessionId,
    required this.paymentStatus,
    required this.totalAmount,
  });
}

/// A session that needs the driver's attention when the app opens: still
/// charging, or finished but not paid yet.
class PendingChargingSession {
  final ChargingSession session;
  final bool isUnpaid;

  PendingChargingSession({required this.session, required this.isUnpaid});
}

abstract class ChargingSessionService {
  /// Calls `ocpp-remote-start`. Returns the new session id.
  Future<String> startCharging(String reservationId);

  /// Calls `ocpp-remote-stop`.
  Future<ChargingStopResult> stopCharging(String reservationId);

  /// Calls `pay-charging-session`.
  Future<void> payForSession({
    required String sessionId,
    required String paymentMethodId,
  });

  /// The session for a reservation (with the reservation + charger), or null.
  Future<ChargingSession?> getSessionByReservation(String reservationId);

  /// A session by id (with the reservation + charger), or null.
  Future<ChargingSession?> getSession(String sessionId);

  /// Live latest reading of a session (Realtime). Emits null until the first
  /// reading exists.
  Stream<SessionStream?> watchLatestReading(String sessionId);

  /// Live session row (Realtime), to notice when it gets completed.
  Stream<ChargingSession?> watchSession(String sessionId);

  /// The bill of a session, or null if it hasn't stopped yet.
  Future<SessionPayment?> getPayment(String sessionId);

  /// The signed-in driver's charging or unpaid session, if any. Charging
  /// takes priority.
  Future<PendingChargingSession?> findPendingSession();
}

class ChargingSessionSupabaseService implements ChargingSessionService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Session columns + embedded reservation and charger.
  static const String _sessionSelect =
      '*, reservations(*, ${Reservation.chargerJoin})';

  /// Invokes a charging edge function and unwraps the
  /// `{ success, data }` envelope. Throws [ChargingException] on failure.
  Future<Map<String, dynamic>> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    dynamic payload;
    try {
      final response = await _client.functions.invoke(function, body: body);
      payload = response.data;
    } on FunctionException catch (e) {
      // Non-2xx: the envelope is in details.
      payload = e.details;
      if (payload is! Map) {
        throw ChargingException(
          e.status == 0 ? 'NETWORK_ERROR' : 'INTERNAL_ERROR',
          'Couldn\'t reach the charging service. Please try again.',
        );
      }
    }

    if (payload is Map && payload['data'] is Map) {
      final data = Map<String, dynamic>.from(payload['data'] as Map);
      if (payload['success'] == true) return data;
      throw ChargingException(
        data['errorCode']?.toString() ?? 'INTERNAL_ERROR',
        data['error']?.toString() ?? 'Something went wrong.',
      );
    }
    throw ChargingException('INTERNAL_ERROR', 'Unexpected response.');
  }

  @override
  Future<String> startCharging(String reservationId) async {
    final data = await _invoke(
      'ocpp-remote-start',
      {'reservationId': reservationId},
    );
    return data['sessionId'] as String;
  }

  @override
  Future<ChargingStopResult> stopCharging(String reservationId) async {
    final data = await _invoke(
      'ocpp-remote-stop',
      {'reservationId': reservationId},
    );
    return ChargingStopResult(
      sessionId: data['sessionId'] as String,
      paymentStatus: data['paymentStatus'] as String? ?? 'unpaid',
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> payForSession({
    required String sessionId,
    required String paymentMethodId,
  }) async {
    await _invoke('pay-charging-session', {
      'sessionId': sessionId,
      'paymentMethodId': paymentMethodId,
    });
  }

  @override
  Future<ChargingSession?> getSessionByReservation(String reservationId) async {
    final data = await _client
        .from('charging_sessions')
        .select(_sessionSelect)
        .eq('reservation_id', reservationId)
        .maybeSingle();
    return data == null ? null : ChargingSession.fromJson(data);
  }

  @override
  Future<ChargingSession?> getSession(String sessionId) async {
    final data = await _client
        .from('charging_sessions')
        .select(_sessionSelect)
        .eq('id', sessionId)
        .maybeSingle();
    return data == null ? null : ChargingSession.fromJson(data);
  }

  @override
  Stream<SessionStream?> watchLatestReading(String sessionId) {
    return _client
        .from('session_streams')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(1)
        .map((rows) => rows.isEmpty ? null : SessionStream.fromJson(rows.first));
  }

  @override
  Stream<ChargingSession?> watchSession(String sessionId) {
    return _client
        .from('charging_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) =>
            rows.isEmpty ? null : ChargingSession.fromJson(rows.first));
  }

  @override
  Future<SessionPayment?> getPayment(String sessionId) async {
    final data = await _client
        .from('session_payments')
        .select()
        .eq('session_id', sessionId)
        .maybeSingle();
    return data == null ? null : SessionPayment.fromJson(data);
  }

  @override
  Future<PendingChargingSession?> findPendingSession() async {
    // RLS limits both queries to the signed-in driver's own sessions.
    final charging = await _client
        .from('charging_sessions')
        .select(_sessionSelect)
        .eq('status', 'charging')
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (charging != null) {
      return PendingChargingSession(
        session: ChargingSession.fromJson(charging),
        isUnpaid: false,
      );
    }

    final unpaid = await _client
        .from('session_payments')
        .select('*, charging_sessions($_sessionSelect)')
        .neq('status', 'paid')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (unpaid != null) {
      final session = SessionPayment.fromJson(unpaid).session;
      if (session != null) {
        return PendingChargingSession(session: session, isUnpaid: true);
      }
    }
    return null;
  }
}
