import 'dart:async';
import 'dart:typed_data';

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

  /// Paginated station search for the Search screen; see
  /// [StationService.searchStations]. Does not touch [stations] or [onSync]
  /// (the Search screen keeps its own paged list and loading state).
  Future<List<Station>> searchStations({
    required double userLat,
    required double userLng,
    String? query,
    String? chargerType,
    String? connectorType,
    double? powerMin,
    double? powerMax,
    int limit = 20,
    int offset = 0,
  }) {
    return service.searchStations(
      userLat: userLat,
      userLng: userLng,
      query: query,
      chargerType: chargerType,
      connectorType: connectorType,
      powerMin: powerMin,
      powerMax: powerMax,
      limit: limit,
      offset: offset,
    );
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

  // ----- Host side -----------------------------------------------------------

  Future<List<Station>> fetchStationsByHost(String hostId) =>
      service.getStationsByHost(hostId);

  Future<List<Charger>> fetchAllStationChargers(String stationId) =>
      service.getAllStationChargers(stationId);

  Future<Station> createStation({
    required String hostId,
    required String name,
    String description = '',
    String address = '',
    required double latitude,
    required double longitude,
  }) =>
      service.createStation(
        hostId: hostId,
        name: name,
        description: description,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );

  Future<Station> updateStation({
    required String stationId,
    required String name,
    String description = '',
    String address = '',
    required double latitude,
    required double longitude,
  }) =>
      service.updateStation(
        stationId: stationId,
        name: name,
        description: description,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );

  Future<String> uploadStationImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      service.uploadStationImage(
        folder: folder,
        index: index,
        bytes: bytes,
        fileExtension: fileExtension,
      );

  Future<StationImage> insertStationImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) =>
      service.insertStationImage(
        stationId: stationId,
        imagePath: imagePath,
        displayOrder: displayOrder,
      );

  Future<void> deleteStationImage(String imageId) =>
      service.deleteStationImage(imageId);

  Future<StationBusinessImage> insertStationBusinessImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) =>
      service.insertStationBusinessImage(
        stationId: stationId,
        imagePath: imagePath,
        displayOrder: displayOrder,
      );

  Future<void> deleteStationBusinessImage(String imageId) =>
      service.deleteStationBusinessImage(imageId);

  Future<StationBusiness> insertStationBusiness({
    required String stationId,
    required String businessType,
    required String businessName,
    String description = '',
  }) =>
      service.insertStationBusiness(
        stationId: stationId,
        businessType: businessType,
        businessName: businessName,
        description: description,
      );

  Future<void> softDeleteStationBusinesses(List<String> businessIds) =>
      service.softDeleteStationBusinesses(businessIds);

  /// Every non-deleted promotion (any status), for the host's panel.
  Future<List<StationPromotion>> fetchStationPromotions(String stationId) =>
      service.getStationPromotions(stationId);

  Future<StationPromotion> createPromotion({
    required String stationId,
    required String title,
    String description = '',
    DateTime? validFrom,
    DateTime? validUntil,
    String status = 'ACTIVE',
    String termsAndConditions = '',
  }) =>
      service.createPromotion(
        stationId: stationId,
        title: title,
        description: description,
        validFrom: validFrom,
        validUntil: validUntil,
        status: status,
        termsAndConditions: termsAndConditions,
      );

  /// Switches a promotion between "ACTIVE" and "INACTIVE" (uppercase for the
  /// DB check constraint).
  Future<StationPromotion> togglePromotionStatus(
    String promotionId,
    bool active,
  ) =>
      service.updatePromotionStatus(
        promotionId,
        active ? 'ACTIVE' : 'INACTIVE',
      );

  Future<void> deletePromotion(String promotionId) =>
      service.deletePromotion(promotionId);

  void dispose() {
    _onSyncController.close();
  }
}
