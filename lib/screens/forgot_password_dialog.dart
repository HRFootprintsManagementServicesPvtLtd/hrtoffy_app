import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/password_reset_rules.dart';

class ForgotPasswordDialog extends StatefulWidget {
  /// Overridable for tests; defaults to the app's session service.
  final AuthService? authService;

  const ForgotPasswordDialog({Key? key, this.authService}) : super(key: key);

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    final invalid = PasswordResetRules.validateEmail(email);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // The server answers the same way whether or not the address is registered (and so do we):
      // no employee lookup here, and no hint about which emails exist.
      await (widget.authService ?? AuthService.instance)
          .requestPasswordResetOtp(email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "If this email is registered, an OTP has been sent. Please check your email.",
          ),
          backgroundColor: Colors.green,
        ),
      );

      // ✅ return email to LoginScreen
      Navigator.pop(context, email);
    } catch (e) {
      debugPrint("OTP: request failed");
      if (mounted) setState(() => _error = _requestErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A safe message: never the server's own text.
  String _requestErrorText(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError)
        return "No connection. Please check your internet and try again.";
      if (e.statusCode == 429)
        return "Too many attempts. Please wait a minute and try again.";
      if (e.statusCode == 400) return "Please enter a valid email address.";
    }
    return "Could not request an OTP. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Forgot Password",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter your email. We will send a 6-digit OTP.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Email Address",
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _sendOtp,
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
                        "Send OTP",
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
    );
  }
}
