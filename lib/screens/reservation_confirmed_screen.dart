import 'package:flutter/material.dart';

/// Success screen shown after a reservation is saved. It confirms the booking,
/// reminds the driver they must start charging within the grace window or the
/// booking is cancelled and the booking fee charged, and shows a summary of
/// what was booked. A single button closes the flow.
class ReservationConfirmedScreen extends StatelessWidget {
  const ReservationConfirmedScreen({
    super.key,
    required this.chargerName,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
  });

  final String chargerName;
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;

  /// Minutes the driver has to start charging before the booking is auto-
  /// cancelled and the fee charged.
  static const int _graceMinutes = 15;

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
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
                        _buildCheckBadge(),
                        const Padding(padding: EdgeInsets.only(top: 24)),
                        const Text(
                          'Booking Confirmed!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: _dark,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 12)),
                        Text(
                          'Start charging within $_graceMinutes minutes of '
                          'your slot. If you don\'t, the booking is cancelled '
                          'and the booking fee is charged.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 28)),
                        _buildSummaryCard(),
                      ],
                    ),
                  ),
                ),
              ),
              _buildCloseButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckBadge() {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.check_rounded, size: 56, color: _primary),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _summaryRow('Charger', chargerName),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Date', dateLabel),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Time', timeLabel),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Duration', durationLabel),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Status', 'Confirmed', valueColor: _primary),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    Color valueColor = _dark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed-width label column so every value starts at the same x,
        // keeping the right-hand values aligned down the card.
        Container(
          width: 110,
          child: Text(
            label,
            style: TextStyle(fontSize: 15, color: _muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: const Text(
          'Done',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
