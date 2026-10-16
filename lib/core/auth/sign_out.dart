import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../payslip_files.dart';
import 'auth_service.dart';

/// Signs the user out and returns to the login screen.
///
/// This deletes any downloaded payslip PDFs (best effort, never fails the sign-out), revokes the server session
/// (`POST /auth/logout`) and clears the stored tokens.
Future<void> signOutAndShowLogin(BuildContext context) async {
  final navigator = Navigator.of(context);
  await PayslipFiles.instance.deleteAll();
  await AuthService.instance.logout();
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
