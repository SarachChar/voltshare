/// Host revenue figures from the `host_revenue` RPC. Amounts are THB from
/// paid charging bills only (booking fees excluded); a session counts in the
/// month it stopped charging (Bangkok time).
class HostRevenue {
  /// First day of the summarised month.
  final DateTime month;
  final RevenueSummary summary;

  /// Selected month, every live charger of the host (0 if no revenue).
  final List<ChargerRevenue> byCharger;

  /// 6 latest months up to the current month, oldest first.
  final List<MonthlyRevenue> monthly;

  HostRevenue({
    required this.month,
    required this.summary,
    required this.byCharger,
    required this.monthly,
  });

  factory HostRevenue.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => (json[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return HostRevenue(
      month: _parseMonth(json['month']) ?? firstOfMonth(DateTime.now()),
      summary: RevenueSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? {}),
      ),
      byCharger: rows('by_charger').map(ChargerRevenue.fromJson).toList(),
      monthly: rows('monthly').map(MonthlyRevenue.fromJson).toList(),
    );
  }

  /// Revenue of one charger in [month], or zeros if it isn't listed.
  ChargerRevenue forCharger(String chargerId) =>
      byCharger.where((c) => c.chargerId == chargerId).firstOrNull ??
      ChargerRevenue(chargerId: chargerId, name: '');
}

class RevenueSummary {
  final double gross;
  final double net;
  final double platformFee;
  final int sessions;

  /// Paid booking fees for bookings starting this month (host keeps 100%,
  /// cancelled bookings included). Not part of [gross] / [net].
  final double reservationFee;
  final int reservationCount;

  const RevenueSummary({
    this.gross = 0,
    this.net = 0,
    this.platformFee = 0,
    this.sessions = 0,
    this.reservationFee = 0,
    this.reservationCount = 0,
  });

  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
        gross: _num(json['gross']),
        net: _num(json['net']),
        platformFee: _num(json['platform_fee']),
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        reservationFee: _num(json['reservation_fee']),
        reservationCount: (json['reservation_count'] as num?)?.toInt() ?? 0,
      );
}

class ChargerRevenue {
  final String chargerId;
  final String name;
  final int sessions;
  final double gross;
  final double net;

  ChargerRevenue({
    required this.chargerId,
    required this.name,
    this.sessions = 0,
    this.gross = 0,
    this.net = 0,
  });

  factory ChargerRevenue.fromJson(Map<String, dynamic> json) => ChargerRevenue(
        chargerId: json['charger_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        gross: _num(json['gross']),
        net: _num(json['net']),
      );
}

class MonthlyRevenue {
  final DateTime month;
  final double gross;
  final double net;

  MonthlyRevenue({required this.month, this.gross = 0, this.net = 0});

  factory MonthlyRevenue.fromJson(Map<String, dynamic> json) => MonthlyRevenue(
        month: _parseMonth(json['month']) ?? firstOfMonth(DateTime.now()),
        gross: _num(json['gross']),
        net: _num(json['net']),
      );
}

// --- Helpers ------------------------------------------------------------------

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

DateTime? _parseMonth(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? null : DateTime(d.year, d.month);
}

DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month);

/// The current month and the 5 before it, newest first.
List<DateTime> lastSixMonths([DateTime? now]) {
  final base = firstOfMonth(now ?? DateTime.now());
  return [for (int i = 0; i < 6; i++) DateTime(base.year, base.month - i)];
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Jul".
String monthShortLabel(DateTime d) => _monthNames[d.month - 1];

/// "Jul 2026".
String monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "฿10,760" for whole baht, "฿79.84" otherwise.
String formatBaht(double value) {
  final rounded = (value * 100).round();
  final whole = rounded ~/ 100;
  final cents = (rounded % 100).abs();
  final str = whole.abs().toString();
  final buffer = StringBuffer(whole < 0 ? '-฿' : '฿');
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  if (cents != 0) buffer.write('.${cents.toString().padLeft(2, '0')}');
  return buffer.toString();
}
