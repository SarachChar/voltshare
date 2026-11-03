import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// Thin controller over [ChargerService]: the host's charger form and on/off
/// switch, the Pending tab, and charger hours for the booking flow.
class ChargerController {
  ChargerController(this.service);

  final ChargerService service;

  /// The host's pending chargers (status 'review', 'setup' or 'rejected'),
  /// most recent first.
  Future<List<Charger>> fetchPendingChargersByHost(String hostId) {
    return service.getPendingChargersByHost(hostId);
  }

  /// The weekly availability for a charger, ordered by day of week.
  Future<List<ChargerAvailability>> fetchChargerAvailability(String chargerId) {
    return service.getChargerAvailability(chargerId);
  }

  /// Creates a new charger in [stationId] (status 'review' by default).
  Future<Charger> createCharger({
    required String stationId,
    required String name,
    String chargerType = '',
    String connectorType = '',
    double powerKw = 0.0,
    double pricePerKwh = 0.0,
    String status = 'review',
  }) {
    return service.createCharger(
      stationId: stationId,
      name: name,
      chargerType: chargerType,
      connectorType: connectorType,
      powerKw: powerKw,
      pricePerKwh: pricePerKwh,
      status: status,
    );
  }

  /// Updates a charger's name and price; hardware specs only when non-null
  /// (see [ChargerService.updateCharger]).
  Future<Charger> updateCharger({
    required String chargerId,
    required String name,
    required double pricePerKwh,
    String? chargerType,
    String? connectorType,
    double? powerKw,
  }) {
    return service.updateCharger(
      chargerId: chargerId,
      name: name,
      pricePerKwh: pricePerKwh,
      chargerType: chargerType,
      connectorType: connectorType,
      powerKw: powerKw,
    );
  }

  /// Updates only a charger's availability status and returns the saved row.
  Future<Charger> updateChargerStatus({
    required String chargerId,
    required String status,
  }) {
    return service.updateChargerStatus(chargerId: chargerId, status: status);
  }

  /// Replaces a charger's weekly availability with [days].
  Future<void> replaceChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) {
    return service.replaceChargerAvailability(chargerId: chargerId, days: days);
  }

  /// Saves a new charger's weekly opening hours.
  Future<void> insertChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) {
    return service.insertChargerAvailability(chargerId: chargerId, days: days);
  }
}
