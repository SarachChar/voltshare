import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key, this.controller});

  final ChargerController? controller;

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF10B981);
  static const Color _headerDark = Color(0xFF0F766E);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);

  late final ChargerController _controller =
      widget.controller ?? ChargerController(ChargerSupabaseService());
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  late Future<List<Charger>> _chargersFuture;

  /// Local on/off state for each charger's toggle, keyed by charger id.
  /// No backend action is wired up yet; this only drives the UI.
  final Map<String, bool> _activeById = {};

  /// Which charger cards have their promotions panel expanded.
  final Set<String> _expandedPromotions = {};

  /// Loaded promotions per charger id, kept in memory once fetched so toggles
  /// and newly created promotions are reflected without a full reload.
  final Map<String, List<ChargerPromotion>> _promotionsById = {};

  /// Charger ids whose promotions are currently loading.
  final Set<String> _loadingPromotions = {};

  // Fixed mock header stats for now.
  static const String _totalEarned = '฿9,146';
  static const String _sessions = '59';
  static const String _active = '1';

  @override
  void initState() {
    super.initState();
    _chargersFuture = _loadChargers();
  }

  Future<List<Charger>> _loadChargers() {
    final hostId = Supabase.instance.client.auth.currentUser?.id ?? '';
    return _controller.fetchChargersByHost(hostId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyChargersTab(),
                const _PlaceholderTab(label: 'Pending'),
                const _PlaceholderTab(label: 'Revenue'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- Header ---------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerDark, _primary],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBackButton(),
                  const Padding(padding: EdgeInsets.only(left: 16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HOST MODE',
                          style: TextStyle(
                            color: Color(0xFFB9F5DE),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const Padding(padding: EdgeInsets.only(top: 2)),
                        const Text(
                          'My Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 20)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStat('TOTAL EARNED', _totalEarned),
                  _buildStat('SESSIONS', _sessions),
                  _buildStat('ACTIVE', _active),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 16)),
            _buildTabBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).maybePop(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD1FAE5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 4)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: Colors.white,
      unselectedLabelColor: const Color(0xFFB9F5DE),
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      unselectedLabelStyle:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      tabs: const [
        Tab(text: 'My Chargers'),
        Tab(text: 'Pending'),
        Tab(text: 'Revenue'),
      ],
    );
  }

  // ----- My Chargers tab ------------------------------------------------------

  Widget _buildMyChargersTab() {
    return FutureBuilder<List<Charger>>(
      future: _chargersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load your chargers.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          );
        }

        final chargers = snapshot.data ?? const <Charger>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildAddChargerButton(),
            const Padding(padding: EdgeInsets.only(top: 16)),
            for (final charger in chargers) ...[
              _buildChargerCard(charger),
              const Padding(padding: EdgeInsets.only(top: 16)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAddChargerButton() {
    return Container(
      height: 64,
      child: ElevatedButton.icon(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEAFBF3),
          foregroundColor: _primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _primary, width: 1.5),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text(
          'Add New Charger',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildChargerCard(Charger charger) {
    final bool isActive =
        _activeById[charger.id] ?? (charger.status != 'unavailable');
    // Mocked per-charger figures (not yet in the chargers table). These are
    // fixed to the charger's original status so the toggle doesn't change them.
    final bool wasActive = charger.status != 'unavailable';
    final int sessions = wasActive ? 47 : 12;
    final int gross = wasActive ? 8420 : 2340;
    final int net = (gross * 0.85).round();

    final bool expanded = _expandedPromotions.contains(charger.id);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildChargerIcon(isActive),
                    const Padding(padding: EdgeInsets.only(left: 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            charger.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                            ),
                          ),
                          const Padding(padding: EdgeInsets.only(top: 4)),
                          Text(
                            _cardSubtitle(charger),
                            style:
                                const TextStyle(fontSize: 14, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusToggle(charger.id, isActive),
                  ],
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                Row(
                  children: [
                    _buildMetric('SESSIONS', '$sessions'),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    _buildMetric('GROSS', '฿${_formatMoney(gross)}'),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    _buildMetric('NET (-15%)', '฿${_formatMoney(net)}'),
                  ],
                ),
                const Padding(padding: EdgeInsets.only(top: 12)),
                Row(
                  children: [
                    Expanded(child: _buildEditButton()),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    Expanded(
                      child: _buildPromotionsButton(charger.id, expanded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (expanded) _buildPromotionsPanel(charger.id),
        ],
      ),
    );
  }

  Widget _buildChargerIcon(bool isActive) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFDFF7EF) : const Color(0xFFF1F2F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.bolt,
        color: isActive ? _primary : const Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildStatusToggle(String chargerId, bool isActive) {
    return Switch.adaptive(
      value: isActive,
      activeThumbColor: Colors.white,
      activeTrackColor: _primary,
      onChanged: (value) {
        setState(() => _activeById[chargerId] = value);
      },
    );
  }

  Widget _buildMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.3,
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 4)),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditButton() {
    return OutlinedButton.icon(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        foregroundColor: _dark,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text(
        'Edit',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPromotionsButton(String chargerId, bool expanded) {
    return OutlinedButton(
      onPressed: () => _togglePromotionsPanel(chargerId),
      style: OutlinedButton.styleFrom(
        foregroundColor: expanded ? _primary : _dark,
        backgroundColor: expanded ? const Color(0xFFEAFBF3) : null,
        side: BorderSide(
          color: expanded ? _primary : const Color(0xFFE5E7EB),
          width: expanded ? 1.5 : 1,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_offer_outlined, size: 18),
          const Padding(padding: EdgeInsets.only(left: 6)),
          const Text(
            'Promotions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Padding(padding: EdgeInsets.only(left: 6)),
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 20,
          ),
        ],
      ),
    );
  }

  void _togglePromotionsPanel(String chargerId) {
    setState(() {
      if (_expandedPromotions.contains(chargerId)) {
        _expandedPromotions.remove(chargerId);
      } else {
        _expandedPromotions.add(chargerId);
        if (!_promotionsById.containsKey(chargerId)) {
          _loadPromotions(chargerId);
        }
      }
    });
  }

  Future<void> _loadPromotions(String chargerId) async {
    _loadingPromotions.add(chargerId);
    try {
      final promos = await _controller.fetchChargerPromotions(chargerId);
      if (!mounted) return;
      setState(() {
        _promotionsById[chargerId] = promos;
        _loadingPromotions.remove(chargerId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promotionsById[chargerId] = [];
        _loadingPromotions.remove(chargerId);
      });
    }
  }

  Future<void> _togglePromotionStatus(
    String chargerId,
    ChargerPromotion promo,
    bool active,
  ) async {
    try {
      final updated =
          await _controller.togglePromotionStatus(promo.id, active);
      if (!mounted) return;
      setState(() {
        final list = _promotionsById[chargerId];
        if (list == null) return;
        final index = list.indexWhere((p) => p.id == updated.id);
        if (index != -1) list[index] = updated;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update promotion status.')),
      );
    }
  }

  Future<void> _deletePromotion(
    String chargerId,
    ChargerPromotion promo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete promotion?'),
        content: Text(
          '"${promo.title}" will be removed from your charger listing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _controller.deletePromotion(promo.id);
      if (!mounted) return;
      setState(() {
        _promotionsById[chargerId]?.removeWhere((p) => p.id == promo.id);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete promotion.')),
      );
    }
  }

  Future<void> _openCreatePromotionForm(String chargerId) async {
    final created = await showModalBottomSheet<ChargerPromotion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePromotionSheet(
        onSubmit: ({
          required String title,
          required String description,
          DateTime? validFrom,
          DateTime? validUntil,
          required bool active,
          required String termsAndConditions,
        }) {
          return _controller.createPromotion(
            chargerId: chargerId,
            title: title,
            description: description,
            validFrom: validFrom,
            validUntil: validUntil,
            status: active ? 'ACTIVE' : 'INACTIVE',
            termsAndConditions: termsAndConditions,
          );
        },
      ),
    );

    if (created == null || !mounted) return;
    setState(() {
      _promotionsById.putIfAbsent(chargerId, () => []).insert(0, created);
    });
  }

  // ----- Promotions panel -----------------------------------------------------

  Widget _buildPromotionsPanel(String chargerId) {
    final promos = _promotionsById[chargerId];
    final loading = _loadingPromotions.contains(chargerId);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PARTNER PROMOTIONS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _muted,
              letterSpacing: 0.6,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 12)),
          if (loading || promos == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: _primary),
              ),
            )
          else ...[
            for (final promo in promos) ...[
              _buildPromotionTile(chargerId, promo),
              const Padding(padding: EdgeInsets.only(top: 12)),
            ],
            _buildAddPromotionButton(chargerId),
            const Padding(padding: EdgeInsets.only(top: 14)),
            _buildPromotionsFooter(),
          ],
        ],
      ),
    );
  }

  Widget _buildPromotionTile(String chargerId, ChargerPromotion promo) {
    final active = promo.isActive;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 20,
              color: _muted,
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  promo.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                  ),
                ),
                if (promo.description.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 2)),
                  Text(
                    promo.description,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ],
                const Padding(padding: EdgeInsets.only(top: 4)),
                Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: _muted,
                    ),
                    const Padding(padding: EdgeInsets.only(left: 4)),
                    Flexible(
                      child: Text(
                        promo.validRangeLabel,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 8)),
          Switch.adaptive(
            value: active,
            activeThumbColor: Colors.white,
            activeTrackColor: _primary,
            onChanged: (value) =>
                _togglePromotionStatus(chargerId, promo, value),
          ),
          const Padding(padding: EdgeInsets.only(left: 4)),
          _buildDeletePromotionButton(chargerId, promo),
        ],
      ),
    );
  }

  Widget _buildDeletePromotionButton(
    String chargerId,
    ChargerPromotion promo,
  ) {
    return Material(
      color: const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _deletePromotion(chargerId, promo),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(Icons.close, size: 20, color: Colors.red.shade400),
        ),
      ),
    );
  }

  Widget _buildAddPromotionButton(String chargerId) {
    return OutlinedButton.icon(
      onPressed: () => _openCreatePromotionForm(chargerId),
      style: OutlinedButton.styleFrom(
        foregroundColor: _muted,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        'Add promotion',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPromotionsFooter() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.local_offer_outlined, size: 16, color: _muted),
        const Padding(padding: EdgeInsets.only(left: 8)),
        const Expanded(
          child: Text(
            'Active promotions appear on your charger listing. '
            'VoltShare takes no commission on partner deals.',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          ),
        ),
      ],
    );
  }

  String _cardSubtitle(Charger charger) {
    final parts = <String>[
      charger.powerLabel,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      '฿${_trimNum(charger.pricePerKwh)}/kWh',
    ];
    return parts.join(' · ');
  }

  static String _trimNum(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _formatMoney(int value) {
    final str = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}



/// Callback used by [_CreatePromotionSheet] to persist a new promotion. Returns
/// the created row so the sheet can hand it back to the dashboard.
typedef _CreatePromotionCallback = Future<ChargerPromotion> Function({
  required String title,
  required String description,
  DateTime? validFrom,
  DateTime? validUntil,
  required bool active,
  required String termsAndConditions,
});

/// Bottom-sheet form for creating a new charger promotion.
class _CreatePromotionSheet extends StatefulWidget {
  const _CreatePromotionSheet({required this.onSubmit});

  final _CreatePromotionCallback onSubmit;

  @override
  State<_CreatePromotionSheet> createState() => _CreatePromotionSheetState();
}

class _CreatePromotionSheetState extends State<_CreatePromotionSheet> {
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
    final now = DateTime.now();
    final initial = isFrom
        ? (_validFrom ?? now)
        : (_validUntil ?? _validFrom ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
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

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    setState(() => _showDateErrors = true);
    if (!formValid) return;
    if (_validFrom == null || _validUntil == null) return;
    if (_validUntil!.isBefore(_validFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valid until must be after valid from.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final created = await widget.onSubmit(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        validFrom: _validFrom,
        validUntil: _validUntil,
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

    return Padding(
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
                  decoration: _inputDecoration(
                    'Short details shown to drivers',
                  ),
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
                      ),
                    ),
                    const Padding(padding: EdgeInsets.only(left: 12)),
                    Expanded(
                      child: _buildDateField(
                        label: 'Valid until',
                        value: _validUntil,
                        onTap: () => _pickDate(isFrom: false),
                        required: true,
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
                Container(
                  height: 52,
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
                        ? Container(
                            width: 22,
                            height: 22,
                            child: const CircularProgressIndicator(
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
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
  }) {
    final hasError = required && _showDateErrors && value == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, required: required),
        const Padding(padding: EdgeInsets.only(top: 6)),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                        : ChargerPromotion.formatDate(value),
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
            'Required',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
        ],
      ],
    );
  }
}
