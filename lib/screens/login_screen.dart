import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'dashboard_screen.dart';
import '../main.dart';
import 'manager/manager_dashboard_screen.dart';
import 'otp_password_reset_dialog.dart';
import 'forgot_password_dialog.dart';
import '../widgets/employee_ui.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../core/manager_access.dart';

/// The screen a signed-in AWS user starts on, decided from `/auth/resolve-user` (the role in [AuthUser]).
/// Used by sign-in and by the splash so both land in the same place: managers on the manager dashboard,
/// everyone else on the employee dashboard.
Widget awsHomeScreenFor(AuthUser user) {
  if (user.isManager)
    return managerScreen(() => ManagerDashboardScreen(userEmail: user.email));
  return DashboardScreen(email: user.email, employeeId: user.employeeId ?? '');
}

class LoginScreen extends StatefulWidget {
  /// Overridable for tests; default to the app's session service and [awsHomeScreenFor].
  final AuthService? authService;
  final Widget Function(AuthUser user)? homeBuilder;

  const LoginScreen({Key? key, this.authService, this.homeBuilder})
    : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  AuthService get _auth => widget.authService ?? AuthService.instance;

  bool _isLoading = false, _obscurePassword = true;
  String? _error;

  /// AWS-backend password login.
  /// Signs in via /auth/login, then routes on the role from /auth/resolve-user.
  Future<AuthOrganization?> _pickOrganization(List<AuthOrganization> orgs) {
    return showDialog<AuthOrganization>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Select organization"),
        children: [
          for (final o in orgs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o.name.isEmpty ? o.id : o.name),
            ),
        ],
      ),
    );
  }

  Future<void> _loginWithAws({String? organizationId}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await _auth.login(
        _emailController.text,
        _passwordController.text.trim(),
        organizationId: organizationId,
      );
      if ((user.employeeId ?? '').isEmpty) {
        setState(() => _error = "Employee not found");
        return;
      }
      await _showLocationDisclosure();
      // Push listeners start now; the device token is not stored (no AWS endpoint for it yet).
      await FirebaseNotificationService.startForUser(user.email);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => (widget.homeBuilder ?? awsHomeScreenFor)(user),
        ),
      );
    } on MultipleOrganizationsException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final picked = await _pickOrganization(e.organizations);
      if (picked != null) await _loginWithAws(organizationId: picked.id);
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted)
        setState(
          () => _error = e.isNetworkError
              ? "Network error. Please try again."
              : (e.isUnauthorized ? "Invalid credentials" : e.message),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() => _loginWithAws();

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

  Future<void> _showLocationDisclosure() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Location Permission Required"),
        content: const Text(
          "HR Toffy uses your location to verify employee attendance.\n\n"
          "Background location is required so attendance verification can continue while the app is running in the background.\n\n"
          "Your location is used only for attendance purposes and is never shared for advertising.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Continue"),
          ),
        ],
      ),
    );
    if (result == true) {
      await Geolocator.requestPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFD7E8FF), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
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
                      Text(
                        "Sign in to continue to your workspace",
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: EmployeeUi.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                "Sign In",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      TextButton(
                        onPressed: _showForgotPassword,
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 10),
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
