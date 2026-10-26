import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/controllers/payment_controller.dart';
import 'package:voltshare_app/controllers/payment_method_controller.dart';
import 'package:voltshare_app/controllers/reservation_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/payment_method_model.dart';
import 'package:voltshare_app/screens/payment_failed_screen.dart';
import 'package:voltshare_app/screens/payment_methods_screen.dart';
import 'package:voltshare_app/screens/reservation_confirmed_screen.dart';
import 'package:voltshare_app/services/payment_method_service.dart';
import 'package:voltshare_app/services/payment_service.dart';
import 'package:voltshare_app/services/reservation_service.dart';

/// Review step shown after the driver taps "Next" on the reserve screen. It
/// lays out the full booking summary, lets the driver pick which saved card to
/// pay with, and holds the "Confirm Reservation" action.
///
/// Confirm flow (payment is mocked via the `pay-booking-fee` edge function):
///   1. create the reservation (fails early if the slot was just taken)
///   2. pay the booking fee with the chosen card
///      - success -> (server records booking_fee) go to the confirmation screen
///      - failure -> roll back (delete) the reservation, let the driver retry
///
/// Returns a [ReservationSummaryResult] when popped so the reserve screen knows
/// whether the booking went through, the slot was taken, or payment failed.
class ReservationSummaryScreen extends StatefulWidget {
  const ReservationSummaryScreen({
    super.key,
    required this.charger,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.fee,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
    this.reservationController,
    this.paymentMethodController,
    this.paymentController,
  });

  final Charger charger;
  final DateTime date;

  /// Full local start/end timestamps of the booking.
  final DateTime startTime;
  final DateTime endTime;

  final int durationMinutes;
  final int fee;

  /// Pre-formatted labels, so this screen matches the reserve screen exactly.
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;

  final ReservationController? reservationController;
  final PaymentMethodController? paymentMethodController;
  final PaymentController? paymentController;

  @override
  State<ReservationSummaryScreen> createState() =>
      _ReservationSummaryScreenState();
}

/// Outcome reported back to the reserve screen when this screen is popped.
enum ReservationSummaryResult {
  /// Booking saved and paid (confirmation screen shown and dismissed).
  booked,

  /// The slot was just taken — reserve screen should refresh the day.
  slotTaken,
}

