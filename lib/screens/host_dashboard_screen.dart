import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/charger_controller.dart';
import 'package:voltshare_app/controllers/host_revenue_controller.dart';
import 'package:voltshare_app/controllers/station_controller.dart';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/models/station_model.dart';
import 'package:voltshare_app/screens/add_station_screen.dart';
import 'package:voltshare_app/screens/host_revenue_tab.dart';
import 'package:voltshare_app/screens/host_station_screen.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';
import 'package:voltshare_app/services/station_service.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({
    super.key,
    this.controller,
    this.stationController,
  });

  /// Still used by the Pending tab (pending chargers by host).
  final ChargerController? controller;

  /// Loads the host's stations for the My Stations tab.
  final StationController? stationController;

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
  late final StationController _stationController =
      widget.stationController ?? StationController(StationSupabaseService());
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  late Future<List<Station>> _stationsFuture;
  late Future<List<Charger>> _pendingChargersFuture;

  final HostRevenueController _revenueController =
      HostRevenueController(HostRevenueSupabaseService());

  /// Current month's revenue, for the header stats. Null until loaded (or on
  /// error).
  HostRevenue? _currentRevenue;

  /// The current month, shown next to the header figures so the host knows
  /// which month they cover.
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
      // Header keeps showing "–".
    }
  }

  /// The host's loaded stations, kept in state so the header's "ACTIVE" stat
  /// can be derived from them.
  List<Station> _myStations = const <Station>[];

  /// Available chargers across all of the host's stations.
  String get _active =>
      '${_myStations.fold<int>(0, (sum, s) => sum + s.availableCount)}';

  String get _hostId => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _stationsFuture = _loadStations();
    _pendingChargersFuture = _loadPendingChargers();
    _loadCurrentRevenue();
  }

  Future<List<Station>> _loadStations() {
    final future = _stationController.fetchStationsByHost(_hostId);
    // Cache the result for the header stat once the load settles (not
    // mid-build inside the FutureBuilder).
    future.then((stations) {
      if (!mounted) return;
      setState(() => _myStations = stations);
    }).catchError((_) {
      // Load errors are surfaced by the FutureBuilder.
    });
    return future;
  }

  Future<List<Charger>> _loadPendingChargers() {
    return _controller.fetchPendingChargersByHost(_hostId);
  }

  /// Pull-to-refresh for My Stations; also refreshes the header revenue.
  Future<void> _refreshStations() async {
    _loadCurrentRevenue();
    final future = _loadStations();
    setState(() => _stationsFuture = future);
    try {
      await future;
    } catch (_) {
      // Errors surface through the FutureBuilder.
    }
  }

  /// Pull-to-refresh for the Pending tab.
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
                _buildMyStationsTab(),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HOST MODE',
                          style: TextStyle(
                            color: Color(0xFFB9F5DE),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        Padding(padding: EdgeInsets.only(top: 2)),
                        Text(
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
        Tab(text: 'My Stations'),
        Tab(text: 'Pending'),
        Tab(text: 'Revenue'),
      ],
    );
  }

  // ----- My Stations tab ------------------------------------------------------

  Widget _buildMyStationsTab() {
    return FutureBuilder<List<Station>>(
      future: _stationsFuture,
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
                'Failed to load your stations.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          );
        }

        final stations = snapshot.data ?? const <Station>[];
        return RefreshIndicator(
          color: _primary,
          onRefresh: _refreshStations,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildAddStationButton(),
              const Padding(padding: EdgeInsets.only(top: 16)),
              if (stations.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'You have no stations yet.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                for (final station in stations) ...[
                  _buildStationCard(station),
                  const Padding(padding: EdgeInsets.only(top: 16)),
                ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAddStation() async {
    final created = await Navigator.of(context).push<Station>(
      MaterialPageRoute(
        builder: (_) => AddStationScreen(controller: _stationController),
      ),
    );
    if (created != null && mounted) _refreshStations();
  }

  Future<void> _openStation(Station station) async {
    var changed = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HostStationScreen(
          station: station,
          controller: _stationController,
          onChanged: () => changed = true,
        ),
      ),
    );
    // Reload after any way of leaving (button, swipe, system back).
    if (changed && mounted) _refreshStations();
  }

  Widget _buildAddStationButton() {
    return SizedBox(
      height: 64,
      child: ElevatedButton.icon(
        key: const ValueKey('add-station'),
        onPressed: _openAddStation,
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
          'Add New Station',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildStationCard(Station station) {
    final hasLive = station.availableCount > 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: ValueKey('station-${station.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openStation(station),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasLive
                      ? const Color(0xFFDFF7EF)
                      : const Color(0xFFF1F2F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.ev_station,
                  color: hasLive ? _primary : const Color(0xFF9CA3AF),
                ),
              ),
              const Padding(padding: EdgeInsets.only(left: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _dark,
                      ),
                    ),
                    if (station.address.isNotEmpty) ...[
                      const Padding(padding: EdgeInsets.only(top: 4)),
                      Text(
                        station.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                    ],
                    const Padding(padding: EdgeInsets.only(top: 6)),
                    Text(
                      station.hostCountsLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📋', style: TextStyle(fontSize: 22)),
          Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
