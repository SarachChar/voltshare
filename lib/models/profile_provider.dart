import 'package:flutter/material.dart';
import 'package:voltshare_app/models/profile_model.dart';

/// Pure state holder for the signed-in user's profile.
/// Mirrors the ChangeNotifier providers in the example project.
class ProfileProvider extends ChangeNotifier {
  Profile? _profile;

  Profile? get profile => _profile;

  String get name => _profile?.name ?? '';
  String get email => _profile?.email ?? '';
  String get phone => _profile?.phone ?? '';

  void setProfile(Profile profile) {
    _profile = profile;
    notifyListeners();
  }

  void reset() {
    _profile = null;
    notifyListeners();
  }
}
