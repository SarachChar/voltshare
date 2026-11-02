import 'package:flutter/material.dart';
import 'package:voltshare_app/components/create_promotion_sheet.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/host_revenue_controller.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/add_charger_screen.dart';
import 'package:voltshare_app/screens/add_station_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';
import 'package:voltshare_app/services/station_service.dart';

/// Host view of one station: its details (with Edit), its chargers (add,
/// edit, on/off toggle, this month's revenue) and its promotions. Calls
/// [onChanged] whenever something the dashboard shows changed (station
/// details, a new charger, a toggled charger), so it can reload its list.
class HostStationScreen extends StatefulWidget {
  const HostStationScreen({
    super.key,
    required this.station,
    this.controller,
    this.chargerController,
    this.revenueController,
    this.openEditStation,
    this.openChargerForm,
    this.onChanged,
  });

  final Station station;
  final StationController? controller;

  /// Status toggle. Defaults to a Supabase-backed controller.
  final ChargerController? chargerController;

  /// This month's per-charger figures. Defaults to Supabase.
  final HostRevenueController? revenueController;

  /// Called after something shown on the dashboard changed.
  final VoidCallback? onChanged;

  /// Opens the add (charger == null) / edit charger flow and returns the
  /// saved charger. Defaults to [AddChargerScreen]; tests override it.
  final Future<Charger?> Function(
    BuildContext context,
    Station station,
    Charger? charger,
    int existingChargerCount,
  )?
  openChargerForm;

  /// Opens the edit flow and returns the saved station (null if cancelled).
  /// Defaults to [AddStationScreen]; tests override it.
  final Future<Station?> Function(BuildContext context, Station station)?
  openEditStation;

  @override
  State<HostStationScreen> createState() => _HostStationScreenState();
}

