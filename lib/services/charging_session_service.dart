import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/session_payment_model.dart';
import 'package:voltshare_app/models/session_stream_model.dart';

/// Error returned by a charging edge function, e.g. errorCode "TOO_EARLY".
///
/// `pay-charging-session` returns Stripe-style errors instead: then [code] is
/// the Stripe code (e.g. "card_declined", "amount_mismatch") and [type],
/// [declineCode], [param] and [charge] carry the rest of the error object.
class ChargingException implements Exception {
  final String code;
  final String message;

  /// Stripe error type, e.g. "card_error" (payment errors only).
  final String? type;

  /// Stripe decline_code, e.g. "insufficient_funds".
  final String? declineCode;

  /// Request field the error relates to, e.g. "payment_method".
  final String? param;

  /// Charge id ("ch_...") of a declined card charge.
  final String? charge;

  ChargingException(
    this.code,
    this.message, {
    this.type,
    this.declineCode,
    this.param,
    this.charge,
  });

  @override
  String toString() => 'ChargingException($code): $message';

  /// Friendly text for the app's error popups.
  ///
  /// Sources of the codes handled here:
  ///   [Pay]    pay-charging-session  (Stripe-style, Session Summary → Pay)
  ///   [Refund] refund-booking-fee    (Stripe-style, Plug In → charger
  ///                                   unavailable)
  ///   [OCPP]   ocpp-status / ocpp-remote-start / ocpp-remote-stop
  ///            (old { errorCode, error } format)
  ///
  /// pay-booking-fee (paying the booking fee when reserving) is NOT handled
  /// here; its messages are in PaymentResult.failureMessage
  /// (payment_result_model.dart).
  String get userMessage {
    // ---- Stripe-style errors: Pay + Refund --------------------------------

    // [Pay] card ending in 0000 (decline_code of a card_error).
    if (declineCode == 'insufficient_funds') {
      return 'Payment declined: insufficient funds. Try another card.';
    }
    switch (code) {
      // [Pay] card declined without a more specific decline_code.
      case 'card_declined':
        return 'Payment declined. Try another card.';

      // [Pay] + [Refund] something wasn't found; param says what.
      case 'resource_missing':
        switch (param) {
          // [Pay] the chosen card was deleted / isn't the driver's.
          case 'payment_method':
            return 'That card is no longer available. Please choose another.';
          // [Refund] no booking_fee row / charge id for this booking (also
          // thrown by the app itself before calling the function).
          case 'charge':
            return 'No booking fee payment was found for this booking.';
          // [Refund] reservation not found.
          case 'metadata.reservation_id':
            return 'This booking could not be found.';
          // [Pay] metadata.sessionId: session or its bill not found.
          default:
            return 'This charging session could not be found.';
        }

      // [Pay] amount != the session bill (screen reloads the bill).
      // [Refund] amount != the full booking fee.
      case 'amount_mismatch':
        return 'The amount has changed. Please review and try again.';

      // [Pay] bill already paid (screen treats it as success).
      case 'payment_intent_unexpected_state':
        return 'This charging session has already been paid.';

      // [Refund] booking fee already refunded.
      case 'charge_already_refunded':
        return 'This booking fee has already been refunded.';

      // [Refund] the charge id belongs to another reservation.
      case 'charge_mismatch':
        return 'This payment doesn\'t match the booking. Please try again.';

      // [Refund] booking isn't 'confirmed' or charging already started.
      case 'reservation_not_active':
        return 'This booking can no longer be refunded.';

      // [Refund] charger is fine, so no refund (server re-check).
      case 'charger_available':
        return 'The charger is available, so the booking fee is not '
            'refundable.';
    }

    // [Pay] + [Refund] fallbacks by Stripe error type when the code above
    // didn't match (e.g. 401, 403 NOT_OWNER with code null, 400 parameter_*,
    // 500). Note: the wording says "Payment" for refunds too.
    // api_connection_error (no response) falls through to NETWORK_ERROR.
    switch (type) {
      case 'authentication_error':
        return 'Please sign in again and retry.';
      case 'invalid_request_error':
        return 'Payment could not be processed. Please try again.';
      case 'api_error':
        return 'Payment failed. Please try again or use another card.';
    }

    // ---- Old { errorCode, error } format: OCPP functions -------------------
    switch (code) {
      // [OCPP] ocpp-remote-start
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

      // [OCPP] ocpp-remote-stop
      case 'NO_ACTIVE_TRANSACTION':
        return 'This charging session has already ended.';

      // Legacy (pre-Stripe) Pay / Refund codes. Currently unused: the edge
      // functions now map these to Stripe codes, and _invokeStripe reads
      // `code`, not `errorCode`. Safe to delete.
      case 'PAYMENT_DECLINED':
        return 'Payment declined: insufficient funds. Try another card.';
      case 'INVALID_PAYMENT_METHOD':
        return 'That card is no longer available. Please choose another.';
      case 'AMOUNT_MISMATCH':
        return 'The amount has changed. Please review your bill and try '
            'again.';
      case 'ALREADY_PAID':
        return 'This charging session has already been paid.';
      case 'ALREADY_REFUNDED':
        return 'This booking fee has already been refunded.';

      // [OCPP] ocpp-status
      case 'CHARGER_NOT_FOUND':
        return 'This charger could not be found.';

      // [OCPP] + [Pay] + [Refund] set by the app when there's no response.
      case 'NETWORK_ERROR':
        return 'Couldn\'t connect. Please check your connection and try again.';
      default:
        return message.isNotEmpty
            ? message
            : 'Something went wrong. Please try again.';
    }
  }
}

/// Connector status reported by the (mock) charger via `ocpp-status`.
class ChargerStatus {
  /// OCPP status, e.g. "Available" / "Unavailable".
  final String status;

