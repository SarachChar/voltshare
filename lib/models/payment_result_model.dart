/// Result of the `pay-booking-fee` edge function, which uses the same
/// envelope as the charging functions:
///   { "success": true,  "data": { "status": "paid", "bookingFeeId", "totalAmount",
///                                 "transactionId", "paidAt" } }
///   { "success": false, "data": { "errorCode": "...", "error": "..." } }
class PaymentResult {
  final bool success;
  final int amount;
  final String? bookingFeeId;
  final String? transactionId;

  /// errorCode on failure, e.g. "PAYMENT_DECLINED".
  final String? errorCode;

  /// Server message on failure.
  final String? error;

  PaymentResult({
    required this.success,
    this.amount = 0,
    this.bookingFeeId,
    this.transactionId,
    this.errorCode,
    this.error,
  });

  factory PaymentResult.fromEnvelope(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? {});
    if (json['success'] == true) {
      return PaymentResult(
        success: true,
        amount: (data['totalAmount'] as num?)?.toInt() ?? 0,
        bookingFeeId: data['bookingFeeId'] as String?,
        transactionId: data['transactionId'] as String?,
      );
    }
    return PaymentResult(
      success: false,
      errorCode: data['errorCode'] as String? ?? 'INTERNAL_ERROR',
      error: data['error'] as String?,
    );
  }

  /// A user-facing message for a failed payment.
  String get failureMessage {
    switch (errorCode) {
      case 'PAYMENT_DECLINED':
        return 'Payment declined: insufficient funds. Try another card.';
      case 'INVALID_PAYMENT_METHOD':
        return 'That card is no longer available. Please choose another.';
      case 'NETWORK_ERROR':
        return 'Couldn\'t connect. Please check your connection and try again.';
      case 'INVALID_REQUEST':
        return 'Payment could not be processed. Please try again.';
      default:
        return 'Payment failed. Please try again or use another card.';
    }
  }
}
