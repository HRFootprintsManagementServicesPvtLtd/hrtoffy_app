import 'package:flutter/material.dart';

import '../screens/manager/manager_unavailable_screen.dart';

/// The manager features, one per area of the manager module.
enum ManagerFeature {
  dashboard,
  approvals,
  teamAttendance,
  loans,
  travel,
  expenses,
  benefits,
  engage,
  compliance,
  disciplinary,
  requisitions,
}

/// Safety boundary for the manager/admin screens. A manager screen is switched on only once the AWS routes it
/// uses, and the server's authorization for them, have been verified; every other manager screen shows the
/// "not available yet" screen instead (the screen is never constructed, so no data is loaded and no approval action
/// is shown). Who may actually see or decide something is always decided by the server, never by this switch.
class ManagerAccess {
  ManagerAccess._();

  /// Features wired to the AWS API and verified. Add a feature here only together with its screen and tests.
  static const Set<ManagerFeature> live = {...ManagerFeature.values};

  static bool? _override;

  /// Whether [feature] may be shown. Only a test can change the answer (see [debugOverride]).
  static bool isAvailable(ManagerFeature feature) =>
      _override ?? live.contains(feature);

  /// Whether the manager home (and so the manager role switch) is available.
  static bool get available => isAvailable(ManagerFeature.dashboard);

  /// Tests only: force every manager feature on ([true]) or off ([false]); null restores the real answer.
  @visibleForTesting
  static void debugOverride(bool? available) => _override = available;
}

/// [build]'s screen when the manager home is available; otherwise the "not available yet" screen ([build] is not called).
Widget managerScreen(Widget Function() build) =>
    managerScreenFor(ManagerFeature.dashboard, build);

/// [build]'s screen when [feature] is available; otherwise the "not available yet" screen ([build] is not called).
Widget managerScreenFor(ManagerFeature feature, Widget Function() build) =>
    ManagerAccess.isAvailable(feature)
    ? build()
    : const ManagerUnavailableScreen();