class _ReservationSummaryScreenState extends State<ReservationSummaryScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF3F4F6);

  late final ReservationController _reservationController =
      widget.reservationController ??
          ReservationController(ReservationSupabaseService());

  late final PaymentMethodController _paymentMethodController =
      widget.paymentMethodController ??
          PaymentMethodController(PaymentMethodSupabaseService());

  late final PaymentController _paymentController =
      widget.paymentController ?? PaymentController(PaymentSupabaseService());

  /// The user's saved cards, and the one currently selected to pay with.
  List<PaymentMethod> _cards = List.empty();
  PaymentMethod? _selectedCard;
  bool _isLoadingCards = true;

  /// True while the confirm flow (reserve + charge) is running.
  bool _isBooking = false;

  /// Whether we created the payment controllers (and must dispose them). When
  /// injected (tests), the caller owns their lifecycle.
  late final bool _ownsPaymentMethodController =
      widget.paymentMethodController == null;
  late final bool _ownsPaymentController = widget.paymentController == null;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    if (_ownsPaymentMethodController) _paymentMethodController.dispose();
    if (_ownsPaymentController) _paymentController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      setState(() => _isLoadingCards = false);
      return;
    }
    try {
      final cards = await _paymentMethodController.fetchPaymentMethods(userId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // Default card first (service orders by is_default desc), else the
        // first card.
        _selectedCard = cards.isNotEmpty ? cards.first : null;
        _isLoadingCards = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingCards = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stack wraps the whole Scaffold (including the bottom Pay button) so the
    // processing overlay covers the entire screen, not just the body. The
    // outer Material gives the overlay's text/spinner a proper theme ancestor
    // (without it, Text renders with the yellow debug underline).
    return Material(
      color: _bg,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: _bg,
            body: SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _buildHeader(),
                  const Padding(padding: EdgeInsets.only(top: 20)),
                  _buildChargerCard(),
                  const Padding(padding: EdgeInsets.only(top: 24)),
                  _buildSummary(),
                  const Padding(padding: EdgeInsets.only(top: 24)),
                  _buildPaymentSection(),
                ],
              ),
            ),
            bottomNavigationBar: _buildConfirmBar(),
          ),
          // Full-screen blocking overlay while the booking + payment runs, so
          // the driver can't tap anything (including the Pay button) until the
          // result is known.
          if (_isBooking) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _primary),
              const Padding(padding: EdgeInsets.only(top: 18)),
              const Text(
                'Processing payment…',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 4)),
              Text(
                'Please don\'t close this screen.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Header ---------------------------------------------------------------

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.arrow_back, color: _dark, size: 22),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 14)),
        const Text(
          'Review Booking',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
      ],
    );
  }

  // --- Charger card ---------------------------------------------------------

  Widget _buildChargerCard() {
    final charger = widget.charger;
    final specParts = <String>[
      charger.powerLabel,
      if (charger.chargerType.isNotEmpty) charger.chargerType,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      '฿${charger.pricePerKwh.toStringAsFixed(2)}/kWh',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            charger.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            specParts.join(' · '),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Summary --------------------------------------------------------------

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Summary',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 14)),
          _summaryRow('Date', widget.dateLabel),
          const Padding(padding: EdgeInsets.only(top: 10)),
          _summaryRow('Time', widget.timeLabel),
          const Padding(padding: EdgeInsets.only(top: 10)),
          _summaryRow('Duration', widget.durationLabel),
          const Padding(padding: EdgeInsets.only(top: 12)),
          Divider(height: 1, color: _primary.withValues(alpha: 0.25)),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _summaryRow('Booking fee', '฿${widget.fee}', emphasize: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: emphasize ? _dark : _muted,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
      ],
    );
  }

  // --- Payment section ------------------------------------------------------

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pay with',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _dark,
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        if (_isLoadingCards)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: _cardBoxDecoration(),
            child: const CircularProgressIndicator(color: _primary),
          )
        else if (_selectedCard == null)
          _buildNoCard()
        else
          _buildSelectedCard(_selectedCard!),
      ],
    );
  }

  BoxDecoration _cardBoxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
    );
  }

  Widget _buildNoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardBoxDecoration(),
      child: Column(
        children: [
          Icon(Icons.credit_card_off_outlined,
              size: 36, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 10)),
          Text(
            'No payment method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 4)),
          Text(
            'Add a card before confirming your booking.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const Padding(padding: EdgeInsets.only(top: 14)),
          Container(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _goToAddCard,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Card',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedCard(PaymentMethod card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBoxDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.credit_card, color: _primary, size: 22),
          ),
          const Padding(padding: EdgeInsets.only(left: 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.brandLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  card.maskedNumber,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isBooking ? null : _onChangeCard,
            child: const Text(
              'Change',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onChangeCard() async {
    final picked = await showModalBottomSheet<PaymentMethod>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CardPickerSheet(
        cards: _cards,
        selectedId: _selectedCard?.id,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedCard = picked);
    }
  }

  Future<void> _goToAddCard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PaymentMethodsScreen()),
    );
    // Reload in case the driver added a card.
    if (mounted) {
      setState(() => _isLoadingCards = true);
      await _loadCards();
    }
  }

  // --- Confirm bar ----------------------------------------------------------

  Widget _buildConfirmBar() {
    // Can't confirm without a card to pay with.
    final canConfirm = !_isBooking && !_isLoadingCards && _selectedCard != null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        height: 56,
        child: ElevatedButton(
          onPressed: canConfirm ? _onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: Text(
            _selectedCard == null
                ? 'Add a payment method'
                : 'Pay ฿${widget.fee}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onConfirm() async {
    final card = _selectedCard;
    if (card == null) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showMessage('Please sign in before booking.');
      return;
    }

    setState(() => _isBooking = true);

    // 1. Create the reservation first. If the slot was just taken, the DB's
    //    no-overlap constraint rejects it and no payment is attempted.
    final String reservationId;
    try {
      final reservation = await _reservationController.createReservation(
        userId: userId,
        chargerId: widget.charger.id,
        startTime: widget.startTime,
        endTime: widget.endTime,
        durationMinutes: widget.durationMinutes,
      );
      reservationId = reservation.id;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBooking = false);
      _showMessage(
        'Couldn\'t complete the booking. Those times may have just been '
        'taken — please pick again.',
      );
      Navigator.of(context).pop(ReservationSummaryResult.slotTaken);
      return;
    }

    // 2. Pay the booking fee (mock). The server charges the card and records
    //    the booking_fee row; on failure we roll back the reservation.
    try {
      final result = await _paymentController.payBookingFee(
        reservationId: reservationId,
        paymentMethodId: card.id,
        amount: widget.fee,
      );

      if (!result.success) {
        // Payment declined — roll back the reservation and show the failure
        // screen so the driver can retry or switch cards.
        await _reservationController.deleteReservation(reservationId);
        if (!mounted) return;
        setState(() => _isBooking = false);
        await _showPaymentFailed(result.failureMessage);
        return;
      }
    } catch (_) {
      // Payment errored — roll back so we don't leave an unpaid booking.
      await _reservationController.deleteReservation(reservationId);
      if (!mounted) return;
      setState(() => _isBooking = false);
      await _showPaymentFailed('Payment failed. Please try again.');
      return;
    }

    if (!mounted) return;
    // 3. Done — show the confirmation screen, then leave the flow.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationConfirmedScreen(
          chargerName: widget.charger.name,
          dateLabel: widget.dateLabel,
          timeLabel: widget.timeLabel,
          durationLabel: widget.durationLabel,
        ),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(ReservationSummaryResult.booked);
  }

  /// Shows the full-screen payment-failed result, then returns here so the
  /// driver can retry or change card.
  Future<void> _showPaymentFailed(String message) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentFailedScreen(message: message),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Bottom sheet listing the user's cards to pick one to pay with. Pops the
/// chosen [PaymentMethod].
class _CardPickerSheet extends StatelessWidget {
  const _CardPickerSheet({required this.cards, required this.selectedId});

  final List<PaymentMethod> cards;
  final String? selectedId;

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            'Choose a card',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 12)),
          for (final card in cards) _cardRow(context, card),
        ],
      ),
    );
  }

  Widget _cardRow(BuildContext context, PaymentMethod card) {
    final selected = card.id == selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop(card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.credit_card, color: _primary, size: 22),
            const Padding(padding: EdgeInsets.only(left: 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${card.brandLabel}  ${card.maskedNumber}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: _primary, size: 22),
          ],
        ),
      ),
    );
  }
}
