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

  /// Pays the booking fee for [reservationId] with [paymentMethodId]. The
  /// server records the `booking_fee` row on success.
  Future<PaymentResult> payBookingFee({
    required String reservationId,
    required String paymentMethodId,
    required int amount,
  }) async {
    onSyncController.add(true);
    try {
      return await service.payBookingFee(
        reservationId: reservationId,
        paymentMethodId: paymentMethodId,
        amount: amount,
      );
    } finally {
      onSyncController.add(false);
    }
  }

  void dispose() {
    onSyncController.close();
  }
}
