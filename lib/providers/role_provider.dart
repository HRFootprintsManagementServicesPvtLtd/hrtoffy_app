import 'package:flutter/material.dart';

class RoleProvider extends ChangeNotifier {
  String _activeRole = 'employee';

  String get activeRole => _activeRole;

  void switchRole(String role) {
    _activeRole = role;
    notifyListeners();
  }
}