import 'dart:async';

import 'package:voltshare_app/models/payment_method_model.dart';
import 'package:voltshare_app/services/payment_method_service.dart';

/// Thin controller over [PaymentMethodService], following the project's
/// Model → Service → Controller pattern. Kept in its own file so payment data
/// doesn't share state with other features.
///
/// Emits on [onSync] around every operation — `true` while a call is in flight,
/// `false` when it finishes — so the UI can show a loading indicator. Mirrors
/// the pattern used by `ProfileController` / `ChargerController`.
class PaymentMethodController {
  final PaymentMethodService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  PaymentMethodController(this.service);

  /// Fetches the user's saved cards (default first).
  Future<List<PaymentMethod>> fetchPaymentMethods(String userId) async {
    onSyncController.add(true);
    final cards = await service.getPaymentMethods(userId);
    onSyncController.add(false);
    return cards;
  }

  /// Saves a new card for the user.
  Future<PaymentMethod> addPaymentMethod({
    required String userId,
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
    bool isDefault = false,
  }) async {
    onSyncController.add(true);
    final card = await service.addPaymentMethod(
      userId: userId,
      cardNumber: cardNumber,
      holderName: holderName,
      expMonth: expMonth,
      expYear: expYear,
      isDefault: isDefault,
    );
    onSyncController.add(false);
    return card;
  }

  /// Removes a saved card.
  Future<void> deletePaymentMethod(String id) async {
    onSyncController.add(true);
    await service.deletePaymentMethod(id);
    onSyncController.add(false);
  }

  /// Makes a card the user's default (clears the previous default first).
  Future<void> setDefaultPaymentMethod({
    required String userId,
    required String id,
  }) async {
    onSyncController.add(true);
    await service.setDefaultPaymentMethod(userId: userId, id: id);
    onSyncController.add(false);
  }

  /// Closes the sync stream. Call when the owner is disposed.
  void dispose() {
    onSyncController.close();
  }
}
