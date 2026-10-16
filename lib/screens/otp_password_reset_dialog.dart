import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/password_reset_rules.dart';

class OTPPasswordResetDialog extends StatefulWidget {
  final String email;

  /// Overridable for tests; defaults to the app's session service.
  final AuthService? authService;

  const OTPPasswordResetDialog({
    Key? key,
    required this.email,
    this.authService,
  }) : super(key: key);

  @override
  State<OTPPasswordResetDialog> createState() => _OTPPasswordResetDialogState();
}

class _OTPPasswordResetDialogState extends State<OTPPasswordResetDialog> {
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _error;

  Future<void> _resetPassword() async {
    final otp = _otpController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    final problem =
        PasswordResetRules.validateOtp(otp) ??
        PasswordResetRules.validateNewPassword(password);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (password != confirm) {
      setState(() => _error = "Passwords do not match");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await (widget.authService ?? AuthService.instance)
          .confirmPasswordResetOtp(
            email: widget.email,
            otp: otp,
            newPassword: password,
          );

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset successful. Please login."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("OTP: reset failed");
      if (mounted) setState(() => _error = _resetErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A safe message: never the server's own text.
  String _resetErrorText(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError)
        return "No connection. Please check your internet and try again.";
      if (e.statusCode == 429)
        return "Too many attempts. Please wait a minute and try again.";
      if (e.statusCode == 400)
        return "The OTP is invalid or has expired. Please check it or request a new one.";
    }
    return "Could not reset the password. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔙 HEADER WITH BACK ICON
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      "Enter OTP & New Password",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                "OTP sent to ${widget.email}",
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 16),

              // OTP
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: "6-digit OTP",
                  border: OutlineInputBorder(),
                  counterText: "",
                ),
              ),

              const SizedBox(height: 12),

              // 🔐 NEW PASSWORD WITH EYE
              TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "New Password",
                  helperText:
                      "At least 8 characters, with an uppercase letter and a number",
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 🔐 CONFIRM PASSWORD WITH EYE
              TextField(
                controller: _confirmController,
                obscureText: !_showConfirmPassword,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _showConfirmPassword = !_showConfirmPassword;
                      });
                    },
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 16),

              // RESET BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Reset Password",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
