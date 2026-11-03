/// One charging unit inside a station, stored in the `chargers` table.
/// Location, owner, photos, businesses and promotions belong to the station
/// (see station_model.dart).
class Charger {
  String id;
  String name;
  String chargerType;
  String connectorType;
  double powerKw;
  double pricePerKwh;
  String status;
  DateTime? createdAt;

  /// The station this charger belongs to (`chargers.station_id`).
  String stationId;

  /// The station's name, when the query embedded `stations(name)`. Empty
  /// otherwise.
  String stationName;

  /// Approval states before a charger goes live.
  static const Set<String> pendingStatuses = {'review', 'setup', 'rejected'};

  /// Live chargers ('available' / 'unavailable') have passed device setup:
  /// the host can toggle them, and their hardware specs are locked.
  bool get isLive => status == 'available' || status == 'unavailable';

  /// Connectors allowed for each current type. Used by the host form and the
  /// search filter so a connector can only be picked after the type.
  static const Map<String, List<String>> connectorsByChargerType = {
    'AC': ['Type 2'],
    'DC': ['CCS2', 'CHAdeMO'],
  };

  /// Connectors for [chargerType]; empty for an unknown type.
  static List<String> connectorsFor(String chargerType) =>
      connectorsByChargerType[chargerType] ?? const [];

  Charger(
    this.id,
    this.name,
    this.chargerType,
    this.connectorType,
    this.powerKw,
    this.pricePerKwh,
    this.status, {
    this.createdAt,
    this.stationId = '',
    this.stationName = '',
  });

  factory Charger.fromJson(Map<String, dynamic> json) {
    // Embedded `stations(...)` arrives as an object (tolerate a list too).
    final rawStation = json['stations'];
    final station = rawStation is Map
        ? rawStation
        : (rawStation is List && rawStation.isNotEmpty && rawStation.first is Map
            ? rawStation.first as Map
            : null);
    return Charger(
      json['id'] as String,
      json['name'] as String? ?? '',
      json['charger_type'] as String? ?? '',
      json['connector_type'] as String? ?? '',
      (json['power_kw'] as num?)?.toDouble() ?? 0.0,
      (json['price_per_kwh'] as num?)?.toDouble() ?? 0.0,
      json['status'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String)?.toLocal(),
      stationId: json['station_id'] as String? ?? '',
      stationName: station?['name'] as String? ?? '',
    );
  }

  /// Human-readable power label, e.g. "22 kW" or "7.4 kW".
  String get powerLabel {
    final value = powerKw == powerKw.roundToDouble()
        ? powerKw.toStringAsFixed(0)
        : powerKw.toString();
    return '$value kW';
  }
}

class AllChargers {
  final List<Charger> chargers;
  AllChargers(this.chargers);

  factory AllChargers.fromJson(List<dynamic> json) {
    return AllChargers(
      json
          .map((item) => Charger.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One row of a charger's weekly schedule, stored in the `charger_availability`
/// table. [dayOfWeek] follows the DB convention where 0 = Sunday .. 6 = Saturday.
/// [startTime] and [endTime] come from Postgres `time` columns as "HH:mm:ss".
class ChargerAvailability {
  final String id;
  final String chargerId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool isAvailable;

  ChargerAvailability({
    required this.id,
    required this.chargerId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.isAvailable = true,
  });

  factory ChargerAvailability.fromJson(Map<String, dynamic> json) {
    return ChargerAvailability(
      id: json['id'] as String,
      chargerId: json['charger_id'] as String? ?? '',
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }

  /// A synthetic "closed" slot for a [day] that has no row in the DB.
  factory ChargerAvailability.closed({
    required String chargerId,
    required int day,
  }) {
    return ChargerAvailability(
      id: 'closed-$chargerId-$day',
      chargerId: chargerId,
      dayOfWeek: day,
      startTime: '',
      endTime: '',
      isAvailable: false,
    );
  }

  static const List<String> _dayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  /// Full day label for [dayOfWeek], e.g. "Sunday". Falls back to the raw
  /// number if it's outside the expected 0..6 range.
  String get dayLabel {
    if (dayOfWeek < 0 || dayOfWeek >= _dayNames.length) return 'Day $dayOfWeek';
    return _dayNames[dayOfWeek];
  }

  /// Whether this day should be shown as closed: either explicitly marked
  /// unavailable, or missing a usable time range.
  bool get isClosed {
    if (!isAvailable) return true;
    return _trimSeconds(startTime).isEmpty && _trimSeconds(endTime).isEmpty;
  }

  /// Time range formatted as "HH:mm - HH:mm" (seconds trimmed), or "Closed"
  /// when this day is closed.
  String get timeRangeLabel {
    if (isClosed) return 'Closed';
    return '${_trimSeconds(startTime)} - ${_trimSeconds(endTime)}';
  }

  /// Turns "09:00:00" into "09:00". Leaves other formats untouched.
  static String _trimSeconds(String time) {
    final parts = time.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return time;
  }

  /// Expands [rows] into a full Sunday..Saturday week for [chargerId]. Days
  /// absent from [rows] are filled in as closed. If a day appears more than
  /// once, the first occurrence wins. Result is ordered 0 (Sunday) .. 6.
  static List<ChargerAvailability> fullWeek(
    String chargerId,
    List<ChargerAvailability> rows,
  ) {
    final byDay = <int, ChargerAvailability>{};
    for (final row in rows) {
      byDay.putIfAbsent(row.dayOfWeek, () => row);
    }
    return List.generate(7, (day) {
      return byDay[day] ??
          ChargerAvailability.closed(chargerId: chargerId, day: day);
    });
  }
}
