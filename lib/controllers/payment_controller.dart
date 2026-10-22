import 'dart:async';

import 'package:voltshare_app/models/payment_result_model.dart';
import 'package:voltshare_app/services/payment_service.dart';

/// Thin controller over [PaymentService] for the booking payment step.
///
/// Emits on [onSync] around every call — `true` while running, `false` when
/// done — mirroring the project's other controllers.
class PaymentController {
  final PaymentService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  PaymentController(this.service);

  /// Runs the mock charge for [amount] against the card with [cardLast4].
  Future<PaymentResult> charge({
    required String cardLast4,
    required int amount,
    String? reservationRef,
  }) async {
    onSyncController.add(true);
    final result = await service.charge(
      cardLast4: cardLast4,
      amount: amount,
      reservationRef: reservationRef,
    );
    onSyncController.add(false);
    return result;
  }

  /// Records the paid booking fee for a reservation.
  Future<void> recordBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
    String? transactionId,
  }) async {
    onSyncController.add(true);
    await service.recordBookingFee(
      reservationId: reservationId,
      paymentMethodId: paymentMethodId,
      amount: amount,
      transactionId: transactionId,
    );
    onSyncController.add(false);
  }

  void dispose() {
    onSyncController.close();
  }
}
