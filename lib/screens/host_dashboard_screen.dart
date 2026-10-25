import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/host_revenue_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/screens/add_charger_screen.dart';
import 'package:voltshare_app/screens/host_revenue_tab.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';

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
  late Future<List<Charger>> _pendingChargersFuture;

  /// On/off state for each charger's toggle, keyed by charger id. Seeded from
  /// the charger's `status` and updated optimistically when the host flips a
  /// switch (the change is persisted via the controller).
  final Map<String, bool> _activeById = {};

  /// Charger ids whose status update is currently in flight. Their switch is
  /// disabled until the request settles to avoid overlapping toggles.
  final Set<String> _togglingStatus = {};

  /// Which charger cards have their promotions panel expanded.
  final Set<String> _expandedPromotions = {};

  /// Loaded promotions per charger id, kept in memory once fetched so toggles
  /// and newly created promotions are reflected without a full reload.
  final Map<String, List<ChargerPromotion>> _promotionsById = {};

  /// Charger ids whose promotions are currently loading.
  final Set<String> _loadingPromotions = {};

  final HostRevenueController _revenueController =
      HostRevenueController(HostRevenueSupabaseService());

  /// Current month's revenue, for the header stats and the per-charger
  /// figures on the My Chargers cards. Null until loaded (or on error).
  HostRevenue? _currentRevenue;

  /// The current month, shown next to the header / card figures so the host
  /// knows which month they cover.
  final DateTime _currentMonth = firstOfMonth(DateTime.now());

  String get _totalEarned =>
      _currentRevenue == null ? '–' : formatBaht(_currentRevenue!.summary.net);

  String get _sessions => _currentRevenue == null
      ? '–'
      : '${_currentRevenue!.summary.sessions}';

  Future<void> _loadCurrentRevenue() async {
    try {
      final revenue = await _revenueController.fetchHostRevenue();
      if (!mounted) return;
      setState(() => _currentRevenue = revenue);
    } catch (_) {
      // Header / cards keep showing "–".
    }
  }

  /// The host's loaded chargers (status 'available' / 'unavailable'), kept in
  /// state so the header's "ACTIVE" stat can be derived from them. Populated
  /// when the My Chargers tab finishes loading.
  List<Charger> _myChargers = const <Charger>[];

  /// Number of currently-active chargers, shown in the header. A charger counts
  /// as active when its effective status is 'available' — taking into account
  /// any in-session toggle override in [_activeById] so flipping a switch
  /// updates the stat immediately.
  String get _active {
    final count = _myChargers.where((charger) {
      final overridden = _activeById[charger.id];
      final isActive = overridden ?? (charger.status != 'unavailable');
      return isActive;
    }).length;
    return '$count';
  }

  @override
  void initState() {
    super.initState();
    _chargersFuture = _loadChargers();
    _pendingChargersFuture = _loadPendingChargers();
    _loadCurrentRevenue();
  }

  Future<List<Charger>> _loadChargers() {
    final hostId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final future = _controller.fetchChargersByHost(hostId);
    // Cache the result in state so the header's "ACTIVE" stat can be derived
    // from it. Done here (rather than in the FutureBuilder's builder) so we
    // only setState after the load settles, not mid-build.
    future.then((chargers) {
      if (!mounted) return;
      setState(() => _myChargers = chargers);
    }).catchError((_) {
      // Load errors are surfaced by the FutureBuilder; the stat just stays
      // at its last known value.
    });
    return future;
  }

  Future<List<Charger>> _loadPendingChargers() {
    final hostId = Supabase.instance.client.auth.currentUser?.id ?? '';
    return _controller.fetchPendingChargersByHost(hostId);
  }

  /// Pull-to-refresh for the My Chargers tab. Starts a fresh load, points the
  /// FutureBuilder at it, and awaits it so the refresh spinner stays until the
  /// data settles. Also clears the per-charger toggle overrides so the
  /// switches re-seed from the freshly loaded statuses.
  Future<void> _refreshChargers() async {
    _loadCurrentRevenue();
    final future = _loadChargers();
    setState(() {
      _chargersFuture = future;
      _activeById.clear();
    });
    try {
      await future;
    } catch (_) {
      // Errors surface through the FutureBuilder; swallow here so the
      // RefreshIndicator just finishes.
    }
  }

  /// Pull-to-refresh for the Pending tab. Mirrors [_refreshChargers].
  Future<void> _refreshPendingChargers() async {
    final future = _loadPendingChargers();
    setState(() => _pendingChargersFuture = future);
    try {
      await future;
    } catch (_) {
      // Errors surface through the FutureBuilder.
    }
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
                _buildPendingTab(),
                const HostRevenueTab(),
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
              child: Text(
                'Earned & sessions: ${monthLabel(_currentMonth)}',
                style: const TextStyle(
                  color: Color(0xFFD1FAE5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 8)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Earned gets the most room (fits "฿999,999.99" on one
                  // line); sessions / active only need a few digits.
                  _buildStat('TOTAL EARNED', _totalEarned, flex: 5),
                  _buildStat('SESSIONS', _sessions, flex: 2),
                  _buildStat('ACTIVE', _active, flex: 2),
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

  Widget _buildStat(String label, String value, {int flex = 1}) {
    return Expanded(
      flex: flex,
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
          // Never wraps: shrinks to fit if the value is still too wide
          // (narrow screens / large text settings).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
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
        return RefreshIndicator(
          color: _primary,
          onRefresh: _refreshChargers,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildAddChargerButton(),
              const Padding(padding: EdgeInsets.only(top: 16)),
              for (final charger in chargers) ...[
                _buildChargerCard(charger),
                const Padding(padding: EdgeInsets.only(top: 16)),
              ],
            ],
          ),
        );
      },
    );
  }

  // ----- Pending tab ----------------------------------------------------------

  Widget _buildPendingTab() {
    return FutureBuilder<List<Charger>>(
      future: _pendingChargersFuture,
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
                'Failed to load your pending chargers.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          );
        }

        final chargers = snapshot.data ?? const <Charger>[];
        return RefreshIndicator(
          color: _primary,
          onRefresh: _refreshPendingChargers,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildApprovalBanner(),
              const Padding(padding: EdgeInsets.only(top: 16)),
              _buildApprovalStepsCard(),
              const Padding(padding: EdgeInsets.only(top: 16)),
              if (chargers.isEmpty)
                _buildPendingEmpty()
              else
                for (final charger in chargers) ...[
                  _buildPendingCard(charger),
                  const Padding(padding: EdgeInsets.only(top: 16)),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildApprovalBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋', style: TextStyle(fontSize: 22)),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Approval Required',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
                Padding(padding: EdgeInsets.only(top: 4)),
                Text(
                  'New chargers are reviewed by our team and require '
                  'physical device setup before going live.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalStepsCard() {
    const steps = [
      'Request submitted',
      'Admin reviews charger info',
      'Physical device setup & verification',
      'Charger goes live on VoltShare',
    ];
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'APPROVAL STEPS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _headerDark,
              letterSpacing: 0.6,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          for (int i = 0; i < steps.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFF7EF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBBF0DC)),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _headerDark,
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.only(left: 12)),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      fontSize: 15,
                      color: _dark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (i != steps.length - 1)
              const Padding(padding: EdgeInsets.only(top: 14)),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      alignment: Alignment.center,
      child: Text(
        'No chargers are awaiting approval.',
        style: TextStyle(color: Colors.grey.shade600),
      ),
    );
  }

  Widget _buildPendingCard(Charger charger) {
    final progress = _PendingProgress.of(charger.status);

    return Container(
      padding: const EdgeInsets.all(16),
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
                child: const Icon(Icons.bolt, color: _primary),
              ),
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
              const Padding(padding: EdgeInsets.only(left: 8)),
              _buildPendingBadge(progress),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          _buildProgressBar(progress),
          const Padding(padding: EdgeInsets.only(top: 8)),
          Text(
            progress.stepLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 12)),
          _buildPendingNote(progress),
          if (charger.createdAt != null) ...[
            const Padding(padding: EdgeInsets.only(top: 12)),
            Text(
              'Submitted ${_formatDate(charger.createdAt!)}',
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingBadge(_PendingProgress progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: progress.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(progress.badgeIcon, size: 16, color: progress.accent),
          const Padding(padding: EdgeInsets.only(left: 6)),
          Text(
            progress.badgeLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: progress.accent,
            ),
          ),
        ],
      ),
    );
  }

  /// The 4-segment progress bar. Completed segments are green, the current
  /// (active) segment uses the status accent colour (orange, or red when the
  /// charger was rejected), and upcoming segments are a faint green.
  Widget _buildProgressBar(_PendingProgress progress) {
    return Row(
      children: [
        for (int i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: progress.segmentColor(i),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i != 3) const Padding(padding: EdgeInsets.only(left: 6)),
        ],
      ],
    );
  }

  Widget _buildPendingNote(_PendingProgress progress) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: progress.noteBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(progress.noteIcon, size: 18, color: progress.accent),
          const Padding(padding: EdgeInsets.only(left: 10)),
          Expanded(
            child: Text(
              progress.note,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: progress.noteText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _openAddCharger() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddChargerScreen()),
    );
    // A charger was created — it starts in 'review', so reload both lists.
    if (created == true && mounted) {
      setState(() {
        _chargersFuture = _loadChargers();
        _pendingChargersFuture = _loadPendingChargers();
      });
    }
  }

  Future<void> _openEditCharger(Charger charger) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddChargerScreen(initialCharger: charger),
      ),
    );
    // Edits were saved — reload the list so the card reflects them.
    if (saved == true && mounted) {
      setState(() {
        _chargersFuture = _loadChargers();
      });
    }
  }

  Widget _buildAddChargerButton() {
    return Container(
      height: 64,
      child: ElevatedButton.icon(
        onPressed: _openAddCharger,
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
    // Current month's figures for this charger (zeros until loaded).
    final revenue = _currentRevenue?.forCharger(charger.id);
    String money(double? v) => revenue == null ? '–' : formatBaht(v ?? 0);

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
                    _buildMetric(
                      'SESSIONS',
                      revenue == null ? '–' : '${revenue.sessions}',
                    ),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    _buildMetric('GROSS', money(revenue?.gross)),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    _buildMetric('NET (-15%)', money(revenue?.net)),
                  ],
                ),
                const Padding(padding: EdgeInsets.only(top: 12)),
                Row(
                  children: [
                    Expanded(child: _buildEditButton(charger)),
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
      onChanged: _togglingStatus.contains(chargerId)
          ? null
          : (value) => _toggleChargerStatus(chargerId, value),
    );
  }

  /// Flips a charger's availability status in the backend. [isActive] true
  /// means the switch was turned on → status 'available'; false → 'unavailable'.
  ///
  /// The UI is updated optimistically so the switch moves immediately, then
  /// rolled back if the update fails.
  Future<void> _toggleChargerStatus(String chargerId, bool isActive) async {
    setState(() {
      _activeById[chargerId] = isActive;
      _togglingStatus.add(chargerId);
    });

    try {
      await _controller.updateChargerStatus(
        chargerId: chargerId,
        status: isActive ? 'available' : 'unavailable',
      );
    } catch (error) {
      // Roll the switch back to its previous position and let the host know.
      if (!mounted) return;
      setState(() => _activeById[chargerId] = !isActive);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update charger status: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _togglingStatus.remove(chargerId));
      }
    }
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

  Widget _buildEditButton(Charger charger) {
    return OutlinedButton.icon(
      onPressed: () => _openEditCharger(charger),
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
    final expired = promo.status.toUpperCase() == 'EXPIRED';
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
          if (expired)
            _buildExpiredBadge()
          else
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

  /// Shown in place of the on/off switch when a promotion has expired. The
  /// status is read-only here — expiry is driven by `valid_until` on the
  /// backend, so there's nothing to toggle.
  Widget _buildExpiredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
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
}

/// View-model that maps a pending charger's `status` onto the 4-step approval
/// flow (Submitted → Review → Setup → Live) and the colours/labels/notes the
/// Pending card renders. The active step is highlighted in orange, except when
/// the charger was rejected, where the Review step turns red.
class _PendingProgress {
  _PendingProgress._({
    required this.activeStep,
    required this.rejected,
    required this.badgeLabel,
    required this.badgeIcon,
    required this.stepLabel,
    required this.note,
  });

  static const Color _green = Color(0xFF10B981);
  static const Color _greenFaint = Color(0xFFBBF0DC);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFEF4444);

  /// 0-based index of the current step in the 4-step flow.
  final int activeStep;
  final bool rejected;
  final String badgeLabel;
  final IconData badgeIcon;
  final String stepLabel;
  final String note;

  /// Builds the view-model for a charger status. Unknown statuses fall back to
  /// the review step so the card still renders sensibly.
  factory _PendingProgress.of(String status) {
    switch (status) {
      case 'setup':
        return _PendingProgress._(
          activeStep: 2,
          rejected: false,
          badgeLabel: 'Device Setup',
          badgeIcon: Icons.error_outline,
          stepLabel: 'Step 3 of 4 · Device Setup',
          note: 'Admin approved — awaiting physical device setup & '
              'inspection.',
        );
      case 'rejected':
        return _PendingProgress._(
          activeStep: 1,
          rejected: true,
          badgeLabel: 'Rejected',
          badgeIcon: Icons.cancel_outlined,
          stepLabel: 'Step 2 of 4 · Review',
          note: 'Your charger info was rejected.',
        );
      case 'review':
      default:
        return _PendingProgress._(
          activeStep: 1,
          rejected: false,
          badgeLabel: 'In Review',
          badgeIcon: Icons.hourglass_empty,
          stepLabel: 'Step 2 of 4 · Review',
          note: 'Our team is reviewing your charger info. This usually takes '
              '1–2 business days.',
        );
    }
  }

  /// Accent colour for the badge, note icon and active progress segment.
  Color get accent => rejected ? _red : _orange;

  Color get badgeBg =>
      rejected ? const Color(0xFFFDECEC) : const Color(0xFFEAF2FF);

  Color get noteBg =>
      rejected ? const Color(0xFFFDECEC) : const Color(0xFFEAF2FF);

  Color get noteText =>
      rejected ? const Color(0xFFB91C1C) : const Color(0xFF1E3A8A);

  IconData get noteIcon =>
      rejected ? Icons.cancel_outlined : Icons.check_circle_outline;

  /// Colour of progress segment [index]: completed steps are green, the active
  /// step uses the accent colour, and upcoming steps are a faint green.
  Color segmentColor(int index) {
    if (index < activeStep) return _green;
    if (index == activeStep) return accent;
    return _greenFaint;
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
      // The date picker returns midnight of the chosen day; push validUntil
      // to the last instant of that day so the promotion stays valid for
      // the whole day the host picked, not just until 00:00.
      final until = _validUntil!;
      final validUntilEndOfDay = DateTime(
        until.year,
        until.month,
        until.day,
        23,
        59,
        59,
      );

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
