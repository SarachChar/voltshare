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

    return Container(
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
                      style: const TextStyle(fontSize: 14, color: _muted),
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
              Expanded(child: _buildPromotionsButton()),
            ],
          ),
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

  Widget _buildPromotionsButton() {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        foregroundColor: _dark,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.local_offer_outlined, size: 18),
          Padding(padding: EdgeInsets.only(left: 6)),
          Text(
            'Promotions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Padding(padding: EdgeInsets.only(left: 6)),
          Icon(Icons.keyboard_arrow_down, size: 20),
        ],
      ),
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


