import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/pin_location_picker_screen.dart';
import 'package:voltshare_app/services/station_service.dart';

/// Two-step "Add Station" flow (Info, Business) opened from the host
/// dashboard. Chargers are added to the station afterwards, one at a time.
///
/// Passing [initialStation] turns it into "Edit Station": both steps are
/// pre-filled, removed photos / businesses are deleted on save, new ones are
/// added, untouched ones are left alone. Pops with the saved [Station], or
/// null when the host backs out.
class AddStationScreen extends StatefulWidget {
  const AddStationScreen({super.key, this.controller, this.initialStation});

  final StationController? controller;
  final Station? initialStation;

  @override
  State<AddStationScreen> createState() => _AddStationScreenState();
}

enum _Step { info, business }

extension on _Step {
  String get label => this == _Step.info ? 'Info' : 'Business';
}

/// A photo in the form: either a new pick ([bytes]) or an already-uploaded
/// image ([existingId] + [existingUrl]) when editing.
class _PickedPhoto {
  _PickedPhoto({
    this.bytes,
    this.fileExtension = 'jpg',
    this.existingId,
    this.existingUrl,
  });

  final Uint8List? bytes;
  final String fileExtension;
  final String? existingId;
  final String? existingUrl;

  bool get isExisting => existingId != null;
}

/// A business in the form. [existingId] is set for saved rows (and for rows
/// inserted by an earlier save attempt while editing).
class _DraftBusiness {
  _DraftBusiness({
    required this.typeValue,
    required this.name,
    required this.description,
    this.existingId,
  });

  final String typeValue;
  final String name;
  final String description;
  String? existingId;

  bool get isExisting => existingId != null;
}

/// Business type: UI label + `station_businesses.business_type` value.
class _BusinessType {
  const _BusinessType(this.label, this.value);

  final String label;
  final String value;
}

