import 'package:voltshare_app/models/charging_session_model.dart';

/// The bill for a finished charging session, from `session_payments`.
///
/// Amounts are THB and computed on the server when the session stops:
///   totalAmount    = max(energyAmount - bookingFeeDeducted, 0)  (charged)
///   platformAmount = 15% of totalAmount, hostAmount = the rest.
/// [status] is "unpaid", "paid" or "failed".
class SessionPayment {
  final String id;
  final String sessionId;
  final String? paymentMethodId;
  final double energyAmount;
  final double bookingFeeDeducted;
  final double totalAmount;
  final double platformAmount;
  final double hostAmount;
  final String status;
  final String? transactionId;
  final DateTime? paidAt;

  /// The session, when the query embedded it (`charging_sessions(...)`).
  final ChargingSession? session;

  SessionPayment({
    required this.id,
    required this.sessionId,
    this.paymentMethodId,
    required this.energyAmount,
    required this.bookingFeeDeducted,
    required this.totalAmount,
    required this.platformAmount,
    required this.hostAmount,
    required this.status,
    this.transactionId,
    this.paidAt,
    this.session,
  });

  factory SessionPayment.fromJson(Map<String, dynamic> json) {
    double amount(String key) => (json[key] as num?)?.toDouble() ?? 0;
    final session = json['charging_sessions'];
    return SessionPayment(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      paymentMethodId: json['payment_method_id'] as String?,
      energyAmount: amount('energy_amount'),
      bookingFeeDeducted: amount('booking_fee_deducted'),
      totalAmount: amount('total_amount'),
      platformAmount: amount('platform_amount'),
      hostAmount: amount('host_amount'),
      status: json['status'] as String? ?? 'unpaid',
      transactionId: json['transaction_id'] as String?,
      paidAt: DateTime.tryParse(json['paid_at']?.toString() ?? '')?.toLocal(),
      session: session is Map<String, dynamic>
          ? ChargingSession.fromJson(session)
          : null,
    );
  }

  bool get isPaid => status == 'paid';
}
