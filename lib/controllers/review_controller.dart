import 'package:flutter/foundation.dart';

import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/services/review_service.dart';

/// Thin controller over [ReviewService] (Model → Service → Controller).
class ReviewController {
  final ReviewService service;

  ReviewController(this.service);

  /// Bumped after a review is saved so the Bookings list can refresh its
  /// "Review" / "View Review" buttons.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<Review?> fetchReviewByReservation(String reservationId) =>
      service.getReviewByReservation(reservationId);

  Future<Review> createReview({
    required String reservationId,
    required int rating,
    String? comment,
  }) async {
    final review = await service.createReview(
      reservationId: reservationId,
      rating: rating,
      comment: comment,
    );
    changes.value++;
    return review;
  }

  Future<ChargerReviewSummary> fetchChargerReviewSummary(String chargerId) =>
      service.getChargerReviewSummary(chargerId);

  Future<List<ChargerReview>> fetchChargerReviews(
    String chargerId, {
    int limit = 20,
    int offset = 0,
  }) =>
      service.getChargerReviews(chargerId, limit: limit, offset: offset);
}
