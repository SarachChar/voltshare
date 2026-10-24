import 'package:flutter/material.dart';

/// Shown after a charging session has been paid. "Back to Home" returns to
/// the root (Home) screen; the back gesture is blocked so the driver can't go
/// back to the paid bill.
class ChargingPaymentCompleteScreen extends StatelessWidget {
  const ChargingPaymentCompleteScreen({
    super.key,
    required this.amount,
    required this.energyKwh,
  });

  /// Amount charged to the card (THB).
  final double amount;
  final double energyKwh;

  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _mint = Color(0xFFE8F8F3);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBadge(),
                  const Padding(padding: EdgeInsets.only(top: 28)),
                  const Text(
                    'Payment Complete!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 10)),
                  const Text(
                    'Thanks for charging with VoltShare.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: _muted),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 12)),
                  Text(
                    '฿${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: _primary,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 28)),
                  _buildDetails(),
                  const Padding(padding: EdgeInsets.only(top: 28)),
                  Container(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: const Text(
                        'Back to Home',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 8)),
                  TextButton(
                    // Reviews aren't built yet.
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reviews are coming soon.'),
                        ),
                      );
                    },
                    child: const Text(
                      'Leave a review ⭐',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    // Same style as the Booking Confirmed badge.
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.check_rounded, color: _primary, size: 56),
    );
  }

  Widget _buildDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Energy delivered',
              style: TextStyle(fontSize: 16, color: _muted),
            ),
          ),
          Text(
            '${energyKwh.toStringAsFixed(2)} kWh',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
        ],
      ),
    );
  }
}
