import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:voltshare_app/models/charger_model.dart';

/// Shared external-map navigation helpers.
///
/// Both the home map popup and the charger details screen let the user open a
/// map app to get directions to a charger. This keeps that logic in one place:
/// a bottom sheet to pick the map app, the launch logic for each app, and a
/// reusable [NavigateButton] for the UI.
const Color _navPrimary = Color(0xFF10B981);

/// Shows a bottom sheet to pick which map app to navigate with, then opens the
/// chosen app with directions to [charger].
void showChargerNavigationOptions(BuildContext context, Charger charger) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Navigate with',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.map, color: _navPrimary),
              title: const Text('Google Maps'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openInGoogleMaps(context, charger);
              },
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined, color: _navPrimary),
              title: const Text('Apple Maps'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openInAppleMaps(context, charger);
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _openInGoogleMaps(BuildContext context, Charger charger) async {
  final lat = charger.latitude;
  final lng = charger.longitude;
  // Prefer the Google Maps app scheme; fall back to the universal https URL.
  final appUri = Uri.parse(
    'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
  );
  final webUri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
  );

  if (await canLaunchUrl(appUri)) {
    await launchUrl(appUri);
  } else if (!await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
    if (!context.mounted) return;
    _showNavError(context);
  }
}

Future<void> _openInAppleMaps(BuildContext context, Charger charger) async {
  final lat = charger.latitude;
  final lng = charger.longitude;
  final appUri = Uri.parse('maps://?daddr=$lat,$lng');
  final webUri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng');

  if (await canLaunchUrl(appUri)) {
    await launchUrl(appUri);
  } else if (!await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
    if (!context.mounted) return;
    _showNavError(context);
  }
}

void _showNavError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Could not open a map app.'),
      backgroundColor: Colors.red.shade600,
    ),
  );
}

/// A small square "navigate" icon button that opens the map-app picker for
/// [charger]. Used beside primary action buttons on the home popup and the
/// charger details screen.
class NavigateButton extends StatelessWidget {
  const NavigateButton({super.key, required this.charger, this.size = 54});

  final Charger charger;

  /// Width/height of the square button.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: _navPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 2 >= 28 ? 28 : 16),
      ),
      child: IconButton(
        onPressed: () => showChargerNavigationOptions(context, charger),
        icon: const Icon(Icons.directions, color: _navPrimary),
        tooltip: 'Navigate',
      ),
    );
  }
}
