import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/reservation_confirmed_screen.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// Review step shown after the driver taps "Next" on the reserve screen. It
/// lays out the full booking summary and holds the single "Confirm
/// Reservation" action, which inserts the `reservations` row and, on success,
/// moves on to the confirmation screen.
///
/// Returns a [ReservationSummaryResult] when popped so the reserve screen knows
/// whether the booking went through (leave the flow) or failed because the
/// slot was just taken (refresh and let the driver pick again).
class ReservationSummaryScreen extends StatefulWidget {
  const ReservationSummaryScreen({
    super.key,
    required this.charger,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.fee,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
    this.reservationController,
  });

  final Charger charger;
  final DateTime date;

  /// Full local start/end timestamps of the booking.
  final DateTime startTime;
  final DateTime endTime;

  final int durationMinutes;
  final int fee;

  /// Pre-formatted labels, so this screen matches the reserve screen exactly.
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;

  final ReservationController? reservationController;

  @override
  State<ReservationSummaryScreen> createState() =>
      _ReservationSummaryScreenState();
}

/// Outcome reported back to the reserve screen when this screen is popped.
enum ReservationSummaryResult {
  /// Booking saved (and the confirmation screen was shown and dismissed).
  booked,

  /// Insert failed because the slot was just taken — reserve screen should
  /// refresh the day and let the driver pick again.
  slotTaken,
}

class _ReservationSummaryScreenState extends State<ReservationSummaryScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF3F4F6);

  late final ReservationController _reservationController =
      widget.reservationController ??
          ReservationController(ReservationSupabaseService());

  /// True while an insert is in flight, so the button shows a spinner and
  /// double-taps are blocked.
  bool _isBooking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _buildHeader(),
            const Padding(padding: EdgeInsets.only(top: 20)),
            _buildChargerCard(),
            const Padding(padding: EdgeInsets.only(top: 24)),
            _buildSummary(),
          ],
        ),
      ),
      bottomNavigationBar: _buildConfirmBar(),
    );
  }

  // --- Header ---------------------------------------------------------------

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.arrow_back, color: _dark, size: 22),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 14)),
        const Text(
          'Review Booking',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
      ],
    );
  }

  // --- Charger card ---------------------------------------------------------

  Widget _buildChargerCard() {
    final charger = widget.charger;
    final specParts = <String>[
      charger.powerLabel,
      if (charger.chargerType.isNotEmpty) charger.chargerType,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      '฿${charger.pricePerKwh.toStringAsFixed(2)}/kWh',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            charger.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            specParts.join(' · '),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Summary --------------------------------------------------------------

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Summary',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Date', widget.dateLabel),
          const Padding(padding: EdgeInsets.only(top: 10)),
          _summaryRow('Time', widget.timeLabel),
          const Padding(padding: EdgeInsets.only(top: 10)),
          _summaryRow('Duration', widget.durationLabel),
          const Padding(padding: EdgeInsets.only(top: 12)),
          Divider(height: 1, color: _primary.withValues(alpha: 0.25)),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _summaryRow('Booking fee', '฿${widget.fee}', emphasize: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: emphasize ? _dark : _muted,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
      ],
    );
  }

  // --- Confirm bar ----------------------------------------------------------

  Widget _buildConfirmBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 56,
        child: ElevatedButton(
          onPressed: _isBooking ? null : _onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: _isBooking
              ? Container(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Confirm Reservation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }

  Future<void> _onConfirm() async {
    // The booking is tied to the signed-in driver's profile (FK -> profiles).
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showMessage('Please sign in before booking.');
      return;
    }

    setState(() => _isBooking = true);
    try {
      await _reservationController.createReservation(
        userId: userId,
        chargerId: widget.charger.id,
        startTime: widget.startTime,
        endTime: widget.endTime,
        durationMinutes: widget.durationMinutes,
      );

      if (!mounted) return;
      // Show the confirmation screen; when it's dismissed, leave the summary
      // and tell the reserve screen the booking is done.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReservationConfirmedScreen(
            chargerName: widget.charger.name,
            dateLabel: widget.dateLabel,
            timeLabel: widget.timeLabel,
            durationLabel: widget.durationLabel,
          ),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(ReservationSummaryResult.booked);
    } catch (_) {
      if (!mounted) return;
      // Most likely cause: someone booked an overlapping slot first and the
      // DB's no-overlap constraint rejected this insert. Return to the reserve
      // screen so it can refresh and let the driver pick again.
      _showMessage(
        'Couldn\'t complete the booking. Those times may have just been '
        'taken — please pick again.',
      );
      Navigator.of(context).pop(ReservationSummaryResult.slotTaken);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
