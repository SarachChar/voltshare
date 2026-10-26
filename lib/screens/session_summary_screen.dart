import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/components/primary_button.dart';
import 'package:voltshare_app/controllers/charging_session_controller.dart';
import 'package:voltshare_app/controllers/payment_method_controller.dart';
import 'package:voltshare_app/models/charging_session_model.dart';
import 'package:voltshare_app/models/payment_method_model.dart';
import 'package:voltshare_app/models/session_payment_model.dart';
import 'package:voltshare_app/screens/charging_payment_complete_screen.dart';
import 'package:voltshare_app/screens/payment_failed_screen.dart';
import 'package:voltshare_app/screens/payment_methods_screen.dart';
import 'package:voltshare_app/services/charging_session_service.dart';
import 'package:voltshare_app/services/payment_method_service.dart';

/// Bill for a finished charging session: energy delivered, duration, cost
/// breakdown (energy − booking fee), and card selection to pay.
///
/// The driver can't leave this screen until the session is paid: there's no
/// back button and the back gesture is blocked. The app also routes here on
/// launch while a session is unpaid (see PendingSessionGate).
class SessionSummaryScreen extends StatefulWidget {
  const SessionSummaryScreen({
    super.key,
    required this.sessionId,
    this.controller,
    this.paymentMethodController,
  });

  final String sessionId;
  final ChargingSessionController? controller;
  final PaymentMethodController? paymentMethodController;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _mint = Color(0xFFE8F8F3);
  static const Color _mintBorder = Color(0xFFC8EDE0);

  late final ChargingSessionController _controller = widget.controller ??
      ChargingSessionController(ChargingSessionSupabaseService());

  late final PaymentMethodController _cardController =
      widget.paymentMethodController ??
          PaymentMethodController(PaymentMethodSupabaseService());
  late final bool _ownsCardController = widget.paymentMethodController == null;

  ChargingSession? _session;
  SessionPayment? _payment;
  List<PaymentMethod> _cards = List.empty();
  PaymentMethod? _selectedCard;

