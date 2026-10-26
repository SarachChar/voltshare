import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/screens/charger_unavailable_screen.dart';
import 'package:voltshare_app/screens/charging_session_screen.dart';
import 'package:voltshare_app/services/charging_session_service.dart';

/// Shown after the driver taps "Start" on a booking. Asks them to plug the
/// charging cable into their car first. "I've Plugged In" asks the (mock)
/// charger for its connector status (`ocpp-status`):
///   - Available   -> this page is replaced by the [ChargingSessionScreen]
///   - Unavailable -> the booking is cancelled and its fee refunded
///                    (`refund-booking-fee`), then this page is replaced by
///                    [ChargerUnavailableScreen]. If the refund call fails, an
///                    error popup lets the driver retry from here.
class PlugInScreen extends StatefulWidget {
  const PlugInScreen({super.key, required this.reservation, this.controller});

  final Reservation reservation;
  final ChargingSessionController? controller;

  @override
  State<PlugInScreen> createState() => _PlugInScreenState();
}

class _PlugInScreenState extends State<PlugInScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  late final ChargingSessionController _controller =
      widget.controller ??
      ChargingSessionController(ChargingSessionSupabaseService());

  /// True while the status check is in flight.
  bool _isChecking = false;

  Reservation get reservation => widget.reservation;

  Future<void> _onPluggedIn() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    // 1. Ask the (mock) charger for its status.
    ChargerStatus status;
    try {
      status = await _controller.checkChargerStatus(reservation.chargerId);
    } on ChargingException catch (e) {
      return _fail('Couldn\'t check the charger', e.userMessage);
    } catch (_) {
      return _fail(
        'Couldn\'t check the charger',
        'Please check your connection and try again.',
      );
    }

    if (!mounted) return;
    if (status.isAvailable) {
      setState(() => _isChecking = false);
      // Replace this page so "back" from the session returns to Bookings.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChargingSessionScreen(reservation: reservation),
        ),
      );
      return;
    }

    // 2. Unavailable: cancel the booking and refund the fee.
    double refunded;
    try {
      refunded = await _controller.refundBookingFee(reservation.id);
    } on ChargingException catch (e) {
      return _fail('Couldn\'t refund the booking fee', e.userMessage);
    } catch (_) {
      return _fail(
        'Couldn\'t refund the booking fee',
        'Please check your connection and try again.',
      );
    }

    if (!mounted) return;
    setState(() => _isChecking = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChargerUnavailableScreen(
          reason: status.userMessage,
          refundedAmount: refunded,
        ),
      ),
    );
  }

  Future<void> _fail(String title, String message) async {
    if (!mounted) return;
    setState(() => _isChecking = false);
    await _showError(title, message);
  }

  Future<void> _showError(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'OK',
              style: TextStyle(fontWeight: FontWeight.w700, color: _primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _dark,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildIconBadge(),
                        const Padding(padding: EdgeInsets.only(top: 24)),
                        const Text(
                          'Plug In Your Car',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: _dark,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 12)),
                        Text(
                          'Connect the charging cable to your vehicle\'s '
                          'charging port, then tap the button below to start '
                          'charging.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (reservation.chargerName.isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.only(top: 20)),
                          Text(
                            '${reservation.chargerName} · '
                            '${reservation.timeRangeLabel}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _dark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _buildConfirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconBadge() {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Icon(Icons.power_rounded, size: 56, color: _primary),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        // Stays green (not disabled-grey) while checking.
        onPressed: _isChecking ? () {} : _onPluggedIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: _isChecking
            ? Container(
                width: 24,
                height: 24,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'I\'ve Plugged In',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}
