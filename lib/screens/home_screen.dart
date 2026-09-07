import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/blank_screen.dart';
import 'package:voltshare_app/screens/profile_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const LatLng _initialCenter = LatLng(13.7460, 100.5340);

  static const double _initialSheetSize = 0.30;

  final ChargerController _controller = ChargerController(
    ChargerSupabaseService(),
  );
  GoogleMapController? _mapController;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  List<Charger> _chargers = List.empty();
  bool _isLoadingChargers = false;
  bool _isLocating = false;
  bool _locationGranted = false;
  int _navIndex = 0;

  /// When set, the sheet shows this charger's details instead of the list.
  Charger? _selectedCharger;

  /// Measured height of the details panel, used to position the recenter
  /// button just above it.
  final GlobalKey _detailsKey = GlobalKey();
  double _detailsHeight = 0;

  /// Current sheet size as a fraction of screen height (0..1). Drives the
  /// position of the Google logo (via map padding) and the recenter button.
  double _sheetSize = _initialSheetSize;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetMoved);
    _controller.onSync.listen((bool syncState) {
      if (!mounted) return;
      setState(() {
        _isLoadingChargers = syncState;
      });
    });
    _loadChargers();
    // Request location and move to the user's position on first open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenter());
  }

  void _onSheetMoved() {
    if (!mounted || !_sheetController.isAttached) return;
    setState(() {
      _sheetSize = _sheetController.size;
    });
  }

  Future<void> _loadChargers() async {
    try {
      final chargers = await _controller.fetchNearbyChargers();
      if (!mounted) return;
      setState(() {
        _chargers = chargers;
      });
      _fitMapToChargers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load chargers. Please try again.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  void _fitMapToChargers() {
    if (_mapController == null || _chargers.isEmpty) return;
    // Center on the first charger for now.
    final first = _chargers.first;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(first.latitude, first.longitude), 13),
    );
  }

  /// Focuses the map on [charger] and shows its details in the sheet.
  /// Called from both a map marker tap and a list item tap.
  void _selectCharger(Charger charger) {
    setState(() => _selectedCharger = charger);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(charger.latitude, charger.longitude),
        16,
      ),
    );

    // Bring the sheet up to a comfortable height for the details.
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.45,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Returns from the details view back to the nearby list.
  void _clearSelection() {
    setState(() {
      _selectedCharger = null;
      _detailsHeight = 0;
      // Reset immediately so the recenter button snaps back above the sheet
      // instead of waiting for the sheet to move.
      _sheetSize = _initialSheetSize;
    });
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _initialSheetSize,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Reads the rendered height of the details panel and updates state so the
  /// recenter button can be positioned just above it.
  void _measureDetails() {
    if (!mounted) return;
    final box = _detailsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final height = box.size.height;
    if (height != _detailsHeight) {
      setState(() => _detailsHeight = height);
    }
  }

  Future<void> _recenter() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final position = await _determinePosition();
      if (!mounted || position == null) return;
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Requests location permission (if needed) and returns the current
  /// position, or null if unavailable. Shows a message on failure.
  Future<Position?> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationMessage('Location services are turned off.');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showLocationMessage('Location permission denied.');
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationMessage(
        'Location permission permanently denied. Enable it in Settings.',
      );
      return null;
    }

    // Permission granted: enable the blue "my location" dot on the map.
    if (!_locationGranted && mounted) {
      setState(() => _locationGranted = true);
    }

    try {
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      _showLocationMessage('Could not get your current location.');
      return null;
    }
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade600),
    );
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetMoved);
    _sheetController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildMapTab(),
          const BlankPage(title: 'Search'),
          const BlankPage(title: 'Bookings'),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMapTab() {
    return Stack(
      children: [
        // Full-screen map as the background layer.
        Positioned.fill(child: _buildMap()),

        // Recenter button. In details mode it sits just above the details
        // panel; in list mode it follows the sheet (capped at half screen).
        Positioned(
          right: 16,
          bottom: _selectedCharger != null
              ? _detailsHeight + 16
              : MediaQuery.of(context).size.height *
                        _sheetSize.clamp(0.0, 0.5) +
                    16,
          child: _buildRecenterButton(),
        ),

        if (_isLoadingChargers)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Container(
                width: 22,
                height: 22,
                child: const CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),

        // Floating search bar (with filter) at the top.
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(padding: EdgeInsets.only(top: 8)),
                _buildSearchBar(),
              ],
            ),
          ),
        ),

        // Draggable Nearby Chargers sheet.
        _buildNearbySheet(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey.shade500),
            const Padding(padding: EdgeInsets.only(left: 10)),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search chargers near you...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: InputBorder.none,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: Colors.grey.withValues(alpha: 0.25),
            ),
            const Padding(padding: EdgeInsets.only(left: 10)),
            Icon(Icons.tune, color: _primary),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: _initialCenter,
        zoom: 14,
      ),
      markers: _buildMarkers(),
      myLocationEnabled: _locationGranted,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      zoomGesturesEnabled: true,
      onMapCreated: (controller) {
        _mapController = controller;
        _fitMapToChargers();
      },
    );
  }

  Set<Marker> _buildMarkers() {
    return _chargers.map((charger) {
      return Marker(
        markerId: MarkerId(charger.id),
        position: LatLng(charger.latitude, charger.longitude),
        icon: BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(
          title: charger.name,
          snippet: '${charger.powerLabel} · ${charger.connectorType}',
        ),
        onTap: () => _selectCharger(charger),
      );
    }).toSet();
  }

  Widget _buildRecenterButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isLocating ? null : _recenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isLocating
              ? Container(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _primary,
                  ),
                )
              : const Icon(Icons.my_location, color: _primary),
        ),
      ),
    );
  }

  Widget _buildNearbySheet() {
    const sheetDecoration = BoxDecoration(
      color: Color(0xFFF3F4F6),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 12,
          offset: Offset(0, -2),
        ),
      ],
    );

    // Details mode: a bottom panel sized to its content (fixed height up to
    // the "More details" button), not draggable.
    if (_selectedCharger != null) {
      // Measure the panel's height after it lays out, so the recenter button
      // can sit right above it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureDetails());
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          key: _detailsKey,
          decoration: sheetDecoration,
          child: SafeArea(
            top: false,
            child: _buildDetailsView(_selectedCharger!),
          ),
        ),
      );
    }

    // List mode: draggable sheet.
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _initialSheetSize,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: sheetDecoration,
          child: _buildListView(scrollController),
        );
      },
    );
  }

  Widget _buildListView(ScrollController scrollController) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // Drag handle + header at the top of the sheet.
        SliverToBoxAdapter(child: _buildSheetHeader()),

        if (!_isLoadingChargers && _chargers.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No chargers found nearby.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                ),
              ),
            ),
          ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildChargerCard(_chargers[index]),
              childCount: _chargers.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsView(Charger charger) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Title row with a back-to-list button.
          Row(
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
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (charger.address.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.only(top: 4)),
                      Text(
                        charger.address,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                tooltip: 'Back to list',
              ),
            ],
          ),

          const Padding(padding: EdgeInsets.only(top: 16)),

          // Quick info rows.
          _buildInfoRow(
            Icons.attach_money,
            'Price',
            '฿${charger.pricePerKwh.toStringAsFixed(2)} / kWh',
          ),
          _buildInfoRow(Icons.access_time, 'Hours', 'Open 24 hrs'),
          _buildInfoRow(
            Icons.bolt,
            'Power',
            '${charger.powerLabel} · ${charger.connectorType}',
          ),
          _buildInfoRow(
            Icons.info_outline,
            'Status',
            charger.status.isNotEmpty ? charger.status : 'Unknown',
          ),

          const Padding(padding: EdgeInsets.only(top: 20)),

          // More details button (no real navigation yet).
          Container(
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Charger details coming soon.')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'More details',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _buildSheetHeader() {
    return Column(
      children: [
        // Drag handle.
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nearby Chargers',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'See all',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChargerCard(Charger charger) {
    return GestureDetector(
      onTap: () => _selectCharger(charger),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
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
                  const Padding(padding: EdgeInsets.only(top: 4)),
                  Text(
                    charger.subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (charger.rating != null) ...[
              const Padding(padding: EdgeInsets.only(left: 10)),
              Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFF59E0B), size: 20),
                  const Padding(padding: EdgeInsets.only(left: 4)),
                  Text(
                    charger.rating!.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: _primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? _primary : Colors.grey.shade600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? _primary : Colors.grey.shade600,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (index) => setState(() => _navIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Map',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
