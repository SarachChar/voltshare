import 'package:voltshare_app/models/review_model.dart';

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

  /// When the charging session actually began. Null until the driver starts
  /// charging. A reservation is "charging now" when it's confirmed AND has a
  /// [startedAt]; once finished its status becomes "completed".
  final DateTime? startedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Charger details joined in for list views (e.g. the Bookings screen).
  /// Empty / null when the query didn't join the `chargers` table.
  final String chargerName;
  final String chargerAddress;
  final double? chargerPowerKw;

  /// Current type from the joined charger, e.g. "AC" / "DC". Empty if not
  /// joined.
  final String chargerType;

  /// Connector from the joined charger, e.g. "Type 2". Empty if not joined.
  final String chargerConnectorType;

  /// Charger price per kWh (THB) from the join. Null when not joined.
  final double? chargerPricePerKwh;

  /// The driver's review, when the query embedded `reviews(...)`. Null when
  /// not reviewed (or not embedded).
  final Review? review;

  /// Actual charging times from the embedded `charging_sessions` row. Null
  /// when charging never started (or the session wasn't embedded).
  final DateTime? sessionStartedAt;
  final DateTime? sessionEndedAt;

  /// Energy charge of the session (THB, `session_payments.energy_amount`).
  /// Null until the session has stopped and been billed.
  final double? chargingCost;

  Reservation({
    required this.id,
    required this.userId,
    required this.chargerId,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.status = 'confirmed',
    this.startedAt,
    this.createdAt,
    this.updatedAt,
    this.chargerName = '',
    this.chargerAddress = '',
    this.chargerPowerKw,
    this.chargerType = '',
    this.chargerConnectorType = '',
    this.chargerPricePerKwh,
    this.review,
    this.sessionStartedAt,
    this.sessionEndedAt,
    this.chargingCost,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    // A joined charger row arrives nested under the `chargers` key (Supabase
    // names the embedded object after the related table).
    final charger = json['chargers'] as Map<String, dynamic>?;
    // 1-1 embeds: PostgREST returns an object, tolerate a list too.
    final session = _embeddedOne(json['charging_sessions']);
    final payment = _embeddedOne(session?['session_payments']);

    return Reservation(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      chargerId: json['charger_id'] as String? ?? '',
      // start/end are NOT NULL in the DB; fall back to epoch only to stay
      // null-safe if a malformed row ever comes back.
      startTime:
          _parseDate(json['start_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endTime:
          _parseDate(json['end_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'confirmed',
      startedAt: _parseDate(json['started_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      chargerName: charger?['name'] as String? ?? '',
      chargerAddress: charger?['address'] as String? ?? '',
      chargerPowerKw: (charger?['power_kw'] as num?)?.toDouble(),
      chargerType: charger?['charger_type'] as String? ?? '',
      chargerConnectorType: charger?['connector_type'] as String? ?? '',
      chargerPricePerKwh: (charger?['price_per_kwh'] as num?)?.toDouble(),
      review: Review.fromEmbedded(json['reviews']),
      sessionStartedAt: _parseDate(session?['started_at']),
      sessionEndedAt: _parseDate(session?['ended_at']),
      chargingCost: (payment?['energy_amount'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic>? _embeddedOne(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  /// Actual charging time range, e.g. "16:04 - 17:21". Falls back to the
  /// booked [timeRangeLabel] when the session times aren't known.
  String get sessionTimeRangeLabel {
    final start = sessionStartedAt;
    final end = sessionEndedAt;
    if (start == null || end == null) return timeRangeLabel;
    return '${_hhmm(start)} - ${_hhmm(end)}';
  }

  /// Charging cost, e.g. "฿99.84"; "-" when not billed.
  String get chargingCostLabel {
    final cost = chargingCost;
    if (cost == null) return '-';
    return '฿${cost.toStringAsFixed(2)}';
  }

  /// Parses a DB timestamp (stored as UTC) into local device time.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  /// PostgREST embed for the charger fields this model reads. Use as
  /// `.select('*, ${Reservation.chargerJoin}')`.
  static const String chargerJoin =
      'chargers(name, address, power_kw, charger_type, connector_type, '
      'price_per_kwh)';

  /// Charger spec line, e.g. "22 kW AC".
  String get chargerSpecLabel =>
      [chargerPowerLabel, chargerType].where((p) => p.isNotEmpty).join(' ');

  bool get isConfirmed => status == 'confirmed';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  /// True while a charging session is in progress for this booking.
  bool get isCharging => isConfirmed && startedAt != null;

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
    final value = power == power.roundToDouble()
        ? power.toStringAsFixed(0)
        : '$power';
    return '$value kW';
  }

  static String _hhmm(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
