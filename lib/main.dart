import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controllers/profile_controller.dart';
import 'models/profile_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/profile_service.dart';
import 'supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ProfileProvider())],
      child: AuthGate(),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;

  /// True after a password-recovery deep link is opened, until the user
  /// finishes setting a new password.
  bool _isRecoveringPassword = false;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _isRecoveringPassword = true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        // Password recovery takes priority: force the reset screen even
        // though a (temporary) session exists.
        if (_isRecoveringPassword) {
          return MaterialApp(
            title: 'VoltShare',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF10B981),
              ),
            ),
            home: ResetPasswordScreen(
              onDone: () => setState(() => _isRecoveringPassword = false),
            ),
          );
        }

        if (session != null) {
          return const ProfileGate();
        }
        return MaterialApp(
          title: 'VoltShare',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
            ),
          ),
          home: const AuthScreen(),
        );
      },
    );
  }
}

/// Runs after a session exists. Checks whether the signed-in user already has
/// a row in the `profiles` table. If not, the user must complete their profile
/// before reaching the home screen.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final ProfileController _controller = ProfileController(
    ProfileSupabaseService(),
  );

  late Future<bool> _hasProfileFuture;

  @override
  void initState() {
    super.initState();
    _hasProfileFuture = _loadHasProfile();
  }

  Future<bool> _loadHasProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await _controller.fetchProfile(userId);

    if (profile != null && profile.name.isNotEmpty) {
      if (mounted) {
        context.read<ProfileProvider>().setProfile(profile);
      }
      return true;
    }
    return false;
  }

  void _onProfileCompleted() {
    // CompleteProfileScreen already stored the saved profile in ProfileProvider.
    setState(() {
      _hasProfileFuture = Future.value(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltShare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      home: FutureBuilder<bool>(
        future: _hasProfileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              backgroundColor: Color(0xFFF3F4F6),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final hasProfile = snapshot.data ?? false;
          if (hasProfile) {
            return const HomeScreen();
          }
          return CompleteProfileScreen(onCompleted: _onProfileCompleted);
        },
      ),
    );
  }
}
