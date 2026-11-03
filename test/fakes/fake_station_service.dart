import 'dart:typed_data';

import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/services/station_service.dart';

/// In-memory [StationService] for tests. Set the fields, then read the
/// `last*` fields to check what the caller asked for.
class FakeStationService implements StationService {
  List<Station> stations = const [];
  List<Charger> chargers = const [];
  Map<String, List<ChargerAvailability>> availability = const {};
  List<StationImage> images = const [];
  List<StationBusiness> businesses = const [];
  List<StationBusinessImage> businessImages = const [];
  List<StationPromotion> promotions = const [];

  /// When set, getStationsInBounds / getStationChargers throw it.
  Object? error;

  Map<String, Object?>? lastBoundsCall;
  String? lastChargersStationId;
  List<String>? lastAvailabilityIds;

  @override
  Future<List<Station>> getStationsInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit = 200,
  }) async {
    lastBoundsCall = {
      'userLat': userLat,
      'userLng': userLng,
      'minLat': minLat,
      'minLng': minLng,
      'maxLat': maxLat,
      'maxLng': maxLng,
      'limit': limit,
    };
    if (error != null) throw error!;
    return stations;
  }

  /// Pages returned by searchStations, by offset. Missing offsets return [].
  Map<int, List<Station>> searchPages = const {};

  /// Every searchStations call, in order.
  final List<Map<String, Object?>> searchCalls = [];

  @override
  Future<List<Station>> searchStations({
    required double userLat,
    required double userLng,
    String? query,
    String? chargerType,
    String? connectorType,
    double? powerMin,
    double? powerMax,
    String? businessType,
    int limit = 20,
    int offset = 0,
  }) async {
    searchCalls.add({
      'userLat': userLat,
      'userLng': userLng,
      'query': query,
      'chargerType': chargerType,
      'connectorType': connectorType,
      'powerMin': powerMin,
      'powerMax': powerMax,
      'businessType': businessType,
      'limit': limit,
      'offset': offset,
    });
    if (error != null) throw error!;
    return searchPages[offset] ?? const [];
  }

  @override
  Future<List<Charger>> getStationChargers(String stationId) async {
    lastChargersStationId = stationId;
    if (error != null) throw error!;
    return chargers;
  }

  @override
  Future<Map<String, List<ChargerAvailability>>> getChargersAvailability(
    List<String> chargerIds,
  ) async {
    lastAvailabilityIds = chargerIds;
    return availability;
  }

  @override
  Future<List<StationImage>> getStationImages(String stationId) async =>
      images;

  @override
  Future<List<StationBusiness>> getStationBusinesses(String stationId) async =>
      businesses;

  @override
  Future<List<StationBusinessImage>> getStationBusinessImages(
    String stationId,
  ) async =>
      businessImages;

  @override
  Future<List<StationPromotion>> getActivePromotions(String stationId) async =>
      promotions.where((p) => p.isActive).toList();

  // ----- Host side -----------------------------------------------------------

  List<Station> hostStations = const [];
  List<Charger> allChargers = const [];

  /// Every write call, as `name: args`, in order.
  final List<String> writes = [];
  int _nextId = 1;
  String _id(String prefix) => '$prefix-${_nextId++}';

  @override
  Future<List<Station>> getStationsByHost(String hostId) async {
    writes.add('getStationsByHost: $hostId');
    return hostStations;
  }

  @override
  Future<List<Charger>> getAllStationChargers(String stationId) async =>
      allChargers;

  @override
  Future<Station> createStation({
    required String hostId,
    required String name,
    String description = '',
    String address = '',
    required double latitude,
    required double longitude,
  }) async {
    writes.add('createStation: $hostId $name');
    return Station(
      id: _id('station'),
      hostId: hostId,
      name: name,
      description: description,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<Station> updateStation({
    required String stationId,
    required String name,
    String description = '',
    String address = '',
    required double latitude,
    required double longitude,
  }) async {
    writes.add('updateStation: $stationId $name');
    return Station(
      id: stationId,
      name: name,
      description: description,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<String> uploadStationImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    writes.add('upload: $folder');
    return '$folder/$index.$fileExtension';
  }

  @override
  Future<StationImage> insertStationImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) async {
    writes.add('insertStationImage: $stationId');
    return StationImage(
      id: _id('img'),
      stationId: stationId,
      imageUrl: imagePath,
      displayOrder: displayOrder,
    );
  }

  @override
  Future<void> deleteStationImage(String imageId) async =>
      writes.add('deleteStationImage: $imageId');

  @override
  Future<StationBusinessImage> insertStationBusinessImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) async {
    writes.add('insertStationBusinessImage: $stationId');
    return StationBusinessImage(
      id: _id('bimg'),
      stationId: stationId,
      imageUrl: imagePath,
      displayOrder: displayOrder,
    );
  }

  @override
  Future<void> deleteStationBusinessImage(String imageId) async =>
      writes.add('deleteStationBusinessImage: $imageId');

  @override
  Future<StationBusiness> insertStationBusiness({
    required String stationId,
    required String businessType,
    required String businessName,
    String description = '',
  }) async {
    writes.add('insertStationBusiness: $stationId $businessName');
    return StationBusiness(
      id: _id('biz'),
      stationId: stationId,
      businessType: businessType,
      businessName: businessName,
      description: description,
    );
  }

  @override
  Future<void> softDeleteStationBusinesses(List<String> businessIds) async {
    if (businessIds.isEmpty) return;
    writes.add('softDeleteStationBusinesses: ${businessIds.join(',')}');
  }

  @override
  Future<List<StationPromotion>> getStationPromotions(String stationId) async =>
      promotions;

  @override
  Future<StationPromotion> createPromotion({
    required String stationId,
    required String title,
    String description = '',
    DateTime? validFrom,
    DateTime? validUntil,
    String status = 'ACTIVE',
    String termsAndConditions = '',
  }) async {
    writes.add('createPromotion: $stationId $title $status');
    return StationPromotion(
      id: _id('promo'),
      stationId: stationId,
      title: title,
      description: description,
      validFrom: validFrom,
      validUntil: validUntil,
      status: status,
      termsAndConditions: termsAndConditions,
    );
  }

  @override
  Future<StationPromotion> updatePromotionStatus(
    String promotionId,
    String status,
  ) async {
    writes.add('updatePromotionStatus: $promotionId $status');
    final current = promotions.firstWhere((p) => p.id == promotionId);
    return StationPromotion(
      id: current.id,
      stationId: current.stationId,
      title: current.title,
      description: current.description,
      validFrom: current.validFrom,
      validUntil: current.validUntil,
      status: status,
      termsAndConditions: current.termsAndConditions,
    );
  }

  @override
  Future<void> deletePromotion(String promotionId) async =>
      writes.add('deletePromotion: $promotionId');
}
