import 'package:flutter/material.dart';

import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/models/station_model.dart';

/// Top card of the booking flow (Reserve and Review screens): which station,
/// which charger in it, the charger's specs and price, and the address.
class BookingChargerCard extends StatelessWidget {
  const BookingChargerCard({
    super.key,
    required this.station,
    required this.charger,
  });

  final Station station;
  final Charger charger;

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    final specParts = <String>[
      charger.name,
      charger.powerLabel,
      if (charger.chargerType.isNotEmpty) charger.chargerType,
      if (charger.connectorType.isNotEmpty) charger.connectorType,
      '฿${charger.pricePerKwh.toStringAsFixed(2)}/kWh',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            station.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            specParts.join(' · '),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _dark,
            ),
          ),
          if (station.address.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 6)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const Padding(padding: EdgeInsets.only(left: 4)),
                Expanded(
                  child: Text(
                    station.address,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
