import 'dart:async';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

class ChargerController {
  List<Charger> chargers = List.empty();
  final ChargerService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  ChargerController(this.service);

  Future<List<Charger>> fetchNearbyChargers() async {
    onSyncController.add(true);
    chargers = await service.getNearbyChargers();
    onSyncController.add(false);
    return chargers;
  }

  /// Fetches the chargers owned by [hostId], most recent first.
  Future<List<Charger>> fetchChargersByHost(String hostId) async {
    onSyncController.add(true);
    chargers = await service.getChargersByHost(hostId);
    onSyncController.add(false);
    return chargers;
  }

  /// Fetches the images for a charger, ordered for display.
  Future<List<ChargerImage>> fetchChargerImages(String chargerId) {
    return service.getChargerImages(chargerId);
  }

  /// Fetches the weekly availability for a charger, ordered by day of week.
  Future<List<ChargerAvailability>> fetchChargerAvailability(String chargerId) {
    return service.getChargerAvailability(chargerId);
  }
}
