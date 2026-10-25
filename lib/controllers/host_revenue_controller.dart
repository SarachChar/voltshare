import 'package:voltshare_app/models/host_revenue_model.dart';
import 'package:voltshare_app/services/host_revenue_service.dart';

/// Thin controller over [HostRevenueService] (Model → Service → Controller).
class HostRevenueController {
  final HostRevenueService service;

  HostRevenueController(this.service);

  Future<HostRevenue> fetchHostRevenue({DateTime? month}) =>
      service.getHostRevenue(month: month);
}
