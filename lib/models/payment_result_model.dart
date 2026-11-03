/// Result of the `pay-booking-fee` edge function, which mimics Stripe's
/// PaymentIntent API inside the app's envelope:
///   { "success": true,  "data": { "id": "pi_...", "object": "payment_intent",
///       "amount": 15000, "currency": "thb", "status": "succeeded",
///       "created": 1793685460, "payment_method", "latest_charge": "ch_...",
///       "description",
///       "metadata": { "reservationId", "bookingFeeId" } } }
///   { "success": false, "data": { "type": "card_error",
///       "code": "card_declined", "decline_code": "insufficient_funds",
///       "message": "...", "param": null, "charge": "ch_..." } }
///
/// Amounts on the wire are in satang; [amount] here is whole baht.
class PaymentResult {
  final bool success;

  /// Amount paid, in THB (baht).
  final int amount;

  /// PaymentIntent id ("pi_...").
  final String? paymentIntentId;
  final String? bookingFeeId;

  /// Charge id ("ch_..."), stored as booking_fee.transaction_id.
  final String? transactionId;

  /// Stripe error type on failure: card_error, invalid_request_error,
  /// authentication_error, api_error, or api_connection_error (client-side,
  /// no response).
  final String? errorType;

  /// Stripe error code, e.g. "card_declined", "resource_missing".
  final String? errorCode;

  /// Stripe decline_code for card errors, e.g. "insufficient_funds".
  final String? declineCode;

  /// Parameter the error relates to, e.g. "payment_method".
  final String? errorParam;

  /// Server message on failure.
  final String? error;

  PaymentResult({
    required this.success,
    this.amount = 0,
    this.paymentIntentId,
    this.bookingFeeId,
    this.transactionId,
    this.errorType,
    this.errorCode,
    this.declineCode,
    this.errorParam,
    this.error,
  });

  factory PaymentResult.fromEnvelope(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? {});
    if (json['success'] == true) {
      final metadata = Map<String, dynamic>.from(data['metadata'] as Map? ?? {});
      return PaymentResult(
        success: true,
        amount: ((data['amount'] as num?) ?? 0) ~/ 100,
        paymentIntentId: data['id'] as String?,
        bookingFeeId: metadata['bookingFeeId'] as String?,
        transactionId: data['latest_charge'] as String?,
      );
    }
    return PaymentResult(
      success: false,
      errorType: data['type'] as String? ?? 'api_error',
      errorCode: data['code'] as String?,
      declineCode: data['decline_code'] as String?,
      errorParam: data['param'] as String?,
      transactionId: data['charge'] as String?,
      error: data['message'] as String?,
    );
  }

  /// A user-facing message for a failed payment.
  String get failureMessage {
    if (declineCode == 'insufficient_funds') {
      return 'Payment declined: insufficient funds. Try another card.';
    }
    if (errorCode == 'card_declined') {
      return 'Payment declined. Try another card.';
    }
    if (errorCode == 'resource_missing' && errorParam == 'payment_method') {
      return 'That card is no longer available. Please choose another.';
    }
    if (errorCode == 'payment_intent_unexpected_state') {
      return 'This booking fee has already been paid.';
    }
    switch (errorType) {
      case 'api_connection_error':
        return 'Couldn\'t connect. Please check your connection and try again.';
      case 'authentication_error':
        return 'Please sign in again and retry.';
      case 'invalid_request_error':
        return 'Payment could not be processed. Please try again.';
      default:
        return 'Payment failed. Please try again or use another card.';
    }
  }
}
