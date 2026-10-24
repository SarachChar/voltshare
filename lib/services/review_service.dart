import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/review_model.dart';

/// Thrown when a reservation already has a review (1-1 unique constraint).
class ReviewAlreadyExistsException implements Exception {}

abstract class ReviewService {
  /// The review for [reservationId], or null if not reviewed yet.
  Future<Review?> getReviewByReservation(String reservationId);

  /// Saves a review. Throws [ReviewAlreadyExistsException] when the
  /// reservation was already reviewed. RLS only allows the owner of a
  /// completed reservation.
  Future<Review> createReview({
    required String reservationId,
    required int rating,
    String? comment,
  });

  /// Average rating + count for a charger.
  Future<ChargerReviewSummary> getChargerReviewSummary(String chargerId);

  /// A charger's reviews, newest first, with censored reviewer names.
  Future<List<ChargerReview>> getChargerReviews(
    String chargerId, {
    int limit = 20,
    int offset = 0,
  });
}

class ReviewSupabaseService implements ReviewService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<Review?> getReviewByReservation(String reservationId) async {
    final data = await _client
        .from('reviews')
        .select()
        .eq('reservation_id', reservationId)
        .maybeSingle();
    return data == null ? null : Review.fromJson(data);
  }

  @override
  Future<Review> createReview({
    required String reservationId,
    required int rating,
    String? comment,
  }) async {
    final trimmed = comment?.trim() ?? '';
    try {
      final data = await _client
          .from('reviews')
          .insert({
            'reservation_id': reservationId,
            'rating': rating,
            'comment': trimmed.isEmpty ? null : trimmed,
          })
          .select()
          .single();
      return Review.fromJson(data);
    } on PostgrestException catch (e) {
      // 23505 = unique_violation on reservation_id.
      if (e.code == '23505') throw ReviewAlreadyExistsException();
      rethrow;
    }
  }

  @override
  Future<ChargerReviewSummary> getChargerReviewSummary(String chargerId) async {
    final List<dynamic> data = await _client.rpc(
      'charger_review_summary',
      params: {'p_charger_id': chargerId},
    );
    if (data.isEmpty) return ChargerReviewSummary.empty;
    return ChargerReviewSummary.fromJson(data.first as Map<String, dynamic>);
  }

  @override
  Future<List<ChargerReview>> getChargerReviews(
    String chargerId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final List<dynamic> data = await _client.rpc(
      'charger_reviews',
      params: {
        'p_charger_id': chargerId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return data
        .map((row) => ChargerReview.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
