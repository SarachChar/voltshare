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
