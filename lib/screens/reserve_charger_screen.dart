import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/screens/reservation_summary_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// Reservation flow opened from the charger detail screen's "Book This
/// Charger" button. The driver picks a date, then one or more consecutive
/// 30-minute start-time slots, reviews a summary, and confirms.
///
/// The grid of time slots is derived from the charger's weekly opening hours
/// (`charger_availability`) for the selected day, with slots that overlap an
/// existing CONFIRMED booking (from the `reservations` table) disabled.
/// Confirming inserts a new `reservations` row tied to the signed-in driver's
/// profile and this charger.
class ReserveChargerScreen extends StatefulWidget {
  const ReserveChargerScreen({
    super.key,
    required this.charger,
    this.controller,
    this.reservationController,
  });

  final Charger charger;

  /// Optional injected charger controller (useful for tests). Falls back to a
  /// default Supabase-backed controller when not provided.
  final ChargerController? controller;

  /// Optional injected reservation controller (useful for tests). Falls back
  /// to a default Supabase-backed controller when not provided.
  final ReservationController? reservationController;

  @override
  State<ReserveChargerScreen> createState() => _ReserveChargerScreenState();
}

class _ReserveChargerScreenState extends State<ReserveChargerScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  /// Each reservable block is 30 minutes.
  static const int _slotMinutes = 30;

  /// Flat booking fee charged per 30-minute slot (THB).
  static const int _feePerSlot = 10;

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  late final ReservationController _reservationController =
      widget.reservationController ??
          ReservationController(ReservationSupabaseService());

  /// Weekly opening hours, normalized to a full Sun..Sat week. Drives which
  /// slots exist for the selected day.
  List<ChargerAvailability> _availability = List.empty();
  bool _isLoadingAvailability = true;

  /// True while loading existing bookings for the selected day.
  bool _isLoadingSlots = false;

  /// The month currently shown in the calendar (always the 1st of the month).
  late DateTime _visibleMonth;

  /// The day the driver has selected. Null until they tap a date.
  DateTime? _selectedDate;

  /// How many days ahead (including today) a driver may book.
  static const int _maxAdvanceDays = 7;

  /// Start-of-day "today", used to disable past dates.
  late final DateTime _today;

  /// Last bookable day, inclusive: today + 6 (a 7-day window including today).
  late final DateTime _maxDate;

  /// All selectable 30-minute slots for the selected day, in order.
  List<_TimeSlot> _slots = List.empty();

  /// True when the selected day has no opening hours at all (charger closed),
  /// as opposed to being open but having no bookable slots left (e.g. today's
  /// hours have already passed). Drives which empty-state message is shown.
  bool _dayIsClosed = false;

  /// Indexes into [_slots] that the driver has selected. Kept contiguous so
  /// the booking is always one unbroken block.
  final Set<int> _selectedSlots = <int>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _maxDate = _today.add(const Duration(days: _maxAdvanceDays - 1));
    _visibleMonth = DateTime(now.year, now.month);
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final rows =
          await _controller.fetchChargerAvailability(widget.charger.id);
      if (!mounted) return;
      setState(() {
        _availability =
            ChargerAvailability.fullWeek(widget.charger.id, rows);
        _isLoadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availability =
            ChargerAvailability.fullWeek(widget.charger.id, const []);
        _isLoadingAvailability = false;
      });
    }

    // Opening hours are loaded, so today's slots can now be built. Preselect
    // today and load its bookings so the driver lands on a ready-to-book day.
    if (!mounted) return;
    _selectDate(_today);
  }

  // --- Slot generation ------------------------------------------------------

  /// Called when the driver taps a date: records the selection, clears slots,
  /// then loads the existing bookings for that day and rebuilds the grid.
  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _selectedSlots.clear();
      _slots = List.empty();
      _isLoadingSlots = true;
    });

    List<Reservation> taken;
    try {
      taken = await _reservationController
          .fetchConfirmedReservationsForChargerOnDate(
        chargerId: widget.charger.id,
        date: date,
      );
    } catch (_) {
      // If the taken-slots lookup fails, fall back to showing every open slot
      // as available rather than blocking the whole day.
      taken = const [];
    }

    if (!mounted) return;
    // Ignore a stale result if the driver has since picked a different day.
    if (_selectedDate == null || !_isSameDay(_selectedDate!, date)) return;

    setState(() {
      _dayIsClosed = _isDayClosed(date);
      _slots = _buildSlots(date, taken);
      _isLoadingSlots = false;
    });
  }

  /// Whether the charger has no opening hours on [date] (closed that weekday).
  bool _isDayClosed(DateTime date) {
    final dow = date.weekday % 7; // Dart Mon=1..Sun=7 -> Sun=0
    final slot = _availability.firstWhere(
      (a) => a.dayOfWeek == dow,
      orElse: () =>
          ChargerAvailability.closed(chargerId: widget.charger.id, day: dow),
    );
    return slot.isClosed;
  }

  /// Builds the day's 30-minute slots from the charger's opening hours for
  /// [date], marking any slot that overlaps a [taken] reservation as
  /// unavailable.
  List<_TimeSlot> _buildSlots(DateTime date, List<Reservation> taken) {
    final dow = date.weekday % 7; // Dart Mon=1..Sun=7 -> Sun=0
    final slot = _availability.firstWhere(
      (a) => a.dayOfWeek == dow,
      orElse: () =>
          ChargerAvailability.closed(chargerId: widget.charger.id, day: dow),
    );

    if (slot.isClosed) return List.empty();

    final open = _parseMinutes(slot.startTime);
    final close = _parseMinutes(slot.endTime);
    if (open == null || close == null || close <= open) return List.empty();

    // Turn each taken booking into a [startMin, endMin) window relative to the
    // selected day, so we can test slot overlap in minutes-since-midnight.
    final dayStart = DateTime(date.year, date.month, date.day);
    final takenRanges = taken.map((r) {
      final startMin = r.startTime.difference(dayStart).inMinutes;
      final endMin = r.endTime.difference(dayStart).inMinutes;
      return _MinuteRange(startMin, endMin);
    }).toList();

    // When booking for today, drop slots whose start time has already passed —
    // you can't reserve a block in the past. For future days this is 0 so no
    // slots are cut. Compared as minutes-since-midnight against "now".
    final now = DateTime.now();
    final earliestStart = _isSameDay(date, now)
        ? now.hour * 60 + now.minute
        : 0;

    final slots = <_TimeSlot>[];
    for (int start = open; start + _slotMinutes <= close;
        start += _slotMinutes) {
      final end = start + _slotMinutes;
      // A block is unavailable when it overlaps an existing booking, or (today
      // only) when its start time has already passed. Past slots stay visible
      // but disabled, matching how booked slots look.
      final overlapsBooking =
          takenRanges.any((range) => start < range.end && end > range.start);
      final isPast = start <= earliestStart;
      slots.add(
        _TimeSlot(
          startMinutes: start,
          endMinutes: end,
          available: !overlapsBooking && !isPast,
        ),
      );
    }
    return slots;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Parses a "HH:mm" or "HH:mm:ss" time into minutes since midnight.
  static int? _parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  // --- Selection logic ------------------------------------------------------

  /// Handles a tap on the slot at [index]. Selection must stay one contiguous
  /// block: tapping extends the block when adjacent, starts fresh otherwise,
  /// and tapping an end of the block shrinks it.
  void _onSlotTap(int index) {
    final slot = _slots[index];
    if (!slot.available) return;

    setState(() {
      if (_selectedSlots.isEmpty) {
        _selectedSlots.add(index);
        return;
      }

      final min = _selectedSlots.reduce((a, b) => a < b ? a : b);
      final max = _selectedSlots.reduce((a, b) => a > b ? a : b);

      // Tapping an already-selected end: shrink from that end.
      if (index == min && _selectedSlots.length > 1) {
        _selectedSlots.remove(index);
        return;
      }
      if (index == max && _selectedSlots.length > 1) {
        _selectedSlots.remove(index);
        return;
      }
      if (_selectedSlots.length == 1 && _selectedSlots.contains(index)) {
        _selectedSlots.clear();
        return;
      }

      // Extending by one slot on either side, as long as the gap is bridged by
      // available slots only.
      if (index == min - 1 || index == max + 1) {
        _selectedSlots.add(index);
        return;
      }

      // Non-adjacent tap: start a new block from here.
      _selectedSlots
        ..clear()
        ..add(index);
    });
  }

  // --- Derived summary values ----------------------------------------------

  bool get _hasSelection => _selectedSlots.isNotEmpty;

  _TimeSlot get _firstSelected =>
      _slots[_selectedSlots.reduce((a, b) => a < b ? a : b)];

  _TimeSlot get _lastSelected =>
      _slots[_selectedSlots.reduce((a, b) => a > b ? a : b)];

  int get _durationMinutes => _selectedSlots.length * _slotMinutes;

  int get _fee => _selectedSlots.length * _feePerSlot;

  /// Duration in hours, e.g. "0.5 hr", "1 hr", "1.5 hrs", "2 hrs". Drops the
  /// trailing ".0" for whole hours and uses the singular "hr" only for 1.
  String get _durationLabel {
    final hours = _durationMinutes / 60;
    final isWhole = hours == hours.roundToDouble();
    final value = isWhole ? hours.toInt().toString() : hours.toString();
    final unit = hours == 1 ? 'hr' : 'hrs';
    return '$value $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: _isLoadingAvailability
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _buildHeader(),
                  const Padding(padding: EdgeInsets.only(top: 20)),
                  _buildChargerCard(),
                  const Padding(padding: EdgeInsets.only(top: 24)),
                  _buildSectionTitle('Select Date'),
                  const Padding(padding: EdgeInsets.only(top: 12)),
                  _buildCalendar(),
                  const Padding(padding: EdgeInsets.only(top: 24)),
                  _buildSectionTitle('Select Start Time'),
                  const Padding(padding: EdgeInsets.only(top: 12)),
                  _buildTimeSlots(),
                ],
              ),
      ),
      bottomNavigationBar: _buildConfirmBar(),
    );
  }

  // --- Section title --------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _dark,
      ),
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
          'Reserve Charger',
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

  // --- Calendar -------------------------------------------------------------

  Widget _buildCalendar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _buildCalendarHeader(),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _buildWeekdayLabels(),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    // Only allow stepping back to the current month, never into the past.
    final canGoBack = _visibleMonth.isAfter(DateTime(_today.year, _today.month));
    // Only allow stepping forward while the booking window (up to _maxDate)
    // still reaches a later month.
    final canGoForward =
        _visibleMonth.isBefore(DateTime(_maxDate.year, _maxDate.month));
    return Row(
      children: [
        _calArrow(
          icon: Icons.chevron_left,
          enabled: canGoBack,
          onTap: canGoBack
              ? () => setState(() {
                    _visibleMonth = DateTime(
                        _visibleMonth.year, _visibleMonth.month - 1);
                  })
              : null,
        ),
        Expanded(
          child: Text(
            _monthLabel(_visibleMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
        ),
        _calArrow(
          icon: Icons.chevron_right,
          enabled: canGoForward,
          onTap: canGoForward
              ? () => setState(() {
                    _visibleMonth = DateTime(
                        _visibleMonth.year, _visibleMonth.month + 1);
                  })
              : null,
        ),
      ],
    );
  }

  Widget _calArrow({
    required IconData icon,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 26,
          color: enabled ? _dark : Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildWeekdayLabels() {
    const labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // Leading blanks so the 1st lands under the right weekday (Sun=0).
    final leadingBlanks = firstOfMonth.weekday % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            final dayNumber = cellIndex - leadingBlanks + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return Expanded(child: Container(height: 44));
            }
            return Expanded(child: _buildDayCell(DateTime(year, month, dayNumber)));
          }),
        );
      }),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final isPast = date.isBefore(_today);
    final isBeyondWindow = date.isAfter(_maxDate);
    final disabled = isPast || isBeyondWindow;
    final isSelected = _selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day;

    return GestureDetector(
      onTap: disabled ? null : () => _selectDate(date),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${date.day}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : disabled
                    ? Colors.grey.shade300
                    : _dark,
          ),
        ),
      ),
    );
  }

  // --- Time slots -----------------------------------------------------------

  Widget _buildTimeSlots() {
    if (_selectedDate == null) {
      return _slotPlaceholder('Pick a date to see available times.');
    }
    if (_isLoadingSlots) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: const CircularProgressIndicator(color: _primary),
      );
    }
    if (_slots.isEmpty) {
      return _slotPlaceholder(
        _dayIsClosed
            ? 'Closed on this day. Pick another date.'
            : 'No more available times today. Pick another date.',
      );
    }

    return Column(
      children: [
        for (int i = 0; i < _slots.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: _slotTile(i)),
                const Padding(padding: EdgeInsets.only(left: 12)),
                Expanded(
                  child: i + 1 < _slots.length
                      ? _slotTile(i + 1)
                      : Container(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _slotPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.schedule, size: 32, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 10)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotTile(int index) {
    final slot = _slots[index];
    final isSelected = _selectedSlots.contains(index);
    final disabled = !slot.available;

    final Color bg;
    final Color fg;
    final Color border;
    if (disabled) {
      bg = const Color(0xFFF0F1F3);
      fg = Colors.grey.shade400;
      border = Colors.transparent;
    } else if (isSelected) {
      bg = _primary;
      fg = Colors.white;
      border = _primary;
    } else {
      bg = Colors.white;
      fg = _dark;
      border = _primary.withValues(alpha: 0.4);
    }

    return GestureDetector(
      onTap: disabled ? null : () => _onSlotTap(index),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Text(
          slot.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }

  // --- Next bar -------------------------------------------------------------

  Widget _buildConfirmBar() {
    final enabled = _hasSelection;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 56,
        child: ElevatedButton(
          onPressed: enabled ? _onNext : null,
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
          child: const Text(
            'Next',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  /// Takes the current selection to the review screen, which owns the actual
  /// "Confirm Reservation" action. If that screen reports the slot was taken
  /// (lost a race with another booking), refresh the day so the grid updates.
  Future<void> _onNext() async {
    final date = _selectedDate;
    if (!_hasSelection || date == null) return;

    // Build full local timestamps from the selected day + slot minutes.
    final startTime = DateTime(date.year, date.month, date.day)
        .add(Duration(minutes: _firstSelected.startMinutes));
    final endTime = DateTime(date.year, date.month, date.day)
        .add(Duration(minutes: _lastSelected.endMinutes));
    final timeLabel =
        '${_firstSelected.startLabel} - ${_lastSelected.endLabel}';

    final result = await Navigator.of(context).push<ReservationSummaryResult>(
      MaterialPageRoute(
        builder: (_) => ReservationSummaryScreen(
          charger: widget.charger,
          date: date,
          startTime: startTime,
          endTime: endTime,
          durationMinutes: _durationMinutes,
          fee: _fee,
          dateLabel: _fullDateLabel(date),
          timeLabel: timeLabel,
          durationLabel: _durationLabel,
          reservationController: _reservationController,
        ),
      ),
    );

    if (!mounted) return;
    if (result == ReservationSummaryResult.booked) {
      // Whole flow done — leave the reserve screen and report success.
      Navigator.of(context).pop(true);
    } else if (result == ReservationSummaryResult.slotTaken) {
      // The slot was taken while reviewing; refresh the day's availability.
      await _selectDate(date);
    }
  }

  // --- Date/time formatting helpers ----------------------------------------

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthLabel(DateTime month) =>
      '${_monthNames[month.month - 1]} ${month.year}';

  String _fullDateLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

/// A single 30-minute reservable block for the selected day.
class _TimeSlot {
  _TimeSlot({
    required this.startMinutes,
    required this.endMinutes,
    required this.available,
  });

  /// Minutes since midnight for the start and end of the block.
  final int startMinutes;
  final int endMinutes;

  /// False when the block overlaps an existing confirmed booking.
  final bool available;

  String get startLabel => _format(startMinutes);
  String get endLabel => _format(endMinutes);

  /// e.g. "15:00 - 15:30".
  String get label => '$startLabel - $endLabel';

  static String _format(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// A half-open [start, end) window in minutes-since-midnight, used to test
/// whether a slot overlaps an existing booking.
class _MinuteRange {
  _MinuteRange(this.start, this.end);
  final int start;
  final int end;
}
