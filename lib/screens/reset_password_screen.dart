import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/utils/password_policy.dart';

class _Brand {
  static const Color primary = Color(0xFF10B981);
  static const Color surface = Color(0xFFF3F4F6);
  static const Color field = Color(0xFFEDF0F2);
  static const Color textDark = Color(0xFF334155);
}

/// Shown when the app is opened from a Supabase password-recovery deep link
/// (AuthChangeEvent.passwordRecovery). Lets the user set a new password.
///
/// On success [onDone] is called so the gate can route away from this screen.
class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;

  const ResetPasswordScreen({super.key, required this.onDone});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      _showMessage('Password updated. You are now signed in.');
      widget.onDone();
    } on AuthException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage(
        'Could not update password. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.surface,
      appBar: AppBar(
        backgroundColor: _Brand.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Set a new password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_reset, color: _Brand.primary, size: 64),
                const Padding(padding: EdgeInsets.only(top: 12)),
                const Text(
                  'Create a new password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const Padding(padding: EdgeInsets.only(top: 6)),
                Text(
                  'Enter a new password for your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                _buildPasswordField(
                  controller: _passwordController,
                  hint: 'New password',
                  validator: validateStrongPassword,
                ),
                const Padding(padding: EdgeInsets.only(top: 16)),
                _buildPasswordField(
                  controller: _confirmController,
                  hint: 'Confirm new password',
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const Padding(padding: EdgeInsets.only(top: 28)),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscure,
      validator: validator,
      style: const TextStyle(fontSize: 17, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _Brand.textDark.withValues(alpha: 0.7)),
        filled: true,
        fillColor: _Brand.field,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility : Icons.visibility_off,
            color: _Brand.textDark,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
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

  Widget _buildSubmitButton() {
    return Container(
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
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
                'Update password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
