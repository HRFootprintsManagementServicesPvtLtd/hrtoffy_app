import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../providers/role_provider.dart';
import '../dashboard_screen.dart';

/// Shown instead of any manager/admin screen until manager-scoped AWS APIs and their authorization are verified.
/// It loads nothing and offers no approval actions.
class ManagerUnavailableScreen extends StatelessWidget {
  const ManagerUnavailableScreen({super.key});

  static const String message = 'Manager features are not available yet';
  static const String detail =
      "We're moving them to the new system. Your employee features are not affected.";

  void _toEmployeeHome(BuildContext context) {
    try {
      context.read<RoleProvider>().switchRole('employee');
    } catch (_) {} // no RoleProvider above: nothing to reset
    final user = AuthService.instance.currentUser;
    if (user == null || (user.employeeId ?? '').isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            DashboardScreen(email: user.email, employeeId: user.employeeId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manager')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_rounded,
                size: 56,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _toEmployeeHome(context),
                child: const Text('Go to my dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
