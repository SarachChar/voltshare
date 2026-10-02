import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/screens/pin_location_picker_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// Multi-step "Add Charger" flow shown when a host taps "Add New Charger" on
/// the dashboard. The flow is split into four steps: Info, Pricing, Business
/// and Hours (opening/closing times).
///
/// For now the first step (Info) captures the charger name and a set of photos.
/// Photos are only picked and previewed locally while the host fills in the
/// form; the actual upload to Supabase Storage happens when they tap
/// "Request to list my charger" on the final step. The remaining steps are
/// placeholders and the rest of the fields are not wired up yet.
class AddChargerScreen extends StatefulWidget {
  const AddChargerScreen({super.key, this.controller});

  /// Optional injected controller (useful for tests). Falls back to a default
  /// Supabase-backed controller when not provided.
  final ChargerController? controller;

  @override
  State<AddChargerScreen> createState() => _AddChargerScreenState();
}

/// The ordered steps of the Add Charger flow.
enum _AddChargerStep { info, pricing, business, hours }

extension _AddChargerStepLabel on _AddChargerStep {
  String get label {
    switch (this) {
      case _AddChargerStep.info:
        return 'Info';
      case _AddChargerStep.pricing:
        return 'Pricing';
      case _AddChargerStep.business:
        return 'Business';
      case _AddChargerStep.hours:
        return 'Hours';
    }
  }
}

/// A photo the host selected but hasn't uploaded yet. Holds the in-memory bytes
/// (used for both the preview and the eventual upload) plus the original file
/// extension so we can name the uploaded object correctly.
class _PickedPhoto {
  _PickedPhoto({required this.bytes, required this.fileExtension});

  final Uint8List bytes;
  final String fileExtension;
}

/// A business the host has added in the Business step but hasn't saved yet.
/// [typeValue] is the DB enum value (e.g. `CAFE`), not the display label.
class _DraftBusiness {
  _DraftBusiness({
    required this.typeValue,
    required this.name,
    required this.description,
  });

  final String typeValue;
  final String name;
  final String description;
}

/// A selectable business type: the label shown in the UI paired with the value
/// accepted by the `charger_businesses.business_type` check constraint.
class _BusinessType {
  const _BusinessType(this.label, this.value);

  final String label;
  final String value;
}

/// One day's opening hours in the Hours step. [dayOfWeek] follows the DB
/// convention (0 = Sunday .. 6 = Saturday). When [isOpen] is false the day is
/// saved as unavailable.
class _DayHours {
  _DayHours({required this.dayOfWeek, required this.label});

  final int dayOfWeek;
  final String label;
  bool isOpen = true;
  TimeOfDay start = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay end = const TimeOfDay(hour: 22, minute: 0);
}

