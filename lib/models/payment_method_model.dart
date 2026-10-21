/// A saved card shown on the Payment screen, stored in the `payment_methods`
/// table.
///
/// MOCK ONLY: for now the card is stored directly in our own DB (full number,
/// holder name, expiry) because no real payment gateway is wired up and no real
/// card data is used. For production this MUST be replaced with a provider
/// (Stripe/Omise) that tokenizes the card, so we'd keep only a token plus the
/// last 4 digits — never the full number or CVV.
class PaymentMethod {
  final String id;
  final String userId;

  /// Full card number (mock only — see class note).
  final String cardNumber;

  /// Name printed on the card.
  final String holderName;

  final int expMonth;
  final int expYear;

  /// Whether this is the user's default card.
  final bool isDefault;

  final DateTime? createdAt;

  PaymentMethod({
    required this.id,
    required this.userId,
    required this.cardNumber,
    required this.holderName,
    required this.expMonth,
    required this.expYear,
    this.isDefault = false,
    this.createdAt,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      cardNumber: json['card_number'] as String? ?? '',
      holderName: json['holder_name'] as String? ?? '',
      expMonth: (json['exp_month'] as num?)?.toInt() ?? 0,
      expYear: (json['exp_year'] as num?)?.toInt() ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  /// Digits only, stripped of any spaces the user typed.
  String get _digits => cardNumber.replaceAll(RegExp(r'\s+'), '');

  /// Last four digits, e.g. "4242".
  String get last4 {
    final digits = _digits;
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  /// Masked display number, e.g. "•••• •••• •••• 4242".
  String get maskedNumber => '•••• •••• •••• $last4';

  /// Card network guessed from the leading digit(s). Good enough for a mock.
  String get brandLabel {
    final digits = _digits;
    if (digits.isEmpty) return 'Card';
    switch (digits[0]) {
      case '4':
        return 'Visa';
      case '5':
        return 'Mastercard';
      case '3':
        return 'Amex';
      case '6':
        return 'Discover';
      default:
        return 'Card';
    }
  }

  /// Expiry formatted as "MM/YY", e.g. "08/27".
  String get expiryLabel {
    final mm = expMonth.toString().padLeft(2, '0');
    final yy = (expYear % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }
}
