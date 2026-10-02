import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Full-screen map for choosing a charger's location. A pin is fixed at the
/// center of the screen; the host pans the map beneath it and the coordinate
/// under the pin is what gets returned.
///
/// Pops with the selected [LatLng] when the host confirms, or null if they
/// back out. Runs the map full-screen (rather than embedded in a scroll view)
/// so panning gestures aren't swallowed by a surrounding ListView.
class PinLocationPickerScreen extends StatefulWidget {
  const PinLocationPickerScreen({
    super.key,
    required this.initialLocation,
    this.centerOnCurrentLocation = false,
  });

  /// Where the map starts centered — typically the last chosen pin.
  final LatLng initialLocation;

  /// When true, the picker jumps to the device's current location as soon as
  /// it opens (used the first time, before the host has chosen a spot).
  final bool centerOnCurrentLocation;

  @override
  State<PinLocationPickerScreen> createState() =>
      _PinLocationPickerScreenState();
}

class _PinLocationPickerScreenState extends State<PinLocationPickerScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);

  GoogleMapController? _mapController;

  /// The coordinate under the fixed center pin, updated as the host pans.
  late LatLng _pinLocation = widget.initialLocation;

  bool _locationGranted = false;

  /// Key on the bottom confirm bar, used to measure its real height so the
  /// recenter button can sit just above it regardless of screen insets.
  final GlobalKey _confirmBarKey = GlobalKey();

  /// Measured height of the confirm bar; null until the first frame is laid
  /// out. Drives the recenter button's bottom offset.
  double? _confirmBarHeight;

  /// Gap between the recenter button and the top of the confirm bar.
  static const double _recenterGap = 16;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureConfirmBar());
    if (widget.centerOnCurrentLocation) {
      _recenterOnCurrentLocation(silent: true);
    }
  }

  /// Reads the confirm bar's rendered height and stores it, so the recenter
  /// button can be positioned relative to it. Re-runs whenever the height
  /// changes (e.g. the coordinate text wraps or safe-area insets shift).
  void _measureConfirmBar() {
    final context = _confirmBarKey.currentContext;
    if (context == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if (height != _confirmBarHeight) {
      setState(() => _confirmBarHeight = height);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Resolves the device's current location, requesting permission if needed.
  /// Returns null (without an error) when unavailable.
  Future<Position?> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Moves the map to the device's current location. [silent] suppresses the
  /// error message when location is unavailable (used for the auto-center on
  /// open, where the host hasn't explicitly asked).
  Future<void> _recenterOnCurrentLocation({bool silent = false}) async {
    final position = await _determinePosition();
    if (position == null) {
      if (silent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
      return;
    }
    final target = LatLng(position.latitude, position.longitude);
    if (!mounted) return;
    setState(() {
      _pinLocation = target;
      _locationGranted = true;
    });
    // Recenter on the location and reset the map so north is up (bearing and
    // tilt default back to 0 with a plain CameraPosition).
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16),
      ),
    );
  }

  void _confirm() {
    Navigator.of(context).pop(_pinLocation);
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure after this frame in case the confirm bar's height changed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureConfirmBar());
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 16,
            ),
            myLocationEnabled: _locationGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onCameraMove: (position) => _pinLocation = position.target,
            onCameraIdle: () => setState(() {}),
            onMapCreated: (controller) => _mapController = controller,
          ),
          // Fixed center pin, nudged up so its tip marks the exact center.
          const Padding(
            padding: EdgeInsets.only(bottom: 44),
            child: Icon(Icons.location_on, size: 52, color: _primary),
          ),
          _buildTopBar(),
          _buildRecenterButton(),
          _buildConfirmBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildBackButton(),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Drag the map to move the pin',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _dark,
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

  Widget _buildBackButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).maybePop(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back, color: _dark),
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    // Sit just above the confirm bar using its measured height. Before the
    // first measurement, fall back to an estimate so it never overlaps.
    final bottom = (_confirmBarHeight ?? 160) + _recenterGap;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _recenterOnCurrentLocation,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.near_me, color: _primary),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        key: _confirmBarKey,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: _primary),
                  const Padding(padding: EdgeInsets.only(left: 4)),
                  Text(
                    '${_pinLocation.latitude.toStringAsFixed(5)}, '
                    '${_pinLocation.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                    ),
                  ),
                ],
              ),
              const Padding(padding: EdgeInsets.only(top: 12)),
              Container(
                height: 52,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Confirm location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
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
}
