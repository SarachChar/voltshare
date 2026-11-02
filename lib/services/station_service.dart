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

  /// The live chargers of [stationId] ('available' and 'unavailable'),
  /// available first, then by name.
  Future<List<Charger>> getStationChargers(String stationId);
}

/// Supabase-backed implementation.
class StationSupabaseService implements StationService {
  final SupabaseClient _client = Supabase.instance.client;

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
}
