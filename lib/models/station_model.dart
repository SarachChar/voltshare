/// A charging location owned by a host, stored in the `stations` table. Each
/// station holds one or more chargers (`chargers.station_id`).
///
/// The summary fields ([chargerCount], [availableCount], [connectorTypes],
/// [chargerTypes], [minPrice], [maxPowerKw]) and [distanceMeters] are only
/// populated by the station RPCs (e.g. `stations_in_bounds`); they are
/// zero / empty / null for stations loaded straight from the table.
class Station {
  final String id;
  final String hostId;
  final String name;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;

  /// Great-circle distance in metres from the user. Null when not computed.
  final double? distanceMeters;

  /// Live chargers in the station ('available' + 'unavailable').
  final int chargerCount;

  /// Chargers currently 'available'.
  final int availableCount;

  /// Distinct connector types of the available chargers, e.g. ["CCS2", "Type 2"].
  final List<String> connectorTypes;

  /// Distinct current types of the available chargers, e.g. ["AC", "DC"].
  final List<String> chargerTypes;

  /// Cheapest price per kWh (THB) among the available chargers.
  final double? minPrice;

  /// Highest power (kW) among the available chargers.
  final double? maxPowerKw;

  const Station({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.hostId = '',
    this.description = '',
    this.address = '',
    this.createdAt,
    this.distanceMeters,
    this.chargerCount = 0,
    this.availableCount = 0,
    this.connectorTypes = const [],
    this.chargerTypes = const [],
    this.minPrice,
    this.maxPowerKw,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'] as String,
      hostId: json['host_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String)?.toLocal(),
      distanceMeters: (json['distance_m'] as num?)?.toDouble(),
      chargerCount: (json['charger_count'] as num?)?.toInt() ?? 0,
      availableCount: (json['available_count'] as num?)?.toInt() ?? 0,
      connectorTypes: _stringList(json['connector_types']),
      chargerTypes: _stringList(json['charger_types']),
      minPrice: (json['min_price'] as num?)?.toDouble(),
      maxPowerKw: (json['max_power_kw'] as num?)?.toDouble(),
    );
  }

  static List<Station> listFromJson(List<dynamic> json) {
    return json
        .map((item) => Station.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((s) => s.isNotEmpty).toList();
  }

  /// "0.3 km" / "850 m"; empty when [distanceMeters] is null.
  String get distanceLabel {
    final metres = distanceMeters;
    if (metres == null) return '';
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  /// "2/3 available". Falls back to "x available" when [chargerCount] is
  /// unknown (0) or smaller than [availableCount].
  String get availabilityLabel {
    if (chargerCount <= 0 || chargerCount < availableCount) {
      return '$availableCount available';
    }
    return '$availableCount/$chargerCount available';
  }

  /// "from ฿7.50/kWh"; empty when [minPrice] is unknown.
  String get priceFromLabel {
    final price = minPrice;
    if (price == null) return '';
    return 'from ฿${price.toStringAsFixed(2)}/kWh';
  }

  /// "up to 120 kW" / "up to 7.4 kW"; empty when [maxPowerKw] is unknown.
  String get maxPowerLabel {
    final power = maxPowerKw;
    if (power == null) return '';
    final value = power == power.roundToDouble()
        ? power.toStringAsFixed(0)
        : power.toString();
    return 'up to $value kW';
  }
}
