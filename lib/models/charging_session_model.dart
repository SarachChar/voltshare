import 'package:voltshare_app/models/reservation_model.dart';

/// One charging session (OCPP "transaction"), from `charging_sessions`.
///
/// Created by the `ocpp-remote-start` edge function and closed by
/// `ocpp-remote-stop` (or the mock charger's auto-stop). [status] is
/// "charging" or "completed".
class ChargingSession {
  final String id;
  final String reservationId;

  /// OCPP transactionId.
  final int transactionId;

  /// Price per kWh (THB) locked when charging started.
  final double pricePerKwhAtStart;

  final int meterStartWh;
  final int? meterStopWh;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Final energy (kWh); null until the session is completed.
  final double? totalEnergyKwh;

  final String status;

  /// "user" | "time_up" | "battery_full"; null while charging.
  final String? stopReason;

  /// The reservation, when the query embedded it (`reservations(...)`).
  final Reservation? reservation;

  ChargingSession({
    required this.id,
    required this.reservationId,
    required this.transactionId,
    required this.pricePerKwhAtStart,
    required this.meterStartWh,
    this.meterStopWh,
    required this.startedAt,
    this.endedAt,
    this.totalEnergyKwh,
    required this.status,
    this.stopReason,
    this.reservation,
  });

  factory ChargingSession.fromJson(Map<String, dynamic> json) {
    final reservation = json['reservations'];
    return ChargingSession(
      id: json['id'] as String,
      reservationId: json['reservation_id'] as String? ?? '',
      transactionId: (json['transaction_id'] as num?)?.toInt() ?? 0,
      pricePerKwhAtStart:
          (json['price_per_kwh_at_start'] as num?)?.toDouble() ?? 0,
      meterStartWh: (json['meter_start_wh'] as num?)?.toInt() ?? 0,
      meterStopWh: (json['meter_stop_wh'] as num?)?.toInt(),
      startedAt: _parseDate(json['started_at']) ?? DateTime.now(),
      endedAt: _parseDate(json['ended_at']),
      totalEnergyKwh: (json['total_energy_kwh'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'charging',
      stopReason: json['stop_reason'] as String?,
      reservation: reservation is Map<String, dynamic>
          ? Reservation.fromJson(reservation)
          : null,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isCharging => status == 'charging';
  bool get isCompleted => status == 'completed';

  /// Elapsed charging time: until [endedAt], or until now while charging.
  Duration get elapsed {
    final end = endedAt ?? DateTime.now();
    final d = end.difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }
}
