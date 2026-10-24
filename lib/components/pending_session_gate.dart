import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/screens/charging_session_screen.dart';
import 'package:voltshare_app/screens/session_summary_screen.dart';
import 'package:voltshare_app/services/charging_session_service.dart';

/// Wraps the Home screen and forces the driver back into an unfinished
/// charging flow:
///   - a session still charging  -> Charging Session screen
///   - a finished, unpaid session -> Session Summary (pay) screen
///
/// Checked when the gate first appears (app launch / sign-in) and whenever the
/// app returns to the foreground while Home is the top screen. Both target
/// screens block the back gesture, so the driver can't leave until the
/// session is stopped and paid.
class PendingSessionGate extends StatefulWidget {
  const PendingSessionGate({super.key, required this.child, this.controller});

  final Widget child;
  final ChargingSessionController? controller;

  @override
  State<PendingSessionGate> createState() => _PendingSessionGateState();
}

class _PendingSessionGateState extends State<PendingSessionGate>
    with WidgetsBindingObserver {
  late final ChargingSessionController _controller = widget.controller ??
      ChargingSessionController(ChargingSessionSupabaseService());

  /// True while a check is running or a forced screen is open.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // Only redirect from Home itself; if the driver is already somewhere in
    // the charging flow (or any other pushed screen), leave them be.
    if (_busy || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    _busy = true;
    try {
      final pending = await _controller.findPendingSession();
      if (!mounted || pending == null) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

      final session = pending.session;
      final Widget screen;
      if (pending.isUnpaid) {
        screen = SessionSummaryScreen(sessionId: session.id);
      } else {
        final reservation = session.reservation;
        if (reservation == null) return;
        screen = ChargingSessionScreen(reservation: reservation);
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    } catch (_) {
      // Offline etc.: don't block the app; we'll check again on next resume.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
