import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/charger_model.dart';

abstract class ChargerService {
  /// Returns the chargers shown on the home/map view — only those with
  /// status 'available' — most recent first.
  Future<List<Charger>> getNearbyChargers();

  /// Returns available chargers whose coordinates fall inside the map's visible
  /// rectangle, backed by the `chargers_in_bounds` Postgres function. Results
  /// are ordered by distance from ([userLat], [userLng]) — nearest first — with
  /// each result's [Charger.distanceMeters] populated.
  ///
  /// The bounds are the visible region's corners:
  ///   [minLat]/[minLng]  south-west corner
  ///   [maxLat]/[maxLng]  north-east corner
  /// [limit] caps how many rows come back in dense areas.
  Future<List<Charger>> getChargersInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit,
  });

  /// Distance-sorted, paginated search for the Search screen, backed by the
  /// `search_chargers` Postgres function. Returns up to [limit] available
  /// chargers starting at [offset], nearest to ([userLat], [userLng]) first,
  /// with each result's [Charger.distanceMeters] populated.
  ///
  /// All filters are optional:
  ///   [query]          case-insensitive substring match on the charger name
  ///   [chargerType]    'AC' | 'DC'
  ///   [connectorType]  'CCS2' | 'Type 2' | 'CHAdeMO'
  ///   [powerMin]/[powerMax]  power_kw range in kW, half-open [min, max)
  Future<List<Charger>> searchChargers({
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

  /// Returns the live chargers owned by [hostId] (the `host_id` column) —
  /// those with status 'available' or 'unavailable' — most recent first.
  Future<List<Charger>> getChargersByHost(String hostId);

  /// Returns the pending chargers owned by [hostId] — those still going
  /// through the approval flow (status 'review', 'setup' or 'rejected') —
  /// most recent first.
  Future<List<Charger>> getPendingChargersByHost(String hostId);

  /// Returns the images for [chargerId], ordered by `display_order`.
  /// Each [ChargerImage.imageUrl] is a ready-to-use public URL.
  Future<List<ChargerImage>> getChargerImages(String chargerId);

  /// Returns the weekly availability rows for [chargerId], ordered by
  /// `day_of_week` (0 = Sunday .. 6 = Saturday).
  Future<List<ChargerAvailability>> getChargerAvailability(String chargerId);

  /// Returns the non-deleted businesses attached to [chargerId].
  Future<List<ChargerBusiness>> getChargerBusinesses(String chargerId);

  /// Returns the business photos for [chargerId], ordered by `display_order`.
  /// Each [BusinessImage.imageUrl] is a ready-to-use public URL.
  Future<List<BusinessImage>> getBusinessImages(String chargerId);

  /// Returns the promotions for [chargerId], most recent first.
  Future<List<ChargerPromotion>> getChargerPromotions(String chargerId);

  /// Returns only the ACTIVE, non-deleted promotions for [chargerId]
  /// (the user-facing view), most recent first.
  Future<List<ChargerPromotion>> getActivePromotions(String chargerId);

  /// Updates the `status` of a promotion ("ACTIVE" / "INACTIVE" / "EXPIRED")
  /// and returns the saved row.
  Future<ChargerPromotion> updatePromotionStatus(
    String promotionId,
    String status,
  );

  /// Creates a new promotion and returns the inserted row.
  Future<ChargerPromotion> createPromotion({
    required String chargerId,
    required String title,
    String description,
    DateTime? validFrom,
    DateTime? validUntil,
    String status,
    String termsAndConditions,
  });

  /// Soft-deletes a promotion by stamping its `deleted_at` column.
  Future<void> deletePromotion(String promotionId);

  /// Inserts a new charger row and returns the saved [Charger] (with the
  /// database-generated id).
  Future<Charger> createCharger({
    required String hostId,
    required String name,
    String description,
    String address,
    double latitude,
    double longitude,
    String chargerType,
    String connectorType,
    double powerKw,
    double pricePerKwh,
    String status,
  });

  /// Updates an existing charger row (identified by [chargerId]) and returns
  /// the saved [Charger].
  Future<Charger> updateCharger({
    required String chargerId,
    required String name,
    String description,
    String address,
    double latitude,
    double longitude,
    String chargerType,
    String connectorType,
    double powerKw,
    double pricePerKwh,
  });

  /// Updates only the `status` of a charger (e.g. 'available' /
  /// 'unavailable') and returns the saved [Charger]. Used by the host
  /// dashboard's availability toggle.
  Future<Charger> updateChargerStatus({
    required String chargerId,
    required String status,
  });

  /// Inserts a row into `charger_images` linking [imagePath] (a storage path
  /// inside the images bucket) to [chargerId] at [displayOrder].
  Future<ChargerImage> insertChargerImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  });

  /// Removes the `charger_images` row with [imageId] and deletes its backing
  /// file from storage. Used when a host removes an existing photo while
  /// editing a charger. Throws if the DB row couldn't be deleted (e.g. a
  /// missing RLS policy).
  Future<void> deleteChargerImage(String imageId);

  /// Removes the `business_images` row with [imageId] and deletes its backing
  /// file from storage. Used when a host removes an existing business photo
  /// while editing a charger. Throws if the DB row couldn't be deleted.
  Future<void> deleteBusinessImage(String imageId);

  /// Replaces all of a charger's weekly availability rows with [days]:
  /// deletes the existing rows for [chargerId], then inserts the new set.
  Future<void> replaceChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  });

  /// Replaces a charger's businesses with [businesses]: soft-deletes the
  /// existing non-deleted rows for [chargerId], then inserts the new set.
  /// Only the `businessType`, `businessName` and `description` of each entry
  /// are used; ids are generated by the database.
  Future<void> replaceChargerBusinesses({
    required String chargerId,
    required List<ChargerBusiness> businesses,
  });

  /// Inserts the weekly opening-hours rows for [chargerId] into
  /// `charger_availability` (one row per day, 0 = Sunday .. 6 = Saturday).
  Future<void> insertChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  });

  /// Inserts a business offered at [chargerId] into `charger_businesses`.
  /// [businessType] must be one of the DB's allowed values (e.g. `CAFE`).
  Future<ChargerBusiness> insertChargerBusiness({
    required String chargerId,
    required String businessType,
    required String businessName,
    String description,
  });

  /// Inserts a row into `business_images` linking [imagePath] (a storage path
  /// inside the images bucket) to [chargerId] at [displayOrder]. Business
  /// photos belong to the charger as a whole, not to a single business.
  Future<BusinessImage> insertBusinessImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  });

  /// Uploads a single charger image to storage and returns the stored path
  /// (relative to the charger images bucket, e.g. `<folder>/<index>.jpg`).
  ///
  /// [folder] groups the images (typically a charger id). [index] drives both
  /// the file name and the intended display order. [fileExtension] is the
  /// original file's extension (without the dot), used to build the file name
  /// and pick a content type.
  Future<String> uploadChargerImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  });
}

