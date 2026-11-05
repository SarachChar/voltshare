import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

/// Three-step "Add Charger" flow (Info, Pricing, Hours) for one charger inside
/// [station]. Location, photos and businesses belong to the station, so they
/// aren't asked for here. New chargers start in 'review'.
///
/// Passing [initialCharger] turns it into "Edit Charger". Once a charger is
/// live ('available' / 'unavailable') its hardware specs (type, connector,
/// power) are locked: only the name, price and hours can change.
///
/// Pops with the saved [Charger], or null when the host backs out.
class AddChargerScreen extends StatefulWidget {
  const AddChargerScreen({
    super.key,
    required this.station,
    this.controller,
    this.initialCharger,
    this.existingChargerCount = 0,
  });

  final Station station;
  final ChargerController? controller;
  final Charger? initialCharger;

  /// How many chargers the station already has; a blank name becomes
  /// "Charger N" with N = count + 1.
  final int existingChargerCount;

  @override
  State<AddChargerScreen> createState() => _AddChargerScreenState();
}

enum _Step { info, pricing, hours }

extension on _Step {
  String get label {
    switch (this) {
      case _Step.info:
        return 'Info';
      case _Step.pricing:
        return 'Pricing';
      case _Step.hours:
        return 'Hours';
    }
  }
}

