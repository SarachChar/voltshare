import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/controllers/payment_method_controller.dart';
import 'package:voltshare_app/models/payment_method_model.dart';
import 'package:voltshare_app/services/payment_method_service.dart';

/// Lists the signed-in user's saved credit/debit cards, with an "Add Card"
/// button pinned to the bottom.
///
/// Adding a card is a placeholder for now: the real flow needs a payment
/// provider (Stripe/Omise) to tokenize the card, since we never collect or
/// store raw card data ourselves. Tapping "Add Card" shows a coming-soon note.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, this.controller});

  /// Optional injected controller (useful for tests). Falls back to a default
  /// Supabase-backed controller when not provided.
  final PaymentMethodController? controller;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  late final PaymentMethodController _controller =
      widget.controller ??
          PaymentMethodController(PaymentMethodSupabaseService());

  /// Whether this screen created the controller and must dispose it. When the
  /// controller is injected (tests), the caller owns its lifecycle.
  late final bool _ownsController = widget.controller == null;

  StreamSubscription<bool>? _syncSub;

  List<PaymentMethod> _cards = List.empty();
  bool _isLoading = true;
  bool _hasError = false;

  /// True while a controller call is in flight (driven by onSync). Used for the
  /// overlay spinner shown during add / set-default, so those blocking ops give
  /// visible feedback.
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _syncSub = _controller.onSync.listen((busy) {
      if (!mounted) return;
      setState(() => _isBusy = busy);
    });
    _load();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _cards = List.empty();
        _isLoading = false;
      });
      return;
    }

    try {
      final cards = await _controller.fetchPaymentMethods(userId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _onAddCard() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to add a card.')),
      );
      return;
    }

    final draft = await showModalBottomSheet<_CardDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCardSheet(),
    );
    if (draft == null) return;

    try {
      // MOCK: store the entered card straight into our DB. No gateway yet.
      await _controller.addPaymentMethod(
        userId: userId,
        cardNumber: draft.cardNumber,
        holderName: draft.holderName,
        expMonth: draft.expMonth,
        expYear: draft.expYear,
        // First card added becomes the default.
        isDefault: _cards.isEmpty,
      );
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t save the card. Try again.')),
      );
    }
  }

  Future<void> _onCardTap(PaymentMethod card) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set as default?'),
        content: Text(
          'Use ${card.brandLabel} ${card.maskedNumber} as your default '
          'payment method?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Set as default',
              style: TextStyle(fontWeight: FontWeight.w700, color: _primary),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _controller.setDefaultPaymentMethod(userId: userId, id: card.id);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t update the default card.')),
      );
    }
  }

  /// Red swipe background with a trash icon, revealed when dragging a card left.
  Widget _deleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
    );
  }

  /// Confirm dialog shown before a swipe-to-delete removes the card. Returns
  /// true only when the user confirms.
  Future<bool> _confirmDelete(PaymentMethod card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove card?'),
        content: Text(
          'Remove ${card.brandLabel} ${card.maskedNumber} from your '
          'payment methods?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Deletes the card (already confirmed). Dismissible has already animated the
  /// row away, so remove it from [_cards] immediately to keep the list in sync
  /// with the widget tree — otherwise Flutter complains that a dismissed item
  /// is still present. The DB delete then runs; a failure reloads to restore.
  Future<void> _deleteCard(PaymentMethod card) async {
    setState(() {
      _cards = _cards.where((c) => c.id != card.id).toList();
    });

    try {
      await _controller.deletePaymentMethod(card.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t remove the card.')),
      );
      // Delete failed — reload so the card reappears.
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Payment Methods',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(child: _buildBody()),
          // Overlay spinner for mutating ops (add / set-default). The initial
          // fetch uses its own full-screen spinner via _isLoading, so skip the
          // overlay then to avoid stacking two indicators.
          if (_isBusy && !_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: _primary),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildAddBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_hasError) {
      return _emptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t load your cards',
        message: 'Pull down to try again.',
      );
    }
    if (_cards.isEmpty) {
      return _emptyState(
        icon: Icons.credit_card_off_outlined,
        title: 'No cards yet',
        message: 'Add a credit or debit card to pay for bookings.',
      );
    }

    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        itemCount: _cards.length,
        itemBuilder: (context, index) {
          final card = _cards[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Dismissible(
              key: ValueKey(card.id),
              direction: DismissDirection.endToStart,
              background: _deleteBackground(),
              // Ask before removing; returning false leaves the card in place.
              confirmDismiss: (_) => _confirmDelete(card),
              onDismissed: (_) => _deleteCard(card),
              child: _cardTile(card),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 16)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _cardTile(PaymentMethod card) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Tapping the current default does nothing; otherwise offer to make it
        // the default.
        onTap: card.isDefault ? null : () => _onCardTap(card),
        child: _cardTileContent(card),
      ),
    );
  }

  Widget _cardTileContent(PaymentMethod card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.credit_card, color: _primary, size: 24),
          ),
          const Padding(padding: EdgeInsets.only(left: 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      card.brandLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (card.isDefault) ...[
                      const Padding(padding: EdgeInsets.only(left: 8)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Default',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  card.maskedNumber,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                ),
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  'Expires ${card.expiryLabel}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _onAddCard,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'Add Card',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// The validated card details collected by [_AddCardSheet].
class _CardDraft {
  _CardDraft({
    required this.cardNumber,
    required this.holderName,
    required this.expMonth,
    required this.expYear,
  });

  final String cardNumber;
  final String holderName;
  final int expMonth;
  final int expYear;
}

/// Bottom-sheet form to enter a (mock) card. Returns a [_CardDraft] when the
/// user taps Save, or null if they dismiss it.
class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);

  /// Max card-number length accepted (ISO/IEC 7812), matching the validator.
  static const int _maxCardDigits = 19;

  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _expController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _expController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final parts = _expController.text.trim().split('/');
    final month = int.parse(parts[0]);
    // Accept 2-digit years as 20xx.
    final rawYear = int.parse(parts[1]);
    final year = rawYear < 100 ? 2000 + rawYear : rawYear;

    Navigator.of(context).pop(
      _CardDraft(
        cardNumber: _numberController.text.replaceAll(RegExp(r'\s+'), ''),
        holderName: _nameController.text.trim(),
        expMonth: month,
        expYear: year,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lift the sheet above the keyboard.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 16)),
              const Text(
                'Add Card',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 16)),
              _field(
                controller: _numberController,
                label: 'Card number',
                hint: '1234 5678 9012 3456',
                keyboardType: TextInputType.number,
                // Digits only, capped at the max the validator allows.
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_maxCardDigits),
                ],
                validator: (value) {
                  final digits =
                      (value ?? '').replaceAll(RegExp(r'\s+'), '');
                  if (digits.isEmpty) return 'Enter the card number';
                  if (digits.length < 13 || digits.length > 19) {
                    return 'Card number looks invalid';
                  }
                  if (!RegExp(r'^[0-9]+$').hasMatch(digits)) {
                    return 'Digits only';
                  }
                  return null;
                },
              ),
              const Padding(padding: EdgeInsets.only(top: 12)),
              _field(
                controller: _nameController,
                label: 'Name on card',
                hint: 'Name as shown on card',
                keyboardType: TextInputType.name,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter the name' : null,
              ),
              const Padding(padding: EdgeInsets.only(top: 12)),
              _field(
                controller: _expController,
                label: 'Expiry (MM/YY)',
                hint: 'MM/YY',
                keyboardType: TextInputType.number,
                inputFormatters: [_ExpiryInputFormatter()],
                validator: (value) {
                  final text = (value ?? '').trim();
                  final match =
                      RegExp(r'^(\d{2})/(\d{2})$').firstMatch(text);
                  if (match == null) return 'Use MM/YY';
                  final month = int.parse(match.group(1)!);
                  if (month < 1 || month > 12) return 'Month must be 1–12';
                  return null;
                },
              ),
              const Padding(padding: EdgeInsets.only(top: 20)),
              Container(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Save Card',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _dark,
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 6)),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Formats expiry input as "MM/YY": keeps at most 4 digits and inserts a "/"
/// after the first two, so the user only types the numbers.
class _ExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip everything but digits, cap at 4 (MMYY).
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);

    // Re-insert the slash once we're past the month.
    final text =
        digits.length <= 2 ? digits : '${digits.substring(0, 2)}/${digits.substring(2)}';

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