  bool _isLoading = true;
  bool _hasError = false;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsCardController) _cardController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final session = await _controller.fetchSession(widget.sessionId);
      final payment = await _controller.fetchPayment(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _payment = payment;
        _isLoading = false;
        _hasError = session == null || payment == null;
      });
      await _loadCards();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _loadCards() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    try {
      final cards = await _cardController.fetchPaymentMethods(userId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // Keep the current pick if it still exists; else the default card
        // (service orders default first).
        final keep = _selectedCard == null
            ? null
            : cards.where((c) => c.id == _selectedCard!.id).firstOrNull;
        _selectedCard = keep ?? (cards.isNotEmpty ? cards.first : null);
      });
    } catch (_) {
      // Cards are optional to render the bill; the Pay button stays disabled.
    }
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _goToAddCard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PaymentMethodsScreen()),
    );
    if (mounted) await _loadCards();
  }

  void _goToComplete() {
    final payment = _payment;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChargingPaymentCompleteScreen(
          amount: payment?.totalAmount ?? 0,
          energyKwh: _session?.totalEnergyKwh ?? 0,
          reservation: _session?.reservation,
        ),
      ),
    );
  }

  Future<void> _onPay() async {
    final card = _selectedCard;
    if (card == null) return;

    setState(() => _isPaying = true);
    try {
      await _controller.payForSession(
        sessionId: widget.sessionId,
        paymentMethodId: card.id,
        amount: _payment?.totalAmount ?? 0,
      );
      if (!mounted) return;
      setState(() => _isPaying = false);
      _goToComplete();
    } on ChargingException catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      if (e.code == 'ALREADY_PAID') {
        _goToComplete();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaymentFailedScreen(
            message: e.userMessage,
            detail: 'Your charging session is still unpaid. Please try again '
                'or use a different card.',
          ),
        ),
      );
      if (!mounted) return;
      // The bill may have changed: reload it before the next attempt.
      if (e.code == 'AMOUNT_MISMATCH') {
        await _load();
      } else {
        await _loadCards();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment failed. Please try again.')),
      );
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: _bg,
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: _bg,
              body: _buildBody(),
              bottomNavigationBar:
                  _isLoading || _hasError ? null : _buildPayBar(),
            ),
            if (_isPaying) _buildProcessingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_hasError) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 44, color: Colors.grey.shade400),
                const Padding(padding: EdgeInsets.only(top: 12)),
                const Text(
                  'Couldn\'t load your charging bill.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCostBreakdown(),
              if (!(_payment?.isPaid ?? false)) ...[
                const Padding(padding: EdgeInsets.only(top: 24)),
                _buildPaymentMethods(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final session = _session!;
    final r = session.reservation;
    final subtitle = [
      if (r != null && r.chargerName.isNotEmpty) r.chargerName,
      _dateLabel(session.startedAt),
    ].join(' · ');

    return Container(
      color: _primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Session Summary',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 4)),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 20)),
              Row(
                children: [
                  Expanded(
                    child: _headerTile(
                      Icons.bolt_outlined,
                      '${(session.totalEnergyKwh ?? 0).toStringAsFixed(2)} kWh',
                      'DELIVERED',
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(left: 12)),
                  Expanded(
                    child: _headerTile(
                      Icons.schedule,
                      _durationLabel(session.elapsed),
                      'DURATION',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerTile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 4)),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostBreakdown() {
    final session = _session!;
    final payment = _payment!;
    final energy = session.totalEnergyKwh ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _mintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cost Breakdown',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          _costRow(
            title: 'Energy charge',
            subtitle: '${energy.toStringAsFixed(2)} kWh × '
                '฿${session.pricePerKwhAtStart.toStringAsFixed(2)}',
            value: '฿${payment.energyAmount.toStringAsFixed(2)}',
            valueColor: _navy,
          ),
          if (payment.bookingFeeDeducted > 0) ...[
            const Divider(height: 28),
            _costRow(
              title: 'Booking fee paid',
              subtitle: 'Deducted from total',
              value: '-฿${payment.bookingFeeDeducted.toStringAsFixed(2)}',
              valueColor: _primary,
            ),
          ],
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                '฿${payment.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _costRow({
    required String title,
    required String subtitle,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, color: _navy),
              ),
              const Padding(padding: EdgeInsets.only(top: 2)),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Method',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        for (final card in _cards) ...[
          _cardTile(card),
          const Padding(padding: EdgeInsets.only(top: 12)),
        ],
        Container(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _isPaying ? null : _goToAddCard,
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Add card',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardTile(PaymentMethod card) {
    final selected = card.id == _selectedCard?.id;
    return Material(
      color: selected ? _mint : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _isPaying ? null : () => setState(() => _selectedCard = card),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _primary : _mintBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected ? _primary : const Color(0xFFEEF1F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.credit_card,
                  color: selected ? Colors.white : _muted,
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Credit / Debit Card',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const Padding(padding: EdgeInsets.only(top: 2)),
                    Text(
                      '${card.brandLabel} •••• ${card.last4}'
                      '${card.isDefault ? '  ·  Default' : ''}',
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? _primary : _mintBorder,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayBar() {
    final payment = _payment!;
    if (payment.isPaid) {
      // Nothing to charge (energy cost covered by the booking fee).
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(label: 'Continue', onPressed: _goToComplete),
      );
    }
    final hasCard = _selectedCard != null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: PrimaryButton(
        label: hasCard
            ? 'Pay ฿${payment.totalAmount.toStringAsFixed(2)}'
            : 'Add a payment method',
        icon: Icons.credit_card,
        isLoading: _isPaying,
        onPressed: hasCard ? _onPay : _goToAddCard,
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
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _primary),
              Padding(padding: EdgeInsets.only(top: 18)),
              Text(
                'Processing payment…',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Formatting -----------------------------------------------------------

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dateLabel(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  static String _durationLabel(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} sec';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours} hr' : '${d.inHours} hr $m min';
  }
}
