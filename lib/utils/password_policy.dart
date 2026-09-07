/// Shared password policy used for account creation and password reset.
///
/// Requirements:
///  - longer than 8 characters
///  - at least one lowercase letter
///  - at least one uppercase letter
///  - at least one number
///  - at least one special character
///
/// Returns an error message when invalid, or null when the password passes.
String? validateStrongPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Please enter your password';
  }
  if (password.length <= 8) {
    return 'Password must be longer than 8 characters';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Password must contain a lowercase letter';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Password must contain an uppercase letter';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Password must contain a number';
  }
  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]\\/;+=~`]').hasMatch(password)) {
    return 'Password must contain a special character';
  }
  return null;
}
