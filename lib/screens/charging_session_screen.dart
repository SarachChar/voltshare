import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:voltshare_app/components/primary_button.dart';
import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/session_stream_model.dart';
import 'package:voltshare_app/screens/session_summary_screen.dart';
import 'package:voltshare_app/services/charging_session_service.dart';

/// Live charging session for a reservation.
///
/// Two states:
///   - Ready: no session yet. "Start Charging" calls `ocpp-remote-start`.
///   - Charging: values come from the charger's MeterValues stream
///     (`session_streams`, via Realtime). Duration ticks locally from
///     `started_at`; cost = price at start × energy received.
/// When the session completes (Stop Charging, or the charger auto-stops on
/// time up / battery full) the screen moves on to [SessionSummaryScreen].
///
/// While charging the driver can't leave this screen (no back button, back
/// gesture blocked) until the session is stopped.
class ChargingSessionScreen extends StatefulWidget {
  const ChargingSessionScreen({
    super.key,
    required this.reservation,
    this.controller,
  });

  final Reservation reservation;
  final ChargingSessionController? controller;

  @override
  State<ChargingSessionScreen> createState() => _ChargingSessionScreenState();
}

class _ChargingSessionScreenState extends State<ChargingSessionScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _mint = Color(0xFFE8F8F3);
  static const Color _mintBorder = Color(0xFFC8EDE0);
  static const Color _lime = Color(0xFF84CC16);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _cream = Color(0xFFFFFBEB);
  static const Color _creamBorder = Color(0xFFFDEFC3);
  static const Color _danger = Color(0xFFDC2626);

  late final ChargingSessionController _controller = widget.controller ??
      ChargingSessionController(ChargingSessionSupabaseService());

  /// Pulsing halo around the ring while charging.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  ChargingSession? _session;
  SessionStream? _latest;

  bool _isLoading = true;
  bool _isStarting = false;
  bool _isStopping = false;

  /// Set once we've moved on to the summary, so the session stream and the
  /// stop call can't both navigate.
  bool _leaving = false;

  StreamSubscription<SessionStream?>? _readingSub;
  StreamSubscription<ChargingSession?>? _sessionSub;
  Timer? _ticker;

  Reservation get _reservation => _session?.reservation ?? widget.reservation;

  bool get _isCharging => _session?.isCharging ?? false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _sessionSub?.cancel();
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // --- Data -----------------------------------------------------------------

  /// Resumes an existing session for this reservation (e.g. app reopened).
  Future<void> _loadExisting() async {
    try {
      final session =
          await _controller.fetchSessionByReservation(widget.reservation.id);
      if (!mounted) return;
      if (session != null && session.isCompleted) {
        _goToSummary(session.id);
        return;
      }
      setState(() {
        _session = session;
        _isLoading = false;
      });
      if (session != null) _attach(session);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// Subscribes to the session's live readings and status.
  void _attach(ChargingSession session) {
    _readingSub?.cancel();
    _sessionSub?.cancel();

    _readingSub = _controller.watchLatestReading(session.id).listen((reading) {
      if (!mounted || reading == null) return;
      setState(() => _latest = reading);
    }, onError: (_) {});

    _sessionSub = _controller.watchSession(session.id).listen((updated) {
      if (!mounted || updated == null) return;
      if (updated.isCompleted) {
        _goToSummary(updated.id);
        return;
      }
      // Keep the embedded reservation (the realtime row doesn't carry it).
      setState(() => _session = ChargingSession(
            id: updated.id,
            reservationId: updated.reservationId,
            transactionId: updated.transactionId,
            pricePerKwhAtStart: updated.pricePerKwhAtStart,
            meterStartWh: updated.meterStartWh,
            startedAt: updated.startedAt,
            status: updated.status,
            reservation: _session?.reservation,
          ));
    }, onError: (_) {});

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isCharging) setState(() {});
    });
    _pulse.repeat();
  }

  void _goToSummary(String sessionId) {
    if (_leaving || !mounted) return;
    _leaving = true;
    _ticker?.cancel();
    _pulse.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionSummaryScreen(sessionId: sessionId),
      ),
    );
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _onStart() async {
    setState(() => _isStarting = true);
    try {
      await _controller.startCharging(widget.reservation.id);
      final session =
          await _controller.fetchSessionByReservation(widget.reservation.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _isStarting = false;
      });
      if (session != null) _attach(session);
    } on ChargingException catch (e) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      if (e.code == 'SESSION_ALREADY_STARTED') {
        // Started elsewhere (another device / double tap): just resume.
        await _loadExisting();
        return;
      }
      await _showError('Can\'t start charging', e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      await _showError(
        'Can\'t start charging',
        'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> _onStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop charging?'),
        content: const Text(
          'Charging will stop and you\'ll be asked to pay for the energy '
          'delivered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep charging'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Stop',
              style: TextStyle(fontWeight: FontWeight.w700, color: _danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isStopping = true);
    try {
      final result = await _controller.stopCharging(widget.reservation.id);
      if (!mounted) return;
      _goToSummary(result.sessionId);
    } on ChargingException catch (e) {
      if (!mounted) return;
      setState(() => _isStopping = false);
      if (e.code == 'NO_ACTIVE_TRANSACTION') {
        // Already stopped (e.g. auto-stop raced the tap): move on.
        await _loadExisting();
        return;
      }
      await _showError('Can\'t stop charging', e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isStopping = false);
      await _showError(
        'Can\'t stop charging',
        'Something went wrong. Please try again.',
      );
    }
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

  // --- Derived values -------------------------------------------------------

  double get _pricePerKwh =>
      _session?.pricePerKwhAtStart ?? _reservation.chargerPricePerKwh ?? 0;

  double get _energyKwh => _latest?.totalEnergyReceivedKwh ?? 0;

  double get _cost => _pricePerKwh * _energyKwh;

  String get _powerLabel {
    final power = _latest?.powerKw;
    if (!_isCharging || power == null) return '— kW';
    return power >= 10
        ? '${power.round()} kW'
        : '${power.toStringAsFixed(1)} kW';
  }

  String get _durationLabel {
    final elapsed = _session?.elapsed ?? Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canLeave = !_isCharging && !_isStarting && !_isStopping;
    return PopScope(
      canPop: canLeave,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    _buildHeader(canLeave),
                    const Padding(padding: EdgeInsets.only(top: 28)),
                    Center(child: _buildRing()),
                    const Padding(padding: EdgeInsets.only(top: 28)),
                    _buildStats(),
                    const Padding(padding: EdgeInsets.only(top: 16)),
                    _buildEnergyCard(),
                    if (_isCharging) ...[
                      const Padding(padding: EdgeInsets.only(top: 16)),
                      _buildChargerCard(),
                    ],
                  ],
                ),
        ),
        bottomNavigationBar: _isLoading ? null : _buildBottomButton(),
      ),
    );
  }

  Widget _buildHeader(bool canLeave) {
    final subtitle = [
      _reservation.chargerName,
      _reservation.chargerSpecLabel,
    ].where((p) => p.isNotEmpty).join(' · ');

    return Stack(
      alignment: Alignment.center,
      children: [
        if (canLeave)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: _navy),
              tooltip: 'Back',
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            children: [
              const Text(
                'Charging Session',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: _muted),
                ),
              ],
              // Booked slot, so the driver knows when charging must end.
              const Padding(padding: EdgeInsets.only(top: 6)),
              Text(
                'Booked ${_reservation.timeRangeLabel}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRing() {
    final soc = _latest?.socPercent ?? 0;
    return Container(
      width: 230,
      height: 230,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => CustomPaint(
          painter: _RingPainter(
            charging: _isCharging,
            progress: (soc / 100).clamp(0.0, 1.0),
            pulse: _isCharging ? _pulse.value : null,
          ),
          child: child,
        ),
        child: Center(
          child: _isCharging ? _ringChargingLabel(soc) : _ringReadyLabel(),
        ),
      ),
    );
  }

  Widget _ringReadyLabel() {
    return Text(
      _isStarting ? 'Connecting…' : 'Ready to charge',
      style: const TextStyle(fontSize: 18, color: _muted),
    );
  }

  Widget _ringChargingLabel(double soc) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.battery_charging_full_rounded, size: 18, color: _lime),
            Padding(padding: EdgeInsets.only(left: 4)),
            Text('Battery', style: TextStyle(fontSize: 16, color: _muted)),
          ],
        ),
        Text(
          '${soc.floor()}%',
          style: const TextStyle(
            fontSize: 52,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: _navy,
          ),
        ),
        Text(
          _isStopping ? 'Stopping…' : 'Charging…',
          style: const TextStyle(fontSize: 16, color: _muted),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.bolt_outlined,
            iconColor: _lime,
            label: 'POWER',
            value: _powerLabel,
            background: _mint,
            border: _mintBorder,
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        Expanded(
          child: _statCard(
            icon: Icons.schedule,
            iconColor: _primary,
            label: 'DURATION',
            value: _durationLabel,
            background: _mint,
            border: _mintBorder,
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        Expanded(
          child: _statCard(
            icon: Icons.attach_money,
            iconColor: _amber,
            label: 'COST',
            value: '฿${_cost.toStringAsFixed(2)}',
            background: _cream,
            border: _creamBorder,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color background,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const Padding(padding: EdgeInsets.only(top: 10)),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _mintBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Energy delivered',
                  style: TextStyle(fontSize: 16, color: _muted),
                ),
              ),
              Text(
                '${_energyKwh.toStringAsFixed(3)} kWh',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 14)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rate',
                  style: TextStyle(fontSize: 16, color: _muted),
                ),
              ),
              Text(
                '฿${_pricePerKwh.toStringAsFixed(2)}/kWh',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChargerCard() {
    final r = _reservation;
    final details = [
      r.chargerConnectorType,
      r.chargerType,
      r.chargerAddress,
    ].where((p) => p.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: _primary, size: 26),
          ),
          const Padding(padding: EdgeInsets.only(left: 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.chargerName.isNotEmpty ? r.chargerName : 'Charger',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 2)),
                  Text(
                    details,
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: _isCharging ? _stopButton() : _startButton(),
    );
  }

  Widget _startButton() {
    return PrimaryButton(
      label: 'Start Charging',
      icon: Icons.bolt,
      isLoading: _isStarting,
      onPressed: _onStart,
    );
  }

  Widget _stopButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: _isStopping ? null : _onStop,
          child: Center(
            child: _isStopping
                ? Container(
                    width: 24,
                    height: 24,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _danger,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_rounded, color: _danger, size: 28),
                      Padding(padding: EdgeInsets.only(left: 8)),
                      Text(
                        'Stop Charging',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _danger,
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

/// Battery ring. Ready: plain track with a grey dot at the top. Charging:
/// track + a green arc for [progress] (SoC), plus an expanding, fading halo
/// driven by [pulse] (0..1).
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.charging,
    required this.progress,
    required this.pulse,
  });

  final bool charging;
  final double progress;
  final double? pulse;

  static const double _stroke = 12;
  static const Color _track = Color(0xFFD5EFE6);
  static const Color _arc = Color(0xFF8BD346);
  static const Color _dot = Color(0xFF9CA3AF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;

    final p = pulse;
    if (p != null) {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _arc.withValues(alpha: (1 - p) * 0.35);
      canvas.drawCircle(center, radius * (1 + 0.45 * p), halo);
    }

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = _track;
    canvas.drawCircle(center, radius, track);

    if (!charging) {
      canvas.drawCircle(
        Offset(center.dx, center.dy - radius),
        6,
        Paint()..color = _dot,
      );
      return;
    }

    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = _arc;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.charging != charging ||
      old.progress != progress ||
      old.pulse != pulse;
}
