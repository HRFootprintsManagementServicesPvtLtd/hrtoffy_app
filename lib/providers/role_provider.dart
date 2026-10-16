import 'package:flutter/material.dart';

import '../core/manager_access.dart';

class RoleProvider extends ChangeNotifier {
  String _activeRole = 'employee';

  String get activeRole => _activeRole;

  void switchRole(String role) {
    // The manager role is unavailable (no verified manager-scoped AWS APIs yet).
    if (role == 'manager' && !ManagerAccess.available) return;
    _activeRole = role;
    notifyListeners();
  }
}