  /// OCPP errorCode, "NoError" when healthy.
  final String errorCode;

  ChargerStatus({required this.status, required this.errorCode});

  bool get isAvailable => status == 'Available';

  /// Friendly reason for the error popup when not available.
  String get userMessage {
    switch (errorCode) {
      case 'NoError':
        return 'This charger is currently unavailable. Please try again '
            'later.';
      case 'ConnectorLockFailure':
        return 'The connector couldn\'t lock. Please unplug the cable, plug '
            'it in again and retry.';
      case 'EVCommunicationError':
        return 'The charger can\'t communicate with your car. Check the '
            'cable is fully plugged in and retry.';
      case 'GroundFailure':
        return 'The charger detected a ground fault. For safety it can\'t '
            'start charging. Please contact the host.';
      case 'HighTemperature':
        return 'The charger is too hot right now. Please wait a few minutes '
            'and retry.';
      case 'OverCurrentFailure':
      case 'OverVoltage':
      case 'UnderVoltage':
        return 'The charger detected a power problem and can\'t start '
            'charging. Please contact the host.';
      case 'WeakSignal':
        return 'The charger has a weak network connection. Please retry in '
            'a moment.';
      default:
        return 'The charger reported a problem ($errorCode) and can\'t '
            'start charging. Please retry or contact the host.';
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
  /// Calls `ocpp-status` for [chargerId]'s connector.
  Future<ChargerStatus> checkChargerStatus(String chargerId);

  /// Calls `refund-booking-fee` (Stripe Refund-style) with the booking fee's
  /// charge id: cancels [reservationId] and refunds its fee in full (server
  /// re-checks the charger is unavailable). Returns the refunded amount (THB).
  /// Throws [ChargingException] with the Stripe error code on failure.
  Future<double> refundBookingFee(String reservationId);

  /// Calls `ocpp-remote-start`. Returns the new session id.
  Future<String> startCharging(String reservationId);

  /// Calls `ocpp-remote-stop`.
  Future<ChargingStopResult> stopCharging(String reservationId);

  /// Calls `pay-charging-session` (Stripe PaymentIntent-style). [amount] is
  /// the bill total (THB) shown to the driver; the server rejects it
  /// (amount_mismatch) if it differs. Throws [ChargingException] with the
  /// Stripe error code on failure.
  Future<void> payForSession({
    required String sessionId,
    required String paymentMethodId,
    required double amount,
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
  Future<ChargerStatus> checkChargerStatus(String chargerId) async {
    final data = await _invoke(
      'ocpp-status',
      {'chargerId': chargerId, 'connectorId': 1},
    );
    return ChargerStatus(
      status: data['status'] as String? ?? 'Unavailable',
      errorCode: data['errorCode'] as String? ?? 'OtherError',
    );
  }

  /// Invokes a Stripe-style payment edge function (`pay-charging-session`,
  /// `refund-booking-fee`) and unwraps the `{ success, data }` envelope.
  /// Throws [ChargingException] carrying the Stripe error fields on failure.
  Future<Map<String, dynamic>> _invokeStripe(
    String function,
    Map<String, dynamic> body,
  ) async {
    dynamic payload;
    try {
      final response = await _client.functions.invoke(function, body: body);
      payload = response.data;
    } on FunctionException catch (e) {
      // Non-2xx (e.g. 402 card_error): the envelope is in details.
      payload = e.details;
      if (payload is! Map) {
        throw ChargingException(
          e.status == 0 ? 'NETWORK_ERROR' : 'INTERNAL_ERROR',
          'Couldn\'t reach the payment service. Please try again.',
          type: e.status == 0 ? 'api_connection_error' : 'api_error',
        );
      }
    }

    if (payload is Map && payload['data'] is Map) {
      final data = Map<String, dynamic>.from(payload['data'] as Map);
      if (payload['success'] == true) return data;
      throw ChargingException(
        data['code']?.toString() ?? 'INTERNAL_ERROR',
        data['message']?.toString() ?? 'Something went wrong.',
        type: data['type']?.toString() ?? 'api_error',
        declineCode: data['decline_code']?.toString(),
        param: data['param']?.toString(),
        charge: data['charge']?.toString(),
      );
    }
    throw ChargingException(
      'INTERNAL_ERROR',
      'Unexpected response.',
      type: 'api_error',
    );
  }

  @override
  Future<double> refundBookingFee(String reservationId) async {
    // The refund targets the booking fee's charge, so look it up first
    // (RLS: drivers can read their own booking_fee rows).
    final fee = await _client
        .from('booking_fee')
        .select('transaction_id, amount')
        .eq('reservation_id', reservationId)
        .maybeSingle();
    final charge = fee?['transaction_id'] as String?;
    if (fee == null || charge == null || charge.isEmpty) {
      throw ChargingException(
        'resource_missing',
        'No booking fee payment was found for this booking.',
        type: 'invalid_request_error',
        param: 'charge',
      );
    }

    // Stripe Refund-style body. Amount in satang (THB x 100), full refund.
    final data = await _invokeStripe('refund-booking-fee', {
      'charge': charge,
      'amount': ((fee['amount'] as num) * 100).round(),
      'reason': 'requested_by_customer',
      'metadata': {'reservation_id': reservationId},
    });
    return ((data['amount'] as num?) ?? 0) / 100;
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
    required double amount,
  }) async {
    // Amount in satang (THB x 100), rounded to avoid float drift.
    await _invokeStripe('pay-charging-session', {
      'amount': (amount * 100).round(),
      'currency': 'thb',
      'payment_method': paymentMethodId,
      'description': 'charging session #$sessionId',
      'receipt_email': _client.auth.currentUser?.email,
      'metadata': {'sessionId': sessionId},
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
