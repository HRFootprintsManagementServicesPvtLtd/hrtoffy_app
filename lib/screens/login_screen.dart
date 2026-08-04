import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'dashboard_screen.dart';
import '../main.dart';
import 'manager/manager_dashboard_screen.dart';
import 'otp_password_reset_dialog.dart';
import 'forgot_password_dialog.dart';
import '../widgets/employee_ui.dart';
import 'package:uuid/uuid.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();

  bool _showMobileLogin = false;
  bool _showOtpField = false;
  bool _isOtpLoading = false;
  bool _isLoading = false, _obscurePassword = true;
  String? _error;

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());
      if (response.user == null) { setState(() => _error = "Invalid credentials"); return; }
      final empData = await Supabase.instance.client.from("employee_records").select("id, emp_role").eq("email", response.user!.email!).maybeSingle();
      if (empData == null) { setState(() => _error = "Employee not found"); return; }
      await Geolocator.requestPermission();
      await FirebaseNotificationService.setupFCM(userEmail: response.user!.email!);
      if (!mounted) return;
      if (empData["emp_role"] == "manager") {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ManagerDashboardScreen(userEmail: _emailController.text.trim())));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: _emailController.text.trim(), employeeId: empData["id"])));
      }
    } on AuthException catch (e) { setState(() => _error = e.message); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _showForgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const ForgotPasswordDialog(),
    );

    if (email != null && mounted) {
      showDialog(
        context: context,
        builder: (_) => OTPPasswordResetDialog(email: email),
      );
    }
  }
  Future<void> _sendOtp() async {
    setState(() {
      _isOtpLoading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-phone-otp',
        body: {
          'phone': _mobileController.text.trim(),
          'purpose': 'login',
          'idempotency_key': const Uuid().v4(),
        },
      );
      final data = response.data;
      if (response.status != 200 || data['success'] != true) {
        setState(() {
          _error = data['error'] ?? 'Failed to send OTP';
        });
        return;
      }
      setState(() {
        _showOtpField = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP sent successfully")),
      );
    } catch (e) {
      String message = "Something went wrong";
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map && details['error'] != null) {
          message = details['error'].toString();
        } else {
          message = e.reasonPhrase ?? message;
        }
      } else {
        message = e.toString();
      }
      setState(() {
        _error = message;
      });
    } finally {
      setState(() {
        _isOtpLoading = false;
      });
    }
  }
  Future<void> _verifyOtp() async {
    setState(() {
      _isOtpLoading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-phone-otp',
        body: {
          'phone': _mobileController.text.trim(),
          'otp': _otpController.text.trim(),
          'purpose': 'login',
        },
      );
      final data = response.data;
      if (response.status != 200 || data['success'] != true) {
        setState(() {
          _error = data['error'] ?? 'OTP verification failed';
        });
        return;
      }
      final authResponse = await Supabase.instance.client.auth.setSession(
        data['refresh_token'],
      );
      if (authResponse.session == null) {
        throw Exception("Failed to create session");
      }
      await Geolocator.requestPermission();
      await FirebaseNotificationService.setupFCM(
        userEmail: data['employee']['email'],
      );
      if (!mounted) return;
      if (data['employee']['emp_role'] == "manager") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ManagerDashboardScreen(
              userEmail: data['employee']['email'],
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              email: data['employee']['email'],
              employeeId: data['employee']['id'],
            ),
          ),
        );
      }
    } catch (e) {
      String message = "Something went wrong";
      if (e is FunctionException) {
        final details = e.details;

        if (details is Map && details['error'] != null) {
          message = details['error'].toString();
        } else {
          message = e.reasonPhrase ?? message;
        }
      } else {
        message = e.toString();
      }

      setState(() {
        _error = message;
      });
    } finally {
      setState(() {
        _isOtpLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFD7E8FF), Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Image.asset('assets/HR TOFFY.png', height: 80),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: EmployeeUi.cardDecoration(),
                  child: Column(
                    children: [
                      Text("Welcome Back", style: EmployeeUi.header(24)),
                      const SizedBox(height: 8),
                      Text("Sign in to continue to your workspace", style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 32),
                      TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email_outlined))),
                      const SizedBox(height: 16),
                      TextField(controller: _passwordController, obscureText: _obscurePassword, decoration: InputDecoration(labelText: "Password", prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
                      const SizedBox(height: 32),
                      _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold))),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                      TextButton(onPressed: _showForgotPassword, child: const Text("Forgot Password?", style: TextStyle(color: Colors.grey))),
                      const SizedBox(height: 10),

                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showMobileLogin = !_showMobileLogin;
                            _showOtpField = false;
                            _error = null;
                          });
                        },
                        icon: const Icon(Icons.phone_android, color: Colors.green),
                        label: Text(
                          _showMobileLogin
                              ? "Back to Email Login"
                              : "Login with Mobile Number",
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      if (_showMobileLogin) ...[
                        const SizedBox(height: 20),

                        TextField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: "Mobile Number",
                            hintText: "9876543210",
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),

                        const SizedBox(height: 15),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isOtpLoading ? null : _sendOtp,
                            child: _isOtpLoading
                                ? const CircularProgressIndicator()
                                : const Text("Send OTP"),
                          ),
                        ),

                        if (_showOtpField) ...[
                          const SizedBox(height: 20),

                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: "Enter OTP",
                              prefixIcon: Icon(Icons.lock_clock),
                            ),
                          ),

                          const SizedBox(height: 10),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _verifyOtp,
                              child: const Text("Verify OTP"),
                            ),
                          ),
                        ]
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

