import 'package:flutter/material.dart';
import 'package:voltshare_app/components/map_navigation.dart';
import 'package:voltshare_app/components/review_card.dart';
import 'package:voltshare_app/controllers/review_controller.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/review_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/photo_viewer_screen.dart';
import 'package:voltshare_app/screens/reserve_charger_screen.dart';
import 'package:voltshare_app/screens/reviews_screen.dart';
import 'package:voltshare_app/services/review_service.dart';
import 'package:voltshare_app/services/station_service.dart';

/// Full-screen station details: photo carousel, name/address/rating, then two
/// tabs. "Station info" lists the station's chargers (each with its own hours
/// and a Book button), the description and the latest reviews. "Business"
/// shows the businesses around the station and its promotions.
class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    super.key,
    required this.station,
    this.controller,
    this.reviewController,
    this.onBookCharger,
  });

  final Station station;

  /// Optional injected controllers (tests). Default to Supabase-backed ones.
  final StationController? controller;
  final ReviewController? reviewController;

  /// Called when the driver taps Book on a charger. Defaults to opening
  /// [ReserveChargerScreen]; tests override it to avoid Supabase.
  final void Function(BuildContext context, Charger charger)? onBookCharger;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const double _imageAreaHeight = 280;

  /// How many reviews the details screen previews.
  static const int _reviewPreviewCount = 3;

  late final StationController _controller =
      widget.controller ?? StationController(StationSupabaseService());

  late final ReviewController _reviewController =
      widget.reviewController ?? ReviewController(ReviewSupabaseService());

  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  final PageController _pageController = PageController();
  final PageController _businessPageController = PageController();

  /// Current carousel pages, kept in notifiers so swiping only rebuilds the
  /// page indicators.
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  final ValueNotifier<int> _businessPage = ValueNotifier<int>(0);

  List<StationImage> _images = const [];
  bool _isLoadingImages = true;

  List<Charger> _chargers = const [];
  bool _isLoadingChargers = true;
  bool _chargersFailed = false;

  /// Full Sunday..Saturday week per charger id.
  Map<String, List<ChargerAvailability>> _weeks = const {};

  /// Charger ids whose card shows the whole week instead of only today.
  final Set<String> _expandedHours = {};

  List<StationPromotion> _promotions = const [];
  bool _isLoadingPromotions = true;

  List<StationBusiness> _businesses = const [];
  bool _isLoadingBusinesses = true;

  List<StationBusinessImage> _businessImages = const [];
  bool _isLoadingBusinessImages = true;

  ChargerReviewSummary _reviewSummary = ChargerReviewSummary.empty;
  List<ChargerReview> _latestReviews = const [];
  bool _isLoadingReviews = true;

  String get _stationId => widget.station.id;

  @override
  void initState() {
    super.initState();
    // The page is one long scroll view, so the active tab's content is built
    // inline — rebuild when the selected tab changes.
    _tabController.addListener(_onTabChanged);
    _loadChargers();
    _loadImages();
    _loadPromotions();
    _loadBusinesses();
    _loadBusinessImages();
    _loadReviews();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadChargers() async {
    try {
      final chargers = await _controller.fetchStationChargers(_stationId);
      final weeks = await _controller.fetchChargersWeek(
        chargers.map((c) => c.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _chargers = chargers;
        _weeks = weeks;
        _isLoadingChargers = false;
        _chargersFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingChargers = false;
        _chargersFailed = true;
      });
    }
  }

  Future<void> _loadImages() async {
    try {
      final images = await _controller.fetchStationImages(_stationId);
      if (!mounted) return;
      setState(() {
        _images = images;
        _isLoadingImages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _loadPromotions() async {
    try {
      final promos = await _controller.fetchActivePromotions(_stationId);
      if (!mounted) return;
      setState(() {
        _promotions = promos;
        _isLoadingPromotions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingPromotions = false);
    }
  }

  Future<void> _loadBusinesses() async {
    try {
      final businesses = await _controller.fetchStationBusinesses(_stationId);
      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _isLoadingBusinesses = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBusinesses = false);
    }
  }

  Future<void> _loadBusinessImages() async {
    try {
      final images = await _controller.fetchStationBusinessImages(_stationId);
      if (!mounted) return;
      setState(() {
        _businessImages = images;
        _isLoadingBusinessImages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBusinessImages = false);
    }
  }

  Future<void> _loadReviews() async {
    try {
      final results = await Future.wait([
        _reviewController.fetchStationReviewSummary(_stationId),
        _reviewController.fetchStationReviews(
          _stationId,
          limit: _reviewPreviewCount,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _reviewSummary = results[0] as ChargerReviewSummary;
        _latestReviews = results[1] as List<ChargerReview>;
        _isLoadingReviews = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  void _openAllReviews() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewsScreen(
          subtitle: widget.station.name,
          summary: _reviewSummary,
          loadSummary: () =>
              _reviewController.fetchStationReviewSummary(_stationId),
          loadPage: ({required int limit, required int offset}) =>
              _reviewController.fetchStationReviews(
                _stationId,
                limit: limit,
                offset: offset,
              ),
        ),
      ),
    );
  }

  void _openPhotoViewer(List<String> urls, int initialIndex) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          imageUrls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _bookCharger(Charger charger) {
    final onBook = widget.onBookCharger;
    if (onBook != null) {
      onBook(context, charger);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReserveChargerScreen(charger: charger),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _businessPageController.dispose();
    _currentPage.dispose();
    _businessPage.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildImageHeader(),
              _buildTitleSection(),
              _buildTabBar(),
              _tabController.index == 0
                  ? _buildStationInfoTab()
                  : _buildBusinessTab(),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _circleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildDirectionsBar(),
    );
  }

  // ----- Header ---------------------------------------------------------------

  Widget _buildImageHeader() {
    return SizedBox(
      height: _imageAreaHeight,
      child: Stack(
        children: [
          Positioned.fill(child: _buildCarousel()),
          if (_images.length > 1)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _currentPage,
                  builder: (context, page, _) => Text(
                    '${page + 1}/${_images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          if (_images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentPage,
                builder: (context, page, _) => _dots(
                  count: _images.length,
                  page: page,
                  active: Colors.white,
                  inactive: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    if (_isLoadingImages) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(child: CircularProgressIndicator(color: _primary)),
      );
    }
    if (_images.isEmpty) return _buildImagePlaceholder();

    return PageView.builder(
      controller: _pageController,
      itemCount: _images.length,
      onPageChanged: (index) => _currentPage.value = index,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _openPhotoViewer(
            _images.map((image) => image.imageUrl).toList(),
            index,
          ),
          child: _networkImage(
            _images[index].imageUrl,
            placeholder: _buildImagePlaceholder(),
          ),
        );
      },
    );
  }

  Widget _networkImage(String url, {required Widget placeholder}) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(color: _primary),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(Icons.ev_station, size: 64, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _dots({
    required int count,
    required int page,
    required Color active,
    required Color inactive,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? active : inactive,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: _dark, size: 22),
        ),
      ),
    );
  }

  /// Station name, rating and address, above the tabs.
  Widget _buildTitleSection() {
    final station = widget.station;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  station.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
              ),
              if (_reviewSummary.hasReviews) ...[
                const Padding(padding: EdgeInsets.only(left: 12)),
                _buildRatingBadge(),
              ],
            ],
          ),
          if (station.address.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 6)),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const Padding(padding: EdgeInsets.only(left: 4)),
                Expanded(
                  child: Text(
                    station.address,
                    style:
                        TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// "★ 4.8 (24)" beside the station name.
  Widget _buildRatingBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Semantics(
        label: 'Rated ${_reviewSummary.averageLabel} out of 5 from '
            '${_reviewSummary.reviewCount} reviews',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFF59E0B), size: 22),
              const Padding(padding: EdgeInsets.only(left: 4)),
              Text(
                _reviewSummary.averageLabel,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 4)),
              Text(
                '(${_reviewSummary.reviewCount})',
                style: const TextStyle(fontSize: 15, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: _primary,
        unselectedLabelColor: _muted,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'Station info'),
          Tab(text: 'Business'),
        ],
      ),
    );
  }

  // ----- Station info tab -----------------------------------------------------

  Widget _buildStationInfoTab() {
    final description = widget.station.description;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isLoadingChargers && _chargers.isNotEmpty) ...[
            _buildStatChips(),
            const Padding(padding: EdgeInsets.only(top: 24)),
          ],
          _buildChargersSection(),
          if (description.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 24)),
            _buildSectionTitle('About'),
            const Padding(padding: EdgeInsets.only(top: 8)),
            Text(
              description,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          const Padding(padding: EdgeInsets.only(top: 24)),
          _buildReviewsSection(),
        ],
      ),
    );
  }

  /// Three quick stats computed from the loaded chargers: how many are
  /// available, the top power and the cheapest price (available ones only).
  Widget _buildStatChips() {
    final available = _chargers.where((c) => c.status == 'available').toList();
    final maxPower = available.isEmpty
        ? null
        : available.map((c) => c.powerKw).reduce((a, b) => a > b ? a : b);
    final minPrice = available.isEmpty
        ? null
        : available.map((c) => c.pricePerKwh).reduce((a, b) => a < b ? a : b);

    return Row(
      children: [
        _statChip(
          Icons.ev_station,
          'AVAILABLE',
          '${available.length}/${_chargers.length}',
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        _statChip(
          Icons.bolt,
          'MAX POWER',
          maxPower == null ? '-' : '${_trimNumber(maxPower)} kW',
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        _statChip(
          Icons.attach_money,
          'FROM',
          minPrice == null ? '-' : '฿${minPrice.toStringAsFixed(2)}',
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Icon(icon, color: _primary, size: 26),
            const Padding(padding: EdgeInsets.only(top: 8)),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 2)),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Chargers'),
        const Padding(padding: EdgeInsets.only(top: 2)),
        Text(
          'Pick a charger to book',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        if (_isLoadingChargers)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _primary)),
          )
        else if (_chargersFailed)
          _messageCard(
            'Could not load the chargers.',
            action: TextButton(
              onPressed: () {
                setState(() => _isLoadingChargers = true);
                _loadChargers();
              },
              child: const Text('Try again'),
            ),
          )
        else if (_chargers.isEmpty)
          _messageCard('No chargers at this station yet.')
        else
          for (int i = 0; i < _chargers.length; i++) ...[
            if (i > 0) const Padding(padding: EdgeInsets.only(top: 12)),
            _buildChargerCard(_chargers[i]),
          ],
      ],
    );
  }

  Widget _buildChargerCard(Charger charger) {
    final isAvailable = charger.status == 'available';
    final week = _weeks[charger.id] ??
        ChargerAvailability.fullWeek(charger.id, const []);
    final expanded = _expandedHours.contains(charger.id);
    final specs = [
      if (charger.chargerType.isNotEmpty) charger.chargerType,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      charger.powerLabel,
    ].join(' · ');

    return Opacity(
      opacity: isAvailable ? 1 : 0.55,
      child: Container(
        key: ValueKey('charger-card-${charger.id}'),
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? _primary.withValues(alpha: 0.12)
                        : const Color(0xFFF1F2F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bolt,
                    color: isAvailable ? _primary : const Color(0xFF9CA3AF),
                  ),
                ),
                const Padding(padding: EdgeInsets.only(left: 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        charger.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _dark,
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 2)),
                      Text(
                        specs,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '฿${charger.pricePerKwh.toStringAsFixed(2)}/kWh',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.only(top: 12)),
            _buildChargerHours(charger.id, week, expanded),
            const Padding(padding: EdgeInsets.only(top: 12)),
            if (isAvailable)
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  key: ValueKey('book-${charger.id}'),
                  onPressed: () => _bookCharger(charger),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23),
                    ),
                  ),
                  child: const Text(
                    'Book',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              )
            else
              Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F2F4),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: const Text(
                  'Unavailable',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Today's hours, plus the rest of the week when [expanded].
  Widget _buildChargerHours(
    String chargerId,
    List<ChargerAvailability> week,
    bool expanded,
  ) {
    final todayDow = DateTime.now().weekday % 7; // Mon=1..Sun=7 -> Sun=0
    final visible =
        expanded ? week : week.where((d) => d.dayOfWeek == todayDow).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0) _divider(),
            _hoursRow(visible[i], isToday: visible[i].dayOfWeek == todayDow),
          ],
          _divider(),
          InkWell(
            key: ValueKey('hours-toggle-$chargerId'),
            onTap: () => setState(() {
              if (!_expandedHours.remove(chargerId)) {
                _expandedHours.add(chargerId);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    expanded ? 'Show less' : 'See all hours',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(left: 4)),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: _primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hoursRow(ChargerAvailability slot, {required bool isToday}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            isToday ? 'Today' : slot.dayLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              color: isToday ? _primary : _dark,
            ),
          ),
          const Spacer(),
          Text(
            slot.timeRangeLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: slot.isClosed ? Colors.red.shade400 : _dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSectionTitle('Reviews')),
            if (_reviewSummary.reviewCount > 0)
              TextButton(
                onPressed: _openAllReviews,
                style: TextButton.styleFrom(
                  foregroundColor: _primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'All ${_reviewSummary.reviewCount}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 22),
                  ],
                ),
              ),
          ],
        ),
        const Padding(padding: EdgeInsets.only(top: 8)),
        if (_isLoadingReviews)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _primary)),
          )
        else if (_latestReviews.isEmpty)
          _messageCard('No reviews yet.')
        else
          for (final review in _latestReviews) ...[
            ReviewCard(review: review),
            const Padding(padding: EdgeInsets.only(top: 12)),
          ],
      ],
    );
  }

  // ----- Business tab ---------------------------------------------------------

  Widget _buildBusinessTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildBusinessSection(),
          const Padding(padding: EdgeInsets.only(top: 24)),
          ..._buildPromotions(),
        ],
      ),
    );
  }

  List<Widget> _buildBusinessSection() {
    if (_isLoadingBusinesses || _isLoadingBusinessImages) {
      return [
        Container(
          height: 180,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: _primary),
        ),
      ];
    }
    if (_businesses.isEmpty && _businessImages.isEmpty) return const [];

    return [
      if (_businessImages.isNotEmpty) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Swipe to explore this location',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
            Text(
              _businessImages.length == 1
                  ? '1 photo'
                  : '${_businessImages.length} photos',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
          ],
        ),
        const Padding(padding: EdgeInsets.only(top: 10)),
        _buildBusinessGallery(),
        const Padding(padding: EdgeInsets.only(top: 16)),
      ],
      _buildBusinessIntroBanner(),
      if (_businesses.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.only(top: 24)),
        _buildSectionTitle('Businesses here'),
        const Padding(padding: EdgeInsets.only(top: 2)),
        Text(
          'Added by the station host',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        for (int i = 0; i < _businesses.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.only(top: 12)),
          _buildBusinessCard(_businesses[i]),
        ],
      ],
    ];
  }

  Widget _buildBusinessGallery() {
    final storefront = Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.storefront_outlined,
          size: 48,
          color: Colors.grey.shade400,
        ),
      ),
    );
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 200,
            color: Colors.grey.shade200,
            child: PageView.builder(
              controller: _businessPageController,
              itemCount: _businessImages.length,
              onPageChanged: (index) => _businessPage.value = index,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _openPhotoViewer(
                    _businessImages.map((image) => image.imageUrl).toList(),
                    index,
                  ),
                  child: _networkImage(
                    _businessImages[index].imageUrl,
                    placeholder: storefront,
                  ),
                );
              },
            ),
          ),
        ),
        if (_businessImages.length > 1) ...[
          const Padding(padding: EdgeInsets.only(top: 10)),
          ValueListenableBuilder<int>(
            valueListenable: _businessPage,
            builder: (context, page, _) => _dots(
              count: _businessImages.length,
              page: page,
              active: _primary,
              inactive: Colors.grey.shade300,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBusinessIntroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_outlined, size: 20, color: _primary),
              Padding(padding: EdgeInsets.only(left: 8)),
              Expanded(
                child: Text(
                  'Charge, dine, and unwind',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Text(
            'Make the most of your time at the businesses available while '
            'your EV is charging.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard(StationBusiness business) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _businessIcon(business.businessType),
                  size: 22,
                  color: _primary,
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.businessName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (business.businessType.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.only(top: 2)),
                      Text(
                        business.businessType,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (business.description.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 12)),
            Text(
              business.description,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _businessIcon(String businessType) {
    final type = businessType.toLowerCase();
    if (type.contains('caf') || type.contains('coffee')) {
      return Icons.local_cafe_outlined;
    }
    if (type.contains('restaurant') ||
        type.contains('food') ||
        type.contains('dining')) {
      return Icons.restaurant_outlined;
    }
    if (type.contains('shop') ||
        type.contains('retail') ||
        type.contains('store') ||
        type.contains('mart') ||
        type.contains('convenience')) {
      return Icons.shopping_bag_outlined;
    }
    if (type.contains('gym') || type.contains('fitness')) {
      return Icons.fitness_center_outlined;
    }
    if (type.contains('hotel') || type.contains('stay')) {
      return Icons.hotel_outlined;
    }
    return Icons.storefront_outlined;
  }

  List<Widget> _buildPromotions() {
    final title = _buildSectionTitle('Host Promotions');
    if (_isLoadingPromotions) {
      return [
        title,
        const Padding(padding: EdgeInsets.only(top: 12)),
        Container(
          height: 140,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: _primary),
        ),
      ];
    }
    if (_promotions.isEmpty) {
      return [
        title,
        const Padding(padding: EdgeInsets.only(top: 12)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: _cardDecoration(),
          child: Column(
            children: [
              Icon(Icons.local_offer_outlined,
                  size: 32, color: Colors.grey.shade400),
              const Padding(padding: EdgeInsets.only(top: 10)),
              Text(
                'No promotions right now',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      title,
      const Padding(padding: EdgeInsets.only(top: 12)),
      for (int i = 0; i < _promotions.length; i++) ...[
        if (i > 0) const Padding(padding: EdgeInsets.only(top: 12)),
        _buildPromotionCard(_promotions[i]),
      ],
    ];
  }

  Widget _buildPromotionCard(StationPromotion promo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_offer_outlined,
                    size: 18, color: _primary),
              ),
              const Padding(padding: EdgeInsets.only(left: 10)),
              Expanded(
                child: Text(
                  promo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
              ),
            ],
          ),
          if (promo.description.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 10)),
            Text(
              promo.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const Padding(padding: EdgeInsets.only(top: 10)),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: Colors.grey.shade500),
              const Padding(padding: EdgeInsets.only(left: 4)),
              Expanded(
                child: Text(
                  promo.validRangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----- Shared bits ----------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _dark,
      ),
    );
  }

  Widget _messageCard(String text, {Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          ?action,
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
    );
  }

  Widget _divider() {
    return Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15));
  }

  static String _trimNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// Bottom bar: directions to the station. Booking lives on each charger.
  Widget _buildDirectionsBar() {
    final station = widget.station;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: 56,
        child: OutlinedButton.icon(
          onPressed: () => showNavigationOptions(
            context,
            latitude: station.latitude,
            longitude: station.longitude,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            backgroundColor: Colors.white,
            side: const BorderSide(color: _primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          icon: const Icon(Icons.directions),
          label: const Text(
            'Get directions',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
