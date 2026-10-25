import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/host_revenue_model.dart';

abstract class HostRevenueService {
  /// Revenue of the signed-in host for the month containing [month]
  /// (current month when null), plus the 6-month chart data.
  Future<HostRevenue> getHostRevenue({DateTime? month});
}

class HostRevenueSupabaseService implements HostRevenueService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<HostRevenue> getHostRevenue({DateTime? month}) async {
    final m = month == null ? null : firstOfMonth(month);
    final data = await _client.rpc(
      'host_revenue',
      params: {
        'p_month': m == null
            ? null
            : '${m.year}-${m.month.toString().padLeft(2, '0')}-01',
      },
    );
    return HostRevenue.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
