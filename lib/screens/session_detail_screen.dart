import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/session_payment_model.dart';
import 'package:voltshare_app/services/charging_session_service.dart';

/// Read-only summary of a completed booking's charging session, opened by
/// tapping a Completed card on My Bookings: charger, actual start/end, charging time, energy delivered and the cost breakdown.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.reservation,
    this.controller,
  });

  /// The booking from the list (used for the header while loading, and as a
  /// fallback for charger fields).
  final Reservation reservation;
  final ChargingSessionController? controller;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _border = Color(0xFFC8EDE0);
  static const Color _mint = Color(0xFFE8F8F3);

  late final ChargingSessionController _controller =
      widget.controller ??
      ChargingSessionController(ChargingSessionSupabaseService());

  ChargingSession? _session;
  SessionPayment? _payment;
  bool _isLoading = true;
  bool _hasError = false;

  Reservation get _r => _session?.reservation ?? widget.reservation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final session = await _controller.fetchSessionByReservation(
        widget.reservation.id,
      );
      final payment = session == null
          ? null
          : await _controller.fetchPayment(session.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _payment = payment;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: _buildHeader(),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.arrow_back, color: _navy, size: 22),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 16)),
        const Text(
          'Session Details',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildChargerCard(),
          const Padding(padding: EdgeInsets.only(top: 16)),
          if (_hasError)
            _message('Couldn\'t load this session. Pull to try again.')
          else if (_session == null)
            _message('No charging session was recorded for this booking.')
          else ...[
            _buildHighlights(_session!),
            const Padding(padding: EdgeInsets.only(top: 16)),
            _buildTimeCard(_session!),
            const Padding(padding: EdgeInsets.only(top: 16)),
            _buildCostCard(_session!, _payment),
          ],
        ],
      ),
    );
  }

  Widget _buildChargerCard() {
    final r = _r;

    return _card(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.bolt, color: _primary, size: 28),
          ),
          const Padding(padding: EdgeInsets.only(left: 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.chargerName.isNotEmpty ? r.chargerName : 'Charger',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                if (r.chargerAddress.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 2)),
                  Text(
                    r.chargerAddress,
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

  /// Energy and charging time, side by side.
  Widget _buildHighlights(ChargingSession s) {
    return Row(
      children: [
        Expanded(
          child: _highlight(
            icon: Icons.bolt_outlined,
            label: 'ENERGY',
            value: '${(s.totalEnergyKwh ?? 0).toStringAsFixed(2)} kWh',
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        Expanded(
          child: _highlight(
            icon: Icons.schedule,
            label: 'CHARGING TIME',
            value: _durationLabel(s.elapsed),
          ),
        ),
      ],
    );
  }

  Widget _highlight({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(icon, color: _primary, size: 24),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 4)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard(ChargingSession s) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Session'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _row('Date', _r.dateLabel),
          _row('Started', _dateTimeLabel(s.startedAt)),
          _row('Ended', s.endedAt == null ? '-' : _dateTimeLabel(s.endedAt!)),
        ],
      ),
    );
  }

  Widget _buildCostCard(ChargingSession s, SessionPayment? p) {
    final energy = s.totalEnergyKwh ?? 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Cost'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _row('Rate', '฿${s.pricePerKwhAtStart.toStringAsFixed(2)}/kWh'),
          _row(
            'Energy charge',
            p == null ? '-' : _baht(p.energyAmount),
            hint:
                '${energy.toStringAsFixed(2)} kWh × '
                '฿${s.pricePerKwhAtStart.toStringAsFixed(2)}',
          ),
          if (p != null && p.bookingFeeDeducted > 0)
            _row(
              'Booking fee paid',
              '-${_baht(p.bookingFeeDeducted)}',
              hint: 'Deducted from total',
              valueColor: _primary,
            ),
          Container(
            height: 1,
            color: _border,
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total paid',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                p == null ? '-' : _baht(p.totalAmount),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _primary,
                ),
              ),
            ],
          ),
          if (p != null) ...[
            const Padding(padding: EdgeInsets.only(top: 8)),
            _row(
              'Payment',
              _paymentStatusLabel(p.status),
              valueColor: p.isPaid ? _primary : const Color(0xFFDC2626),
            ),
            if (p.paidAt != null) _row('Paid on', _dateTimeLabel(p.paidAt!)),
          ],
        ],
      ),
    );
  }

  // --- Pieces ---------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _cardTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _navy,
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    String? hint,
    Color valueColor = _navy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 15, color: _muted),
                ),
                if (hint != null) ...[
                  const Padding(padding: EdgeInsets.only(top: 2)),
                  Text(
                    hint,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(Icons.info_outline, size: 44, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 12)),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Formatting -----------------------------------------------------------

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "Oct 24, 2026 16:04".
  static String _dateTimeLabel(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year} '
      '${_two(d.hour)}:${_two(d.minute)}';

  /// "1 hr 17 min", "34 min", "45 sec".
  static String _durationLabel(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} sec';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours} hr' : '${d.inHours} hr $m min';
  }

  static String _baht(double v) => '฿${v.toStringAsFixed(2)}';

  static String _paymentStatusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      default:
        return 'Unpaid';
    }
  }
}
