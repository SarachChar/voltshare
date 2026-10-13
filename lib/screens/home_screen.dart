import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltshare_app/components/map_navigation.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/blank_screen.dart';
import 'package:voltshare_app/screens/charger_detail_screen.dart';
import 'package:voltshare_app/screens/profile_screen.dart';
import 'package:voltshare_app/screens/search_screen.dart';
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
  bool _initialCameraPositioned = false;
  int _navIndex = 0;

  /// Shared, resolved device location. Populated as soon as we obtain a fix
  /// (either from the early resolve kicked off in [initState] or from a manual
  /// recenter) and handed to [SearchScreen] so its first query can use the real
  /// location instead of querying twice (fallback, then refine).
  final ValueNotifier<LatLng?> _userLocation = ValueNotifier<LatLng?>(null);

  /// When set, the sheet shows this charger's details instead of the list.
  Charger? _selectedCharger;

  /// Measured height of the details panel, used to position the recenter
  /// button just above it.
  final GlobalKey _detailsKey = GlobalKey();
  double _detailsHeight = 0;

  /// Current sheet size as a fraction of screen height (0..1). Drives the
  /// position of the Google logo (via map padding) and the recenter button.
  double _sheetSize = _initialSheetSize;

  /// Last known camera position, tracked so the "reset orientation" button can
  /// restore the default bearing/tilt without moving the map's center or zoom.
  CameraPosition _cameraPosition = const CameraPosition(
    target: _initialCenter,
    zoom: 14,
  );

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
    // Resolve the device location exactly once at startup. This single fix
    // drives both the map's initial center and the Search tab's first query
    // (Search is built eagerly inside the IndexedStack), so we never request
    // GPS twice on launch. The on-demand recenter button fetches its own fresh
    // fix later, which is a separate, user-initiated action.
    _resolveUserLocation();
  }

  /// Resolves the startup device location once and publishes it to
  /// [_userLocation]. Stays silent (no snackbars) and uses a bounded timeout so
  /// Search never blocks for long. Also centers the map on the fix if the map
  /// is already created; otherwise [onMapCreated] centers from [_userLocation].
  Future<void> _resolveUserLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _centerMapOnStartupFallback();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _centerMapOnStartupFallback();
        return;
      }

      if (!_locationGranted && mounted) {
        setState(() => _locationGranted = true);
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
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _centerMapOnStartupFallback();
        return;
      }

      _userLocation.value = LatLng(position.latitude, position.longitude);
      // Center the map on this fix (handles the case where the map was created
      // before the fix resolved).
      _centerMapOnUserLocation();
    } catch (_) {
      // Keep _userLocation null; Search falls back to its default center.
      _centerMapOnStartupFallback();
    }
  }

  /// Centers the map on the resolved [_userLocation], if both the map and a fix
  /// are available. Safe to call before either exists — it no-ops until both
  /// are ready. Only acts for the initial positioning.
  void _centerMapOnUserLocation() {
    final location = _userLocation.value;
    if (_mapController == null || location == null) return;
    _initialCameraPositioned = true;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(location, 15),
    );
  }

  /// Startup fallback when no real location is available: focus the first
  /// charger (once loaded). Mirrors the old `_recenter(fallbackToFirstCharger:
  /// true)` behavior without requesting GPS again.
  void _centerMapOnStartupFallback() {
    if (_initialCameraPositioned) return;
    if (_chargers.isNotEmpty) {
      _initialCameraPositioned = true;
      _focusFirstCharger();
    }
    // If chargers aren't loaded yet, _loadChargers() will focus the first one.
  }

  void _onSheetMoved() {
    if (!mounted || !_sheetController.isAttached) return;
    setState(() {
      _sheetSize = _sheetController.size;
    });
  }

  Future<void> _loadChargers() async {
    setState(() => _isLoadingChargers = true);
    try {
      final chargers = await _controller.fetchNearbyChargers();
      if (!mounted) return;
      setState(() {
        _chargers = chargers;
      });
      // If the map hasn't been positioned yet (no location fix available),
      // focus the first charger now that the list is loaded. Keyed on
      // _initialCameraPositioned so it also covers the "permission granted but
      // GPS fix failed" case.
      if (!_initialCameraPositioned) {
        _initialCameraPositioned = true;
        _focusFirstCharger();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load chargers. Please try again.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingChargers = false);
    }
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

  Future<void> _recenter({bool fallbackToFirstCharger = false}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final position = await _determinePosition();
      if (!mounted) return;

      if (position != null) {
        _initialCameraPositioned = true;
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            15,
          ),
        );
      } else if (fallbackToFirstCharger && _chargers.isNotEmpty) {
        // Location unavailable: focus the first charger instead. If chargers
        // aren't loaded yet, _loadChargers() will focus once ready.
        _initialCameraPositioned = true;
        _focusFirstCharger();
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Resets the map orientation to the default (north-up, no tilt), keeping the
  /// current center and zoom. Used by the "re-center map" button.
  void _resetMapOrientation() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _cameraPosition.target,
          zoom: _cameraPosition.zoom,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }

  /// Centers the map on the first charger in the list, when available.
  void _focusFirstCharger() {
    if (_mapController == null || _chargers.isEmpty) return;
    final first = _chargers.first;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(first.latitude, first.longitude), 13),
    );
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
      final position = await Geolocator.getCurrentPosition();
      // Keep the shared location fresh so Search reflects the latest fix.
      _userLocation.value = LatLng(position.latitude, position.longitude);
      return position;
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
    _userLocation.dispose();
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
          SearchScreen(controller: _controller, userLocation: _userLocation),
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
          child: _buildMapControls(),
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

        // Draggable Nearby Chargers sheet.
        _buildNearbySheet(),
      ],
    );
  }

  /// Reloads the charger list. Sits at the top of the stacked map controls
  /// (above the compass button) and shows a spinner while a reload is in
  /// flight.
  Widget _buildRefreshButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isLoadingChargers ? null : _loadChargers,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isLoadingChargers
              ? Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _primary,
                  ),
                )
              : const Icon(Icons.refresh, color: _primary),
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
      onCameraMove: (position) => _cameraPosition = position,
      onMapCreated: (controller) {
        _mapController = controller;
        // Open at the startup location fix resolved once in initState (shared
        // with Search). If the fix hasn't resolved yet, _resolveUserLocation
        // will center the map when it arrives; if it never resolves,
        // _centerMapOnStartupFallback focuses the first charger instead.
        if (_userLocation.value != null) {
          _centerMapOnUserLocation();
        } else if (_initialCameraPositioned) {
          // Fix already failed before the map existed: fall back now.
          _focusFirstCharger();
        } else {
          _centerMapOnStartupFallback();
        }
      },
    );
  }

  Set<Marker> _buildMarkers() {
    return _chargers.map((charger) {
      return Marker(
        markerId: MarkerId(charger.id),
        position: LatLng(charger.latitude, charger.longitude),
        icon: BitmapDescriptor.defaultMarker,
        // InfoWindow disabled for now; tapping a marker raises the details
        // sheet via _selectCharger instead of showing the plain Google bubble.
        onTap: () => _selectCharger(charger),
      );
    }).toSet();
  }

  /// The stacked map controls: a "reset orientation" button on top of the
  /// "current location" button.
  Widget _buildMapControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRefreshButton(),
        const Padding(padding: EdgeInsets.only(top: 12)),
        _buildRecenterMapButton(),
        const Padding(padding: EdgeInsets.only(top: 12)),
        _buildRecenterButton(),
      ],
    );
  }

  /// Button that resets the map to the default orientation (north-up).
  Widget _buildRecenterMapButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _resetMapOrientation,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.explore, color: _primary),
        ),
      ),
    );
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

          // Action row: navigate (left) + more details (right).
          Row(
            children: [
              // Navigate button — opens an external map app for directions.
              NavigateButton(charger: charger),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Container(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChargerDetailScreen(
                            charger: charger,
                            controller: _controller,
                          ),
                        ),
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
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
                onPressed: () => setState(() => _navIndex = 1),
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
