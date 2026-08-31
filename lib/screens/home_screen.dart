import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/models/profile_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _primary = Color(0xFF10B981);
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.read<ProfileProvider>().reset();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to log out. Please try again.'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        setState(() => _isLoggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<ProfileProvider>().name;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'VoltShare',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _isLoggingOut ? null : _logout,
            tooltip: 'Log Out',
            icon: _isLoggingOut
                ? Container(
                    width: 20,
                    height: 20,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, color: _primary, size: 72),
              const Padding(padding: EdgeInsets.only(top: 16)),
              const Text(
                'Welcome back!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const Padding(padding: EdgeInsets.only(top: 8)),
              Text(
                name.isNotEmpty ? name : 'Signed in',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
