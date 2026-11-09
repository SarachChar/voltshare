import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/controllers/review_controller.dart';
import 'package:voltshare_app/models/host_revenue_model.dart'
    show lastSixMonths, monthLabel;
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/screens/charging_session_screen.dart';
import 'package:voltshare_app/screens/leave_review_screen.dart';
import 'package:voltshare_app/screens/plug_in_screen.dart';
import 'package:voltshare_app/screens/session_detail_screen.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// "My Bookings" tab. Lists the signed-in driver's reservations for one month
/// (dropdown: current month + 5 before, like the host Revenue tab) with
/// filter chips for All / Confirmed / Completed / Cancelled. Only the picked
/// month is queried; "This month" also includes upcoming bookings in later
/// months so confirmed bookings booked ahead are never hidden.
///
/// "Start" re-checks the booking (still confirmed, slot has begun) and then
/// opens the plug-in prompt → charging session. Cancel (X) is wired up;
/// "Review" opens the review form, or the submitted review read-only.
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

  final List<DateTime> _months = lastSixMonths();
  late DateTime _selectedMonth = _months.first;

  List<Reservation> _reservations = List.empty();
  bool _isLoading = true;
  bool _hasError = false;

  /// Ignores responses from an older request when the month changes quickly.
  int _requestId = 0;

  /// Id of the booking whose "Start" check is in flight, so its button shows
  /// a spinner and repeated taps are ignored.
  String? _startingId;

  @override
  void initState() {
    super.initState();
    // The charging flow replaces routes, so we can't rely on awaiting the
    // pushed route to know when to refresh; listen for its changes instead.
    ChargingSessionController.changes.addListener(_onChargingChanged);
    ReviewController.changes.addListener(_onChargingChanged);
    _load();
  }

  @override
  void dispose() {
    ChargingSessionController.changes.removeListener(_onChargingChanged);
    ReviewController.changes.removeListener(_onChargingChanged);
    super.dispose();
  }

  void _onChargingChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
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

    // Local month window. The current month has no upper bound so upcoming
    // bookings in next month (bookable ahead) still show up.
    final from = _selectedMonth;
    final to = _selectedMonth == _months.first
        ? null
        : DateTime(from.year, from.month + 1);

    try {
      final rows = await _controller.fetchReservationsByUser(
        userId,
        from: from,
        to: to,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _reservations = rows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _selectMonth(DateTime month) {
    if (month == _selectedMonth) return;
    setState(() => _selectedMonth = month);
    _load();
  }

  /// The reservations matching the active filter. [_reservations] arrives
  /// newest first (start_time desc), which every tab keeps except Confirmed:
  /// upcoming bookings read better soonest first, so that tab is ascending.
  List<Reservation> get _visible {
    final status = _filter.status;
    if (status == null) return _reservations;
    final rows = _reservations.where((r) => r.status == status).toList();
    if (_filter == _BookingFilter.confirmed) {
      rows.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return rows;
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
            _buildMonthPicker(),
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

  // --- Month picker ---------------------------------------------------------

  Widget _buildMonthPicker() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: _selectedMonth,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down, color: _dark),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _dark,
          ),
          items: [
            for (final month in _months)
              DropdownMenuItem(
                value: month,
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 20,
                      color: _primary,
                    ),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    Text(
                      month == _months.first
                          ? '${monthLabel(month)} (This month)'
                          : monthLabel(month),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (month) {
            if (month != null) _selectMonth(month);
          },
        ),
      ),
    );
  }

  // --- Filters --------------------------------------------------------------

  Widget _buildFilters() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8, bottom: 12),
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
      return _refreshable(
        _emptyState(
          icon: Icons.error_outline,
          message: 'Couldn\'t load your bookings. Pull to try again.',
        ),
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return _refreshable(
        _emptyState(
          icon: Icons.calendar_today_outlined,
          message: _reservations.isEmpty
              ? 'No bookings in ${monthLabel(_selectedMonth)}.'
              : 'No ${_filter.label.toLowerCase()} bookings in '
                    '${monthLabel(_selectedMonth)}.',
        ),
      );
    }

    return _refreshable(
      ListView.builder(
        // Always scrollable so pull-to-refresh works with only a few cards.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: visible.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _bookingCard(visible[index]),
        ),
      ),
    );
  }

  /// Wraps a scrollable in pull-to-refresh that reloads the bookings.
  Widget _refreshable(Widget child) {
    return RefreshIndicator(color: _primary, onRefresh: _load, child: child);
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return ListView(
      // A scrollable (even when empty) is what lets pull-to-refresh trigger.
      physics: const AlwaysScrollableScrollPhysics(),
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
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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

    // Completed cards open the session summary; the Review button inside
    // keeps its own tap.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: r.isCompleted
          ? InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openSessionDetail(r),
              child: card,
            )
          : card,
    );
  }

  void _openSessionDetail(Reservation r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionDetailScreen(reservation: r)),
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
                r.stationTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              if (r.chargerLine.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  r.chargerLine,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
              ],
              if (r.stationAddress.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  r.stationAddress,
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
    final badge = _badge(_capitalize(r.status), bg, fg);
    if (!(r.isCancelled && r.isFeeRefunded)) return badge;

    // Cancelled because the charger was unavailable: fee was refunded.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        badge,
        const Padding(padding: EdgeInsets.only(top: 6)),
        _badge(
          'Refunded',
          _primary.withValues(alpha: 0.15),
          const Color(0xFF0F8A5F),
        ),
      ],
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
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
          // Completed: actual charging times + cost instead of the booked
          // slot and duration.
          if (r.isCompleted) ...[
            _statRow('Time', r.sessionTimeRangeLabel),
            _statRow('Charging cost', r.chargingCostLabel),
          ] else ...[
            _statRow('Time', r.timeRangeLabel),
            _statRow('Duration', r.durationLabel),
          ],
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
    // Power now sits in the charger line at the top of the card, so the
    // footer only holds the actions, right-aligned.
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: _cardActions(r),
    );
  }

  /// The trailing action buttons, which differ by status.
  List<Widget> _cardActions(Reservation r) {
    switch (r.status) {
      case 'confirmed':
        return [
          _startAction(r),
          const Padding(padding: EdgeInsets.only(left: 8)),
          _cancelAction(r),
        ];
      case 'completed':
        // Not reviewed yet: write one. Reviewed: open it read-only.
        return [
          _softAction(
            r.review == null ? 'Review' : 'View Review',
            onTap: () => _openReview(r),
          ),
        ];
      case 'cancelled':
        return const [];
      default:
        return const [];
    }
  }

  Widget _startAction(Reservation r) {
    final isStarting = _startingId == r.id;
    return Material(
      color: _primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _startingId == null ? () => _onStart(r) : null,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          child: isStarting
              ? Container(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Start',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  /// Length of one bookable slot, matching the reservation grid.
  static const Duration _slotLength = Duration(minutes: 30);

  /// Before starting a session, re-fetches the booking and checks that:
  ///   1. it's still confirmed (the cron job may have auto-cancelled it), and
  ///   2. it's time to charge: either the booked slot has begun, or the
  ///      booking is the very next slot and nobody is charging on the charger
  ///      right now (no other confirmed reservation with `started_at`).
  /// On failure an error dialog is shown and nothing else happens; otherwise
  /// the plug-in prompt opens (which then leads to the charging session).
  Future<void> _onStart(Reservation r) async {
    setState(() => _startingId = r.id);

    Reservation? latest;
    String? timingError;
    try {
      latest = await _controller.fetchReservationById(r.id);
      if (latest != null && latest.isConfirmed && !latest.isCharging) {
        timingError = await _startBlockedReason(latest);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _startingId = null);
      await _showStartError(
        'Couldn\'t check this booking. Please check your connection and try '
        'again.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _startingId = null);

    // 0. Already charging (e.g. left the app mid-session): resume directly.
    if (latest != null && latest.isCharging) {
      final reservation = latest.chargerName.isNotEmpty ? latest : r;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChargingSessionScreen(reservation: reservation),
        ),
      );
      return;
    }

    // 1. Still confirmed?
    if (latest == null || !latest.isConfirmed) {
      final message = latest == null
          ? 'This booking no longer exists.'
          : latest.isCancelled
          ? 'This booking was cancelled because charging wasn\'t started '
                'within 15 minutes of the booked start time. The booking '
                'fee is non-refundable.'
          : 'This booking is already ${latest.status}.';
      await _showStartError(message);
      // Refresh so the card reflects its real status.
      if (mounted) await _load();
      return;
    }

    // 2. Is it time to charge?
    if (timingError != null) {
      await _showStartError(timingError);
      return;
    }

    // Keep the joined charger fields from the list row in case they're
    // missing on the re-fetched copy.
    final reservation = latest.chargerName.isNotEmpty ? latest : r;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlugInScreen(reservation: reservation)),
    );
  }

  /// Returns why [r] can't start charging yet, or null if it can. Only covers
  /// timing; the status check is done by the caller. Throws if the
  /// active-session lookup fails.
  Future<String?> _startBlockedReason(Reservation r) async {
    final now = DateTime.now();

    // Booked slot has started: allowed (no check for an overrunning session).
    if (!now.isBefore(r.startTime)) return null;

    final startLabel = r.timeRangeLabel.split(' - ').first;

    // More than one slot early: the next slot isn't ours yet.
    if (now.isBefore(r.startTime.subtract(_slotLength))) {
      return 'It\'s not time yet. Your booking starts on ${r.dateLabel} at '
          '$startLabel. You can start up to ${_slotLength.inMinutes} minutes '
          'early if the charger is free.';
    }

    // Our booking is the next slot: start early only if nobody is charging
    // on this charger right now.
    final inUse = await _controller.hasActiveSessionOnCharger(
      chargerId: r.chargerId,
      excludeReservationId: r.id,
    );
    if (inUse) {
      return 'The charger is still in use by another driver. Please wait '
          'until your booking starts at $startLabel.';
    }
    return null;
  }

  Future<void> _showStartError(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Can\'t start charging'),
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

  Widget _softAction(String label, {VoidCallback? onTap}) {
    return Material(
      color: _primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the review screen: a form if [r] isn't reviewed yet, otherwise
  /// the existing review read-only.
  Future<void> _openReview(Reservation r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LeaveReviewScreen(reservation: r, review: r.review),
      ),
    );
  }

  Widget _cancelAction(Reservation r) {
    return Material(
      color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onCancel(r),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: const Icon(Icons.close, color: Color(0xFFB91C1C), size: 20),
        ),
      ),
    );
  }

  /// Confirms, then cancels a booking (no refund of the booking fee).
  Future<void> _onCancel(Reservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text(
          'This booking will be cancelled. The booking fee is '
          'non-refundable and will not be returned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep booking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Cancel booking',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _controller.cancelReservation(r.id);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t cancel the booking.')),
      );
    }
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
