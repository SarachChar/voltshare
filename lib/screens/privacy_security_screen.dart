import 'package:flutter/material.dart';

/// Privacy & Security page reached from the Profile menu.
///
/// MOCK: read-only placeholder text, no interactive controls.
class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);
  static const Color _bg = Color(0xFFF3F4F6);

  static const List<_Section> _sections = [
    _Section(
      'Information we collect',
      'We collect the information you provide when you create an account, '
          'such as your name, email address and phone number. When you use '
          'VoltShare we also collect booking history, charging sessions and '
          'approximate location to show nearby chargers.',
    ),
    _Section(
      'How we use your information',
      'Your information is used to operate bookings, process payments, '
          'connect you with charger hosts and improve the app. We do not sell '
          'your personal data to third parties.',
    ),
    _Section(
      'Sharing with hosts',
      'When you reserve a charger, the host can see your name and booking '
          'time so they can prepare the charger for you. Your email and phone '
          'number stay private.',
    ),
    _Section(
      'Keeping your account secure',
      'Your password is encrypted and never stored in plain text. Payment '
          'details are handled by our payment provider and are not stored on '
          'our servers. Please do not share your password with anyone.',
    ),
    _Section(
      'Data retention',
      'We keep your account data for as long as your account is active. You '
          'can request deletion of your account and personal data by '
          'contacting our support team.',
    ),
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
          'Privacy & Security',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in _sections) ...[
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 6)),
                  Text(
                    s.body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 20)),
                ],
                Text(
                  'Last updated: 1 Oct 2026',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.body);

  final String title;
  final String body;
}
