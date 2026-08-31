// Basic widget test for the VoltShare auth screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voltshare_app/screens/auth_screen.dart';

void main() {
  testWidgets('AuthScreen renders VoltShare branding and tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    // Branding.
    expect(find.text('VoltShare'), findsOneWidget);
    expect(find.text('P2P EV Charging Network'), findsOneWidget);

    // Tabs.
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsOneWidget);

    // Fields.
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
