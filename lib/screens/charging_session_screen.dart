import 'package:flutter/material.dart';

import 'package:voltshare_app/models/reservation_model.dart';

/// Live charging session for a reservation. Placeholder for now; the session
/// UI (energy delivered, timer, stop button, etc.) will be built here.
class ChargingSessionScreen extends StatelessWidget {
  const ChargingSessionScreen({super.key, required this.reservation});

  final Reservation reservation;

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
        title: const Text(
          'Charging Session',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Container(),
    );
  }
}
