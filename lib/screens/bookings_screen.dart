import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// "My Bookings" tab. Lists the signed-in driver's reservations with filter
/// chips for All / Confirmed / Completed / Cancelled.
///
/// For now this is read-only: the per-card action buttons (Start, Review,
/// cancel) are shown to match the status but don't do anything yet.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, this.controller});

  /// Optional injected controller (useful for tests). Falls back to a default
  /// Supabase-backed controller when not provided.
  final ReservationController? controller;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

/// The filter chips across the top. [all] shows everything; the rest map to a
/// single reservation status.
enum _BookingFilter { all, confirmed, completed, cancelled }

extension _BookingFilterLabel on _BookingFilter {
  String get label {
    switch (this) {
      case _BookingFilter.all:
        return 'All';
      case _BookingFilter.confirmed:
        return 'Confirmed';
      case _BookingFilter.completed:
        return 'Completed';
      case _BookingFilter.cancelled:
        return 'Cancelled';
    }
  }

  /// The reservation status this filter matches, or null for "All".
  String? get status {
    switch (this) {
      case _BookingFilter.all:
        return null;
      case _BookingFilter.confirmed:
        return 'confirmed';
      case _BookingFilter.completed:
        return 'completed';
      case _BookingFilter.cancelled:
        return 'cancelled';
    }
  }
}

class _BookingsScreenState extends State<BookingsScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF3F4F6);
  static const Color _chipBg = Color(0xFFEFF1F3);

  late final ReservationController _controller =
      widget.controller ?? ReservationController(ReservationSupabaseService());

  _BookingFilter _filter = _BookingFilter.confirmed;

  List<Reservation> _reservations = List.empty();
  bool _isLoading = true;
  bool _hasError = false;

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

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _reservations = List.empty();
        _isLoading = false;
      });
      return;
    }

    try {
      final rows = await _controller.fetchReservationsByUser(userId);
      if (!mounted) return;
      setState(() {
        _reservations = rows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  /// The reservations matching the active filter.
  List<Reservation> get _visible {
    final status = _filter.status;
    if (status == null) return _reservations;
    return _reservations.where((r) => r.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilters(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // --- Header ---------------------------------------------------------------

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        'My Bookings',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: _dark,
        ),
      ),
    );
  }

  // --- Filters --------------------------------------------------------------

  Widget _buildFilters() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final filter in _BookingFilter.values) ...[
            _filterChip(filter),
            const Padding(padding: EdgeInsets.only(left: 10)),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(_BookingFilter filter) {
    final selected = filter == _filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: Container(
        // Size to the label; no alignment, so it doesn't try to expand into
        // the horizontal list's unbounded width.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? _primary : _primary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          filter.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : _dark,
          ),
        ),
      ),
    );
  }

  // --- Body -----------------------------------------------------------------

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_hasError) {
      return _emptyState(
        icon: Icons.error_outline,
        message: 'Couldn\'t load your bookings. Pull to try again.',
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return _emptyState(
        icon: Icons.calendar_today_outlined,
        message: _reservations.isEmpty
            ? 'No bookings yet.'
            : 'No ${_filter.label.toLowerCase()} bookings.',
      );
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: visible.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _bookingCard(visible[index]),
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return ListView(
      // Keep pull-to-refresh working even when empty.
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
      children: [
        Icon(icon, size: 44, color: Colors.grey.shade400),
        const Padding(padding: EdgeInsets.only(top: 12)),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // --- Booking card ---------------------------------------------------------

  Widget _bookingCard(Reservation r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTopRow(r),
          const Padding(padding: EdgeInsets.only(top: 16)),
          _cardStatsRow(r),
          const Padding(padding: EdgeInsets.only(top: 16)),
          _cardFooter(r),
        ],
      ),
    );
  }

  Widget _cardTopRow(Reservation r) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt, color: _primary, size: 24),
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.chargerName.isNotEmpty ? r.chargerName : 'Charger',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              if (r.chargerAddress.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  r.chargerAddress,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 8)),
        _statusBadge(r),
      ],
    );
  }

  Widget _statusBadge(Reservation r) {
    final Color bg;
    final Color fg;
    switch (r.status) {
      case 'confirmed':
      case 'completed':
        bg = _primary.withValues(alpha: 0.15);
        fg = const Color(0xFF0F8A5F);
        break;
      case 'cancelled':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        break;
      default:
        bg = _chipBg;
        fg = _muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _capitalize(r.status),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  /// Date, time and duration stacked as three full-width rows inside one grey
  /// panel. Each value gets the whole card width, so nothing is truncated on
  /// narrow screens or with a large system font size.
  Widget _cardStatsRow(Reservation r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _statRow('Date', r.dateLabel),
          _statRow('Time', r.timeRangeLabel),
          _statRow('Duration', r.durationLabel),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          // Value takes the remaining width and may wrap rather than being
          // cut off if the screen is extremely narrow.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardFooter(Reservation r) {
    return Row(
      children: [
        Expanded(
          child: Text(
            r.chargerPowerLabel,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ),
        ..._cardActions(r),
      ],
    );
  }

  /// The trailing action buttons, which differ by status. Purely visual for
  /// now — none of them are wired up.
  List<Widget> _cardActions(Reservation r) {
    switch (r.status) {
      case 'confirmed':
        return [
          _primaryAction('Start'),
          const Padding(padding: EdgeInsets.only(left: 8)),
          _cancelAction(),
        ];
      case 'completed':
        return [_softAction('Review')];
      case 'cancelled':
        return const [];
      default:
        return const [];
    }
  }

  Widget _primaryAction(String label) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _softAction(String label) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: _primary,
        ),
      ),
    );
  }

  Widget _cancelAction() {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.close, color: Color(0xFFB91C1C), size: 20),
    );
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
