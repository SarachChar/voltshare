import 'package:flutter/material.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/photo_viewer_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// Full-screen charger details view. For now it shows a swipeable image
/// carousel at the top, the charger's name, and a (non-functional) "Book This
/// Charger" button pinned to the bottom.
class ChargerDetailScreen extends StatefulWidget {
  const ChargerDetailScreen({
    super.key,
    required this.charger,
    this.controller,
  });

  final Charger charger;

  /// Optional injected controller (useful for tests). Falls back to a default
  /// Supabase-backed controller when not provided.
  final ChargerController? controller;

  @override
  State<ChargerDetailScreen> createState() => _ChargerDetailScreenState();
}

class _ChargerDetailScreenState extends State<ChargerDetailScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const double _imageAreaHeight = 280;

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  /// Drives the two content tabs: "Charger info" and "Business".
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  final PageController _pageController = PageController();

  List<ChargerImage> _images = List.empty();
  bool _isLoadingImages = true;

  /// Current carousel page. Kept in a notifier so swiping only rebuilds the
  /// page indicator instead of the whole screen.
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);

  List<ChargerAvailability> _availability = List.empty();
  bool _isLoadingAvailability = true;

  /// When false (default), only today's hours show; expanding reveals all days.
  bool _showAllHours = false;

  List<ChargerPromotion> _promotions = List.empty();
  bool _isLoadingPromotions = true;

  /// Businesses available while charging, plus their shared photo gallery.
  List<ChargerBusiness> _businesses = List.empty();
  bool _isLoadingBusinesses = true;

  List<BusinessImage> _businessImages = List.empty();
  bool _isLoadingBusinessImages = true;

  final PageController _businessPageController = PageController();

  /// Same idea as [_currentPage], for the business photo gallery.
  final ValueNotifier<int> _businessPage = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // The page is one long scroll view, so the active tab's content is built
    // inline — rebuild when the selected tab changes.
    _tabController.addListener(_onTabChanged);
    _loadImages();
    _loadAvailability();
    _loadPromotions();
    _loadBusinesses();
    _loadBusinessImages();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the full-screen viewer for [urls], starting at [initialIndex].
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

  Future<void> _loadBusinesses() async {
    try {
      final businesses =
          await _controller.fetchChargerBusinesses(widget.charger.id);
      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _isLoadingBusinesses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _businesses = List.empty();
        _isLoadingBusinesses = false;
      });
    }
  }

  Future<void> _loadBusinessImages() async {
    try {
      final images = await _controller.fetchBusinessImages(widget.charger.id);
      if (!mounted) return;
      setState(() {
        _businessImages = images;
        _isLoadingBusinessImages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _businessImages = List.empty();
        _isLoadingBusinessImages = false;
      });
    }
  }

  Future<void> _loadPromotions() async {
    try {
      final promos =
          await _controller.fetchActivePromotions(widget.charger.id);
      if (!mounted) return;
      setState(() {
        _promotions = promos;
        _isLoadingPromotions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promotions = List.empty();
        _isLoadingPromotions = false;
      });
    }
  }

  Future<void> _loadImages() async {
    try {
      final images = await _controller.fetchChargerImages(widget.charger.id);
      if (!mounted) return;
      setState(() {
        _images = images;
        _isLoadingImages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _loadAvailability() async {
    try {
      final rows =
          await _controller.fetchChargerAvailability(widget.charger.id);
      if (!mounted) return;
      setState(() {
        // Normalize into a full week so every day shows, with missing days
        // (and any explicitly unavailable ones) rendered as closed.
        _availability = ChargerAvailability.fullWeek(widget.charger.id, rows);
        _isLoadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // On error, still show a full closed week rather than nothing.
        _availability =
            ChargerAvailability.fullWeek(widget.charger.id, const []);
        _isLoadingAvailability = false;
      });
    }
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
          // One scroll view for the whole page, so the photo header and title
          // scroll away with the content instead of staying pinned.
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildImageHeader(),
              _buildTitleSection(),
              _buildTabBar(),
              _tabController.index == 0
                  ? _buildChargerInfoTab()
                  : _buildBusinessTab(),
            ],
          ),

          // Back button floats above the scroll content so it stays reachable
          // after the photo header scrolls away.
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
      bottomNavigationBar: _buildBookBar(),
    );
  }

  /// Charger name and address, pinned above the tabs.
  Widget _buildTitleSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.charger.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          if (widget.charger.address.isNotEmpty) ...[
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
                    widget.charger.address,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The two content tabs, sitting directly below the charger's address.
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
          Tab(text: 'Charger info'),
          Tab(text: 'Business'),
        ],
      ),
    );
  }

  /// Tab 1: specs, description, details and opening hours.
  Widget _buildChargerInfoTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatChips(),
          if (widget.charger.description.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 24)),
            _buildSectionTitle('About'),
            const Padding(padding: EdgeInsets.only(top: 8)),
            Text(
              widget.charger.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          const Padding(padding: EdgeInsets.only(top: 24)),
          _buildSectionTitle('Details'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _buildInfoCard(),
          const Padding(padding: EdgeInsets.only(top: 24)),
          _buildSectionTitle('Opening Hours'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _buildAvailabilitySection(),
        ],
      ),
    );
  }

  /// Tab 2: the businesses available while charging (photo gallery + list),
  /// followed by the host's promotions.
  Widget _buildBusinessTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildBusinessSection(),
          const Padding(padding: EdgeInsets.only(top: 24)),
          ..._buildBusinessPromotions(),
        ],
      ),
    );
  }

  /// The business area: a swipeable photo gallery of everything around the
  /// charger, a short intro, then one card per business.
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

    // Nothing to show at all — keep the tab focused on promotions instead.
    if (_businesses.isEmpty && _businessImages.isEmpty) {
      return const [];
    }

    return [
      if (_businessImages.isNotEmpty) ...[
        _buildBusinessGalleryHeader(),
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
          'Added by the charger host',
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

  Widget _buildBusinessGalleryHeader() {
    final count = _businessImages.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            'Swipe to explore this location',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ),
        Text(
          count == 1 ? '1 photo' : '$count photos',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _primary,
          ),
        ),
      ],
    );
  }

  /// Swipeable gallery of the charger's business photos.
  Widget _buildBusinessGallery() {
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
                  child: Image.network(
                    _businessImages[index].imageUrl,
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
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade200,
                      child: Center(
                        child: Icon(
                          Icons.storefront_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
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
            builder: (context, page, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_businessImages.length, (index) {
                final active = index == page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? _primary : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
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
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 20, color: _primary),
              const Padding(padding: EdgeInsets.only(left: 8)),
              const Expanded(
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

  Widget _buildBusinessCard(ChargerBusiness business) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
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

  /// Picks an icon that loosely matches the business type. Falls back to a
  /// generic storefront for anything unrecognised.
  static IconData _businessIcon(String businessType) {
    final type = businessType.toLowerCase();
    if (type.contains('caf') || type.contains('coffee')) {
      return Icons.local_cafe_outlined;
    }
    if (type.contains('restaurant') || type.contains('food') ||
        type.contains('dining')) {
      return Icons.restaurant_outlined;
    }
    if (type.contains('shop') || type.contains('retail') ||
        type.contains('store') || type.contains('mart')) {
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

  /// Top image area: a swipeable carousel with a back button, favorite button,
  /// and a page indicator.
  Widget _buildImageHeader() {
    return Container(
      height: _imageAreaHeight,
      child: Stack(
        children: [
          Positioned.fill(child: _buildCarousel()),

          // Page indicator "n/total". Listens to the page notifier so only
          // this label rebuilds while swiping.
          if (_images.length > 1)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          // Dots indicator.
          if (_images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentPage,
                builder: (context, page, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (index) {
                    final active = index == page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
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
        child: const Center(
          child: CircularProgressIndicator(color: _primary),
        ),
      );
    }

    if (_images.isEmpty) {
      return _buildImagePlaceholder();
    }

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
          child: Image.network(
            _images[index].imageUrl,
            fit: BoxFit.cover,
            // Keep the decoded frame on rebuild instead of flashing back to
            // the loading placeholder.
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
            errorBuilder: (context, error, stackTrace) =>
                _buildImagePlaceholder(),
          ),
        );
      },
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.ev_station,
          size: 64,
          color: Colors.grey.shade400,
        ),
      ),
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

  /// Three quick-stat chips: power, connector, and charger type.
  Widget _buildStatChips() {
    final charger = widget.charger;
    return Row(
      children: [
        _statChip(Icons.bolt, 'POWER', charger.powerLabel),
        const Padding(padding: EdgeInsets.only(left: 12)),
        _statChip(
          Icons.power,
          'CONNECTOR',
          charger.connectorType.isNotEmpty ? charger.connectorType : '-',
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        _statChip(
          Icons.ev_station,
          'TYPE',
          charger.chargerType.isNotEmpty ? charger.chargerType : '-',
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
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

  /// Card of detail rows: price and status.
  Widget _buildInfoCard() {
    final charger = widget.charger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _infoRow(
            Icons.attach_money,
            'Price',
            '฿${charger.pricePerKwh.toStringAsFixed(2)} / kWh',
          ),
          _divider(),
          _infoRow(
            Icons.info_outline,
            'Status',
            charger.status.isNotEmpty ? _capitalize(charger.status) : 'Unknown',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: _primary, size: 22),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Text(
            label,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15));
  }

  /// "Host Promotions" content for the Business tab: the active promotions
  /// fed by the `get-active-promotions` edge function, stacked vertically so
  /// they fill the tab. Shows a placeholder when the host has none.
  List<Widget> _buildBusinessPromotions() {
    if (_isLoadingPromotions) {
      return [
        _buildSectionTitle('Host Promotions'),
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
        _buildSectionTitle('Host Promotions'),
        const Padding(padding: EdgeInsets.only(top: 12)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.local_offer_outlined,
                size: 32,
                color: Colors.grey.shade400,
              ),
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
      _buildSectionTitle('Host Promotions'),
      const Padding(padding: EdgeInsets.only(top: 12)),
      for (int i = 0; i < _promotions.length; i++) ...[
        if (i > 0) const Padding(padding: EdgeInsets.only(top: 12)),
        // Fixed height keeps the card's internal Expanded description bounded.
        Container(
          height: 150,
          child: _buildPromotionCard(_promotions[i], width: double.infinity),
        ),
      ],
    ];
  }

  Widget _buildPromotionCard(ChargerPromotion promo, {double width = 260}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
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
                child: const Icon(
                  Icons.local_offer_outlined,
                  size: 18,
                  color: _primary,
                ),
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
            Expanded(
              child: Text(
                promo.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ] else
            const Spacer(),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Weekly opening hours from `charger_availability`, one row per day.
  Widget _buildAvailabilitySection() {
    if (_isLoadingAvailability) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Container(
          width: 24,
          height: 24,
          child: const CircularProgressIndicator(
              strokeWidth: 2.5, color: _primary),
        ),
      );
    }

    // _availability is always a full Sunday..Saturday week here (see
    // _loadAvailability), so today's row always exists.
    final todayDow = DateTime.now().weekday % 7; // Dart: Mon=1..Sun=7 -> Sun=0
    final todayIndex =
        _availability.indexWhere((slot) => slot.dayOfWeek == todayDow);

    // Collapsed: show only today's row. Expanded: show the whole week.
    final visible = _showAllHours
        ? _availability
        : [_availability[todayIndex]];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0) _divider(),
            _availabilityRow(
              visible[i],
              isToday: visible[i].dayOfWeek == todayDow,
            ),
          ],
          _divider(),
          _buildHoursToggle(),
        ],
      ),
    );
  }

  Widget _buildHoursToggle() {
    return InkWell(
      onTap: () => setState(() => _showAllHours = !_showAllHours),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _showAllHours ? 'Show less' : 'See all hours',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 4)),
            Icon(
              _showAllHours ? Icons.expand_less : Icons.expand_more,
              color: _primary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _availabilityRow(ChargerAvailability slot, {required bool isToday}) {
    final closed = slot.isClosed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(
            slot.dayLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              color: isToday ? _primary : _dark,
            ),
          ),
          if (isToday) ...[
            const Padding(padding: EdgeInsets.only(left: 8)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Today',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            slot.timeRangeLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: closed ? Colors.red.shade400 : _dark,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  /// Bottom bar with the "Book This Charger" button. Not wired up yet.
  Widget _buildBookBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 56,
        child: ElevatedButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Booking coming soon.')),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text(
            'Book This Charger',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