class _AddChargerScreenState extends State<AddChargerScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _fieldBorder = Color(0xFFE5E7EB);

  /// Page background — the header and bottom bar share this so they blend into
  /// the screen instead of showing as separate white strips.
  static const Color _bg = Color(0xFFF3F4F6);

  static const List<_AddChargerStep> _steps = _AddChargerStep.values;

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  final ImagePicker _picker = ImagePicker();

  /// Index into [_steps] of the currently visible step.
  int _currentStep = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _powerController =
      TextEditingController(text: '22');
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController =
      TextEditingController(text: '8.00');

  /// Platform fee VoltShare deducts from each transaction, used to show the
  /// host's net payout estimate.
  static const double _platformFeeRate = 0.15;

  // ----- Business step --------------------------------------------------------

  /// Business types offered in the picker, mapped to their DB values.
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

  /// Businesses queued up to be saved with the charger.
  final List<_DraftBusiness> _draftBusinesses = [];

  /// Business location photos. These belong to the charger as a whole rather
  /// than to an individual business.
  final List<_PickedPhoto> _businessPhotos = [];

  /// Whether the inline "New business" form is open.
  bool _isAddingBusiness = false;

  /// Selected type in the inline form (DB value).
  String _newBusinessType = 'CAFE';

  final TextEditingController _businessNameController =
      TextEditingController();
  final TextEditingController _businessDescriptionController =
      TextEditingController();

  /// Default opening/closing times, used for closed days when saving.
  static const TimeOfDay _defaultStart = TimeOfDay(hour: 7, minute: 0);
  static const TimeOfDay _defaultEnd = TimeOfDay(hour: 22, minute: 0);

  /// Weekly opening hours, shown Monday-first to match the design but tagged
  /// with the DB's day_of_week (0 = Sunday .. 6 = Saturday).
  final List<_DayHours> _days = [
    _DayHours(dayOfWeek: 1, label: 'Mon'),
    _DayHours(dayOfWeek: 2, label: 'Tue'),
    _DayHours(dayOfWeek: 3, label: 'Wed'),
    _DayHours(dayOfWeek: 4, label: 'Thu'),
    _DayHours(dayOfWeek: 5, label: 'Fri'),
    _DayHours(dayOfWeek: 6, label: 'Sat'),
    _DayHours(dayOfWeek: 0, label: 'Sun'),
  ];

  /// Available charger types (AC/DC) and the one currently selected.
  static const List<String> _chargerTypes = ['AC', 'DC'];
  String _chargerType = 'AC';

  /// Available connector types and the one currently selected.
  static const List<String> _connectorTypes = [
    'Type 2',
    'CCS2',
    'CHAdeMO',
  ];
  String _connectorType = 'Type 2';

  /// Photos picked so far, in the order they should be displayed/uploaded.
  final List<_PickedPhoto> _photos = [];

  /// True while the finish action is uploading, so the button shows a spinner
  /// and can't be tapped twice.
  bool _isSubmitting = false;

  // ----- Pin location ---------------------------------------------------------

  /// Bangkok, used as the pin's starting point until the host picks a spot.
  static const LatLng _defaultCenter = LatLng(13.75630, 100.50180);

  /// The location chosen for the charger. Saved as latitude/longitude.
  LatLng _pinLocation = _defaultCenter;

  /// True once the host has confirmed a location in the picker, so we only
  /// show "Location selected" when it's meaningful.
  bool _locationTouched = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _powerController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _businessNameController.dispose();
    _businessDescriptionController.dispose();
    super.dispose();
  }

  /// Opens the full-screen map picker so the host can pan to their charger's
  /// spot. The map runs on its own screen so panning gestures aren't swallowed
  /// by this step's scroll view.
  Future<void> _openPinPicker() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => PinLocationPickerScreen(
          initialLocation: _pinLocation,
          // First time (no pin chosen yet): jump to the host's current
          // location. Afterwards, keep whatever they last picked.
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

  bool get _isLastStep => _currentStep == _steps.length - 1;

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

  // ----- Photos ---------------------------------------------------------------

  Future<void> _pickPhotos() => _pickPhotosInto(_photos);

  /// Opens the gallery and appends the chosen images to [target]. Shared by
  /// the charger photos (Info step) and business photos (Business step).
  Future<void> _pickPhotosInto(List<_PickedPhoto> target) async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;

      final loaded = <_PickedPhoto>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        loaded.add(
          _PickedPhoto(
            bytes: bytes,
            fileExtension: _extensionOf(file.name),
          ),
        );
      }

      if (!mounted) return;
      setState(() => target.addAll(loaded));
    } catch (error, stackTrace) {
      // Surface the real error to the debug console so picker failures on a
      // given device/emulator can be diagnosed instead of being swallowed.
      debugPrint('pickMultiImage failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick images: $error')),
      );
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  // ----- Submit ---------------------------------------------------------------

  /// Warns that the listing can't be edited once submitted. Returns true when
  /// the host confirms, null/false when they back out.
  Future<bool?> _confirmSubmission() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Submit this charger?',
          style: TextStyle(fontWeight: FontWeight.w800, color: _dark),
        ),
        content: const Text(
          "Once submitted, your charger details can't be edited. "
          'Please double-check the photos, location, pricing, hours and '
          'business info before continuing.',
          style: TextStyle(fontSize: 15, height: 1.5, color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: const Text(
              'Go back',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Submit',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final hostId = Supabase.instance.client.auth.currentUser?.id;
    if (hostId == null || hostId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to be signed in to do this.')),
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // Charger name lives on the Info step; bounce back there if it's empty.
      setState(() => _currentStep = _steps.indexOf(_AddChargerStep.info));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a charger name.')),
      );
      return;
    }

    // Open days must have a valid time range (end after start). Closed days
    // don't need valid times — they fall back to defaults when saved.
    final invalidDay = _days.firstWhere(
      (day) => day.isOpen && !_isValidRange(day.start, day.end),
      orElse: () => _DayHours(dayOfWeek: -1, label: ''),
    );
    if (invalidDay.dayOfWeek != -1) {
      setState(() => _currentStep = _steps.indexOf(_AddChargerStep.hours));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${invalidDay.label}: closing time must be after opening time.',
          ),
        ),
      );
      return;
    }

    // Everything validates — get an explicit confirmation before saving, since
    // the listing can't be edited afterwards.
    final confirmed = await _confirmSubmission();
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      // 1. Create the charger row. Fields that aren't captured yet get mock
      //    placeholder values for now — later steps will replace these.
      final charger = await _controller.createCharger(
        hostId: hostId,
        name: name,
        description: _descriptionController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _pinLocation.latitude,
        longitude: _pinLocation.longitude,
        chargerType: _chargerType,
        connectorType: _connectorType,
        powerKw: double.tryParse(_powerController.text.trim()) ?? 0.0,
        pricePerKwh: double.tryParse(_priceController.text.trim()) ?? 0.0,
        status: 'available',
      );

      // 2. Upload each photo into the charger's folder, then link it in
      //    charger_images at the matching display order. Files live under
      //    `charger/<charger_id>/<n>.<ext>` and are numbered from 1 to match
      //    the existing bucket layout.
      for (var i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final path = await _controller.uploadChargerImage(
          folder: 'charger/${charger.id}',
          index: i + 1,
          bytes: photo.bytes,
          fileExtension: photo.fileExtension,
        );
        await _controller.insertChargerImage(
          chargerId: charger.id,
          imagePath: path,
          displayOrder: i,
        );
      }

      // 3. Save the weekly opening hours (one row per day). Open days use the
      //    host's chosen times; closed days are stored with is_available=false
      //    and fall back to the default 07:00–22:00 range.
      await _controller.insertChargerAvailability(
        chargerId: charger.id,
        days: _days.map((day) {
          final start = day.isOpen ? day.start : _defaultStart;
          final end = day.isOpen ? day.end : _defaultEnd;
          return ChargerAvailability(
            id: '',
            chargerId: charger.id,
            dayOfWeek: day.dayOfWeek,
            startTime: _formatTimeForDb(start),
            endTime: _formatTimeForDb(end),
            isAvailable: day.isOpen,
          );
        }).toList(),
      );

      // 4. Save the businesses offered at this charger (optional step).
      for (final business in _draftBusinesses) {
        await _controller.insertChargerBusiness(
          chargerId: charger.id,
          businessType: business.typeValue,
          businessName: business.name,
          description: business.description,
        );
      }

      // 5. Upload the shared business location photos into
      //    `business/<charger_id>/` and link them in business_images.
      for (var i = 0; i < _businessPhotos.length; i++) {
        final photo = _businessPhotos[i];
        final path = await _controller.uploadChargerImage(
          folder: 'business/${charger.id}',
          index: i + 1,
          bytes: photo.bytes,
          fileExtension: photo.fileExtension,
        );
        await _controller.insertBusinessImage(
          chargerId: charger.id,
          imagePath: path,
          displayOrder: i,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Charger created.')),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      // Surface the real error so the failing step (charger insert, storage
      // upload, or charger_images insert) can be identified.
      debugPrint('createCharger flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create charger: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Block back navigation while the submission is in flight, so a half-saved
    // charger can't be left behind.
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildStepBody()),
                  _buildContinueBar(),
                ],
              ),
            ),
            if (_isSubmitting) _buildSubmittingOverlay(),
          ],
        ),
      ),
    );
  }

  /// Dim, tap-blocking overlay shown while the charger is being saved.
  Widget _buildSubmittingOverlay() {
    return Positioned.fill(
      // An opaque-to-hit-test container swallows every tap underneath it.
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
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: _primary,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 16)),
              const Text(
                'Submitting your charger',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 6)),
              const Text(
                'Uploading photos — please wait.',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- Header ---------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBackButton(),
              const Padding(padding: EdgeInsets.only(left: 16)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Charger',
                    style: TextStyle(
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
          _buildStepIndicator(),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Material(
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
    );
  }

  Widget _buildStepIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    );
  }

  // ----- Step body ------------------------------------------------------------

  Widget _buildStepBody() {
    switch (_steps[_currentStep]) {
      case _AddChargerStep.info:
        return _buildInfoStep();
      case _AddChargerStep.pricing:
        return _buildPricingStep();
      case _AddChargerStep.business:
        return _buildBusinessStep();
      case _AddChargerStep.hours:
        return _buildHoursStep();
    }
  }

  Widget _buildInfoStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFieldLabel('PHOTOS'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildPhotosSection(),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('CHARGER NAME'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _nameController,
          decoration: _inputDecoration('e.g. "Home Garage – Type 2"'),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('ADDRESS'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _addressController,
          decoration: _inputDecoration('Street address'),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('PIN LOCATION'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildPinLocationSection(),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('CHARGER TYPE'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildChoiceChips(
          options: _chargerTypes,
          selected: _chargerType,
          onSelected: (value) => setState(() => _chargerType = value),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('CONNECTOR TYPE'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildChoiceChips(
          options: _connectorTypes,
          selected: _connectorType,
          onSelected: (value) => setState(() => _connectorType = value),
          assetForOption: _connectorAsset,
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('POWER OUTPUT'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _powerController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration('22').copyWith(
            suffixText: 'kW',
            suffixStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('DESCRIPTION'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: _inputDecoration(
            'Describe location access, parking, anything drivers should know…',
          ),
        ),
      ],
    );
  }

  /// A horizontal set of single-select pills, used for charger type and
  /// connector type.
  Widget _buildChoiceChips({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    String? Function(String option)? assetForOption,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          _buildChoiceChip(
            label: option,
            isSelected: option == selected,
            onTap: () => onSelected(option),
            assetPath: assetForOption?.call(option),
          ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    String? assetPath,
  }) {
    final color = isSelected ? _primary : _dark;
    return Material(
      color: isSelected ? const Color(0xFFEAFBF3) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _primary : _fieldBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (assetPath != null) ...[
                SvgPicture.asset(
                  assetPath,
                  width: 28,
                  height: 28,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
                const Padding(padding: EdgeInsets.only(left: 8)),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a connector type to its SVG asset in assets/images.
  static String? _connectorAsset(String connector) {
    switch (connector) {
      case 'Type 2':
        return 'assets/images/type2.svg';
      case 'CCS2':
        return 'assets/images/css2.svg';
      case 'CHAdeMO':
        return 'assets/images/chademo.svg';
      default:
        return null;
    }
  }

  Widget _buildPinLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLocationCard(),
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

  /// Non-interactive card that opens the full-screen map picker on tap.
  Widget _buildLocationCard() {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openPinPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
          ),
          child: Column(
            children: [
              Icon(
                _locationTouched ? Icons.edit_location_alt : Icons.add_location_alt_outlined,
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
    );
  }

  Widget _buildPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAddPhotoTile(),
        if (_photos.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.only(top: 12)),
          for (int i = 0; i < _photos.length; i++) ...[
            _buildPhotoPreview(i),
            if (i != _photos.length - 1)
              const Padding(padding: EdgeInsets.only(top: 10)),
          ],
        ],
      ],
    );
  }

  Widget _buildAddPhotoTile() {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isSubmitting ? null : _pickPhotos,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFCBD5E1),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: const Column(
            children: [
              Icon(Icons.photo_camera_outlined, color: _muted, size: 30),
              Padding(padding: EdgeInsets.only(top: 8)),
              Text(
                'Add photos of your charger',
                style: TextStyle(
                  fontSize: 15,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(int index) {
    final photo = _photos[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              photo.bytes,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
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
          Material(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isSubmitting ? null : () => _removePhoto(index),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 20, color: Colors.red.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPricingInfoCard(),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _buildFieldLabel('PRICE PER KWH (฿)'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('8.00').copyWith(
            prefixText: '฿  ',
            prefixStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 16)),
        _buildPayoutCard(),
      ],
    );
  }

  /// Explains the platform fee above the price input.
  Widget _buildPricingInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: const TextSpan(
          style: TextStyle(fontSize: 15, color: _muted, height: 1.4),
          children: [
            TextSpan(
              text: 'Set your price per kWh. VoltShare deducts a ',
            ),
            TextSpan(
              text: '15% platform fee',
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: ' from each transaction. Your net payout is shown below.',
            ),
          ],
        ),
      ),
    );
  }

  /// Estimated hourly payout = power (kW) × price (฿/kWh) × (1 − fee).
  /// Power comes from the Info step; price from this step.
  Widget _buildPayoutCard() {
    final power = double.tryParse(_powerController.text.trim()) ?? 0.0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final payout = power * price * (1 - _platformFeeRate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Est. payout per hour',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  'Based on ${_trimNumber(power)} kW · after 15% fee',
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '฿${_formatMoney(payout)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 2)),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  '/hr',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Formats a payout amount: no decimals when whole, otherwise two.
  static String _formatMoney(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  /// Trims a trailing ".0" from whole numbers for display (e.g. 22 not 22.0).
  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  Widget _buildHoursStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFieldLabel('OPENING HOURS'),
        const Padding(padding: EdgeInsets.only(top: 12)),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _fieldBorder),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _days.length; i++) ...[
                _buildDayRow(_days[i]),
                if (i != _days.length - 1)
                  const Divider(height: 1, color: _fieldBorder),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayRow(_DayHours day) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                child: Text(
                  day.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 8)),
              Switch.adaptive(
                value: day.isOpen,
                activeThumbColor: Colors.white,
                activeTrackColor: _primary,
                onChanged: (value) => setState(() => day.isOpen = value),
              ),
            ],
          ),
          if (day.isOpen) ...[
            const Padding(padding: EdgeInsets.only(top: 10)),
            Row(
              children: [
                Expanded(child: _buildTimeField(day, isStart: true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '–',
                    style: TextStyle(fontSize: 18, color: _muted),
                  ),
                ),
                Expanded(child: _buildTimeField(day, isStart: false)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeField(_DayHours day, {required bool isStart}) {
    final time = isStart ? day.start : day.end;
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickTime(day, isStart: isStart),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.centerLeft,
          child: Text(
            _formatTime(time),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _dark,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime(_DayHours day, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? day.start : day.end,
      builder: (context, child) {
        // Force 24-hour layout so it matches the "07:00 – 22:00" display.
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        day.start = picked;
      } else {
        day.end = picked;
      }
    });
  }

  /// Formats a [TimeOfDay] as "HH:mm" (24-hour, zero-padded).
  static String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Formats a [TimeOfDay] as a Postgres `time` value "HH:mm:ss".
  static String _formatTimeForDb(TimeOfDay time) {
    return '${_formatTime(time)}:00';
  }

  /// Whether [end] is strictly after [start] (both as minutes-of-day).
  static bool _isValidRange(TimeOfDay start, TimeOfDay end) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return endMinutes > startMinutes;
  }

  Widget _buildBusinessStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBusinessIntroCard(),

        // --- Section 1: the shared photo gallery -------------------------
        const Padding(padding: EdgeInsets.only(top: 28)),
        _buildBusinessSectionHeader(
          'BUSINESS LOCATION PHOTO',
          subtitle: 'One shared gallery for this charger',
          trailing: _businessPhotos.isEmpty
              ? null
              : '${_businessPhotos.length} selected',
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        _buildBusinessPhotosSection(),

        // --- Section 2: the individual businesses ------------------------
        const Padding(padding: EdgeInsets.only(top: 28)),
        _buildBusinessSectionDivider(),
        const Padding(padding: EdgeInsets.only(top: 28)),
        _buildBusinessSectionHeader(
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

  /// Section heading for the Business step: an uppercase label with a short
  /// explanation underneath, plus an optional count on the right.
  Widget _buildBusinessSectionHeader(
    String label, {
    String? subtitle,
    String? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel(label),
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
        if (trailing != null) ...[
          const Padding(padding: EdgeInsets.only(left: 12)),
          Container(
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
      ],
    );
  }

  /// Thin rule that visually separates the two Business-step sections.
  Widget _buildBusinessSectionDivider() {
    return Container(height: 1, color: _fieldBorder);
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
            child: const Icon(
              Icons.storefront_outlined,
              color: _primary,
              size: 22,
            ),
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
                  'Tell drivers what they can enjoy at your location while '
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

  /// Photo picker + previews for the shared business location photos.
  Widget _buildBusinessPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _isSubmitting ? null : () => _pickPhotosInto(_businessPhotos),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      color: _primary, size: 30),
                  const Padding(padding: EdgeInsets.only(top: 8)),
                  const Text(
                    'Add a business location photo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _primary,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 4)),
                  Text(
                    'This photo represents all businesses at this charger',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_businessPhotos.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.only(top: 12)),
          for (int i = 0; i < _businessPhotos.length; i++) ...[
            _buildBusinessPhotoPreview(i),
            if (i != _businessPhotos.length - 1)
              const Padding(padding: EdgeInsets.only(top: 10)),
          ],
        ],
      ],
    );
  }

  Widget _buildBusinessPhotoPreview(int index) {
    final photo = _businessPhotos[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              photo.bytes,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
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
          Material(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isSubmitting
                  ? null
                  : () => setState(() => _businessPhotos.removeAt(index)),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 20, color: Colors.red.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A business already queued up, with a remove button.
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
            child: const Icon(
              Icons.storefront_outlined,
              color: _primary,
              size: 26,
            ),
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
                    color: const Color(0xFFF3F4F6),
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
          Material(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isSubmitting
                  ? null
                  : () => setState(() => _draftBusinesses.remove(business)),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 22, color: Colors.red.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBusinessButton() {
    final hasBusinesses = _draftBusinesses.isNotEmpty;
    return Material(
      color: const Color(0xFFEAFBF3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isSubmitting ? null : _openNewBusinessForm,
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
                hasBusinesses ? 'Add Another Business' : 'Add Business',
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

  /// Inline form for composing a new business entry.
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
          _buildFieldLabel('NEW BUSINESS'),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _buildFieldLabel('BUSINESS TYPE'),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _buildBusinessTypeGrid(),
          const Padding(padding: EdgeInsets.only(top: 14)),
          TextField(
            controller: _businessNameController,
            decoration: _inputDecoration('Business name (e.g. Café de Charge)'),
          ),
          const Padding(padding: EdgeInsets.only(top: 12)),
          TextField(
            controller: _businessDescriptionController,
            maxLines: 4,
            decoration:
                _inputDecoration('Tell drivers what your business offers…'),
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelNewBusinessForm,
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
                  onPressed: _commitNewBusiness,
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

  /// Two-column grid of business type options.
  Widget _buildBusinessTypeGrid() {
    return Column(
      children: [
        for (int i = 0; i < _businessTypes.length; i += 2) ...[
          if (i > 0) const Padding(padding: EdgeInsets.only(top: 10)),
          Row(
            children: [
              Expanded(child: _buildBusinessTypeOption(_businessTypes[i])),
              const Padding(padding: EdgeInsets.only(left: 10)),
              Expanded(
                child: i + 1 < _businessTypes.length
                    ? _buildBusinessTypeOption(_businessTypes[i + 1])
                    : const Padding(padding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBusinessTypeOption(_BusinessType type) {
    final isSelected = type.value == _newBusinessType;
    return Material(
      color: isSelected ? const Color(0xFFEAFBF3) : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _newBusinessType = type.value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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

  void _openNewBusinessForm() {
    setState(() {
      _isAddingBusiness = true;
      _newBusinessType = 'CAFE';
      _businessNameController.clear();
      _businessDescriptionController.clear();
    });
  }

  void _cancelNewBusinessForm() {
    setState(() {
      _isAddingBusiness = false;
      _businessNameController.clear();
      _businessDescriptionController.clear();
    });
  }

  /// Validates the inline form and queues the business for saving.
  void _commitNewBusiness() {
    final name = _businessNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a business name.')),
      );
      return;
    }

    setState(() {
      _draftBusinesses.add(
        _DraftBusiness(
          typeValue: _newBusinessType,
          name: name,
          description: _businessDescriptionController.text.trim(),
        ),
      );
      _isAddingBusiness = false;
      _businessNameController.clear();
      _businessDescriptionController.clear();
    });
  }

  /// Display label for a stored business type value.
  static String _businessTypeLabel(String value) {
    for (final type in _businessTypes) {
      if (type.value == value) return type.label;
    }
    return value;
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  // ----- Continue bar ---------------------------------------------------------

  Widget _buildContinueBar() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _onContinue,
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
          child: _isSubmitting
              ? Container(
                  height: 22,
                  width: 22,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  _isLastStep ? 'Request to list my charger' : 'Continue →',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}
