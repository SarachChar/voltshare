import 'package:flutter/material.dart';

import 'package:voltshare_app/controllers/host_revenue_controller.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';

/// Host dashboard → Revenue tab.
///
///   1. Month dropdown (current month + 5 before).
///   2. Gross / Net payout / Reservation fee / Sessions for the picked month.
///   3. By Charger for the picked month.
///   4. Monthly Revenue chart: the 6 latest months (independent of the
///      picker; tapping a bar picks that month).
///
/// Data: `host_revenue` RPC (paid charging bills only, booking fee excluded).
class HostRevenueTab extends StatefulWidget {
  const HostRevenueTab({super.key, this.controller});

  final HostRevenueController? controller;

  @override
  State<HostRevenueTab> createState() => _HostRevenueTabState();
}

class _HostRevenueTabState extends State<HostRevenueTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _primary = Color(0xFF10B981);
  static const Color _navy = Color(0xFF0F1D3A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFC8EDE0);
  static const Color _grossBar = Color(0xFFD1EDE4);

  late final HostRevenueController _controller = widget.controller ??
      HostRevenueController(HostRevenueSupabaseService());

  final List<DateTime> _months = lastSixMonths();
  late DateTime _selected = _months.first;

  HostRevenue? _data;
  bool _isLoading = true;
  bool _hasError = false;

  /// Ignores responses from an older request when the month changes quickly.
  int _requestId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final data = await _controller.fetchHostRevenue(month: _selected);
      if (!mounted || id != _requestId) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _select(DateTime month) {
    if (month == _selected) return;
    setState(() => _selected = month);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _data;
    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildMonthPicker(),
          const Padding(padding: EdgeInsets.only(top: 16)),
          if (data == null && _isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator(color: _primary)),
            )
          else if (data == null || _hasError)
            _buildError()
          else ...[
            // Fade the month-specific parts while the new month loads.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _isLoading ? 0.4 : 1,
              child: Column(
                children: [
                  _buildSummaryGrid(data.summary),
                  const Padding(padding: EdgeInsets.only(top: 16)),
                  _buildByCharger(data.byCharger),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 16)),
            _buildMonthlyChart(data.monthly),
          ],
        ],
      ),
    );
  }

  // --- Month picker -----------------------------------------------------------

  Widget _buildMonthPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: _selected,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down, color: _navy),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
          items: [
            for (final month in _months)
              DropdownMenuItem(
                value: month,
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 20,
                      color: _primary,
                    ),
                    const Padding(padding: EdgeInsets.only(left: 10)),
                    Text(
                      month == _months.first
                          ? '${monthLabel(month)} (This month)'
                          : monthLabel(month),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (month) {
            if (month != null) _select(month);
          },
        ),
      ),
    );
  }

  // --- Summary ------------------------------------------------------------------

  Widget _buildSummaryGrid(RevenueSummary s) {
    final month = monthLabel(_selected);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                label: 'GROSS REVENUE',
                value: formatBaht(s.gross),
                caption: month,
                background: Colors.white,
                border: _border,
                valueColor: _navy,
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 12)),
            Expanded(
              child: _statCard(
                label: 'NET PAYOUT',
                value: formatBaht(s.net),
                caption: 'After 15% fee',
                background: const Color(0xFFE6FAF4),
                border: _border,
                valueColor: _primary,
              ),
            ),
          ],
        ),
        const Padding(padding: EdgeInsets.only(top: 12)),
        Row(
          children: [
            Expanded(
              child: _statCard(
                label: 'RESERVATION FEE',
                value: formatBaht(s.reservationFee),
                caption: '${s.reservationCount} '
                    'booking${s.reservationCount == 1 ? '' : 's'}',
                background: const Color(0xFFFEF3C7),
                border: const Color(0xFFFDE68A),
                valueColor: const Color(0xFF92400E),
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 12)),
            Expanded(
              child: _statCard(
                label: 'TOTAL SESSIONS',
                value: '${s.sessions}',
                caption: 'All chargers',
                background: const Color(0xFFDBEAFE),
                border: const Color(0xFFBFDBFE),
                valueColor: const Color(0xFF1E40AF),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String caption,
    required Color background,
    required Color border,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              color: _muted,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 8)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(caption, style: const TextStyle(fontSize: 14, color: _muted)),
        ],
      ),
    );
  }

  // --- By charger --------------------------------------------------------------

  Widget _buildByCharger(List<ChargerRevenue> rows) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'By Charger',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                monthLabel(_selected),
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 8)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No live chargers yet.',
                style: TextStyle(fontSize: 15, color: _muted),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: _border),
              _chargerRow(rows[i]),
            ],
        ],
      ),
    );
  }

  Widget _chargerRow(ChargerRevenue r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.bolt_outlined, color: _primary, size: 22),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name.isNotEmpty ? r.name : 'Charger',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 2)),
                Text(
                  '${r.sessions} session${r.sessions == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 14, color: _muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatBaht(r.net),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 2)),
              Text(
                'gross ${formatBaht(r.gross)}',
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Monthly chart -----------------------------------------------------------

  Widget _buildMonthlyChart(List<MonthlyRevenue> months) {
    const chartHeight = 130.0;
    final maxValue = months.fold<double>(
      0,
      (m, e) => e.gross > m ? e.gross : m,
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Monthly Revenue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              _legend(_grossBar, 'Gross'),
              const Padding(padding: EdgeInsets.only(left: 12)),
              _legend(_primary, 'Net'),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 20)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(child: _monthBars(m, maxValue, chartHeight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthBars(MonthlyRevenue m, double maxValue, double chartHeight) {
    double h(double v) =>
        maxValue <= 0 ? 0 : (v / maxValue * chartHeight).clamp(2, chartHeight);
    final selected = m.month == _selected;
    final canSelect = _months.contains(m.month);

    return Semantics(
      button: canSelect,
      selected: selected,
      label: '${monthLabel(m.month)}: gross ${formatBaht(m.gross)}, '
          'net ${formatBaht(m.net)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canSelect ? () => _select(m.month) : null,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  height: chartHeight,
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _bar(h(m.gross), _grossBar)),
                      const Padding(padding: EdgeInsets.only(left: 3)),
                      Expanded(child: _bar(h(m.net), _primary)),
                    ],
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 8)),
                Text(
                  monthShortLabel(m.month),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? _navy : _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 6)),
        Text(label, style: const TextStyle(fontSize: 14, color: _muted)),
      ],
    );
  }

  // --- Shared -------------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 44, color: Colors.grey.shade400),
          const Padding(padding: EdgeInsets.only(top: 12)),
          Text(
            'Couldn\'t load revenue. Pull to try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
