import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/controllers/profile_controller.dart';
import 'package:voltshare_app/models/profile_model.dart';
import 'package:voltshare_app/models/profile_provider.dart';
import 'package:voltshare_app/services/profile_service.dart';

/// Brand colors reused from the auth experience.
class _Brand {
  static const Color primary = Color(0xFF10B981);
  static const Color surface = Color(0xFFF3F4F6);
  static const Color field = Color(0xFFEDF0F2);
  static const Color textDark = Color(0xFF334155);
}

/// Shown after login when the signed-in user has no profile row yet.
///
/// On successful save, the auth/profile gate in main.dart re-checks and
/// routes the user to the home screen.
class CompleteProfileScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const CompleteProfileScreen({super.key, required this.onCompleted});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final ProfileController controller =
      ProfileController(ProfileSupabaseService());

  bool _isLoading = false;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    controller.onSync.listen((bool syncState) {
      if (!mounted) return;
      setState(() {
        _isLoading = syncState;
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade600 : _Brand.primary,
        ),
      );
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.read<ProfileProvider>().reset();
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Failed to log out. Please try again.', isError: true);
        setState(() => _isLoggingOut = false);
      }
    }
  }

  /// Validates a Thai mobile phone number.
  ///
  /// Accepts common formats:
  ///   - 0812345678  (10 digits starting with 06/08/09)
  ///   - 081-234-5678
  ///   - 081 234 5678
  ///   - +66812345678 or +66 81 234 5678
  ///
  /// The input is stripped of spaces, dashes, and an optional +66 prefix,
  /// then validated against the 10-digit 0[689]x pattern.
  String? _validateThaiPhone(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Please enter your phone number';

    // Strip spaces and dashes.
    String digits = raw.replaceAll(RegExp(r'[\s\-]'), '');

    // Convert +66 prefix to leading 0.
    if (digits.startsWith('+66')) {
      digits = '0${digits.substring(3)}';
    }

    // Must be exactly 10 digits.
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
      return 'Phone number must be 10 digits';
    }

    // Must start with 06, 08, or 09 (Thai mobile prefixes).
    if (!RegExp(r'^0[689]').hasMatch(digits)) {
      return 'Phone number must start with 06, 08, or 09';
    }

    return null;
  }

  /// Normalizes a Thai phone input to 0xxxxxxxxx format.
  String _normalizeThaiPhone(String raw) {
    String digits = raw.replaceAll(RegExp(r'[\s\-]'), '');
    if (digits.startsWith('+66')) {
      digits = '0${digits.substring(3)}';
    }
    return digits;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = Profile(
      user.id,
      _nameController.text.trim(),
      _normalizeThaiPhone(_phoneController.text.trim()),
      user.email ?? '',
    );

    try {
      final saved = await controller.saveProfile(profile);
      if (!mounted) return;
      context.read<ProfileProvider>().setProfile(saved);
      widget.onCompleted();
    } on PostgrestException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage('Could not save your profile. Please try again.',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: _Brand.surface,
      appBar: AppBar(
        backgroundColor: _Brand.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Complete your profile',
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_outline, color: _Brand.primary, size: 64),
                const Padding(padding: EdgeInsets.only(top: 12)),
                const Text(
                  'Tell us about you',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const Padding(padding: EdgeInsets.only(top: 6)),
                Text(
                  'We just need a few details before you get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                _buildTextField(
                  controller: _nameController,
                  hint: 'Full name',
                  icon: Icons.badge_outlined,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                _buildTextField(
                  controller: _phoneController,
                  hint: 'Phone number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: _validateThaiPhone,
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                _buildReadOnlyEmail(user?.email ?? ''),
                const Padding(padding: EdgeInsets.only(top: 28)),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(fontSize: 17, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _Brand.textDark),
        hintStyle: TextStyle(color: _Brand.textDark.withValues(alpha: 0.7)),
        filled: true,
        fillColor: _Brand.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _Brand.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildReadOnlyEmail(String email) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: _Brand.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.email_outlined, color: _Brand.textDark),
          const Padding(padding: EdgeInsets.only(left: 12)),
          Expanded(
            child: Text(
              email.isEmpty ? 'No email' : email,
              style: TextStyle(fontSize: 17, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: _Brand.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? Container(
                width: 24,
                height: 24,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Save & Continue',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
