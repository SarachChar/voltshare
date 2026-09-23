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

/// Mock implementation kept for offline/local development.
class ChargerMockService implements ChargerService {
  @override
  Future<List<Charger>> getNearbyChargers() async {
    await Future.delayed(const Duration(milliseconds: 400));

    return [
      Charger('c1', "Somchai's Fast Charger", 'AC', 'Type 2', 22, 8, 'available',
          13.7466, 100.5340, distanceKm: 0.3, rating: 4.8),
      Charger('c2', 'Apinya Home Station', 'AC', 'Type 2', 7, 6, 'available',
          13.7500, 100.5300, distanceKm: 0.7, rating: 4.5),
      Charger('c3', 'DC Fast Hub Ratchada', 'DC', 'CCS2', 50, 12, 'available',
          13.7420, 100.5280, distanceKm: 1.2, rating: 4.9),
    ];
  }

  @override
  Future<List<Charger>> getChargersByHost(String hostId) async {
    await Future.delayed(const Duration(milliseconds: 400));

    return [
      Charger('c1', 'Home Garage – Type 2', 'AC', 'Type 2', 22, 8, 'available',
          13.7466, 100.5340, hostId: hostId),
      Charger('c2', 'Backyard DC Fast', 'DC', 'CCS2', 50, 8, 'unavailable',
          13.7500, 100.5300, hostId: hostId),
    ];
  }

  @override
  Future<List<ChargerImage>> getChargerImages(String chargerId) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return [
      ChargerImage(
        id: 'img1',
        chargerId: chargerId,
        imageUrl: 'https://picsum.photos/seed/$chargerId-1/800/600',
        displayOrder: 0,
      ),
      ChargerImage(
        id: 'img2',
        chargerId: chargerId,
        imageUrl: 'https://picsum.photos/seed/$chargerId-2/800/600',
        displayOrder: 1,
      ),
      ChargerImage(
        id: 'img3',
        chargerId: chargerId,
        imageUrl: 'https://picsum.photos/seed/$chargerId-3/800/600',
        displayOrder: 2,
      ),
    ];
  }

  @override
  Future<List<ChargerAvailability>> getChargerAvailability(
    String chargerId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return List.generate(7, (day) {
      // Mock: closed on Sunday (0), open 09:00-20:00 the rest of the week.
      final open = day != 0;
      return ChargerAvailability(
        id: 'avail-$chargerId-$day',
        chargerId: chargerId,
        dayOfWeek: day,
        startTime: open ? '09:00:00' : '',
        endTime: open ? '20:00:00' : '',
        isAvailable: open,
      );
    });
  }
}
