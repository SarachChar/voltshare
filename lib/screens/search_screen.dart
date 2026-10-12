import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/charger_detail_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// A power band used by the quick filters. Maps a human label to the half-open
/// [min, max) kW range sent to the `search_chargers` RPC.
enum PowerBand {
  any('All', null, null),
  low('< 11 kW', null, 11),
  mid('11-50 kW', 11, 50),
  high('> 50 kW', 50, null);

  const PowerBand(this.label, this.min, this.max);

  final String label;
  final double? min;
  final double? max;
}

/// Distance-sorted charger search with name search, quick filters
/// (charger type / connector / power) and offset pagination (20 at a time,
/// loading the next page as the user scrolls near the bottom).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.controller});

  /// Optional injected controller (useful for tests and for reusing the home
  /// screen's controller). Falls back to a default Supabase-backed controller.
  final ChargerController? controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);

  /// Fallback location (central Bangkok) used when the device location is
  /// unavailable, mirroring the home map's initial center.
  static const double _fallbackLat = 13.7460;
  static const double _fallbackLng = 100.5340;

  /// How many rows a single page requests. The next page loads when the user
  /// scrolls near the bottom.
  static const int _pageSize = 20;

  /// Allowed filter values. 'All' (index 0) means "no filter".
  static const List<String> _chargerTypes = ['All', 'AC', 'DC'];
  static const List<String> _connectorTypes = [
    'All',
    'Type 2',
    'CCS2',
    'CHAdeMO',
  ];

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// User location used for distance sorting; falls back to Bangkok center.
  double _userLat = _fallbackLat;
  double _userLng = _fallbackLng;

  // Active filters.
  String _query = '';
  String _chargerType = 'All';
  String _connectorType = 'All';
  PowerBand _powerBand = PowerBand.any;

  // Paged result state.
  final List<Charger> _chargers = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false; // first page / after a filter change
  bool _isLoadingMore = false; // appending the next page
  bool _hasError = false;

  /// Debounce timer for the search field so we don't query on every keystroke.
  Timer? _debounce;

  /// Guards against an out-of-order first load racing the location lookup.
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    // Kick off the first search immediately with the fallback location so the
    // list isn't blocked on the (possibly slow) permission prompt, then refine
    // once we know the real location.
    _runSearch(reset: true);
    await _resolveUserLocation();
  }

  /// Best-effort device location. Never prompts aggressively or throws — if
  /// permission is denied or location is off, we keep the Bangkok fallback.
  ///
  /// On a physical device the first GPS fix can be slow, so we bound
  /// [Geolocator.getCurrentPosition] with a timeout and fall back to the last
  /// known position if it fails. Whenever we obtain a real position we re-run
  /// the search unconditionally — the first search already ran against the
  /// Bangkok fallback, so comparing against it is not a reliable signal.
  Future<void> _resolveUserLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // First fix timed out or failed (common on a cold-started physical
        // device). Fall back to the last known fix if the OS has one cached.
        position = await Geolocator.getLastKnownPosition();
      }

      if (!mounted || position == null) return;

      _userLat = position.latitude;
      _userLng = position.longitude;

      // Re-run so distances/order reflect the real location, replacing the
      // results that were fetched against the Bangkok fallback.
      _runSearch(reset: true);
    } catch (_) {
      // Keep the fallback location silently.
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    final position = _scrollController.position;
    // Within ~400px of the bottom: fetch the next page.
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (value.trim() == _query) return;
      _query = value.trim();
      _runSearch(reset: true);
    });
  }

  /// Loads the first page for the current filters, replacing the list.
  Future<void> _runSearch({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
    }
    final token = ++_searchToken;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final results = await _fetchPage(offset: 0);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _chargers
          ..clear()
          ..addAll(results);
        _offset = results.length;
        _hasMore = results.length == _pageSize;
        _isLoading = false;
      });
      // Jump back to the top when filters change.
      if (reset && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  /// Appends the next page to the existing list.
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final token = _searchToken;

    setState(() => _isLoadingMore = true);

    try {
      final results = await _fetchPage(offset: _offset);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _chargers.addAll(results);
        _offset += results.length;
        _hasMore = results.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      // Stop trying to page further on error, but keep what we have.
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<List<Charger>> _fetchPage({required int offset}) {
    return _controller.searchChargers(
      userLat: _userLat,
      userLng: _userLng,
      query: _query.isEmpty ? null : _query,
      chargerType: _chargerType == 'All' ? null : _chargerType,
      connectorType: _connectorType == 'All' ? null : _connectorType,
      powerMin: _powerBand.min,
      powerMax: _powerBand.max,
      limit: _pageSize,
      offset: offset,
    );
  }

  /// Count of currently active (non-"All") filters, shown as a badge on the
  /// filter button.
  int get _activeFilterCount {
    var count = 0;
    if (_chargerType != 'All') count++;
    if (_connectorType != 'All') count++;
    if (_powerBand != PowerBand.any) count++;
    return count;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Find Chargers',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          Row(
            children: [
              Expanded(child: _buildSearchField()),
              const Padding(padding: EdgeInsets.only(left: 12)),
              _buildFilterButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Area, province, or name...',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: _muted),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: _muted, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _debounce?.cancel();
                    _query = '';
                    _runSearch(reset: true);
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterButton() {
    final count = _activeFilterCount;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openFilterSheet,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.tune, color: _primary),
              if (count > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _primary),
      );
    }

    if (_hasError) {
      return _buildMessage(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: 'Could not load chargers. Pull to retry.',
        showRetry: true,
      );
    }

    if (_chargers.isEmpty) {
      return _buildMessage(
        icon: Icons.search_off,
        title: 'No chargers found',
        subtitle: 'Try adjusting your search or filters.',
      );
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: () => _runSearch(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        // One extra slot for the count header (index 0) and, when paging,
        // one for the bottom loader.
        itemCount: _chargers.length + 1 + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) return _buildCountHeader();

          final chargerIndex = index - 1;
          if (chargerIndex >= _chargers.length) {
            // Bottom loader slot.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _primary,
                  ),
                ),
              ),
            );
          }

          return _buildChargerCard(_chargers[chargerIndex]);
        },
      ),
    );
  }

  Widget _buildCountHeader() {
    final count = _chargers.length;
    final suffix = _hasMore ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 16, color: _dark),
          children: [
            TextSpan(
              text: '$count$suffix ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: 'chargers found',
              style: TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargerCard(Charger charger) {
    final distance = charger.distanceLabel;
    final locationLine = [
      if (charger.address.isNotEmpty) charger.address,
      if (distance.isNotEmpty) distance,
    ].join(' · ');

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChargerDetailScreen(
              charger: charger,
              controller: _controller,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.bolt, color: _primary, size: 28),
            ),
            const Padding(padding: EdgeInsets.only(left: 14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    charger.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  if (locationLine.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.only(top: 4)),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: _muted,
                        ),
                        const Padding(padding: EdgeInsets.only(left: 2)),
                        Expanded(
                          child: Text(
                            locationLine,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Padding(padding: EdgeInsets.only(top: 8)),
                  _buildSpecLine(charger),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The "22 kW · Type 2 · ฿8/kWh" line, with the price in the primary colour.
  Widget _buildSpecLine(Charger charger) {
    final specs = <String>[
      charger.powerLabel,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
    ].join('   ·   ');

    return Row(
      children: [
        Flexible(
          child: Text(
            specs,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 10)),
        Text(
          '฿${charger.pricePerKwh.toStringAsFixed(0)}/kWh',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _primary,
          ),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    // Wrapped in a scrollable so RefreshIndicator (pull to retry) still works
    // when the list is empty.
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          color: _primary,
          onRefresh: () => _runSearch(reset: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 56, color: Colors.grey.shade400),
                      const Padding(padding: EdgeInsets.only(top: 16)),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _dark,
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 6)),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                      if (showRetry) ...[
                        const Padding(padding: EdgeInsets.only(top: 16)),
                        ElevatedButton(
                          onPressed: () => _runSearch(reset: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens the filter bottom sheet. Edits are kept local to the sheet until
  /// "Apply" is tapped, so cancelling leaves the current results untouched.
  Future<void> _openFilterSheet() async {
    var chargerType = _chargerType;
    var connectorType = _connectorType;
    var powerBand = _powerBand;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Widget section(String title, Widget child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 10)),
                  child,
                  const Padding(padding: EdgeInsets.only(top: 20)),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _dark,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              chargerType = 'All';
                              connectorType = 'All';
                              powerBand = PowerBand.any;
                            });
                          },
                          child: const Text(
                            'Reset',
                            style: TextStyle(
                              color: _primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.only(top: 12)),
                    section(
                      'CHARGER TYPE',
                      _buildChipRow(
                        options: _chargerTypes,
                        selected: chargerType,
                        onSelected: (value) =>
                            setSheetState(() => chargerType = value),
                      ),
                    ),
                    section(
                      'CONNECTOR',
                      _buildChipRow(
                        options: _connectorTypes,
                        selected: connectorType,
                        onSelected: (value) =>
                            setSheetState(() => connectorType = value),
                      ),
                    ),
                    section(
                      'POWER',
                      _buildChipRow(
                        options: PowerBand.values.map((b) => b.label).toList(),
                        selected: powerBand.label,
                        onSelected: (label) {
                          setSheetState(() {
                            powerBand = PowerBand.values
                                .firstWhere((b) => b.label == label);
                          });
                        },
                      ),
                    ),
                    Container(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true) {
      setState(() {
        _chargerType = chargerType;
        _connectorType = connectorType;
        _powerBand = powerBand;
      });
      _runSearch(reset: true);
    }
  }

  Widget _buildChipRow({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final isSelected = option == selected;
        return GestureDetector(
          onTap: () => onSelected(option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? _primary
                    : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              option,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : _dark,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
