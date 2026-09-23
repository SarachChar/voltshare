import 'package:flutter/material.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
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

class _ChargerDetailScreenState extends State<ChargerDetailScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const double _imageAreaHeight = 280;

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  final PageController _pageController = PageController();

  List<ChargerImage> _images = List.empty();
  bool _isLoadingImages = true;
  int _currentPage = 0;

  List<ChargerAvailability> _availability = List.empty();
  bool _isLoadingAvailability = true;

  /// When false (default), only today's hours show; expanding reveals all days.
  bool _showAllHours = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _loadAvailability();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _buildImageHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                  const Padding(padding: EdgeInsets.only(top: 20)),
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBookBar(),
    );
  }

  /// Top image area: a swipeable carousel with a back button, favorite button,
  /// and a page indicator.
  Widget _buildImageHeader() {
    return Container(
      height: _imageAreaHeight,
      child: Stack(
        children: [
          Positioned.fill(child: _buildCarousel()),

          // Back button.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _circleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),

          // Page indicator "n/total".
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
                child: Text(
                  '${_currentPage + 1}/${_images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_images.length, (index) {
                  final active = index == _currentPage;
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
      onPageChanged: (index) => setState(() => _currentPage = index),
      itemBuilder: (context, index) {
        return Image.network(
          _images[index].imageUrl,
          fit: BoxFit.cover,
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
