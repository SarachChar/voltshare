import 'dart:async';
import 'dart:typed_data';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

class ChargerController {
  List<Charger> chargers = List.empty();
  final ChargerService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  ChargerController(this.service);

  Future<List<Charger>> fetchNearbyChargers() async {
    onSyncController.add(true);
    chargers = await service.getNearbyChargers();
    onSyncController.add(false);
    return chargers;
  }

  /// Fetches the chargers owned by [hostId], most recent first.
  Future<List<Charger>> fetchChargersByHost(String hostId) async {
    onSyncController.add(true);
    chargers = await service.getChargersByHost(hostId);
    onSyncController.add(false);
    return chargers;
  }

  /// Fetches the images for a charger, ordered for display.
  Future<List<ChargerImage>> fetchChargerImages(String chargerId) {
    return service.getChargerImages(chargerId);
  }

  /// Fetches the weekly availability for a charger, ordered by day of week.
  Future<List<ChargerAvailability>> fetchChargerAvailability(String chargerId) {
    return service.getChargerAvailability(chargerId);
  }

  /// Fetches the businesses available around a charger.
  Future<List<ChargerBusiness>> fetchChargerBusinesses(String chargerId) {
    return service.getChargerBusinesses(chargerId);
  }

  /// Fetches the business photos for a charger, ordered for display.
  Future<List<BusinessImage>> fetchBusinessImages(String chargerId) {
    return service.getBusinessImages(chargerId);
  }

  /// Fetches the promotions for a charger, most recent first.
  Future<List<ChargerPromotion>> fetchChargerPromotions(String chargerId) {
    return service.getChargerPromotions(chargerId);
  }

  /// Fetches only the ACTIVE promotions for a charger (user-facing view).
  Future<List<ChargerPromotion>> fetchActivePromotions(String chargerId) {
    return service.getActivePromotions(chargerId);
  }

  /// Toggles a promotion's status between "ACTIVE" and "INACTIVE".
  /// (Values are uppercase to satisfy the DB's status check constraint.)
  Future<ChargerPromotion> togglePromotionStatus(
    String promotionId,
    bool active,
  ) {
    return service.updatePromotionStatus(
      promotionId,
      active ? 'ACTIVE' : 'INACTIVE',
    );
  }

  /// Creates a new promotion for a charger.
  Future<ChargerPromotion> createPromotion({
    required String chargerId,
    required String title,
    String description = '',
    DateTime? validFrom,
    DateTime? validUntil,
    String status = 'ACTIVE',
    String termsAndConditions = '',
  }) {
    return service.createPromotion(
      chargerId: chargerId,
      title: title,
      description: description,
      validFrom: validFrom,
      validUntil: validUntil,
      status: status,
      termsAndConditions: termsAndConditions,
    );
  }

  /// Soft-deletes a promotion (stamps its `deleted_at`).
  Future<void> deletePromotion(String promotionId) {
    return service.deletePromotion(promotionId);
  }

  /// Creates a new charger row and returns the saved charger (with its id).
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
  }) {
    return service.createCharger(
      hostId: hostId,
      name: name,
      description: description,
      address: address,
      latitude: latitude,
      longitude: longitude,
      chargerType: chargerType,
      connectorType: connectorType,
      powerKw: powerKw,
      pricePerKwh: pricePerKwh,
      status: status,
    );
  }

  /// Updates an existing charger row and returns the saved charger.
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
  }) {
    return service.updateCharger(
      chargerId: chargerId,
      name: name,
      description: description,
      address: address,
      latitude: latitude,
      longitude: longitude,
      chargerType: chargerType,
      connectorType: connectorType,
      powerKw: powerKw,
      pricePerKwh: pricePerKwh,
    );
  }

  /// Updates only a charger's availability status and returns the saved row.
  Future<Charger> updateChargerStatus({
    required String chargerId,
    required String status,
  }) {
    return service.updateChargerStatus(
      chargerId: chargerId,
      status: status,
    );
  }

  /// Links an uploaded image path to a charger in `charger_images`.
  Future<ChargerImage> insertChargerImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  }) {
    return service.insertChargerImage(
      chargerId: chargerId,
      imagePath: imagePath,
      displayOrder: displayOrder,
    );
  }

  /// Removes a charger image row (used when editing).
  Future<void> deleteChargerImage(String imageId) {
    return service.deleteChargerImage(imageId);
  }

  /// Removes a business image row (used when editing).
  Future<void> deleteBusinessImage(String imageId) {
    return service.deleteBusinessImage(imageId);
  }

  /// Replaces a charger's weekly availability with [days].
  Future<void> replaceChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) {
    return service.replaceChargerAvailability(
      chargerId: chargerId,
      days: days,
    );
  }

  /// Replaces a charger's businesses with [businesses].
  Future<void> replaceChargerBusinesses({
    required String chargerId,
    required List<ChargerBusiness> businesses,
  }) {
    return service.replaceChargerBusinesses(
      chargerId: chargerId,
      businesses: businesses,
    );
  }

  /// Saves a charger's weekly opening hours into `charger_availability`.
  Future<void> insertChargerAvailability({
    required String chargerId,
    required List<ChargerAvailability> days,
  }) {
    return service.insertChargerAvailability(
      chargerId: chargerId,
      days: days,
    );
  }

  /// Adds a business offered at a charger.
  Future<ChargerBusiness> insertChargerBusiness({
    required String chargerId,
    required String businessType,
    required String businessName,
    String description = '',
  }) {
    return service.insertChargerBusiness(
      chargerId: chargerId,
      businessType: businessType,
      businessName: businessName,
      description: description,
    );
  }

  /// Links an uploaded business photo path to a charger in `business_images`.
  Future<BusinessImage> insertBusinessImage({
    required String chargerId,
    required String imagePath,
    required int displayOrder,
  }) {
    return service.insertBusinessImage(
      chargerId: chargerId,
      imagePath: imagePath,
      displayOrder: displayOrder,
    );
  }

  /// Uploads a single charger image to storage and returns its stored path.
  Future<String> uploadChargerImage({
    required String folder,
    required int index,
    required Uint8List bytes,
    required String fileExtension,
  }) {
    return service.uploadChargerImage(
      folder: folder,
      index: index,
      bytes: bytes,
      fileExtension: fileExtension,
    );
  }
}
