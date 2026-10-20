/// A single charger booking, stored in the `reservations` table.
///
/// A reservation ties a driver's profile ([userId] -> `profiles.id`) to a
/// charger ([chargerId] -> `chargers.id`) for a contiguous block of 30-minute
/// slots. [startTime]/[endTime] come from Postgres `timestamptz` columns
/// (stored as UTC) and are exposed here in local device time so the booking UI
/// shows Thailand time (UTC+7). [status] is the raw DB value — one of
/// "confirmed", "completed" or "cancelled".
class Reservation {
  final String id;
  final String userId;
  final String chargerId;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Charger details joined in for list views (e.g. the Bookings screen).
  /// Empty / null when the query didn't join the `chargers` table.
  final String chargerName;
  final String chargerAddress;
  final double? chargerPowerKw;

  Reservation({
    required this.id,
    required this.userId,
    required this.chargerId,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.status = 'confirmed',
    this.createdAt,
    this.updatedAt,
    this.chargerName = '',
    this.chargerAddress = '',
    this.chargerPowerKw,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    // A joined charger row arrives nested under the `chargers` key (Supabase
    // names the embedded object after the related table).
    final charger = json['chargers'] as Map<String, dynamic>?;

    return Reservation(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      chargerId: json['charger_id'] as String? ?? '',
      // start/end are NOT NULL in the DB; fall back to epoch only to stay
      // null-safe if a malformed row ever comes back.
      startTime: _parseDate(json['start_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endTime: _parseDate(json['end_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'confirmed',
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      chargerName: charger?['name'] as String? ?? '',
      chargerAddress: charger?['address'] as String? ?? '',
      chargerPowerKw: (charger?['power_kw'] as num?)?.toDouble(),
    );
  }

  /// Parses a DB timestamp (stored as UTC) into local device time.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isConfirmed => status == 'confirmed';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

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

  /// Booking date, e.g. "Jun 28, 2026".
  String get dateLabel =>
      '${_months[startTime.month - 1]} ${startTime.day}, ${startTime.year}';

  /// Time range in local time, e.g. "16:00 - 18:00".
  String get timeRangeLabel => '${_hhmm(startTime)} - ${_hhmm(endTime)}';

  /// Duration in hours, e.g. "0.5 hr", "1 hr", "1.5 hrs", "2 hrs". Matches the
  /// format used in the booking flow.
  String get durationLabel {
    final hours = durationMinutes / 60;
    final isWhole = hours == hours.roundToDouble();
    final value = isWhole ? hours.toInt().toString() : hours.toString();
    final unit = hours == 1 ? 'hr' : 'hrs';
    return '$value $unit';
  }

  /// Short power label for the joined charger, e.g. "7 kW". Empty when the
  /// charger's power wasn't joined in.
  String get chargerPowerLabel {
    final power = chargerPowerKw;
    if (power == null) return '';
    final value =
        power == power.roundToDouble() ? power.toStringAsFixed(0) : '$power';
    return '$value kW';
  }

  static String _hhmm(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
