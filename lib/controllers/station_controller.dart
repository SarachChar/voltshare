import 'dart:async';

import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/services/station_service.dart';

class StationController {
  StationController(this.service);

  final StationService service;

  /// Last result of [fetchStationsInBounds].
  List<Station> stations = List.empty();

  final StreamController<bool> _onSyncController =
      StreamController<bool>.broadcast();

  /// Emits true when a map load starts and false when it settles, so the home
  /// map can show its loading indicator.
  Stream<bool> get onSync => _onSyncController.stream;

  /// Loads the stations inside the visible map rectangle (see
  /// [StationService.getStationsInBounds]) and caches them in [stations].
  Future<List<Station>> fetchStationsInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit = 200,
  }) async {
    _onSyncController.add(true);
    try {
      stations = await service.getStationsInBounds(
        userLat: userLat,
        userLng: userLng,
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
        limit: limit,
      );
      return stations;
    } finally {
      _onSyncController.add(false);
    }
  }

  /// The live chargers of [stationId], available first.
  Future<List<Charger>> fetchStationChargers(String stationId) {
    return service.getStationChargers(stationId);
  }

  /// Weekly hours of each charger in [chargerIds], each expanded to a full
  /// Sunday..Saturday week (missing days shown as closed).
  Future<Map<String, List<ChargerAvailability>>> fetchChargersWeek(
    List<String> chargerIds,
  ) async {
    final rows = await service.getChargersAvailability(chargerIds);
    return {
      for (final id in chargerIds)
        id: ChargerAvailability.fullWeek(id, rows[id] ?? const []),
    };
  }

  Future<List<StationImage>> fetchStationImages(String stationId) =>
      service.getStationImages(stationId);

  Future<List<StationBusiness>> fetchStationBusinesses(String stationId) =>
      service.getStationBusinesses(stationId);

  Future<List<StationBusinessImage>> fetchStationBusinessImages(
    String stationId,
  ) =>
      service.getStationBusinessImages(stationId);

  Future<List<StationPromotion>> fetchActivePromotions(String stationId) =>
      service.getActivePromotions(stationId);

  void dispose() {
    _onSyncController.close();
  }
}