class _AddStationScreenState extends State<AddStationScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _fieldBorder = Color(0xFFE5E7EB);
  static const Color _bg = Color(0xFFF3F4F6);

  static const List<_Step> _steps = _Step.values;

  static const List<_BusinessType> _businessTypes = [
    _BusinessType('Café', 'CAFE'),
    _BusinessType('Restaurant', 'RESTAURANT'),
    _BusinessType('Co-working', 'CO_WORKING'),
    _BusinessType('Retail', 'RETAIL'),
    _BusinessType('Convenience', 'CONVENIENCE'),
    _BusinessType('Salon', 'SALON'),
    _BusinessType('Gym', 'GYM'),
    _BusinessType('Other', 'OTHER'),
  ];

  /// Bangkok, the pin's starting point until the host picks a spot.
  static const LatLng _defaultCenter = LatLng(13.75630, 100.50180);

  late final StationController _controller =
      widget.controller ?? StationController(StationSupabaseService());

  bool get _isEditing => widget.initialStation != null;

  final ImagePicker _picker = ImagePicker();
  int _currentStep = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _businessNameController =
      TextEditingController();
  final TextEditingController _businessDescriptionController =
      TextEditingController();

  LatLng _pinLocation = _defaultCenter;
  bool _locationTouched = false;

  final List<_PickedPhoto> _photos = [];
  final List<_PickedPhoto> _businessPhotos = [];
  final List<_DraftBusiness> _draftBusinesses = [];

  /// Existing rows the host removed while editing; deleted on save.
  final List<String> _removedImageIds = [];
  final List<String> _removedBusinessImageIds = [];
  final List<String> _removedBusinessIds = [];

  bool _isAddingBusiness = false;
  String _newBusinessType = 'CAFE';

  bool _isLoadingExisting = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final station = widget.initialStation;
    if (station != null) {
      _nameController.text = station.name;
      _addressController.text = station.address;
      _descriptionController.text = station.description;
      if (station.latitude != 0.0 || station.longitude != 0.0) {
        _pinLocation = LatLng(station.latitude, station.longitude);
        _locationTouched = true;
      }
      _loadExistingDetails(station.id);
    }
  }

  Future<void> _loadExistingDetails(String stationId) async {
    setState(() => _isLoadingExisting = true);
    try {
      final results = await Future.wait([
        _controller.fetchStationImages(stationId),
        _controller.fetchStationBusinessImages(stationId),
        _controller.fetchStationBusinesses(stationId),
      ]);
      if (!mounted) return;
      final images = results[0] as List<StationImage>;
      final businessImages = results[1] as List<StationBusinessImage>;
      final businesses = results[2] as List<StationBusiness>;
      setState(() {
        _photos.addAll(images.map(
          (img) => _PickedPhoto(existingId: img.id, existingUrl: img.imageUrl),
        ));
        _businessPhotos.addAll(businessImages.map(
          (img) => _PickedPhoto(existingId: img.id, existingUrl: img.imageUrl),
        ));
        _draftBusinesses.addAll(businesses.map(
          (b) => _DraftBusiness(
            typeValue: b.businessType,
            name: b.businessName,
            description: b.description,
            existingId: b.id,
          ),
        ));
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load current station data: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _businessNameController.dispose();
    _businessDescriptionController.dispose();
    super.dispose();
  }

  // ----- Navigation -----------------------------------------------------------

  bool get _isLastStep => _currentStep == _steps.length - 1;

  String get _continueLabel {
    if (!_isLastStep) return 'Continue →';
    return _isEditing ? 'Save' : 'Create station';
  }

  Future<void> _onContinue() async {
    if (_isSubmitting) return;
    if (_isLastStep) {
      await _submit();
      return;
    }
    setState(() => _currentStep++);
  }

  void _onBack() {
    if (_isSubmitting) return;
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _currentStep--);
    }
  }

  Future<void> _openPinPicker() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => PinLocationPickerScreen(
          initialLocation: _pinLocation,
          centerOnCurrentLocation: !_locationTouched,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pinLocation = result;
      _locationTouched = true;
    });
  }

  // ----- Photos / businesses --------------------------------------------------

  Future<void> _pickPhotosInto(List<_PickedPhoto> target) async {
    try {
      // Downscale on pick so uploads stay small (see AddChargerScreen).
      final picked = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked.isEmpty) return;
      final loaded = <_PickedPhoto>[];
      for (final file in picked) {
        loaded.add(_PickedPhoto(
          bytes: await file.readAsBytes(),
          fileExtension: _extensionOf(file.name),
        ));
      }
      if (!mounted) return;
      setState(() => target.addAll(loaded));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick images: $error')),
      );
    }
  }

  void _removePhoto(List<_PickedPhoto> list, int index, List<String> removed) {
    setState(() {
      final photo = list.removeAt(index);
      if (photo.isExisting) removed.add(photo.existingId!);
    });
  }

  void _removeBusiness(_DraftBusiness business) {
    setState(() {
      _draftBusinesses.remove(business);
      if (business.isExisting) _removedBusinessIds.add(business.existingId!);
    });
  }

  void _commitNewBusiness() {
    final name = _businessNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a business name.')),
      );
      return;
    }
    setState(() {
      _draftBusinesses.add(_DraftBusiness(
        typeValue: _newBusinessType,
        name: name,
        description: _businessDescriptionController.text.trim(),
      ));
      _isAddingBusiness = false;
      _businessNameController.clear();
      _businessDescriptionController.clear();
    });
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _businessTypeLabel(String value) {
    for (final type in _businessTypes) {
      if (type.value == value) return type.label;
    }
    return value;
  }

  // ----- Submit ---------------------------------------------------------------

  Future<void> _submit() async {
    final hostId = Supabase.instance.client.auth.currentUser?.id;
    if (hostId == null || hostId.isEmpty) {
      _snack('You need to be signed in to do this.');
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty || !_locationTouched) {
      setState(() => _currentStep = _steps.indexOf(_Step.info));
      _snack(name.isEmpty
          ? 'Please enter a station name.'
          : 'Please set the station location on the map.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final saved = _isEditing
          ? await _runEdit(widget.initialStation!, name)
          : await _runCreate(hostId, name);
      if (!mounted) return;
      _snack(_isEditing ? 'Station updated.' : 'Station created.');
      Navigator.of(context).pop(saved);
    } catch (error, stackTrace) {
      debugPrint('${_isEditing ? 'updateStation' : 'createStation'} '
          'flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      _snack('Failed to ${_isEditing ? 'update' : 'create'} station: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<Station> _runCreate(String hostId, String name) async {
    final station = await _controller.createStation(
      hostId: hostId,
      name: name,
      description: _descriptionController.text.trim(),
      address: _addressController.text.trim(),
      latitude: _pinLocation.latitude,
      longitude: _pinLocation.longitude,
    );
    await _uploadNewPhotos(
      photos: _photos,
      folder: 'station/${station.id}',
      link: (path, order) => _controller.insertStationImage(
        stationId: station.id,
        imagePath: path,
        displayOrder: order,
      ),
    );
    // Every create attempt makes a new station, so insert all businesses and
    // don't record their ids (a retry would otherwise skip them).
    for (final business in _draftBusinesses) {
      await _controller.insertStationBusiness(
        stationId: station.id,
        businessType: business.typeValue,
        businessName: business.name,
        description: business.description,
      );
    }
    await _uploadNewPhotos(
      photos: _businessPhotos,
      folder: 'station_business/${station.id}',
      link: (path, order) => _controller.insertStationBusinessImage(
        stationId: station.id,
        imagePath: path,
        displayOrder: order,
      ),
    );
    return station;
  }

  Future<Station> _runEdit(Station original, String name) async {
    final id = original.id;
    final updated = await _controller.updateStation(
      stationId: id,
      name: name,
      description: _descriptionController.text.trim(),
      address: _addressController.text.trim(),
      latitude: _pinLocation.latitude,
      longitude: _pinLocation.longitude,
    );

    for (final imageId in List.of(_removedImageIds)) {
      await _controller.deleteStationImage(imageId);
      _removedImageIds.remove(imageId);
    }
    await _uploadNewPhotos(
      photos: _photos,
      folder: 'station/$id',
      link: (path, order) => _controller.insertStationImage(
        stationId: id,
        imagePath: path,
        displayOrder: order,
      ),
    );

    await _controller.softDeleteStationBusinesses(_removedBusinessIds);
    _removedBusinessIds.clear();
    for (final business in _draftBusinesses) {
      if (business.isExisting) continue;
      final saved = await _controller.insertStationBusiness(
        stationId: id,
        businessType: business.typeValue,
        businessName: business.name,
        description: business.description,
      );
      // Same station on a retry, so remember it to avoid a duplicate.
      business.existingId = saved.id;
    }

    for (final imageId in List.of(_removedBusinessImageIds)) {
      await _controller.deleteStationBusinessImage(imageId);
      _removedBusinessImageIds.remove(imageId);
    }
    await _uploadNewPhotos(
      photos: _businessPhotos,
      folder: 'station_business/$id',
      link: (path, order) => _controller.insertStationBusinessImage(
        stationId: id,
        imagePath: path,
        displayOrder: order,
      ),
    );

    // Keep the host-side counts from the original (they don't change here).
    return original.copyWith(
      name: updated.name,
      description: updated.description,
      address: updated.address,
      latitude: updated.latitude,
      longitude: updated.longitude,
    );
  }

  /// Uploads the new picks in [photos] (existing ones are skipped) and links
  /// each with [link]. File names are time-based so they never collide with
  /// files already in [folder]. After a successful link the entry is marked
  /// existing, so a retried save doesn't upload it twice.
  Future<void> _uploadNewPhotos({
    required List<_PickedPhoto> photos,
    required String folder,
    required Future<Object> Function(String path, int displayOrder) link,
  }) async {
    final baseIndex = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo.isExisting) continue;
      final path = await _controller.uploadStationImage(
        folder: folder,
        index: baseIndex + i,
        bytes: photo.bytes!,
        fileExtension: photo.fileExtension,
      );
      final row = await link(path, i);
      final rowId = row is StationImage
          ? row.id
          : (row is StationBusinessImage ? row.id : null);
      if (_isEditing && rowId != null) {
        photos[i] = _PickedPhoto(
          existingId: rowId,
          existingUrl: null,
          bytes: photo.bytes,
          fileExtension: photo.fileExtension,
        );
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ----- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _steps[_currentStep] == _Step.info
                          ? _buildInfoStep()
                          : _buildBusinessStep(),
                    ),
                    _buildContinueBar(),
                  ],
                ),
              ),
              if (_isSubmitting) _buildSubmittingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmittingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: 36, height: 36),
                child: CircularProgressIndicator(strokeWidth: 3, color: _primary),
              ),
              const Padding(padding: EdgeInsets.only(top: 16)),
              Text(
                _isEditing ? 'Saving your changes' : 'Creating your station',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _onBack,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back, color: _dark),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 16)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEditing ? 'Edit Station' : 'Add Station',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _dark,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 2)),
                  Text(
                    'Step ${_currentStep + 1} of ${_steps.length}',
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          Row(
            children: [
              for (int i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _currentStep ? _primary : _fieldBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i != _steps.length - 1)
                  const Padding(padding: EdgeInsets.only(left: 6)),
              ],
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 10)),
          Row(
            children: [
              for (int i = 0; i < _steps.length; i++)
                Expanded(
                  child: Text(
                    _steps[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: i == _currentStep ? _primary : _muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ----- Info step ------------------------------------------------------------

  Widget _buildInfoStep() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        _fieldLabel('PHOTOS'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildPhotoPicker(
          photos: _photos,
          removed: _removedImageIds,
          addLabel: 'Add photos of your station',
          icon: Icons.photo_camera_outlined,
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('STATION NAME', required: true),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          key: const ValueKey('station-name'),
          controller: _nameController,
          decoration: _inputDecoration('e.g. "Siam EV Hub"'),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('ADDRESS'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _addressController,
          decoration: _inputDecoration('Street address'),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('PIN LOCATION', required: true),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildPinLocationSection(),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('DESCRIPTION'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: _inputDecoration(
            'Describe access, parking, anything drivers should know…',
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 16)),
        Text(
          'You can add chargers to this station after it is created.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildPinLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openPinPicker,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              ),
              child: Column(
                children: [
                  Icon(
                    _locationTouched
                        ? Icons.edit_location_alt
                        : Icons.add_location_alt_outlined,
                    color: _primary,
                    size: 30,
                  ),
                  const Padding(padding: EdgeInsets.only(top: 8)),
                  Text(
                    _locationTouched
                        ? 'Tap to adjust the pin on the map'
                        : 'Tap to set the location on the map',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 10)),
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 18, color: _primary),
            const Padding(padding: EdgeInsets.only(left: 4)),
            Expanded(
              child: Text(
                _locationTouched
                    ? '${_pinLocation.latitude.toStringAsFixed(5)}, '
                        '${_pinLocation.longitude.toStringAsFixed(5)}'
                    : 'No location selected yet',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _dark,
                ),
              ),
            ),
            if (_locationTouched)
              const Text(
                'Location selected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// "Add photos" tile plus one removable row per photo.
  Widget _buildPhotoPicker({
    required List<_PickedPhoto> photos,
    required List<String> removed,
    required String addLabel,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _isSubmitting ? null : () => _pickPhotosInto(photos),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              ),
              child: Column(
                children: [
                  Icon(icon, color: _muted, size: 30),
                  const Padding(padding: EdgeInsets.only(top: 8)),
                  Text(
                    addLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (int i = 0; i < photos.length; i++) ...[
          const Padding(padding: EdgeInsets.only(top: 10)),
          _buildPhotoRow(photos, i, removed),
        ],
      ],
    );
  }

  Widget _buildPhotoRow(
    List<_PickedPhoto> photos,
    int index,
    List<String> removed,
  ) {
    final photo = photos[index];
    const double size = 56;
    final thumb = photo.bytes != null
        ? Image.memory(photo.bytes!, width: size, height: size, fit: BoxFit.cover)
        : Image.network(
            photo.existingUrl ?? '',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              width: size,
              height: size,
              color: _bg,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, color: _muted),
            ),
          );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: thumb),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Text(
              'Photo ${index + 1}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
          ),
          _removeButton(
            onTap: () => _removePhoto(photos, index, removed),
          ),
        ],
      ),
    );
  }

  Widget _removeButton({required VoidCallback onTap, double size = 40}) {
    return Material(
      color: const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isSubmitting ? null : onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: size, height: size),
          child: Icon(Icons.close, size: 20, color: Colors.red.shade400),
        ),
      ),
    );
  }

  // ----- Business step --------------------------------------------------------

  Widget _buildBusinessStep() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        _buildBusinessIntroCard(),
        const Padding(padding: EdgeInsets.only(top: 28)),
        _sectionHeader(
          'BUSINESS LOCATION PHOTO',
          subtitle: 'One shared gallery for this station',
          trailing: _businessPhotos.isEmpty
              ? null
              : '${_businessPhotos.length} selected',
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        _buildPhotoPicker(
          photos: _businessPhotos,
          removed: _removedBusinessImageIds,
          addLabel: 'Add a business location photo',
          icon: Icons.add_photo_alternate_outlined,
        ),
        const Padding(padding: EdgeInsets.only(top: 28)),
        Container(height: 1, color: _fieldBorder),
        const Padding(padding: EdgeInsets.only(top: 28)),
        _sectionHeader(
          'BUSINESS DETAILS',
          subtitle: 'Add each business drivers can visit',
          trailing: _draftBusinesses.isEmpty
              ? null
              : '${_draftBusinesses.length} added',
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        for (final business in _draftBusinesses) ...[
          _buildDraftBusinessCard(business),
          const Padding(padding: EdgeInsets.only(top: 12)),
        ],
        if (_isAddingBusiness)
          _buildNewBusinessForm()
        else
          _buildAddBusinessButton(),
        const Padding(padding: EdgeInsets.only(top: 16)),
        Text(
          'You can skip this step — business information is optional.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label, {String? subtitle, String? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(label),
              if (subtitle != null) ...[
                const Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBF3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              trailing,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBusinessIntroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storefront_outlined,
                color: _primary, size: 22),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add your business',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  'Tell drivers what they can enjoy at your station while '
                  'their car is charging.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftBusinessCard(_DraftBusiness business) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBF3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_outlined,
                color: _primary, size: 26),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 6)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _businessTypeLabel(business.typeValue),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 8)),
          _removeButton(onTap: () => _removeBusiness(business), size: 44),
        ],
      ),
    );
  }

  Widget _buildAddBusinessButton() {
    return Material(
      color: const Color(0xFFEAFBF3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isSubmitting
            ? null
            : () => setState(() {
                  _isAddingBusiness = true;
                  _newBusinessType = 'CAFE';
                  _businessNameController.clear();
                  _businessDescriptionController.clear();
                }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primary, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: _primary),
              const Padding(padding: EdgeInsets.only(left: 8)),
              Text(
                _draftBusinesses.isEmpty
                    ? 'Add Business'
                    : 'Add Another Business',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewBusinessForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('NEW BUSINESS'),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _fieldLabel('BUSINESS TYPE'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final type in _businessTypes) _buildBusinessTypeOption(type),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _fieldLabel('BUSINESS NAME', required: true),
          const Padding(padding: EdgeInsets.only(top: 8)),
          TextField(
            controller: _businessNameController,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('Business name (e.g. Café de Charge)'),
          ),
          const Padding(padding: EdgeInsets.only(top: 12)),
          TextField(
            controller: _businessDescriptionController,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration:
                _inputDecoration('Tell drivers what your business offers…'),
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isAddingBusiness = false;
                      _businessNameController.clear();
                      _businessDescriptionController.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _dark,
                    side: const BorderSide(color: _fieldBorder),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _commitNewBusiness();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Add Business',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessTypeOption(_BusinessType type) {
    final isSelected = type.value == _newBusinessType;
    return Material(
      color: isSelected ? const Color(0xFFEAFBF3) : _bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _newBusinessType = type.value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            type.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? _primary : _dark,
            ),
          ),
        ),
      ),
    );
  }

  // ----- Shared bits ----------------------------------------------------------

  /// Section label. [required] appends a red asterisk.
  Widget _fieldLabel(String label, {bool required = false}) {
    return Text.rich(
      TextSpan(
        text: label,
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
        ],
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _muted,
        letterSpacing: 0.6,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _fieldBorder),
      ),
    );
  }

  Widget _buildContinueBar() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(height: 56, width: double.infinity),
        child: ElevatedButton(
          onPressed: (_isSubmitting || _isLoadingExisting) ? null : _onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _primary.withValues(alpha: 0.6),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            _continueLabel,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
