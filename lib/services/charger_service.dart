import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/models/charger_model.dart';

abstract class ChargerService {
  Future<List<Charger>> getNearbyChargers();
}

/// Supabase-backed implementation that reads from the `chargers` table.
class ChargerSupabaseService implements ChargerService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<Charger>> getNearbyChargers() async {
    final List<dynamic> data = await _client
        .from('chargers')
        .select()
        .order('created_at', ascending: false);

    return AllChargers.fromJson(data).chargers;
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
}
