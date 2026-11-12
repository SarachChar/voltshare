import 'package:flutter/material.dart';

import 'package:voltshare_app/models/station_model.dart';

/// Persists a new promotion and returns the created row, so the sheet can
/// hand it back to the caller.
typedef CreatePromotionCallback = Future<StationPromotion> Function({
  required String title,
  required String description,
  DateTime? validFrom,
  DateTime? validUntil,
  required bool active,
  required String termsAndConditions,
});

/// Bottom-sheet form for creating a new station promotion. Pops with the
/// created [StationPromotion], or null when dismissed.
class CreatePromotionSheet extends StatefulWidget {
  const CreatePromotionSheet({super.key, required this.onSubmit});

  final CreatePromotionCallback onSubmit;

  @override
  State<CreatePromotionSheet> createState() => _CreatePromotionSheetState();
}

class _CreatePromotionSheetState extends State<CreatePromotionSheet> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _termsController = TextEditingController();

  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _active = true;
  bool _isSaving = false;

  /// Set true once the user tries to submit, so missing required dates show
  /// their inline error.
  bool _showDateErrors = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Only today onwards is selectable. "Valid until" also can't be before
    // the chosen "valid from" date.
    final first = isFrom
        ? today
        : (_validFrom != null && _validFrom!.isAfter(today)
            ? _validFrom!
            : today);
    var initial =
        isFrom ? (_validFrom ?? today) : (_validUntil ?? _validFrom ?? today);
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
        if (_validUntil != null && _validUntil!.isBefore(picked)) {
          _validUntil = null;
        }
      } else {
        _validUntil = picked;
      }
    });
  }

  /// Inline error for a date field, or null when valid. Only shown after the
  /// user has tried to submit.
  String? _dateError({required bool isFrom}) {
    if (!_showDateErrors) return null;
    final value = isFrom ? _validFrom : _validUntil;
    if (value == null) return 'Required';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (value.isBefore(today)) return 'Must be today or later';
    if (!isFrom && _validFrom != null && value.isBefore(_validFrom!)) {
      return 'Must be on or after valid from';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState!.validate();
    setState(() => _showDateErrors = true);
    final datesValid =
        _dateError(isFrom: true) == null && _dateError(isFrom: false) == null;
    if (!formValid || !datesValid) return;

    setState(() => _isSaving = true);
    try {
      // The picker returns midnight; extend validUntil to the end of that day
      // so the promotion stays valid for the whole day the host picked.
      final until = _validUntil!;
      final validUntilEndOfDay =
          DateTime(until.year, until.month, until.day, 23, 59, 59);

      final created = await widget.onSubmit(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        validFrom: _validFrom,
        validUntil: validUntilEndOfDay,
        active: _active,
        termsAndConditions: _termsController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create promotion.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Tapping anywhere outside a text field dismisses the keyboard.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                const Text(
                  'New Promotion',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 20)),
                _buildLabel('Title', required: true),
                const Padding(padding: EdgeInsets.only(top: 6)),
                TextFormField(
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration('e.g. ฿50 voucher at FreshMart'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                _buildLabel('Description', required: true),
                const Padding(padding: EdgeInsets.only(top: 6)),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration:
                      _inputDecoration('Short details shown to drivers'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Description is required';
                    }
                    return null;
                  },
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Valid from',
                        value: _validFrom,
                        onTap: () => _pickDate(isFrom: true),
                        required: true,
                        error: _dateError(isFrom: true),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.only(left: 12)),
                    Expanded(
                      child: _buildDateField(
                        label: 'Valid until',
                        value: _validUntil,
                        onTap: () => _pickDate(isFrom: false),
                        required: true,
                        error: _dateError(isFrom: false),
                      ),
                    ),
                  ],
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                _buildLabel('Terms & Conditions'),
                const Padding(padding: EdgeInsets.only(top: 6)),
                TextFormField(
                  controller: _termsController,
                  maxLines: 4,
                  decoration: _inputDecoration(
                    'Any rules or limitations for this promotion (optional)',
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _dark,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _active,
                        activeThumbColor: Colors.white,
                        activeTrackColor: _primary,
                        onChanged: (value) => setState(() => _active = value),
                      ),
                    ],
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 24)),
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(height: 52),
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSaving
                        ? ConstrainedBox(
                            constraints: BoxConstraints.tightFor(width: 22, height: 22),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Create Promotion',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _dark,
        ),
        children: required
            ? const [
                TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
              ]
            : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    bool required = false,
    String? error,
  }) {
    final hasError = error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, required: required),
        const Padding(padding: EdgeInsets.only(top: 6)),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasError
                    ? Colors.red.shade400
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_outlined, size: 18, color: _muted),
                const Padding(padding: EdgeInsets.only(left: 8)),
                Expanded(
                  child: Text(
                    value == null
                        ? 'Select'
                        : StationPromotion.formatDate(value),
                    style: TextStyle(
                      fontSize: 14,
                      color: value == null ? Colors.grey.shade400 : _dark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
        ],
      ],
    );
  }
}
