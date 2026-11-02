import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/services/charger_service.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';

/// [ChargerService] fake for the host screens: records status updates and
/// can be told to fail. Any other call throws.
class FakeChargerService implements ChargerService {
  final List<String> statusUpdates = [];
  Object? statusError;

  @override
  Future<Charger> updateChargerStatus({
    required String chargerId,
    required String status,
  }) async {
    statusUpdates.add('$chargerId $status');
    if (statusError != null) throw statusError!;
    return Charger(chargerId, 'x', 'AC', 'Type 2', 7, 7, status, 0, 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// [HostRevenueService] fake returning a fixed [revenue] (or throwing).
class FakeHostRevenueService implements HostRevenueService {
  FakeHostRevenueService(this.revenue);

  HostRevenue? revenue;

  @override
  Future<HostRevenue> getHostRevenue({DateTime? month}) async {
    final value = revenue;
    if (value == null) throw Exception('no revenue');
    return value;
  }
}
