class Charger {
  String id;
  String hostId;
  String name;
  String description;
  String address;
  double latitude;
  double longitude;
  String chargerType;
  String connectorType;
  double powerKw;
  double pricePerKwh;
  String status;

  /// Not stored in the `chargers` table. Computed from the user's location
  /// when available, otherwise null.
  double? distanceKm;

  /// Not stored in the `chargers` table yet. Null when unknown.
  double? rating;

  Charger(
    this.id,
    this.name,
    this.chargerType,
    this.connectorType,
    this.powerKw,
    this.pricePerKwh,
    this.status,
    this.latitude,
    this.longitude, {
    this.hostId = '',
    this.description = '',
    this.address = '',
    this.distanceKm,
    this.rating,
  });

  factory Charger.fromJson(Map<String, dynamic> json) {
    return Charger(
      json['id'] as String,
      json['name'] as String? ?? '',
      json['charger_type'] as String? ?? '',
      json['connector_type'] as String? ?? '',
      (json['power_kw'] as num?)?.toDouble() ?? 0.0,
      (json['price_per_kwh'] as num?)?.toDouble() ?? 0.0,
      json['status'] as String? ?? '',
      (json['latitude'] as num?)?.toDouble() ?? 0.0,
      (json['longitude'] as num?)?.toDouble() ?? 0.0,
      hostId: json['host_id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'host_id': hostId,
      'name': name,
      'description': description,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'charger_type': chargerType,
      'connector_type': connectorType,
      'power_kw': powerKw,
      'price_per_kwh': pricePerKwh,
      'status': status,
    };
  }

  /// Human-readable power label, e.g. "22 kW" or "7 kW".
  String get powerLabel {
    final value = powerKw == powerKw.roundToDouble()
        ? powerKw.toStringAsFixed(0)
        : powerKw.toString();
    return '$value kW';
  }

  /// Subtitle line for a charger card, e.g. "0.3 km · 22 kW · Type 2".
  /// The distance part is omitted when [distanceKm] is unknown.
  String get subtitle {
    final parts = <String>[];
    if (distanceKm != null) parts.add('$distanceKm km');
    parts.add(powerLabel);
    if (connectorType.isNotEmpty) parts.add(connectorType);
    return parts.join(' · ');
  }
}

class AllChargers {
  final List<Charger> chargers;
  AllChargers(this.chargers);

  factory AllChargers.fromJson(List<dynamic> json) {
    List<Charger> chargers;
    chargers = json
        .map((item) => Charger.fromJson(item as Map<String, dynamic>))
        .toList();
    return AllChargers(chargers);
  }
}

/// A single image belonging to a charger, stored in the `charger_images` table.
///
/// [imageUrl] holds the value straight from the DB. It may be either a full
/// public URL (starts with "http") or a storage path inside the
/// `voltshare_charger` bucket (e.g. `<charger_id>/1.jpg`); the service layer is
/// responsible for turning a path into a public URL before it reaches the UI.
class ChargerImage {
  final String id;
  final String chargerId;
  final String imageUrl;
  final int displayOrder;

  ChargerImage({
    required this.id,
    required this.chargerId,
    required this.imageUrl,
    this.displayOrder = 0,
  });

  factory ChargerImage.fromJson(Map<String, dynamic> json) {
    return ChargerImage(
      id: json['id'] as String,
      chargerId: json['charger_id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
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
