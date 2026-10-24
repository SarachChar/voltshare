/// One meter reading reported by the charger, from `session_streams`.
///
/// Rows arrive roughly every 30 seconds (OCPP MeterValues) while charging, plus
/// one at start and one at stop. [totalEnergyReceivedKwh] is cumulative for
/// the session.
class SessionStream {
  final String id;
  final String sessionId;
  final double socPercent;
  final double powerKw;
  final double totalEnergyReceivedKwh;
  final DateTime createdAt;

  SessionStream({
    required this.id,
    required this.sessionId,
    required this.socPercent,
    required this.powerKw,
    required this.totalEnergyReceivedKwh,
    required this.createdAt,
  });

  factory SessionStream.fromJson(Map<String, dynamic> json) {
    return SessionStream(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      socPercent: (json['soc_percent'] as num?)?.toDouble() ?? 0,
      powerKw: (json['power_kw'] as num?)?.toDouble() ?? 0,
      totalEnergyReceivedKwh:
          (json['total_energy_received_kwh'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}
