import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/review_controller.dart';
import 'package:voltshare_app/models/reservation_model.dart';
import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/screens/review_submitted_screen.dart';
import 'package:voltshare_app/services/review_service.dart';

/// Review for a completed booking: 1-5 stars (Terrible → Excellent) and an
/// optional comment (max 500 chars).
///
/// Pass [review] to show an existing review read-only. Otherwise the screen
/// first checks whether one exists (e.g. reviewed from another entry point)
/// and switches to read-only if so.
class LeaveReviewScreen extends StatefulWidget {
  const LeaveReviewScreen({
    super.key,
    required this.reservation,
    this.review,
    this.controller,
  });

  final Reservation reservation;
  final Review? review;
  final ReviewController? controller;

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _field = Color(0xFFEEF1F5);
  static const Color _border = Color(0xFFC8EDE0);
  static const Color _star = Color(0xFFF59E0B);

  late final ReviewController _controller =
      widget.controller ?? ReviewController(ReviewSupabaseService());

  final TextEditingController _comment = TextEditingController();

  Review? _existing;
  int _rating = 0;
  bool _isChecking = false;
  bool _isSubmitting = false;

  bool get _readOnly => _existing != null;

  Reservation get _r => widget.reservation;

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
    _setExisting(widget.review);
    if (widget.review == null) _checkExisting();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _setExisting(Review? review) {
    _existing = review;
    if (review != null) {
      _rating = review.rating;
      _comment.text = review.comment;
    }
  }

  Future<void> _checkExisting() async {
    setState(() => _isChecking = true);
    try {
      final review = await _controller.fetchReviewByReservation(_r.id);
      if (!mounted) return;
      setState(() {
        _setExisting(review);
        _isChecking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _onSubmit() async {
    if (_rating == 0 || _isSubmitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await _controller.createReview(
        reservationId: _r.id,
        rating: _rating,
        comment: _comment.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ReviewSubmittedScreen()),
      );
    } on ReviewAlreadyExistsException {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage('You\'ve already reviewed this booking.');
      await _checkExisting();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage('Couldn\'t submit your review. Please try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Tapping anywhere outside the comment box closes the keyboard.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: _isChecking
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        // Dragging the form also closes the keyboard.
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          _buildHeader(),
                          const Padding(padding: EdgeInsets.only(top: 20)),
                          _buildChargerCard(),
                          const Padding(padding: EdgeInsets.only(top: 28)),
                          _buildRating(),
                          const Padding(padding: EdgeInsets.only(top: 28)),
                          _buildComment(),
                          if (_readOnly && _existing?.createdAt != null) ...[
                            const Padding(padding: EdgeInsets.only(top: 16)),
                            Text(
                              'Reviewed on ${_dateLabel(_existing!.createdAt!)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // In the body (not bottomNavigationBar) so it rises above the
                    // keyboard and stays tappable while typing.
                    if (!_readOnly) _buildSubmitBar(),
                  ],
                ),
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
        Text(
          _readOnly ? 'Your Review' : 'Leave a Review',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
      ],
    );
  }

  Widget _buildChargerCard() {
    final details = [
      _r.dateLabel,
      _r.durationLabel,
      _r.chargerSpecLabel,
    ].where((p) => p.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _r.chargerName.isNotEmpty ? _r.chargerName : 'Charger',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 4)),
                  Text(
                    details,
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRating() {
    return Column(
      children: [
        const Text(
          'How was your charging experience?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 16)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 1; i <= 5; i++)
              Semantics(
                button: !_readOnly,
                selected: i <= _rating,
                label: '$i star${i == 1 ? '' : 's'}, ${Review.labelFor(i)}',
                child: IconButton(
                  iconSize: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onPressed: _readOnly || _isSubmitting
                      ? null
                      : () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _star,
                  ),
                  disabledColor: _star,
                ),
              ),
          ],
        ),
        if (_rating > 0) ...[
          const Padding(padding: EdgeInsets.only(top: 8)),
          Text(
            Review.labelFor(_rating),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _star,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComment() {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your comment',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        if (_readOnly)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _field,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Text(
              _comment.text.isEmpty ? 'No comment' : _comment.text,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: _comment.text.isEmpty ? _muted : _navy,
              ),
            ),
          )
        else ...[
          TextField(
            controller: _comment,
            enabled: !_isSubmitting,
            minLines: 4,
            maxLines: 6,
            // Keyboard "Done" closes it (Enter no longer adds a new line).
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            maxLength: Review.maxCommentLength,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 16, color: _navy),
            decoration: InputDecoration(
              hintText:
                  'Tell others about the charger speed, accessibility, '
                  'host communication...',
              hintStyle: const TextStyle(color: _muted, height: 1.4),
              filled: true,
              fillColor: _field,
              contentPadding: const EdgeInsets.all(20),
              border: outline,
              enabledBorder: outline,
              focusedBorder: outline.copyWith(
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              // Counter is drawn below to match the design ("0/500").
              counterText: '',
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_comment.text.length}/${Review.maxCommentLength}',
              style: const TextStyle(fontSize: 14, color: _muted),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubmitBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 60,
        child: ElevatedButton(
          onPressed: _rating == 0 ? null : (_isSubmitting ? () {} : _onSubmit),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _field,
            disabledForegroundColor: _muted,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: _isSubmitting
              ? Container(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Submit Review',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _dateLabel(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