/// One day's opening hours in the Hours step. [dayOfWeek] follows the DB
/// convention (0 = Sunday .. 6 = Saturday). Closed days are saved unavailable.
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
  static const Color _bg = Color(0xFFF3F4F6);

  static const List<_Step> _steps = _Step.values;

  /// Platform fee VoltShare deducts, used for the payout estimate.
  static const double _platformFeeRate = 0.15;

  static const TimeOfDay _defaultStart = TimeOfDay(hour: 7, minute: 0);
  static const TimeOfDay _defaultEnd = TimeOfDay(hour: 22, minute: 0);

  static const List<String> _chargerTypes = ['AC', 'DC'];
  static const List<String> _connectorTypes = ['Type 2', 'CCS2', 'CHAdeMO'];

  /// Connectors allowed for the selected charger type (AC: Type 2;
  /// DC: CCS2, CHAdeMO). A live charger saved before this rule keeps showing
  /// its own connector, since its specs are locked anyway.
  List<String> get _connectorOptions {
    final options = Charger.connectorsFor(_chargerType);
    if (_specsLocked && !options.contains(_connectorType)) {
      return [...options, _connectorType];
    }
    return options;
  }

  /// Picks the charger type and, if the current connector doesn't fit it,
  /// switches to the type's first connector.
  void _selectChargerType(String type) {
    setState(() {
      _chargerType = type;
      final allowed = Charger.connectorsFor(type);
      if (!allowed.contains(_connectorType) && allowed.isNotEmpty) {
        _connectorType = allowed.first;
      }
    });
  }

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());

  bool get _isEditing => widget.initialCharger != null;

  /// Live chargers have passed device setup: their specs can't change here.
  bool get _specsLocked => widget.initialCharger?.isLive ?? false;

  String get _defaultName => 'Charger ${widget.existingChargerCount + 1}';

  int _currentStep = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _powerController = TextEditingController(
    text: '22',
  );
  final TextEditingController _priceController = TextEditingController(
    text: '8.00',
  );

  String _chargerType = 'AC';
  String _connectorType = 'Type 2';

  /// Shown Monday-first, tagged with the DB's day_of_week.
  final List<_DayHours> _days = [
    _DayHours(dayOfWeek: 1, label: 'Mon'),
    _DayHours(dayOfWeek: 2, label: 'Tue'),
    _DayHours(dayOfWeek: 3, label: 'Wed'),
    _DayHours(dayOfWeek: 4, label: 'Thu'),
    _DayHours(dayOfWeek: 5, label: 'Fri'),
    _DayHours(dayOfWeek: 6, label: 'Sat'),
    _DayHours(dayOfWeek: 0, label: 'Sun'),
  ];

  bool _isLoadingExisting = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final charger = widget.initialCharger;
    if (charger != null) {
      _nameController.text = charger.name;
      _powerController.text = _trimNumber(charger.powerKw);
      _priceController.text = charger.pricePerKwh.toStringAsFixed(2);
      if (_chargerTypes.contains(charger.chargerType)) {
        _chargerType = charger.chargerType;
      }
      if (_connectorTypes.contains(charger.connectorType)) {
        _connectorType = charger.connectorType;
      }
      // An editable charger saved with a connector that doesn't fit its type
      // (before the AC/DC rule) moves to the type's first connector.
      final allowed = Charger.connectorsFor(_chargerType);
      if (!_specsLocked &&
          !allowed.contains(_connectorType) &&
          allowed.isNotEmpty) {
        _connectorType = allowed.first;
      }
      _loadExistingHours(charger.id);
    }
  }

  Future<void> _loadExistingHours(String chargerId) async {
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await _controller.fetchChargerAvailability(chargerId);
      if (!mounted) return;
      setState(() => _applyAvailability(rows));
    } catch (error) {
      if (!mounted) return;
      _snack('Could not load current hours: $error');
    } finally {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  /// Maps loaded rows onto [_days]: missing or unavailable days are closed.
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
      day.start = _parseDbTime(row.startTime) ?? day.start;
      day.end = _parseDbTime(row.endTime) ?? day.end;
    }
  }

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
    _powerController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // ----- Navigation -----------------------------------------------------------

  bool get _isLastStep => _currentStep == _steps.length - 1;

  String get _continueLabel {
    if (!_isLastStep) return 'Continue →';
    return _isEditing ? 'Save' : 'Request to list this charger';
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

  // ----- Submit ---------------------------------------------------------------

  Future<void> _submit() async {
    final power = double.tryParse(_powerController.text.trim());
    if (!_specsLocked && (power == null || power <= 0)) {
      setState(() => _currentStep = _steps.indexOf(_Step.info));
      _snack('Please enter the power output in kW.');
      return;
    }
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      setState(() => _currentStep = _steps.indexOf(_Step.pricing));
      _snack('Please enter a price per kWh.');
      return;
    }
    final invalidDay = _days
        .where((d) => d.isOpen && !_isValidRange(d.start, d.end))
        .firstOrNull;
    if (invalidDay != null) {
      setState(() => _currentStep = _steps.indexOf(_Step.hours));
      _snack('${invalidDay.label}: closing time must be after opening time.');
      return;
    }

    final confirmed = await _confirmSubmission();
    if (confirmed != true || !mounted) return;

    final typedName = _nameController.text.trim();
    final name = typedName.isNotEmpty
        ? typedName
        : (widget.initialCharger?.name.isNotEmpty ?? false)
        ? widget.initialCharger!.name
        : _defaultName;

    setState(() => _isSubmitting = true);
    try {
      final Charger saved;
      if (_isEditing) {
        final original = widget.initialCharger!;
        saved = await _controller.updateCharger(
          chargerId: original.id,
          name: name,
          pricePerKwh: price,
          chargerType: _specsLocked ? null : _chargerType,
          connectorType: _specsLocked ? null : _connectorType,
          powerKw: _specsLocked ? null : power,
        );
        await _controller.replaceChargerAvailability(
          chargerId: original.id,
          days: _availabilityRows(original.id),
        );
      } else {
        saved = await _controller.createCharger(
          stationId: widget.station.id,
          name: name,
          chargerType: _chargerType,
          connectorType: _connectorType,
          powerKw: power!,
          pricePerKwh: price,
          status: 'review',
        );
        await _controller.insertChargerAvailability(
          chargerId: saved.id,
          days: _availabilityRows(saved.id),
        );
      }
      if (!mounted) return;
      _snack(_isEditing ? 'Charger updated.' : 'Charger submitted for review.');
      Navigator.of(context).pop(saved);
    } catch (error, stackTrace) {
      debugPrint(
        '${_isEditing ? 'updateCharger' : 'createCharger'} '
        'flow failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      _snack('Failed to ${_isEditing ? 'update' : 'create'} charger: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool?> _confirmSubmission() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _isEditing ? 'Save changes?' : 'Submit this charger?',
          style: const TextStyle(fontWeight: FontWeight.w800, color: _dark),
        ),
        content: Text(
          _isEditing
              ? 'This will update the charger with the changes you\'ve made.'
              : 'Our team reviews new chargers and sets up the device before '
                    'it goes live. Once it is live, its type, connector and '
                    'power can\'t be changed. Please double-check them.',
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

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildStepBody()),
                _buildContinueBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_steps[_currentStep]) {
      case _Step.info:
        return _buildInfoStep();
      case _Step.pricing:
        return _buildPricingStep();
      case _Step.hours:
        return _buildHoursStep();
    }
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
              Expanded(
                child: Column(
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
                      '${widget.station.name} · '
                      'Step ${_currentStep + 1} of ${_steps.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
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
        _fieldLabel('CHARGER NAME'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          key: const ValueKey('charger-name'),
          controller: _nameController,
          decoration: _inputDecoration('Optional, e.g. "$_defaultName"'),
        ),
        const Padding(padding: EdgeInsets.only(top: 6)),
        Text(
          'Leave blank to use "${widget.initialCharger?.name.isNotEmpty == true ? widget.initialCharger!.name : _defaultName}".',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        if (_specsLocked) ...[
          const Padding(padding: EdgeInsets.only(top: 20)),
          _buildLockedNotice(),
        ],
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('CHARGER TYPE'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildChoiceChips(
          options: _chargerTypes,
          selected: _chargerType,
          onSelected: _selectChargerType,
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('CONNECTOR TYPE'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        _buildChoiceChips(
          options: _connectorOptions,
          selected: _connectorType,
          onSelected: (value) => setState(() => _connectorType = value),
          assetForOption: Charger.connectorAssetFor,
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('POWER OUTPUT'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          key: const ValueKey('charger-power'),
          controller: _powerController,
          enabled: !_specsLocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration('22').copyWith(
            suffixText: 'kW',
            suffixStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
            fillColor: _specsLocked ? _bg : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildLockedNotice() {
    return Container(
      key: const ValueKey('specs-locked'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Color(0xFF1E3A8A)),
          Padding(padding: EdgeInsets.only(left: 10)),
          Expanded(
            child: Text(
              'This charger is live, so its type, connector and power are '
              'locked to the installed device. Contact support to change them.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
            onTap: _specsLocked ? null : () => onSelected(option),
            assetPath: assetForOption?.call(option),
          ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
    String? assetPath,
  }) {
    final disabled = onTap == null;
    final color = isSelected ? _primary : (disabled ? _muted : _dark);
    return Opacity(
      opacity: disabled && !isSelected ? 0.5 : 1,
      child: Material(
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
      ),
    );
  }

  // ----- Pricing step ---------------------------------------------------------

  Widget _buildPricingStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAFBF3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 15, color: _muted, height: 1.4),
              children: [
                TextSpan(text: 'Set your price per kWh. VoltShare deducts a '),
                TextSpan(
                  text: '15% platform fee',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text:
                      ' from each transaction. Your net payout is shown '
                      'below.',
                ),
              ],
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 20)),
        _fieldLabel('PRICE PER KWH (฿)'),
        const Padding(padding: EdgeInsets.only(top: 8)),
        TextField(
          key: const ValueKey('charger-price'),
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

  /// Estimated hourly payout = power (kW) × price (฿/kWh) × (1 − fee).
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
          Text(
            '฿${_formatMoney(payout)}/hr',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoney(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  // ----- Hours step -----------------------------------------------------------

  Widget _buildHoursStep() {
    if (_isLoadingExisting) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _fieldLabel('OPENING HOURS'),
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
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: 44),
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
      color: _bg,
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
    final picked = await _showHalfHourPicker(isStart ? day.start : day.end);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        day.start = picked;
      } else {
        day.end = picked;
      }
    });
  }

  /// Cupertino wheel limited to the hour / half-hour (00:00 .. 23:30).
  Future<TimeOfDay?> _showHalfHourPicker(TimeOfDay initial) {
    final slots = <TimeOfDay>[
      for (var minutes = 0; minutes < 24 * 60; minutes += 30)
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    ];
    final initialMinutes = initial.hour * 60 + initial.minute;
    final snapped = ((initialMinutes + 15) ~/ 30) * 30 % (24 * 60);
    var initialIndex = snapped ~/ 30;
    if (initialIndex < 0 || initialIndex >= slots.length) initialIndex = 0;
    var selectedIndex = initialIndex;

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(height: 300),
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

  static String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatTimeForDb(TimeOfDay time) => '${_formatTime(time)}:00';

  static bool _isValidRange(TimeOfDay start, TimeOfDay end) =>
      end.hour * 60 + end.minute > start.hour * 60 + start.minute;

  // ----- Shared bits ----------------------------------------------------------

  Widget _fieldLabel(String label) {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      disabledBorder: OutlineInputBorder(
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
          key: const ValueKey('charger-continue'),
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
              ? ConstrainedBox(
                  constraints: BoxConstraints.tightFor(height: 22, width: 22),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  _continueLabel,
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
