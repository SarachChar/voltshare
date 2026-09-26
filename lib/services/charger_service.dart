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

  /// Returns a copy of [image] whose [ChargerImage.imageUrl] is a usable public
  /// URL. If the stored value already looks like a full URL it's kept as-is;
  /// otherwise it's treated as a storage path inside [_imageBucket].
  ChargerImage _withResolvedUrl(ChargerImage image) {
    final raw = image.imageUrl.trim();
    if (raw.isEmpty || raw.startsWith('http')) return image;

    final publicUrl = _client.storage.from(_imageBucket).getPublicUrl(raw);
    return ChargerImage(
      id: image.id,
      chargerId: image.chargerId,
      imageUrl: publicUrl,
      displayOrder: image.displayOrder,
    );
  }
}
