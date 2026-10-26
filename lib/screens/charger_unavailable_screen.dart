import 'package:flutter/material.dart';

/// Shown when the charger reported Unavailable at plug-in. The booking has
/// already been cancelled and its fee refunded (refund-booking-fee). "Done"
/// (or the back gesture) returns to My Bookings, which refreshes itself.
class ChargerUnavailableScreen extends StatelessWidget {
  const ChargerUnavailableScreen({
    super.key,
    required this.reason,
    required this.refundedAmount,
  });

  /// Why the charger can't be used (from the charger's errorCode).
  final String reason;

  /// Booking fee refunded (THB).
  final double refundedAmount;

  static const Color _primary = Color(0xFF10B981);
  static const Color _danger = Color(0xFFDC2626);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _mint = Color(0xFFE8F8F3);

  String get _amountLabel {
    final whole = refundedAmount == refundedAmount.roundToDouble();
    return '฿${refundedAmount.toStringAsFixed(whole ? 0 : 2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: _danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.power_off_rounded,
                    color: _danger,
                    size: 56,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                const Text(
                  'Charger Unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 12)),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: _muted,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 24)),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _mint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Booking fee refunded',
                        style: TextStyle(fontSize: 15, color: _muted),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 6)),
                      Text(
                        _amountLabel,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 6)),
                      const Text(
                        'Your booking has been cancelled and the fee '
                        'returned to your card.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                Container(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
