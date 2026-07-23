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

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
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
                      TextButton(onPressed: () {}, child: const Text("Forgot Password?", style: TextStyle(color: Colors.grey))),
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
