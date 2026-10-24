import 'package:flutter/widgets.dart';

/// A driver's review of a completed booking, from the `reviews` table
/// (one review per reservation).
class Review {
  final String id;
  final String reservationId;

  /// 1-5, see [ratingLabels].
  final int rating;
  final String comment;
  final DateTime? createdAt;

  Review({
    required this.id,
    required this.reservationId,
    required this.rating,
    this.comment = '',
    this.createdAt,
  });

  /// Label for each rating, index = rating - 1.
  static const List<String> ratingLabels = [
    'Terrible',
    'Poor',
    'Okay',
    'Good',
    'Excellent',
  ];

  /// Label for [rating] (1-5), or empty for anything else.
  static String labelFor(int rating) =>
      rating >= 1 && rating <= 5 ? ratingLabels[rating - 1] : '';

  /// Max comment length (matches the DB check constraint).
  static const int maxCommentLength = 500;

  String get ratingLabel => labelFor(rating);

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      reservationId: json['reservation_id'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
          ?.toLocal(),
    );
  }

  /// Parses an embedded `reviews(...)` value. PostgREST returns an object for
  /// a 1-1 relation, but tolerate a list too.
  static Review? fromEmbedded(dynamic value) {
    if (value is Map<String, dynamic>) return Review.fromJson(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Review.fromJson(Map<String, dynamic>.from(value.first as Map));
    }
    return null;
  }
}

/// A public review shown on a charger's page (from the `charger_reviews`
/// RPC). [reviewerName] is already censored by the server, e.g. "P***".
class ChargerReview {
  final String id;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final String reviewerName;

  ChargerReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.reviewerName,
  });

  factory ChargerReview.fromJson(Map<String, dynamic> json) {
    return ChargerReview(
      id: json['id'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      reviewerName: json['reviewer_name'] as String? ?? 'Anonymous',
    );
  }

  /// First letter for the avatar, e.g. "P".
  String get initial =>
      reviewerName.isEmpty ? '?' : reviewerName.characters.first.toUpperCase();

  /// "just now", "5 min ago", "3 hours ago", "3 days ago", "1 week ago", ...
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return plural(diff.inHours, 'hour');
    if (diff.inDays < 7) return plural(diff.inDays, 'day');
    if (diff.inDays < 30) return plural(diff.inDays ~/ 7, 'week');
    if (diff.inDays < 365) return plural(diff.inDays ~/ 30, 'month');
    return plural(diff.inDays ~/ 365, 'year');
  }
}

/// Average rating and review count for a charger (`charger_review_summary`).
class ChargerReviewSummary {
  /// Null when there are no reviews.
  final double? averageRating;
  final int reviewCount;

  const ChargerReviewSummary({this.averageRating, this.reviewCount = 0});

  static const ChargerReviewSummary empty = ChargerReviewSummary();

  factory ChargerReviewSummary.fromJson(Map<String, dynamic> json) {
    return ChargerReviewSummary(
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasReviews => reviewCount > 0 && averageRating != null;

  /// e.g. "4.8".
  String get averageLabel => (averageRating ?? 0).toStringAsFixed(1);
}