/// Supabase-backed implementation that reads from the `chargers` table.
class ChargerSupabaseService implements ChargerService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Storage bucket that holds charger images.
  static const String _imageBucket = 'voltshare_charger';

  @override
  Future<List<Charger>> getNearbyChargers() async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('status', 'available')
        .order('created_at', ascending: false);

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<Charger>> getChargersInBounds({
    required double userLat,
    required double userLng,
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    int limit = 200,
  }) async {
    final List<dynamic> data = await _client.rpc(
      'chargers_in_bounds',
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

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<Charger>> searchChargers({
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
    // Blank/whitespace-only queries are sent as null so the SQL skips the
    // name filter entirely rather than matching on an empty string.
    final trimmedQuery = query?.trim();

    final List<dynamic> data = await _client.rpc(
      'search_chargers',
      params: {
        'user_lat': userLat,
        'user_lng': userLng,
        'search_query': (trimmedQuery == null || trimmedQuery.isEmpty)
            ? null
            : trimmedQuery,
        'charger_type_filter': chargerType,
        'connector_type_filter': connectorType,
        'power_min': powerMin,
        'power_max': powerMax,
        'page_limit': limit,
        'page_offset': offset,
      },
    );

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<Charger>> getChargersByHost(String hostId) async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('host_id', hostId)
        .inFilter('status', ['available', 'unavailable'])
        .order('created_at', ascending: false);

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<Charger>> getPendingChargersByHost(String hostId) async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('host_id', hostId)
        .inFilter('status', ['review', 'setup', 'rejected'])
        .order('created_at', ascending: false);

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<ChargerImage>> getChargerImages(String chargerId) async {
    final List<dynamic> data = await _client
        .from('charger_images')
        .select()
        .eq('charger_id', chargerId)
        .order('display_order', ascending: true);

    return data
        .map((item) => ChargerImage.fromJson(item as Map<String, dynamic>))
        .map(_withResolvedUrl)
        .toList();
  }

  @override
  Future<List<ChargerAvailability>> getChargerAvailability(
    String chargerId,
  ) async {
    final List<dynamic> data = await _client
        .from('charger_availability')
        .select()
        .eq('charger_id', chargerId)
        .order('day_of_week', ascending: true);

    return data
        .map(
          (item) =>
              ChargerAvailability.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<ChargerBusiness>> getChargerBusinesses(String chargerId) async {
    final List<dynamic> data = await _client
        .from('charger_businesses')
        .select()
        .eq('charger_id', chargerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    return data
        .map((item) => ChargerBusiness.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<BusinessImage>> getBusinessImages(String chargerId) async {
    final List<dynamic> data = await _client
        .from('business_images')
        .select()
        .eq('charger_id', chargerId)
        .order('display_order', ascending: true);

    return data
        .map((item) => BusinessImage.fromJson(item as Map<String, dynamic>))
        .map(
          (image) => BusinessImage(
            id: image.id,
            chargerId: image.chargerId,
            imageUrl: _resolvedUrl(image.imageUrl),
            displayOrder: image.displayOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ChargerPromotion>> getChargerPromotions(String chargerId) async {
    // Queries `charger_promotions` directly for every non-deleted promotion
    // for the charger, most recent first. Note this does not run the expiry
    // sweep the `get-charger-promotions` edge function used to do, so a
    // promotion whose `valid_until` has lapsed stays at whatever `status`
    // it already has until something else (e.g. updatePromotionStatus)
    // flips it to EXPIRED.
    final List<dynamic> data = await _client
        .from('charger_promotions')
        .select()
        .eq('charger_id', chargerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data
        .map(
          (item) => ChargerPromotion.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<ChargerPromotion>> getActivePromotions(String chargerId) async {
    // Queries `charger_promotions` directly for rows that are ACTIVE and
    // not soft-deleted, most recent first. Note this does not run the
    // expiry sweep the `get-active-promotions` edge function used to do,
    // so a promotion whose `valid_until` has lapsed stays ACTIVE here until
    // something else (e.g. updatePromotionStatus) flips its status.
    final List<dynamic> data = await _client
        .from('charger_promotions')
        .select()
        .eq('charger_id', chargerId)
        .eq('status', 'ACTIVE')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data
        .map(
          (item) => ChargerPromotion.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<ChargerPromotion> updatePromotionStatus(
    String promotionId,
    String status,
  ) async {
    final data = await _client
        .from('charger_promotions')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', promotionId)
        .select()
        .single();

    return ChargerPromotion.fromJson(data);
  }

  @override
  Future<ChargerPromotion> createPromotion({
    required String chargerId,
    required String title,
    String description = '',
    DateTime? validFrom,
    DateTime? validUntil,
    String status = 'ACTIVE',
    String termsAndConditions = '',
  }) async {
    final data = await _client
        .from('charger_promotions')
        .insert({
          'charger_id': chargerId,
          'title': title,
          'description': description,
          'valid_from': validFrom?.toUtc().toIso8601String(),
          'valid_until': validUntil?.toUtc().toIso8601String(),
          'status': status,
          'terms_and_conditions': termsAndConditions,
        })
        .select()
        .single();

    return ChargerPromotion.fromJson(data);
  }

  @override
  Future<void> deletePromotion(String promotionId) async {
    await _client
        .from('charger_promotions')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', promotionId);
  }

  @override
  Future<Charger> createCharger({
    required String hostId,
    required String name,
    String description = '',
    String address = '',
    double latitude = 0.0,
    double longitude = 0.0,
    String chargerType = '',
    String connectorType = '',
    double powerKw = 0.0,
    double pricePerKwh = 0.0,
    String status = 'available',
  }) async {
    // `id` and `created_at` are left for the DB to generate, so we build the
    // insert payload explicitly rather than using Charger.toJson().
    final data = await _client
        .from('chargers')
        .insert({
          'host_id': hostId,
          'name': name,
          'description': description,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'charger_type': chargerType,
          'connector_type': connectorType,
          'power_kw': powerKw,
          'price_per_kwh': pricePerKwh,
          'status': status,
        })
        .select()
        .single();

    return Charger.fromJson(data);
  }

  @override
  Future<Charger> updateCharger({
    required String chargerId,
    required String name,
    String description = '',
    String address = '',
    double latitude = 0.0,
    double longitude = 0.0,
    String chargerType = '',
    String connectorType = '',
    double powerKw = 0.0,
    double pricePerKwh = 0.0,
  }) async {
    // Mirrors createCharger but as an UPDATE keyed on the existing id. `status`
    // and `host_id` are intentionally left untouched so editing a listing
    // doesn't change its availability toggle or ownership.
    final data = await _client
        .from('chargers')
        .update({
          'name': name,
          'description': description,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'charger_type': chargerType,
          'connector_type': connectorType,
          'power_kw': powerKw,
          'price_per_kwh': pricePerKwh,
        })
        .eq('id', chargerId)
        .select()
        .single();

    return Charger.fromJson(data);
  }

  @override
  Future<Charger> updateChargerStatus({
    required String chargerId,
    required String status,
  }) async {
    final data = await _client
        .from('chargers')
        .update({'status': status})
        .eq('id', chargerId)
        .select()
        .single();

    return Charger.fromJson(data);
  }

  @override
  Future<ChargerImage> insertChargerImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  }) async {
    final data = await _client
        .from('charger_images')
        .insert({
          'charger_id': chargerId,
          'image_url': imagePath,
          'display_order': displayOrder,
        })
        .select()
        .single();

    return ChargerImage.fromJson(data);
  }

  @override
  Future<void> deleteChargerImage(String imageId) async {
    await _deleteImageRow(table: 'charger_images', imageId: imageId);
  }

  @override
  Future<void> deleteBusinessImage(String imageId) async {
    await _deleteImageRow(table: 'business_images', imageId: imageId);
  }

  /// Deletes a single image row from [table] (either `charger_images` or
  /// `business_images`) and removes its backing file from storage.
  ///
  /// The row's raw `image_url` is read first so the storage object can be
  /// located, then the DB row is deleted with `.select()` so the result can be
  /// checked: an empty result means the row wasn't removed (most often a
  /// row-level-security DELETE policy), which is raised as an error instead of
  /// failing silently. The storage file is removed last; a failure there is
  /// logged but doesn't fail the whole operation, since the DB link is already
  /// gone and the orphaned object can be cleaned up separately.
  Future<void> _deleteImageRow({
    required String table,
    required String imageId,
  }) async {
    // 1. Grab the raw stored value (storage path) before the row is gone.
    final existing = await _client
        .from(table)
        .select('image_url')
        .eq('id', imageId)
        .maybeSingle();

    // Already gone — nothing to do.
    if (existing == null) return;

    final rawUrl = (existing['image_url'] as String?)?.trim() ?? '';

    // 2. Delete the DB row and confirm it actually removed something.
    final deleted = await _client
        .from(table)
        .delete()
        .eq('id', imageId)
        .select('id');

    if (deleted.isEmpty) {
      throw StateError(
        'Could not delete image $imageId from $table — the row still exists. '
        'This is usually a missing DELETE row-level-security policy.',
      );
    }

    // 3. Remove the backing storage object.
    final path = _storagePath(rawUrl);
    if (path.isEmpty) return;

    final removed = await _client.storage.from(_imageBucket).remove([path]);

    // When a DELETE storage policy is missing or doesn't match the session,
    // `remove` does not throw — it just returns an empty list. (Storage also
    // needs a matching SELECT policy, or it can't see the object to delete it.)
    // Treat an empty result as a failure so an orphaned file is surfaced
    // instead of silently kept.
    if (removed.isEmpty) {
      throw StateError(
        'The storage object "$path" was not removed from the '
        '"$_imageBucket" bucket (storage.remove returned nothing). This is '
        'usually a missing SELECT and/or DELETE policy on storage.objects for '
        'that bucket.',
      );
    }
  }

  /// Resolves a stored `image_url` to a path inside [_imageBucket], suitable
  /// for `storage.remove`. Handles both raw paths (e.g.
  /// `charger/<id>/1.jpg`) and full public URLs by stripping the known
  /// `.../object/public/<bucket>/` prefix.
  String _storagePath(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return '';
    if (!raw.startsWith('http')) return raw;

    // Full public URL: everything after `/object/public/<bucket>/` is the path.
    final marker = '/object/public/$_imageBucket/';
    final markerIndex = raw.indexOf(marker);
    if (markerIndex != -1) {
      final afterMarker = raw.substring(markerIndex + marker.length);
      // Drop any query string Supabase may append.
      final queryIndex = afterMarker.indexOf('?');
      return queryIndex == -1
          ? afterMarker
          : afterMarker.substring(0, queryIndex);
    }

    // Unrecognised URL shape — can't safely derive a storage path.
    return '';
  }

  @override
  Future<void> replaceChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) async {
    // Clear the old week first so editing can't leave stale rows behind, then
    // reuse the existing insert path.
    await _client
        .from('charger_availability')
        .delete()
        .eq('charger_id', chargerId);
    await insertChargerAvailability(chargerId: chargerId, days: days);
  }

  @override
  Future<void> replaceChargerBusinesses({
    required String chargerId,
    required List<ChargerBusiness> businesses,
  }) async {
    // Soft-delete the current businesses (matching how getChargerBusinesses
    // filters on deleted_at), then insert the edited set as fresh rows.
    await _client
        .from('charger_businesses')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('charger_id', chargerId)
        .isFilter('deleted_at', null);

    for (final business in businesses) {
      await insertChargerBusiness(
        chargerId: chargerId,
        businessType: business.businessType,
        businessName: business.businessName,
        description: business.description,
      );
    }
  }

  @override
  Future<void> insertChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) async {
    if (days.isEmpty) return;
    final rows = days
        .map((day) => {
              'charger_id': chargerId,
              'day_of_week': day.dayOfWeek,
              'start_time': day.startTime,
              'end_time': day.endTime,
              'is_available': day.isAvailable,
            })
        .toList();

    await _client.from('charger_availability').insert(rows);
  }

  @override
  Future<ChargerBusiness> insertChargerBusiness({
    required String chargerId,
    required String businessType,
    required String businessName,
    String description = '',
  }) async {
    final data = await _client
        .from('charger_businesses')
        .insert({
          'charger_id': chargerId,
          'business_type': businessType,
          'business_name': businessName,
          'description': description,
        })
        .select()
        .single();

    return ChargerBusiness.fromJson(data);
  }

  @override
  Future<BusinessImage> insertBusinessImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  }) async {
    final data = await _client
        .from('business_images')
        .insert({
          'charger_id': chargerId,
          'image_url': imagePath,
          'display_order': displayOrder,
        })
        .select()
        .single();

    return BusinessImage.fromJson(data);
  }

  @override
  Future<String> uploadChargerImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final ext = fileExtension.isEmpty ? 'jpg' : fileExtension.toLowerCase();
    final path = '$folder/$index.$ext';

    // upsert is false so this is always an INSERT into storage.objects. Each
    // charger gets a fresh id, so image paths never collide; keeping this an
    // insert means it's covered by the INSERT storage policy (not UPDATE).
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

  /// Maps a file extension to a MIME type for uploads. Falls back to
  /// `image/jpeg` for anything unrecognised.
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
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Returns a copy of [image] whose [ChargerImage.imageUrl] is a usable public
  /// URL. If the stored value already looks like a full URL it's kept as-is;
  /// otherwise it's treated as a storage path inside [_imageBucket].
  ChargerImage _withResolvedUrl(ChargerImage image) {
    final raw = image.imageUrl.trim();
    if (raw.isEmpty || raw.startsWith('http')) return image;

    return ChargerImage(
      id: image.id,
      chargerId: image.chargerId,
      imageUrl: _resolvedUrl(raw),
      displayOrder: image.displayOrder,
    );
  }

  /// Turns a stored image value into a usable URL. Values that already look
  /// like a full URL are returned untouched; anything else is treated as a
  /// path inside [_imageBucket] (e.g. `business/<charger_id>/1.jpg`).
  String _resolvedUrl(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty || raw.startsWith('http')) return raw;
    return _client.storage.from(_imageBucket).getPublicUrl(raw);
  }
}
