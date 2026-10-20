import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
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
/// The same screen doubles as the "Edit Charger" flow: when an [initialCharger]
/// is passed in, every step is pre-filled with that charger's current data and
/// the final step's button becomes "Save", which updates the listing instead of
/// creating a new one. Photos are picked and previewed locally; uploads to
/// Supabase Storage (and, in edit mode, deletions of removed photos) happen when
/// the host confirms on the final step.
class AddChargerScreen extends StatefulWidget {
  const AddChargerScreen({super.key, this.controller, this.initialCharger});

  /// Optional injected controller (useful for tests). Falls back to a default
  /// Supabase-backed controller when not provided.
  final ChargerController? controller;

  /// When provided, the screen runs in "edit" mode: the same four-step flow is
  /// shown pre-filled with this charger's current data, and the final step
  /// saves the edits (via update) instead of creating a new charger.
  final Charger? initialCharger;

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

/// A photo shown in the Info/Business steps.
///
/// Two flavours:
///  - A *new* pick: holds in-memory [bytes] + [fileExtension], uploaded on save.
///  - An *existing* image (edit mode): holds the already-stored [existingId]
///    and public [existingUrl] so it can be previewed from the network and,
///    if the host removes it, deleted by id. Existing photos have no [bytes].
class _PickedPhoto {
  _PickedPhoto({
    this.bytes,
    this.fileExtension = 'jpg',
    this.existingId,
    this.existingUrl,
  });

  /// In-memory bytes for a freshly picked photo. Null for existing photos.
  final Uint8List? bytes;
  final String fileExtension;

  /// DB row id of an already-uploaded image (edit mode). Null for new picks.
  final String? existingId;

  /// Public URL of an already-uploaded image, used for the preview.
  final String? existingUrl;

  /// Whether this entry represents an already-uploaded image.
  bool get isExisting => existingId != null;
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

  /// True when the screen was opened to edit an existing charger. Drives the
  /// pre-filling, the header/button copy, and the save-vs-create branch.
  bool get _isEditing => widget.initialCharger != null;

  /// While editing, the related data (images/businesses/hours) is loaded
  /// asynchronously. This gates the Save button until it's ready so edits
  /// aren't saved against a half-loaded form.
  bool _isLoadingExisting = false;

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
  /// In edit mode this is pre-filled with the charger's existing images.
  final List<_PickedPhoto> _photos = [];

  /// DB ids of existing charger/business images the host removed while editing.
  /// These rows are deleted on save. New picks never appear here.
  final List<String> _removedChargerImageIds = [];
  final List<String> _removedBusinessImageIds = [];

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
  void initState() {
    super.initState();
    if (_isEditing) {
      _prefillFromCharger(widget.initialCharger!);
      _loadExistingDetails(widget.initialCharger!);
    }
  }

  /// Seeds the simple scalar fields from the charger being edited. The related
  /// data (photos, businesses, hours) is loaded separately in
  /// [_loadExistingDetails] since it lives in other tables.
  void _prefillFromCharger(Charger charger) {
    _nameController.text = charger.name;
    _addressController.text = charger.address;
    _descriptionController.text = charger.description;
    _powerController.text = _trimNumber(charger.powerKw);
    _priceController.text = charger.pricePerKwh.toStringAsFixed(2);

    if (_chargerTypes.contains(charger.chargerType)) {
      _chargerType = charger.chargerType;
    }
    if (_connectorTypes.contains(charger.connectorType)) {
      _connectorType = charger.connectorType;
    }

    // Treat a stored location as a real pin only when it isn't the (0,0)
    // placeholder, so the Info step shows "Location selected".
    if (charger.latitude != 0.0 || charger.longitude != 0.0) {
      _pinLocation = LatLng(charger.latitude, charger.longitude);
      _locationTouched = true;
    }
  }

