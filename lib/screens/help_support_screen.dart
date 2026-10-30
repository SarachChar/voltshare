import 'package:flutter/material.dart';

/// Help & Support page reached from the Profile menu.
///
/// MOCK: read-only placeholder text, no interactive controls.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  static const List<_Section> _faqs = [
    _Section(
      'How do I reserve a charger?',
      'Find a charger on the map or through search, open its details and tap '
          'Reserve. Pick a date and time slot, review the summary and confirm '
          'your booking.',
    ),
    _Section(
      'How do I cancel a booking?',
      'Go to the Bookings tab and open the booking you want to cancel. '
          'Please note that the reservation fee is non-refundable once a '
          'booking is cancelled.',
    ),
    _Section(
      'How am I charged for a session?',
      'You pay based on the energy delivered (kWh) at the rate set by the '
          'host. The final amount is charged to your default payment method '
          'when the session ends.',
    ),
    _Section(
      'The charger is not working. What should I do?',
      'Check that the plug is fully connected and the host\'s charger is '
          'powered on. If it still does not work, please contact our support '
          'team.',
    ),
    _Section(
      'How do I become a host?',
      'Switch to Host Mode from your Profile, then add your charger with its '
          'location, plug type, price and available hours.',
    ),
  ];

  static const List<_Section> _contacts = [
    _Section('Email', 'support@voltshare.app'),
    _Section('Phone', '02-123-4567'),
    _Section('Hours', 'Monday – Friday, 9:00 – 18:00'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('Frequently Asked Questions'),
              _card([
                for (final f in _faqs) ...[
                  Text(
                    f.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 6)),
                  Text(
                    f.body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 20)),
                ],
              ]),
              const Padding(padding: EdgeInsets.only(top: 24)),
              _sectionTitle('Contact Us'),
              _card([
                for (final c in _contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 72,
                          child: Text(
                            c.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _dark,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            c.body,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'We usually reply within 24 hours.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.body);

  final String title;
  final String body;
}
