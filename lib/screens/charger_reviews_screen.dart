import 'package:flutter/material.dart';

import 'package:voltshare_app/components/review_card.dart';
import 'package:voltshare_app/controllers/review_controller.dart';
import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/services/review_service.dart';

/// All reviews of one charger, newest first. Loads [_pageSize] at a time and
/// fetches the next page as the driver nears the bottom of the list.
class ChargerReviewsScreen extends StatefulWidget {
  const ChargerReviewsScreen({
    super.key,
    required this.chargerId,
    required this.chargerName,
    this.summary = ChargerReviewSummary.empty,
    this.controller,
  });

  final String chargerId;
  final String chargerName;

  /// Shown in the header; reloaded on pull-to-refresh.
  final ChargerReviewSummary summary;
  final ReviewController? controller;

  @override
  State<ChargerReviewsScreen> createState() => _ChargerReviewsScreenState();
}

class _ChargerReviewsScreenState extends State<ChargerReviewsScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _border = Color(0xFFC8EDE0);
  static const Color _star = Color(0xFFF59E0B);
  static const int _pageSize = 20;

  late final ReviewController _controller =
      widget.controller ?? ReviewController(ReviewSupabaseService());

  late ChargerReviewSummary _summary = widget.summary;
  final List<ChargerReview> _reviews = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = _reviews.isEmpty;
      _hasError = false;
    });
    try {
      final results = await Future.wait([
        _controller.fetchChargerReviewSummary(widget.chargerId),
        _controller.fetchChargerReviews(widget.chargerId, limit: _pageSize),
      ]);
      if (!mounted) return;
      final page = results[1] as List<ChargerReview>;
      setState(() {
        _summary = results[0] as ChargerReviewSummary;
        _reviews
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = _reviews.isEmpty;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _controller.fetchChargerReviews(
        widget.chargerId,
        limit: _pageSize,
        offset: _reviews.length,
      );
      if (!mounted) return;
      setState(() {
        _reviews.addAll(page);
        _hasMore = page.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: _buildHeader(),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.arrow_back, color: _navy, size: 22),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 16)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reviews',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              Text(
                widget.chargerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _loadMore();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (_summary.hasReviews) ...[
              _buildSummaryCard(),
              const Padding(padding: EdgeInsets.only(top: 16)),
            ],
            if (_hasError)
              _message(Icons.error_outline,
                  'Couldn\'t load reviews. Pull to try again.')
            else if (_reviews.isEmpty)
              _message(Icons.rate_review_outlined, 'No reviews yet.')
            else
              for (final review in _reviews) ...[
                ReviewCard(review: review),
                const Padding(padding: EdgeInsets.only(top: 12)),
              ],
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: _primary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: _star, size: 36),
          const Padding(padding: EdgeInsets.only(left: 8)),
          Text(
            _summary.averageLabel,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 6)),
          const Text(
            '/ 5',
            style: TextStyle(fontSize: 16, color: _muted),
          ),
          const Spacer(),
          Text(
            '${_summary.reviewCount} '
            'review${_summary.reviewCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 12)),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
