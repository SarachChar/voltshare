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
      promotions;
}
