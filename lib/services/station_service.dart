import 'package:flutter/foundation.dart';
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
  ///   [businessType]   station_businesses.business_type, e.g. 'CAFE'
  /// The charger filters must all hold on the same available charger.
  Future<List<Station>> searchStations({
    required double userLat,
    required double userLng,
    String? query,
    String? chargerType,
    String? connectorType,
    double? powerMin,
    double? powerMax,
    String? businessType,
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

  // ----- Host side -----------------------------------------------------------

  /// Stations owned by [hostId], newest first, with live / available / pending
  /// charger counts (from an embedded `chargers(id, status)`).
  Future<List<Station>> getStationsByHost(String hostId);

  /// Every charger of [stationId] in any status, by name. Host view.
  Future<List<Charger>> getAllStationChargers(String stationId);

  Future<Station> createStation({
    required String hostId,
    required String name,
    String description,
    String address,
    required double latitude,
    required double longitude,
  });

  /// Updates the station's own fields. `host_id` is never changed.
  Future<Station> updateStation({
    required String stationId,
    required String name,
    String description,
    String address,
    required double latitude,
    required double longitude,
  });

  /// Uploads one photo and returns its storage path (`<folder>/<index>.<ext>`).
  Future<String> uploadStationImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  });

  Future<StationImage> insertStationImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  });

  /// Deletes the `station_images` row and its storage file.
  Future<void> deleteStationImage(String imageId);

  Future<StationBusinessImage> insertStationBusinessImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  });

  /// Deletes the `station_business_images` row and its storage file.
  Future<void> deleteStationBusinessImage(String imageId);

  Future<StationBusiness> insertStationBusiness({
    required String stationId,
    required String businessType,
    required String businessName,
    String description,
  });

  /// Stamps `deleted_at` on the given businesses (already-deleted rows kept).
  Future<void> softDeleteStationBusinesses(List<String> businessIds);

  /// Every non-deleted promotion of the station (any status), newest first.
  Future<List<StationPromotion>> getStationPromotions(String stationId);

  Future<StationPromotion> createPromotion({
    required String stationId,
    required String title,
    String description,
    DateTime? validFrom,
    DateTime? validUntil,
    String status,
    String termsAndConditions,
  });

  Future<StationPromotion> updatePromotionStatus(
    String promotionId,
    String status,
  );

  /// Soft-deletes a promotion (stamps `deleted_at`).
  Future<void> deletePromotion(String promotionId);
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
    String? businessType,
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
        'business_type_filter': businessType,
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

  // ----- Host side -----------------------------------------------------------

  @override
  Future<List<Station>> getStationsByHost(String hostId) async {
    final List<dynamic> data = await _client
        .from('stations')
        .select('*, chargers(id, status)')
        .eq('host_id', hostId)
        .order('created_at', ascending: false);
    return Station.listFromJson(data);
  }

  @override
  Future<List<Charger>> getAllStationChargers(String stationId) async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('station_id', stationId)
        .order('name', ascending: true);
    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<Station> createStation({
    required String hostId,
    required String name,
    String description = '',
    String address = '',
    required double latitude,
    required double longitude,
  }) async {
    final data = await _client
        .from('stations')
        .insert({
          'host_id': hostId,
          'name': name,
          'description': description,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
        })
        .select()
        .single();
    return Station.fromJson(data);
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
    final data = await _client
        .from('stations')
        .update({
          'name': name,
          'description': description,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
        })
        .eq('id', stationId)
        .select()
        .single();
    return Station.fromJson(data);
  }

  @override
  Future<String> uploadStationImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final ext = fileExtension.isEmpty ? 'jpg' : fileExtension.toLowerCase();
    final path = '$folder/$index.$ext';
    // Always an INSERT (upsert false): covered by the INSERT storage policy.
    await _client.storage.from(_imageBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(ext),
            upsert: false,
          ),
        );
    return path;
  }

  @override
  Future<StationImage> insertStationImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) async {
    final data = await _client
        .from('station_images')
        .insert({
          'station_id': stationId,
          'image_url': imagePath,
          'display_order': displayOrder,
        })
        .select()
        .single();
    return StationImage.fromJson(data);
  }

  @override
  Future<void> deleteStationImage(String imageId) =>
      _deleteImageRow(table: 'station_images', imageId: imageId);

  @override
  Future<StationBusinessImage> insertStationBusinessImage({
    required String stationId,
    required String imagePath,
    required int displayOrder,
  }) async {
    final data = await _client
        .from('station_business_images')
        .insert({
          'station_id': stationId,
          'image_url': imagePath,
          'display_order': displayOrder,
        })
        .select()
        .single();
    return StationBusinessImage.fromJson(data);
  }

  @override
  Future<void> deleteStationBusinessImage(String imageId) =>
      _deleteImageRow(table: 'station_business_images', imageId: imageId);

  @override
  Future<StationBusiness> insertStationBusiness({
    required String stationId,
    required String businessType,
    required String businessName,
    String description = '',
  }) async {
    final data = await _client
        .from('station_businesses')
        .insert({
          'station_id': stationId,
          'business_type': businessType,
          'business_name': businessName,
          'description': description,
        })
        .select()
        .single();
    return StationBusiness.fromJson(data);
  }

  @override
  Future<void> softDeleteStationBusinesses(List<String> businessIds) async {
    if (businessIds.isEmpty) return;
    await _client
        .from('station_businesses')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', businessIds)
        .isFilter('deleted_at', null);
  }

  @override
  Future<List<StationPromotion>> getStationPromotions(String stationId) async {
    final List<dynamic> data = await _client
        .from('station_promotions')
        .select()
        .eq('station_id', stationId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return data
        .map((row) => StationPromotion.fromJson(row as Map<String, dynamic>))
        .toList();
  }

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
    final data = await _client
        .from('station_promotions')
        .insert({
          'station_id': stationId,
          'title': title,
          'description': description,
          'valid_from': validFrom?.toUtc().toIso8601String(),
          'valid_until': validUntil?.toUtc().toIso8601String(),
          'status': status,
          'terms_and_conditions': termsAndConditions,
        })
        .select()
        .single();
    return StationPromotion.fromJson(data);
  }

  @override
  Future<StationPromotion> updatePromotionStatus(
    String promotionId,
    String status,
  ) async {
    final data = await _client
        .from('station_promotions')
        .update({'status': status})
        .eq('id', promotionId)
        .select()
        .single();
    return StationPromotion.fromJson(data);
  }

  @override
  Future<void> deletePromotion(String promotionId) async {
    await _client
        .from('station_promotions')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', promotionId);
  }

  /// Deletes one image row from [table] and then its storage object. Throws
  /// when the row wasn't removed (usually a missing DELETE RLS policy) or the
  /// storage object wasn't removed (missing storage SELECT/DELETE policy).
  Future<void> _deleteImageRow({
    required String table,
    required String imageId,
  }) async {
    final existing = await _client
        .from(table)
        .select('image_url')
        .eq('id', imageId)
        .maybeSingle();
    if (existing == null) return;
    final rawUrl = (existing['image_url'] as String?)?.trim() ?? '';

    final deleted =
        await _client.from(table).delete().eq('id', imageId).select('id');
    if (deleted.isEmpty) {
      throw StateError(
        'Could not delete image $imageId from $table (row still exists; '
        'check the DELETE policy).',
      );
    }

    final path = _storagePath(rawUrl);
    if (path.isEmpty) return;
    final removed = await _client.storage.from(_imageBucket).remove([path]);
    if (removed.isEmpty) {
      throw StateError(
        'Storage object "$path" was not removed from "$_imageBucket" '
        '(check the storage SELECT/DELETE policies).',
      );
    }
  }

  /// Storage path for a stored image value: raw paths as-is; public URLs with
  /// the `/object/public/<bucket>/` prefix (and any query) stripped.
  String _storagePath(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return '';
    if (!raw.startsWith('http')) return raw;
    final marker = '/object/public/$_imageBucket/';
    final markerIndex = raw.indexOf(marker);
    if (markerIndex == -1) return '';
    final after = raw.substring(markerIndex + marker.length);
    final q = after.indexOf('?');
    return q == -1 ? after : after.substring(0, q);
  }

  static String _contentTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Full URLs are kept as-is; anything else is a path in [_imageBucket].
  String _resolvedUrl(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty || raw.startsWith('http')) return raw;
    return _client.storage.from(_imageBucket).getPublicUrl(raw);
  }
}
