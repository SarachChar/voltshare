import 'package:flutter/material.dart';

import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/screens/charging_session_screen.dart';

/// Shown after the driver taps "Start" on a booking. Asks them to plug the
/// charging cable into their car first; confirming closes this page and opens
/// the [ChargingSessionScreen] in its place.
class PlugInScreen extends StatelessWidget {
  const PlugInScreen({super.key, required this.reservation});

  final Reservation reservation;

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

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
              _buildConfirmButton(context),
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

  Widget _buildConfirmButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        // Replace this page so "back" from the session returns to Bookings.
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChargingSessionScreen(reservation: reservation),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: const Text(
          'I\'ve Plugged In',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
