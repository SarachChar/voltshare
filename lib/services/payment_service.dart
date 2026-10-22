import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/payment_result_model.dart';

/// Handles the (mock) payment step of a booking: calling the `mock-payment`
/// edge function, and recording a `booking_fee` row once a reservation is
/// created and paid.
abstract class PaymentService {
  /// Calls the `mock-payment` edge function to charge [amount] to the card
  /// with [cardLast4]. Returns the function's result (success or failure).
  ///
  /// MOCK: no real money moves. The function declines cards ending in "0000".
  Future<PaymentResult> charge({
    required String cardLast4,
    required int amount,
    String? reservationRef,
  });

  /// Records a paid booking fee for [reservationId] (1-1 with the reservation).
  Future<void> recordBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
    String? transactionId,
  });
}

class PaymentSupabaseService implements PaymentService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<PaymentResult> charge({
    required String cardLast4,
    required int amount,
    String? reservationRef,
  }) async {
    final response = await _client.functions.invoke(
      'mock-payment',
      body: {
        'card_last4': cardLast4,
        'amount': amount,
        'reservation_ref': ?reservationRef,
      },
    );

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return PaymentResult.fromJson(data);
    }
    // Unexpected shape — treat as a failed payment rather than crashing.
    return PaymentResult(success: false, reason: 'invalid_request');
  }

  @override
  Future<void> recordBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
    String? transactionId,
  }) async {
    await _client.from('booking_fee').insert({
      'reservation_id': reservationId,
      'payment_method_id': paymentMethodId,
      'amount': amount,
      'status': 'paid',
      'transaction_id': transactionId,
    });
  }
}
