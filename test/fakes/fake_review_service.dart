import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/services/review_service.dart';

/// In-memory [ReviewService] for tests. Station and charger calls return the
/// same [summary] / [reviews].
class FakeReviewService implements ReviewService {
  ChargerReviewSummary summary = ChargerReviewSummary.empty;
  List<ChargerReview> reviews = const [];

  String? lastStationId;

  @override
  Future<Review?> getReviewByReservation(String reservationId) async => null;

  @override
  Future<Review> createReview({
    required String reservationId,
    required int rating,
    String? comment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChargerReviewSummary> getChargerReviewSummary(
    String chargerId,
  ) async =>
      summary;

  @override
  Future<List<ChargerReview>> getChargerReviews(
    String chargerId, {
    int limit = 20,
    int offset = 0,
  }) async =>
      reviews;

  @override
  Future<ChargerReviewSummary> getStationReviewSummary(
    String stationId,
  ) async {
    lastStationId = stationId;
    return summary;
  }

  @override
  Future<List<ChargerReview>> getStationReviews(
    String stationId, {
    int limit = 20,
    int offset = 0,
  }) async {
    lastStationId = stationId;
    return reviews.take(limit).toList();
  }
}
