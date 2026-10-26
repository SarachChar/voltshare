import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/payment_result_model.dart';

/// Handles the (mock) payment step of a booking via the `pay-booking-fee`
/// edge function, which charges the card and records the `booking_fee` row
/// on the server.
abstract class PaymentService {
  /// Pays [amount] (THB) for [reservationId] with the saved card
  /// [paymentMethodId]. Returns success or a failure with an errorCode.
  ///
  /// MOCK: no real money moves. Cards ending in "0000" are declined.
  Future<PaymentResult> payBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
  });
}

class PaymentSupabaseService implements PaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<PaymentResult> payBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
  }) async {
    dynamic payload;
    try {
      final response = await _client.functions.invoke(
        'pay-booking-fee',
        body: {
          'reservationId': reservationId,
          'paymentMethodId': paymentMethodId,
          'amount': amount,
        },
      );
      payload = response.data;
    } on FunctionException catch (e) {
      // Non-2xx (e.g. 402 PAYMENT_DECLINED): the envelope is in details.
      payload = e.details;
      if (payload is! Map) {
        return PaymentResult(
          success: false,
          errorCode: e.status == 0 ? 'NETWORK_ERROR' : 'INTERNAL_ERROR',
        );
      }
    }

    if (payload is Map) {
      return PaymentResult.fromEnvelope(Map<String, dynamic>.from(payload));
    }
    // Unexpected shape: treat as a failed payment rather than crashing.
    return PaymentResult(success: false, errorCode: 'INTERNAL_ERROR');
  }
}
