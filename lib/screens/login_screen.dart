import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard_screen.dart';
import '../main.dart';
import 'package:geolocator/geolocator.dart';
import 'manager/manager_dashboard_screen.dart';


// ------------------------------
// IMPORT FOR OTP FLOW
// ------------------------------
import 'otp_password_reset_dialog.dart';
import 'forgot_password_dialog.dart';

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  /// 🔵 REQUEST LOCATION PERMISSION
  Future<void> requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
  }

  /// 🔵 SHOW FORGOT PASSWORD (EMAIL + OTP FLOW)
  Future<void> _showForgotPasswordDialog() async {
    final email = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const ForgotPasswordDialog(),
    );

    if (!mounted || email == null) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => OTPPasswordResetDialog(email: email),
    );
  }


  /// 🔵 LOGIN FUNCTION
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      /// 1️⃣ SUPABASE LOGIN
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        setState(() => _error = "Invalid credentials");
        return;
      }

      /// 2️⃣ FETCH EMPLOYEE RECORD USING AUTH USER EMAIL
      final userEmail = supabase.auth.currentUser!.email!;

      final empData = await supabase
          .from("employee_records")
          .select("id, employee_id, organization_id, emp_role")
          .eq("email", userEmail)
          .maybeSingle();
      if (empData == null) {
        setState(() => _error = "Employee not found in records");
        return;
      }
      final uuid = empData["id"];
      final organizationId = empData["organization_id"];

      /// 3️⃣ CHECK TRIAL EXPIRY
      final trial = await supabase
          .from("trial_periods")
          .select("expires_at,status")
          .eq("organization_id", organizationId)
          .maybeSingle();

      if (trial != null) {
        final expiry = DateTime.tryParse(trial["expires_at"]);

        if (expiry != null && DateTime.now().isAfter(expiry)) {
          if (!mounted) return;

          setState(() {
            _isLoading = false;
            _error = "Your trial period has ended. Please contact HR.";
          });

          return;
        }

        if (trial["status"] != "active") {
          if (!mounted) return;

          setState(() {
            _isLoading = false;
            _error = "Your trial period has ended. Please contact HR.";
          });

          return;
        }
      }
      /// 3️⃣ ASK LOCATION PERMISSION
      await requestLocationPermission();
      /// 4️⃣ FCM SETUP
      await FirebaseNotificationService.setupFCM(userEmail: userEmail);
      /// 5️⃣ NAVIGATE TO DASHBOARD
      /// 5️⃣ NAVIGATE BASED ON ROLE

      final empRole =
      empData["emp_role"]
          ?.toString()
          .toLowerCase();

      if (!mounted) return;

      if (empRole == "manager") {

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ManagerDashboardScreen(

                  userEmail:
                  _emailController.text.trim(),

                ),
          ),
        );

      } else {

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ManagerDashboardScreen(

                  userEmail:
                  _emailController.text.trim(),

                ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Auth error: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              /// 🟦 APP LOGO
              Image.asset(
                'assets/HR TOFFY.png',
                width: 140,
                height: 140,
              ),

              const SizedBox(height: 24),

              Transform.translate(
                offset: const Offset(0, -40),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),

                  child: Column(
                    children: [
                      Text(
                        "Employee Login",
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Enter your email and password",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// ✉️ EMAIL
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),

                      const SizedBox(height: 12),

                      /// 🔒 PASSWORD
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      /// 🚪 LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E90FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text(
                            "Sign In",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),

                      /// 🔵 FORGOT PASSWORD BUTTON
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text(
                          "Forgot password?",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
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
