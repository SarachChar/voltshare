import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voltshare_app/utils/password_policy.dart';

/// Deep link used by Supabase to return to the app after the user taps the
/// email confirmation / password-reset link. Must match the redirect URL
/// configured in the Supabase dashboard and the native URL scheme.
const String kAuthRedirectUrl = 'io.voltshare.app://login-callback';

/// Brand colors used across the VoltShare auth experience.
class _Brand {
  static const Color primary = Color(0xFF10B981); // teal / emerald green
  static const Color gradientTop = Color(0xFF0F2E38); // dark teal
  static const Color gradientMid = Color(0xFF14B8A6);
  static const Color gradientBottom = Color(0xFFA3D94A); // lime green
  static const Color surface = Color(0xFFF3F4F6);
  static const Color field = Color(0xFFEDF0F2);
  static const Color textDark = Color(0xFF334155);
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignIn = true;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isSendingReset = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isSignIn) {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        // On success, the auth state listener in main.dart routes to home.
      } else {
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: kAuthRedirectUrl,
        );
        if (response.session == null) {
          _showMessage(
            'Account created. Check your email to confirm your address.',
          );
        }
      }
    } on AuthException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (error) {
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Validates the password field.
  ///
  /// For sign in we only require a non-empty value (the real check happens
  /// server-side). For account creation we enforce the password policy:
  ///  - longer than 8 characters
  ///  - at least one lowercase letter
  ///  - at least one uppercase letter
  ///  - at least one special character
  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Please enter your password';
    }

    // Sign in: don't enforce the policy, just require a value.
    if (_isSignIn) return null;

    return validateStrongPassword(password);
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email address first.', isError: true);
      return;
    }
    setState(() => _isSendingReset = true);
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: kAuthRedirectUrl,
      );
      _showMessage('Password reset link sent to $email.');
    } on AuthException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage('Could not send reset email.', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.surface,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    _buildTabSwitch(),
                    const Padding(padding: EdgeInsets.only(top: 28)),
                    _buildForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 72, bottom: 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Brand.gradientTop,
            _Brand.gradientMid,
            _Brand.gradientBottom,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 44),
          ),
          const Padding(padding: EdgeInsets.only(top: 18)),
          const Text(
            'VoltShare',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6)),
          Text(
            'P2P EV Charging Network',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitch() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _Brand.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildTab(
            label: 'Sign In',
            selected: _isSignIn,
            onTap: () {
              if (!_isSignIn) setState(() => _isSignIn = true);
            },
          ),
          _buildTab(
            label: 'Create Account',
            selected: !_isSignIn,
            onTap: () {
              if (_isSignIn) setState(() => _isSignIn = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: selected ? _Brand.primary : _Brand.textDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildTextField(
            controller: _emailController,
            hint: 'Email address',
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Please enter your email';
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(text)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const Padding(padding: EdgeInsets.only(top: 16)),
          _buildTextField(
            controller: _passwordController,
            hint: 'Password',
            obscureText: _obscurePassword,
            validator: _validatePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: _Brand.textDark,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          if (_isSignIn) ...[
            const Padding(padding: EdgeInsets.only(top: 10)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (_isLoading || _isSendingReset)
                    ? null
                    : _forgotPassword,
                child: _isSendingReset
                    ? Container(
                        width: 18,
                        height: 18,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _Brand.primary,
                        ),
                      )
                    : const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: _Brand.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ] else
            const Padding(padding: EdgeInsets.only(top: 20)),
          const Padding(padding: EdgeInsets.only(top: 8)),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 17, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _Brand.textDark.withValues(alpha: 0.7)),
        filled: true,
        fillColor: _Brand.field,
        suffixIcon: suffixIcon,
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
      width: double.infinity,
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignIn ? 'Sign In' : 'Create Account',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(left: 10)),
                  const Icon(Icons.arrow_forward, size: 22),
                ],
              ),
      ),
    );
  }
}
