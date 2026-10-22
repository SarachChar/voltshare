/// Result returned by the mock payment edge function (`mock-payment`).
///
/// The function returns `{ "status": "success" | "failed", ... }`. On success
/// it includes a [transactionId] and the charged [amount]; on failure it
/// includes a [reason] code (e.g. "insufficient_funds").
class PaymentResult {
  final bool success;
  final int amount;
  final String? transactionId;
  final String? reason;

  PaymentResult({
    required this.success,
    this.amount = 0,
    this.transactionId,
    this.reason,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    return PaymentResult(
      success: (json['status'] as String?) == 'success',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      transactionId: json['transaction_id'] as String?,
      reason: json['reason'] as String?,
    );
  }

  /// A user-facing message for a failed payment.
  String get failureMessage {
    switch (reason) {
      case 'insufficient_funds':
        return 'Payment declined: insufficient funds. Try another card.';
      case 'invalid_request':
        return 'Payment could not be processed. Please try again.';
      default:
        return 'Payment failed. Please try again or use another card.';
    }
  }
}
