import 'package:flutter/material.dart';

import 'package:voltshare_app/models/review_model.dart';

const Color _primary = Color(0xFF10B981);
const Color _navy = Color(0xFF0F1D3A);
const Color _muted = Color(0xFF64748B);
const Color _border = Color(0xFFC8EDE0);
const Color _star = Color(0xFFF59E0B);

/// Row of 5 small stars, [rating] of them filled.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 18});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rating out of 5 stars',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 1; i <= 5; i++)
              Icon(
                i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: _star,
              ),
          ],
        ),
      ),
    );
  }
}

/// One public review: initial avatar, censored name, time ago, stars and the
/// comment. Used on the charger details and All Reviews screens.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final ChargerReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  review.initial,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const Padding(padding: EdgeInsets.only(top: 2)),
                    Text(
                      review.timeAgo,
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
              RatingStars(rating: review.rating),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 12)),
            Text(
              review.comment,
              style: const TextStyle(fontSize: 15, height: 1.5, color: _muted),
            ),
          ],
        ],
      ),
    );
  }
}
