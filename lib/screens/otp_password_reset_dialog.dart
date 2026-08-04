import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class OTPPasswordResetDialog extends StatefulWidget {
  final String email;
  const OTPPasswordResetDialog({Key? key, required this.email})
      : super(key: key);

  @override
  State<OTPPasswordResetDialog> createState() =>
      _OTPPasswordResetDialogState();
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
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (otp.length != 6) {
      setState(() => _error = "Enter valid 6-digit OTP");
      return;
    }
    if (password.length < 6) {
      setState(() => _error = "Password must be at least 6 characters");
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
      debugPrint("OTP: Verifying OTP for ${widget.email}...");
      final response = await supabase.functions.invoke(
        'verify-otp-reset-password',
        body: {
          'email': widget.email,
          'otp': otp,
          'new_password': password,
        },
      );

      debugPrint("OTP: Status => ${response.status}");
      debugPrint("OTP: Data => ${response.data}");

      if (response.status != 200 && response.status != 204) {
        final errorMsg = response.data is Map ? (response.data['error'] ?? response.data['message']) : "Server error";
        throw Exception(errorMsg.toString());
      }

      final data = response.data;
      if (data is Map && data['success'] == false) {
        throw Exception(data['error'] ?? data['message'] ?? "Invalid OTP or request");
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset successful. Please login."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("OTP: Reset Exception => $e");
      setState(() => _error = e.toString().replaceAll("Exception:", "").trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
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
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
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
