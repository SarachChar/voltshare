import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:voltshare_app/models/charger_model.dart';

/// Connector artwork (same SVGs as the add-charger form), tinted with
/// [color]. Falls back to a bolt icon for connector types without artwork.
class ConnectorIcon extends StatelessWidget {
  const ConnectorIcon({
    super.key,
    required this.connectorType,
    required this.color,
    this.size = 28,
  });

  final String connectorType;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = Charger.connectorAssetFor(connectorType);
    if (asset == null) return Icon(Icons.bolt, color: color);
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
