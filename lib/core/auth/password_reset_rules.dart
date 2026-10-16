/// Client-side checks for the AWS password-reset flow. They mirror what
/// `POST /auth/password-reset/verify-otp` enforces, so a bad entry is caught before the request.
class PasswordResetRules {
  PasswordResetRules._();

  static final _otp = RegExp(r'^\d{6}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// null when [email] looks like an email address.
  static String? validateEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return 'Please enter your email';
    if (!_email.hasMatch(e)) return 'Please enter a valid email address';
    return null;
  }

  /// null when [otp] is exactly 6 digits.
  static String? validateOtp(String otp) {
    return _otp.hasMatch(otp.trim()) ? null : 'Enter valid 6-digit OTP';
  }

  /// null when [password] has at least 8 characters, an uppercase letter and a digit.
  static String? validateNewPassword(String password) {
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(password))
      return 'Password must contain an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(password))
      return 'Password must contain a number';
    return null;
  }
}