  /// Loads the charger's images, businesses and weekly hours so each step
  /// shows the current values. Runs once when editing.
  Future<void> _loadExistingDetails(Charger charger) async {
    setState(() => _isLoadingExisting = true);
    try {
      final results = await Future.wait([
        _controller.fetchChargerImages(charger.id),
        _controller.fetchBusinessImages(charger.id),
        _controller.fetchChargerBusinesses(charger.id),
        _controller.fetchChargerAvailability(charger.id),
      ]);

      if (!mounted) return;

      final images = results[0] as List<ChargerImage>;
      final businessImages = results[1] as List<BusinessImage>;
      final businesses = results[2] as List<ChargerBusiness>;
      final availability = results[3] as List<ChargerAvailability>;

      setState(() {
        _photos
          ..clear()
          ..addAll(images.map(
            (img) => _PickedPhoto(existingId: img.id, existingUrl: img.imageUrl),
          ));

        _businessPhotos
          ..clear()
          ..addAll(businessImages.map(
            (img) => _PickedPhoto(existingId: img.id, existingUrl: img.imageUrl),
          ));

        _draftBusinesses
          ..clear()
          ..addAll(businesses.map(
            (b) => _DraftBusiness(
              typeValue: b.businessType,
              name: b.businessName,
              description: b.description,
            ),
          ));

        _applyAvailability(availability);
      });
    } catch (error, stackTrace) {
      debugPrint('loadExistingDetails failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load current charger data: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  /// Maps the loaded availability rows onto the Hours-step [_days]. Days with
  /// no row (or an explicitly unavailable row) are shown as closed; open days
  /// pick up their stored start/end times.
  void _applyAvailability(List<ChargerAvailability> rows) {
    final byDay = <int, ChargerAvailability>{};
    for (final row in rows) {
      byDay.putIfAbsent(row.dayOfWeek, () => row);
    }
    for (final day in _days) {
      final row = byDay[day.dayOfWeek];
      if (row == null || row.isClosed) {
        day.isOpen = false;
        continue;
      }
      day.isOpen = true;
      final start = _parseDbTime(row.startTime);
      final end = _parseDbTime(row.endTime);
      if (start != null) day.start = start;
      if (end != null) day.end = end;
    }
  }

  /// Parses a Postgres `time` value ("HH:mm" or "HH:mm:ss") into a [TimeOfDay].
  /// Returns null when it can't be parsed, so the default time is kept.
  static TimeOfDay? _parseDbTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

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

  /// Label for the bottom bar's primary button. On the last step this is
  /// "Save" when editing and "Request to list my charger" when creating.
  String get _continueButtonLabel {
    if (!_isLastStep) return 'Continue →';
    return _isEditing ? 'Save' : 'Request to list my charger';
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
        // _PickedPhoto with bytes = a new pick (not an existing image).
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
    setState(() {
      final removed = _photos.removeAt(index);
      if (removed.isExisting) {
        _removedChargerImageIds.add(removed.existingId!);
      }
    });
  }

  void _removeBusinessPhoto(int index) {
    setState(() {
      final removed = _businessPhotos.removeAt(index);
      if (removed.isExisting) {
        _removedBusinessImageIds.add(removed.existingId!);
      }
    });
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
        title: Text(
          _isEditing ? 'Save changes?' : 'Submit this charger?',
          style: const TextStyle(fontWeight: FontWeight.w800, color: _dark),
        ),
        content: Text(
          _isEditing
              ? 'This will update your charger listing with the changes '
                  "you've made. Please double-check the photos, location, "
                  'pricing, hours and business info before saving.'
              : "Once submitted, your charger details can't be edited. "
                  'Please double-check the photos, location, pricing, hours '
                  'and business info before continuing.',
          style: const TextStyle(fontSize: 15, height: 1.5, color: _muted),
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
            child: Text(
              _isEditing ? 'Save' : 'Submit',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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

    // Everything validates — get an explicit confirmation before saving.
    final confirmed = await _confirmSubmission();
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      if (_isEditing) {
        await _runEdit(widget.initialCharger!.id, name);
      } else {
        await _runCreate(hostId, name);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Charger updated.' : 'Charger created.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      // Surface the real error so the failing step (charger insert/update,
      // storage upload, or child-table write) can be identified.
      debugPrint('${_isEditing ? 'updateCharger' : 'createCharger'} '
          'flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to ${_isEditing ? 'update' : 'create'} charger: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Builds the weekly availability rows from the Hours step for [chargerId].
  /// Closed days are stored unavailable with the default 07:00–22:00 range.
  List<ChargerAvailability> _availabilityRows(String chargerId) {
    return _days.map((day) {
      final start = day.isOpen ? day.start : _defaultStart;
      final end = day.isOpen ? day.end : _defaultEnd;
      return ChargerAvailability(
        id: '',
        chargerId: chargerId,
        dayOfWeek: day.dayOfWeek,
        startTime: _formatTimeForDb(start),
        endTime: _formatTimeForDb(end),
        isAvailable: day.isOpen,
      );
    }).toList();
  }

  /// The full create flow: insert the charger, then its images, hours,
  /// businesses and business photos.
  Future<void> _runCreate(String hostId, String name) async {
    // 1. Create the charger row.
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
      status: 'review',
    );

    // 2. Upload each photo into the charger's folder, then link it in
    //    charger_images. Uses the same time-based file naming as edits.
    await _uploadNewPhotos(
      photos: _photos,
      folder: 'charger/${charger.id}',
      link: (path, order) => _controller.insertChargerImage(
        chargerId: charger.id,
        imagePath: path,
        displayOrder: order,
      ),
    );

    // 3. Save the weekly opening hours.
    await _controller.insertChargerAvailability(
      chargerId: charger.id,
      days: _availabilityRows(charger.id),
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

    // 5. Upload the shared business location photos.
    await _uploadNewPhotos(
      photos: _businessPhotos,
      folder: 'business/${charger.id}',
      link: (path, order) => _controller.insertBusinessImage(
        chargerId: charger.id,
        imagePath: path,
        displayOrder: order,
      ),
    );
  }

  /// The full edit flow for [chargerId]: update the charger row, reconcile its
  /// photos (delete removed, upload new, keep untouched), and replace its
  /// hours and businesses with the edited sets.
  Future<void> _runEdit(String chargerId, String name) async {
    // 1. Update the scalar charger fields.
    await _controller.updateCharger(
      chargerId: chargerId,
      name: name,
      description: _descriptionController.text.trim(),
      address: _addressController.text.trim(),
      latitude: _pinLocation.latitude,
      longitude: _pinLocation.longitude,
      chargerType: _chargerType,
      connectorType: _connectorType,
      powerKw: double.tryParse(_powerController.text.trim()) ?? 0.0,
      pricePerKwh: double.tryParse(_priceController.text.trim()) ?? 0.0,
    );

    // 2. Charger photos: remove the ones the host deleted, then upload any
    //    newly added ones. Untouched existing photos are left as-is. New files
    //    use a timestamp-based index so they never collide with existing
    //    objects already stored under `charger/<id>/<n>.<ext>`.
    for (final imageId in _removedChargerImageIds) {
      await _controller.deleteChargerImage(imageId);
    }
    await _uploadNewPhotos(
      photos: _photos,
      folder: 'charger/$chargerId',
      link: (path, order) => _controller.insertChargerImage(
        chargerId: chargerId,
        imagePath: path,
        displayOrder: order,
      ),
    );

    // 3. Replace the weekly opening hours with the edited week.
    await _controller.replaceChargerAvailability(
      chargerId: chargerId,
      days: _availabilityRows(chargerId),
    );

    // 4. Replace the businesses with the edited set.
    await _controller.replaceChargerBusinesses(
      chargerId: chargerId,
      businesses: _draftBusinesses
          .map(
            (b) => ChargerBusiness(
              id: '',
              chargerId: chargerId,
              businessType: b.typeValue,
              businessName: b.name,
              description: b.description,
            ),
          )
          .toList(),
    );

    // 5. Business photos: same reconcile as the charger photos.
    for (final imageId in _removedBusinessImageIds) {
      await _controller.deleteBusinessImage(imageId);
    }
    await _uploadNewPhotos(
      photos: _businessPhotos,
      folder: 'business/$chargerId',
      link: (path, order) => _controller.insertBusinessImage(
        chargerId: chargerId,
        imagePath: path,
        displayOrder: order,
      ),
    );
  }

  /// Uploads the newly-picked photos in [photos] (existing ones are skipped),
  /// linking each via [link]. Used by both the create and edit flows, so file
  /// names are always time-based ([DateTime.now] millis + list offset) to avoid
  /// colliding with any files already in [folder]. [displayOrder] passed to
  /// [link] is the photo's position in the list, preserving order.
  Future<void> _uploadNewPhotos({
    required List<_PickedPhoto> photos,
    required String folder,
    required Future<void> Function(String path, int displayOrder) link,
  }) async {
    final baseIndex = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo.isExisting) continue;
      final path = await _controller.uploadChargerImage(
        folder: folder,
        index: baseIndex + i,
        bytes: photo.bytes!,
        fileExtension: photo.fileExtension,
      );
      await link(path, i);
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
              Text(
                _isEditing ? 'Saving your changes' : 'Submitting your charger',
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
                  Text(
                    _isEditing ? 'Edit Charger' : 'Add Charger',
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

  /// A 56x56 thumbnail for a photo entry: a network image for an existing
  /// (already-uploaded) photo, otherwise the in-memory bytes.
  Widget _buildPhotoThumb(_PickedPhoto photo) {
    const double size = 56;
    if (photo.isExisting) {
      return Image.network(
        photo.existingUrl ?? '',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          color: const Color(0xFFF3F4F6),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: _muted),
        ),
      );
    }
    return Image.memory(
      photo.bytes!,
      width: size,
      height: size,
      fit: BoxFit.cover,
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
            child: _buildPhotoThumb(photo),
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
    final current = isStart ? day.start : day.end;
    final picked = await _showHalfHourPicker(current);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        day.start = picked;
      } else {
        day.end = picked;
      }
    });
  }

  /// Shows a Cupertino wheel picker that only allows picking times on the
  /// hour or half-hour (00:00, 00:30, 01:00, ... 23:30).
  Future<TimeOfDay?> _showHalfHourPicker(TimeOfDay initial) {
    // Build every half-hour slot in the day: 48 entries.
    final slots = <TimeOfDay>[
      for (var minutes = 0; minutes < 24 * 60; minutes += 30)
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    ];

    // Snap the initial selection to the nearest half-hour so the wheel opens
    // on a matching row even if the stored value isn't on a boundary.
    final initialMinutes = initial.hour * 60 + initial.minute;
    final snappedMinutes = ((initialMinutes + 15) ~/ 30) * 30 % (24 * 60);
    var initialIndex = snappedMinutes ~/ 30;
    if (initialIndex < 0 || initialIndex >= slots.length) initialIndex = 0;

    // Tracks the wheel's current selection; confirmed only when the user
    // taps "Done".
    var selectedIndex = initialIndex;

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Container(
            height: 300,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    CupertinoButton(
                      onPressed: () =>
                          Navigator.of(context).pop(slots[selectedIndex]),
                      child: const Text('Done'),
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: initialIndex,
                    ),
                    itemExtent: 40,
                    onSelectedItemChanged: (index) => selectedIndex = index,
                    children: [
                      for (final slot in slots)
                        Center(child: Text(_formatTime(slot))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            child: _buildPhotoThumb(photo),
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
              onTap: _isSubmitting ? null : () => _removeBusinessPhoto(index),
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
                  _continueButtonLabel,
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
