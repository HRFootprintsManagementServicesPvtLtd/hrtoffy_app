import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../feature_flags.dart';
import 'auth_service.dart';

/// Signs the user out and returns to the login screen.
///
/// With the AWS backend this revokes the server session (`POST /auth/logout`)
/// and clears the stored tokens. On the legacy Supabase path the previous
/// behaviour is kept (navigation only).
Future<void> signOutAndShowLogin(BuildContext context) async {
  final navigator = Navigator.of(context);
  if (FeatureFlags.useAwsAuth) {
    await AuthService.instance.logout();
  }
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
