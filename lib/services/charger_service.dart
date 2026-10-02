import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/charger_model.dart';

abstract class ChargerService {
  Future<List<Charger>> getNearbyChargers();

  /// Returns the chargers owned by [hostId] (the `host_id` column),
  /// most recent first.
  Future<List<Charger>> getChargersByHost(String hostId);

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

  /// Inserts a row into `charger_images` linking [imagePath] (a storage path
  /// inside the images bucket) to [chargerId] at [displayOrder].
  Future<ChargerImage> insertChargerImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
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
        .order('created_at', ascending: false);

    return AllChargers.fromJson(data).chargers;
  }

  @override
  Future<List<Charger>> getChargersByHost(String hostId) async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .eq('host_id', hostId)
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
    // Delegates to the `get-charger-promotions` edge function, which runs an
    // expiry sweep (stamping lapsed promotions as EXPIRED) before returning
    // every non-deleted promotion for the charger.
    final response = await _client.functions.invoke(
      'get-charger-promotions',
      body: {'charger_id': chargerId},
    );

    final data = (response.data?['promotions'] as List<dynamic>?) ?? [];

    return data
        .map(
          (item) => ChargerPromotion.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<ChargerPromotion>> getActivePromotions(String chargerId) async {
    // Delegates to the `get-active-promotions` edge function, which runs the
    // same expiry sweep and returns only ACTIVE, non-deleted promotions.
    final response = await _client.functions.invoke(
      'get-active-promotions',
      body: {'charger_id': chargerId},
    );

    final data = (response.data?['promotions'] as List<dynamic>?) ?? [];

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