class _HostStationScreenState extends State<HostStationScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF3F4F6);

  late final StationController _controller =
      widget.controller ?? StationController(StationSupabaseService());

  late final ChargerController _chargerController =
      widget.chargerController ?? ChargerController(ChargerSupabaseService());

  late final HostRevenueController _revenueController =
      widget.revenueController ??
      HostRevenueController(HostRevenueSupabaseService());

  late Station _station = widget.station;

  List<Charger> _chargers = const [];
  bool _isLoadingChargers = true;
  bool _chargersFailed = false;

  /// Charger ids whose status update is in flight (their switch is disabled).
  final Set<String> _togglingStatus = {};

  /// This month's revenue for the host; null until loaded (or on error), in
  /// which case the figures show "–".
  HostRevenue? _revenue;

  List<StationPromotion> _promotions = [];
  bool _isLoadingPromotions = true;
  bool _promotionsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadChargers();
    _loadPromotions();
    _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    try {
      final revenue = await _revenueController.fetchHostRevenue();
      if (!mounted) return;
      setState(() => _revenue = revenue);
    } catch (_) {
      // Figures keep showing "–".
    }
  }

  Future<void> _openChargerForm({Charger? charger}) async {
    final open =
        widget.openChargerForm ??
        (BuildContext context, Station station, Charger? charger, int count) =>
            Navigator.of(context).push<Charger>(
              MaterialPageRoute(
                builder: (_) => AddChargerScreen(
                  station: station,
                  initialCharger: charger,
                  existingChargerCount: count,
                  controller: _chargerController,
                ),
              ),
            );
    final saved = await open(context, _station, charger, _chargers.length);
    if (saved == null || !mounted) return;
    widget.onChanged?.call();
    await _loadChargers();
  }

  /// Flips a live charger between 'available' and 'unavailable'. The switch
  /// moves immediately and rolls back if the update fails.
  Future<void> _toggleChargerStatus(Charger charger, bool isActive) async {
    final previous = charger.status;
    setState(() {
      charger.status = isActive ? 'available' : 'unavailable';
      _togglingStatus.add(charger.id);
    });
    try {
      await _chargerController.updateChargerStatus(
        chargerId: charger.id,
        status: charger.status,
      );
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => charger.status = previous);
      _snack('Could not update charger status: $error');
    } finally {
      if (mounted) setState(() => _togglingStatus.remove(charger.id));
    }
  }

  Future<void> _loadChargers() async {
    setState(() {
      _isLoadingChargers = true;
      _chargersFailed = false;
    });
    try {
      final chargers = await _controller.fetchAllStationChargers(_station.id);
      if (!mounted) return;
      setState(() {
        _chargers = chargers;
        _isLoadingChargers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingChargers = false;
        _chargersFailed = true;
      });
    }
  }

  Future<void> _loadPromotions() async {
    setState(() {
      _isLoadingPromotions = true;
      _promotionsFailed = false;
    });
    try {
      final promos = await _controller.fetchStationPromotions(_station.id);
      if (!mounted) return;
      setState(() {
        // Own a growable copy: toggles / deletes / creates edit it in place.
        _promotions = List.of(promos);
        _isLoadingPromotions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPromotions = false;
        _promotionsFailed = true;
      });
    }
  }

  Future<void> _editStation() async {
    final open =
        widget.openEditStation ??
        (BuildContext context, Station station) =>
            Navigator.of(context).push<Station>(
              MaterialPageRoute(
                builder: (_) => AddStationScreen(
                  initialStation: station,
                  controller: _controller,
                ),
              ),
            );
    final saved = await open(context, _station);
    if (saved == null || !mounted) return;
    setState(() => _station = saved);
    widget.onChanged?.call();
  }

  Future<void> _togglePromotion(StationPromotion promo, bool active) async {
    try {
      final updated = await _controller.togglePromotionStatus(promo.id, active);
      if (!mounted) return;
      setState(() {
        final index = _promotions.indexWhere((p) => p.id == updated.id);
        if (index != -1) _promotions[index] = updated;
      });
    } catch (_) {
      _snack('Failed to update promotion status.');
    }
  }

  Future<void> _deletePromotion(StationPromotion promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete promotion?'),
        content: Text(
          '"${promo.title}" will be removed from your station listing.',
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
      setState(() => _promotions.removeWhere((p) => p.id == promo.id));
    } catch (_) {
      _snack('Failed to delete promotion.');
    }
  }

  Future<void> _openCreatePromotion() async {
    final created = await showModalBottomSheet<StationPromotion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreatePromotionSheet(
        onSubmit:
            ({
              required String title,
              required String description,
              DateTime? validFrom,
              DateTime? validUntil,
              required bool active,
              required String termsAndConditions,
            }) {
              return _controller.createPromotion(
                stationId: _station.id,
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
    setState(() => _promotions.insert(0, created));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ----- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // No PopScope: blocking the pop (canPop: false) also disables the iOS
    // swipe-back gesture. Changes are reported through [onChanged] instead of
    // a pop result, so every way of leaving works.
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _primary,
          onRefresh: () =>
              Future.wait([_loadChargers(), _loadPromotions(), _loadRevenue()]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(),
              const Padding(padding: EdgeInsets.only(top: 16)),
              _buildStationCard(),
              const Padding(padding: EdgeInsets.only(top: 24)),
              _sectionTitle('CHARGERS'),
              const Padding(padding: EdgeInsets.only(top: 10)),
              ..._buildChargers(),
              const Padding(padding: EdgeInsets.only(top: 24)),
              _sectionTitle('PARTNER PROMOTIONS'),
              const Padding(padding: EdgeInsets.only(top: 10)),
              ..._buildPromotions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back, color: _dark),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 16)),
        const Expanded(
          child: Text(
            'My Station',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFDFF7EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.ev_station, color: _primary),
              ),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _station.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (_station.address.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.only(top: 4)),
                      Text(
                        _station.address,
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_station.description.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 12)),
            Text(
              _station.description,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          const Padding(padding: EdgeInsets.only(top: 14)),
          OutlinedButton.icon(
            key: const ValueKey('edit-station'),
            onPressed: _editStation,
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
              'Edit station',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChargers() {
    if (_isLoadingChargers) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(color: _primary)),
        ),
      ];
    }
    if (_chargersFailed) {
      return [
        _messageCard('Could not load the chargers.', retry: _loadChargers),
      ];
    }
    return [
      _buildAddChargerButton(),
      const Padding(padding: EdgeInsets.only(top: 12)),
      if (_chargers.isEmpty)
        _messageCard('No chargers at this station yet.')
      else ...[
        if (_revenue != null) ...[
          Text(
            'Figures for ${monthLabel(_revenue!.month)}',
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const Padding(padding: EdgeInsets.only(top: 8)),
        ],
        for (int i = 0; i < _chargers.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.only(top: 12)),
          _buildChargerCard(_chargers[i]),
        ],
      ],
    ];
  }

  Widget _buildAddChargerButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        key: const ValueKey('add-charger'),
        onPressed: () => _openChargerForm(),
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
          'Add Charger',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildChargerCard(Charger charger) {
    final revenue = _revenue?.forCharger(charger.id);
    String money(double? v) => revenue == null ? '–' : formatBaht(v ?? 0);

    return Container(
      key: ValueKey('host-charger-${charger.id}'),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChargerHeaderRow(charger),
          if (charger.isLive) ...[
            const Padding(padding: EdgeInsets.only(top: 14)),
            Row(
              children: [
                _metric(
                  'SESSIONS',
                  revenue == null ? '–' : '${revenue.sessions}',
                ),
                const Padding(padding: EdgeInsets.only(left: 10)),
                _metric('GROSS', money(revenue?.gross)),
                const Padding(padding: EdgeInsets.only(left: 10)),
                _metric('NET (-15%)', money(revenue?.net)),
              ],
            ),
          ],
          const Padding(padding: EdgeInsets.only(top: 12)),
          OutlinedButton.icon(
            key: ValueKey('edit-charger-${charger.id}'),
            onPressed: () => _openChargerForm(charger: charger),
            style: OutlinedButton.styleFrom(
              foregroundColor: _dark,
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text(
              'Edit',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _bg,
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargerHeaderRow(Charger charger) {
    final specs = [
      charger.powerLabel,
      if (charger.chargerType.isNotEmpty) charger.chargerType,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      '฿${charger.pricePerKwh.toStringAsFixed(2)}/kWh',
    ].join(' · ');
    final isAvailable = charger.status == 'available';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isAvailable
                ? const Color(0xFFDFF7EF)
                : const Color(0xFFF1F2F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.bolt,
            color: isAvailable ? _primary : const Color(0xFF9CA3AF),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                charger.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 2)),
              Text(specs, style: const TextStyle(fontSize: 13, color: _muted)),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 8)),
        // Live chargers get the on/off switch; pending ones show where they
        // are in the approval flow.
        if (charger.isLive)
          Switch.adaptive(
            key: ValueKey('charger-switch-${charger.id}'),
            value: isAvailable,
            activeThumbColor: Colors.white,
            activeTrackColor: _primary,
            onChanged: _togglingStatus.contains(charger.id)
                ? null
                : (value) => _toggleChargerStatus(charger, value),
          )
        else
          _statusBadge(charger.status),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final (String label, Color bg, Color fg) = switch (status) {
      'available' => ('Available', const Color(0xFFEAFBF3), _primary),
      'unavailable' => ('Off', const Color(0xFFF1F2F4), _muted),
      'rejected' => (
        'Rejected',
        const Color(0xFFFDECEC),
        const Color(0xFFB91C1C),
      ),
      'setup' => ('Setup', const Color(0xFFEAF2FF), const Color(0xFF1E3A8A)),
      _ => ('In review', const Color(0xFFEAF2FF), const Color(0xFF1E3A8A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  List<Widget> _buildPromotions() {
    if (_isLoadingPromotions) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(color: _primary)),
        ),
      ];
    }
    if (_promotionsFailed) {
      return [
        _messageCard('Could not load promotions.', retry: _loadPromotions),
      ];
    }
    return [
      for (final promo in _promotions) ...[
        _buildPromotionTile(promo),
        const Padding(padding: EdgeInsets.only(top: 12)),
      ],
      OutlinedButton.icon(
        key: const ValueKey('add-promotion'),
        onPressed: _openCreatePromotion,
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
      ),
      const Padding(padding: EdgeInsets.only(top: 14)),
      const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_offer_outlined, size: 16, color: _muted),
          Padding(padding: EdgeInsets.only(left: 8)),
          Expanded(
            child: Text(
              'Active promotions appear on your station listing. '
              'VoltShare takes no commission on partner deals.',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildPromotionTile(StationPromotion promo) {
    final expired = promo.status.toUpperCase() == 'EXPIRED';
    return Container(
      key: ValueKey('promo-${promo.id}'),
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
              color: _bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
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
                    const Icon(Icons.event_outlined, size: 14, color: _muted),
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
          if (expired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'EXPIRED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            Switch.adaptive(
              key: ValueKey('promo-switch-${promo.id}'),
              value: promo.isActive,
              activeThumbColor: Colors.white,
              activeTrackColor: _primary,
              onChanged: (value) => _togglePromotion(promo, value),
            ),
          const Padding(padding: EdgeInsets.only(left: 4)),
          Material(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _deletePromotion(promo),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.close, size: 20, color: Colors.red.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _muted,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _messageCard(String text, {Future<void> Function()? retry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          if (retry != null)
            TextButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
