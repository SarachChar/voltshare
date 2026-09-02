import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/models/profile_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _primary = Color(0xFF10B981);
  static const Color _dark = Color(0xFF1F2937);

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
    final profile = context.watch<ProfileProvider>();
    final name = profile.name.isNotEmpty ? profile.name : 'User';
    final initial = profile.name.isNotEmpty
        ? profile.name.characters.first.toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAvatar(initial),
              const Padding(padding: EdgeInsets.only(top: 16)),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 4)),
              Text(
                profile.email.isNotEmpty ? profile.email : '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
              const Padding(padding: EdgeInsets.only(top: 8)),
              if (profile.phone.isNotEmpty)
                Text(
                  profile.phone,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                ),
              const Padding(padding: EdgeInsets.only(top: 40)),
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String initial) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F766E), _primary],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoggingOut ? null : _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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
        label: Text(
          _isLoggingOut ? 'Logging out...' : 'Log Out',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
