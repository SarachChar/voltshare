import 'dart:async';
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

  /// Fetches the promotions for a charger, most recent first.
  Future<List<ChargerPromotion>> fetchChargerPromotions(String chargerId) {
    return service.getChargerPromotions(chargerId);
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
}
