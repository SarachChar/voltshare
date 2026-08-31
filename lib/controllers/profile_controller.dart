import 'dart:async';
import 'package:voltshare_app/models/profile_model.dart';
import 'package:voltshare_app/services/profile_service.dart';

class ProfileController {
  Profile? profile;
  final ProfileService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  ProfileController(this.service);

  Future<Profile?> fetchProfile(String userId) async {
    onSyncController.add(true);
    profile = await service.getProfile(userId);
    onSyncController.add(false);
    return profile;
  }

  Future<Profile> saveProfile(Profile newProfile) async {
    onSyncController.add(true);
    profile = await service.upsertProfile(newProfile);
    onSyncController.add(false);
    return profile!;
  }
}
