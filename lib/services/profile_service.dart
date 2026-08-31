import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/models/profile_model.dart';

abstract class ProfileService {
  Future<Profile?> getProfile(String userId);
  Future<Profile> upsertProfile(Profile profile);
}

class ProfileSupabaseService implements ProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<Profile?> getProfile(String userId) async {
    final Map<String, dynamic>? data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return Profile.fromJson(data);
  }

  @override
  Future<Profile> upsertProfile(Profile profile) async {
    final Map<String, dynamic> data = await _client
        .from('profiles')
        .upsert({
          'id': profile.id,
          'name': profile.name,
          'phone': profile.phone,
          'email': profile.email,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return Profile.fromJson(data);
  }
}
