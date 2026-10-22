import 'package:flutter/material.dart';

/// Full-screen result shown when a booking's payment fails. Mirrors the layout
/// of [ReservationConfirmedScreen] but in a "declined" style, with a single
/// button that returns to the review screen so the driver can retry or pick a
/// different card.
class PaymentFailedScreen extends StatelessWidget {
  const PaymentFailedScreen({
    super.key,
    required this.message,
  });

  /// User-facing reason for the failure (e.g. "insufficient funds").
  final String message;

  static const Color _danger = Color(0xFFDC2626);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildErrorBadge(),
                        const Padding(padding: EdgeInsets.only(top: 24)),
                        const Text(
                          'Payment Failed',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: _dark,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 12)),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 12)),
                        Text(
                          'Your booking was not created. Please try again or '
                          'use a different card.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildRetryButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBadge() {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.close_rounded, size: 56, color: _danger),
    );
  }

  Widget _buildRetryButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: _danger,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: const Text(
          'Try Again',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
