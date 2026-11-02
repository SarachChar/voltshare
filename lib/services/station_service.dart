import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';

abstract class StationService {
  /// Stations whose pin is inside the visible map rectangle and that have at
  /// least one 'available' charger, nearest to ([userLat], [userLng]) first,
  /// via the `stations_in_bounds` RPC. Each result carries its charger
  /// summary and [Station.distanceMeters].
  ///
  ///   [minLat]/[minLng]  south-west corner
  ///   [maxLat]/[maxLng]  north-east corner
  ///   [limit]            cap for dense areas
  Future<List<Station>> getStationsInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit,
  });

  /// Distance-sorted, paginated station search via the `search_stations` RPC.
  /// Returns up to [limit] stations starting at [offset], nearest to
  /// ([userLat], [userLng]) first. All filters are optional:
  ///   [query]          case-insensitive substring of the station name
  ///   [chargerType]    'AC' | 'DC'
  ///   [connectorType]  'CCS2' | 'Type 2' | 'CHAdeMO'
  ///   [powerMin]/[powerMax]  power_kw range in kW, half-open [min, max)
  /// The charger filters must all hold on the same available charger.
  Future<List<Station>> searchStations({
    required double userLat,
    required double userLng,
    String? query,
    String? chargerType,
    String? connectorType,
    double? powerMin,
    double? powerMax,
    int limit,
    int offset,
  });

  /// The live chargers of [stationId] ('available' and 'unavailable'),
  /// available first, then by name.
  Future<List<Charger>> getStationChargers(String stationId);

  /// Weekly hours for each of [chargerIds] in one query, keyed by charger id.
  /// Chargers with no rows are absent from the map.
  Future<Map<String, List<ChargerAvailability>>> getChargersAvailability(
    List<String> chargerIds,
  );

  /// The station's photos, ordered by `display_order`, as public URLs.
  Future<List<StationImage>> getStationImages(String stationId);

  /// The station's non-deleted businesses, oldest first.
  Future<List<StationBusiness>> getStationBusinesses(String stationId);

  /// Photos of the businesses around the station, ordered, as public URLs.
  Future<List<StationBusinessImage>> getStationBusinessImages(String stationId);

  /// ACTIVE, non-deleted promotions of the station, newest first.
  Future<List<StationPromotion>> getActivePromotions(String stationId);
}

/// Supabase-backed implementation.
class StationSupabaseService implements StationService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Storage bucket that holds station and business photos.
  static const String _imageBucket = 'voltshare_charger';

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
    final List<dynamic> data = await _client.rpc(
      'stations_in_bounds',
      params: {
        'user_lat': userLat,
        'user_lng': userLng,
        'min_lat': minLat,
        'min_lng': minLng,
        'max_lat': maxLat,
        'max_lng': maxLng,
        'page_limit': limit,
      },
    );
    return Station.listFromJson(data);
  }

  @override
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
  }) async {
    // Blank queries go as null so the SQL skips the name filter.
    final trimmed = query?.trim();
    final List<dynamic> data = await _client.rpc(
      'search_stations',
      params: {
        'user_lat': userLat,
        'user_lng': userLng,
        'search_query': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        'charger_type_filter': chargerType,
        'connector_type_filter': connectorType,
        'power_min': powerMin,
        'power_max': powerMax,
        'page_limit': limit,
        'page_offset': offset,
      },
    );
    return Station.listFromJson(data);
  }

  @override
  Future<List<Charger>> getStationChargers(String stationId) async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('station_id', stationId)
        .inFilter('status', ['available', 'unavailable'])
        .order('name', ascending: true);

    final chargers = AllChargers.fromJson(data).chargers;
    // Available first; stable within each group so the name order holds.
    final available = chargers.where((c) => c.status == 'available');
    final others = chargers.where((c) => c.status != 'available');
    return [...available, ...others];
  }

  @override
  Future<Map<String, List<ChargerAvailability>>> getChargersAvailability(
    List<String> chargerIds,
  ) async {
    if (chargerIds.isEmpty) return const {};
    final List<dynamic> data = await _client
        .from('charger_availability')
        .select()
        .inFilter('charger_id', chargerIds)
        .order('day_of_week', ascending: true);

    final byCharger = <String, List<ChargerAvailability>>{};
    for (final row in data) {
      final slot = ChargerAvailability.fromJson(row as Map<String, dynamic>);
      byCharger.putIfAbsent(slot.chargerId, () => []).add(slot);
    }
    return byCharger;
  }

  @override
  Future<List<StationImage>> getStationImages(String stationId) async {
    final List<dynamic> data = await _client
        .from('station_images')
        .select()
        .eq('station_id', stationId)
        .order('display_order', ascending: true);

    return data
        .map((row) => StationImage.fromJson(row as Map<String, dynamic>))
        .map((image) => image.copyWith(imageUrl: _resolvedUrl(image.imageUrl)))
        .toList();
  }

  @override
  Future<List<StationBusiness>> getStationBusinesses(String stationId) async {
    final List<dynamic> data = await _client
        .from('station_businesses')
        .select()
        .eq('station_id', stationId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    return data
        .map((row) => StationBusiness.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<StationBusinessImage>> getStationBusinessImages(
    String stationId,
  ) async {
    final List<dynamic> data = await _client
        .from('station_business_images')
        .select()
        .eq('station_id', stationId)
        .order('display_order', ascending: true);

    return data
        .map((row) =>
            StationBusinessImage.fromJson(row as Map<String, dynamic>))
        .map((image) => image.copyWith(imageUrl: _resolvedUrl(image.imageUrl)))
        .toList();
  }

  @override
  Future<List<StationPromotion>> getActivePromotions(String stationId) async {
    // The expire-station-promotions cron flips lapsed rows to EXPIRED once a
    // day, so a promotion can stay ACTIVE for up to a day past valid_until.
    final List<dynamic> data = await _client
        .from('station_promotions')
        .select()
        .eq('station_id', stationId)
        .eq('status', 'ACTIVE')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data
        .map((row) => StationPromotion.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Full URLs are kept as-is; anything else is a path in [_imageBucket].
  String _resolvedUrl(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty || raw.startsWith('http')) return raw;
    return _client.storage.from(_imageBucket).getPublicUrl(raw);
  }
}
