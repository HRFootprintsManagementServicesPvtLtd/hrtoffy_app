import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = "Please enter your email");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint("OTP: Checking if email $email exists in employee_records...");
      final empCheck = await supabase
          .from('employee_records')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (empCheck == null) {
        setState(() => _error = "This email is not registered in our system.");
        return;
      }

      debugPrint("OTP: Invoking request-password-otp for $email");
      final response = await supabase.functions.invoke(
        'request-password-otp',
        body: {'email': email},
      );

      debugPrint("OTP: Status => ${response.status}");
      debugPrint("OTP: Data => ${response.data}");

      if (response.status != 200 && response.status != 204) {
        final errorMsg = response.data is Map ? (response.data['error'] ?? response.data['message']) : "Server error";
        throw Exception(errorMsg.toString());
      }

      final data = response.data;
      if (data is Map && data['success'] == false) {
        throw Exception(data['error'] ?? data['message'] ?? "Failed to send OTP");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP sent successfully. Please check your email."), backgroundColor: Colors.green),
      );

      // ✅ return email to LoginScreen
      Navigator.pop(context, email);
    } catch (e) {
      debugPrint("OTP: Exception => $e");
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
