import 'package:flutter/material.dart';

/// Shown after a review is saved. It replaced the review form, so "Done" (or
/// the back gesture) simply returns to whichever screen opened the review:
/// the Bookings list, or Payment Complete after paying for a charge.
class ReviewSubmittedScreen extends StatelessWidget {
  const ReviewSubmittedScreen({super.key});

  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);

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
                    color: _primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: _primary,
                    size: 56,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                const Text(
                  'Review Submitted!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 12)),
                const Text(
                  'Thank you for helping the VoltShare community.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5, color: _muted),
                ),
                const Padding(padding: EdgeInsets.only(top: 32)),
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
