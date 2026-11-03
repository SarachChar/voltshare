import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/services/review_service.dart';

/// In-memory [ReviewService] for tests: station calls return [summary] /
/// [reviews].
class FakeReviewService implements ReviewService {
  ReviewSummary summary = ReviewSummary.empty;
  List<PublicReview> reviews = const [];

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
  Future<ReviewSummary> getStationReviewSummary(
    String stationId,
  ) async {
    lastStationId = stationId;
    return summary;
  }

  @override
  Future<List<PublicReview>> getStationReviews(
    String stationId, {
    int limit = 20,
    int offset = 0,
  }) async {
    lastStationId = stationId;
    return reviews.take(limit).toList();
  }
}
