import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/repositories/coff_repository.dart';
import 'package:hrms_app/repositories/manager_attendance_repository.dart';
import 'package:hrms_app/repositories/manager_repository.dart';
import 'package:hrms_app/screens/manager/time_hub_screen.dart';
import 'package:hrms_app/screens/manager/widgets/coff_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/leave_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/manager_state_views.dart';
import 'package:hrms_app/screens/manager/widgets/overtime_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/regularization_approvals_panel.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

/// Friday 16 October 2026.
final _now = DateTime(2026, 10, 16, 10);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _hub(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: TimeHubScreen(
      userEmail: 'm@x.com',
      userData: const {'id': 'e1', 'full_name': 'Maya Manager'},
      fetchHrmsContext: () async => {},
      managerRepository: ManagerRepository(auth: s.auth),
      attendanceRepository: ManagerAttendanceRepository(auth: s.auth),
      approvalsRepository: ApprovalsRepository(auth: s.auth),
      coffRepository: CoffRepository(auth: s.auth),
      now: () => _now,
    ),
  ),
);

Future<TestSession> _session({bool holidaysFail = false}) => signedIn((
  req,
) async {
  switch (req.url.path) {
    case '$_org/employees':
      return ok({'items': [], 'total': 0});
    case '$_org/leaves/team-applications':
      return ok([]);
    case '$_org/attendance/regularization-requests':
      return ok({'requests': []});
    case '$_org/attendance/overtime/approvable':
      return ok([]);
    case '$_org/leaves/coff-requests':
      return ok([]);
    case '$_org/holidays':
      if (holidaysFail) {
        return jsonResponse({
          'success': false,
          'error': {'message': 'db exploded at https://api.hrtoffy.in'},
        }, 500);
      }
      return ok([
        {'id': 'h2', 'date': '2026-10-20T00:00:00.000Z', 'name': 'Diwali'},
        {
          'id': 'h1',
          'date': '2026-10-02T00:00:00.000Z',
          'name': 'Gandhi Jayanti',
        },
        {'id': 'h3', 'date': '2026-12-25T00:00:00.000Z', 'name': 'Christmas'},
      ]);
  }
  if (req.url.path.endsWith('/row-meta')) return ok({});
  return jsonResponse({
    'success': false,
    'error': {'message': 'unexpected'},
  }, 404);
}, empRole: 'manager');

Iterable<String> _paths(TestSession s) => s.requests.map((r) => r.path);

Future<void> _openTab(WidgetTester t, String name) async {
  await t.tap(find.widgetWithText(Tab, name));
  await _settle(t);
}

void main() {
  testWidgets(
    'tabs: Attendance, Leave, Regularization, Overtime, C-Off, Holidays',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_hub(s));
      await _settle(tester);
      expect(kTimeHubTabs, [
        'Attendance',
        'Leave',
        'Regularization',
        'Overtime',
        'C-Off',
        'Holidays',
      ]);
      for (final t in kTimeHubTabs) {
        expect(find.widgetWithText(Tab, t), findsOneWidget, reason: t);
      }
      // Attendance is the first tab and loads the team.
      expect(find.text('Attendance, every punch counted'), findsOneWidget);
      expect(_paths(s), contains('$_org/employees'));
      expect(_paths(s), isNot(contains('$_org/holidays')));
    },
  );

  testWidgets('switching tabs loads the matching panel', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_hub(s));
    await _settle(tester);

    await _openTab(tester, 'Leave');
    expect(find.byType(LeaveApprovalsPanel), findsOneWidget);
    expect(_paths(s), contains('$_org/leaves/team-applications'));

    await _openTab(tester, 'Regularization');
    expect(find.byType(RegularizationApprovalsPanel), findsOneWidget);
    expect(_paths(s), contains('$_org/attendance/regularization-requests'));

    await _openTab(tester, 'Overtime');
    expect(find.byType(OvertimeApprovalsPanel), findsOneWidget);
    expect(_paths(s), contains('$_org/attendance/overtime/approvable'));

    await _openTab(tester, 'C-Off');
    expect(find.byType(CoffApprovalsPanel), findsOneWidget);
    expect(_paths(s), contains('$_org/leaves/coff-requests'));

    await _openTab(tester, 'Holidays');
    expect(_paths(s), contains('$_org/holidays'));
  });

  testWidgets('a panel back link returns to the Attendance tab', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_hub(s));
    await _settle(tester);
    await _openTab(tester, 'Overtime');
    final panel = tester.widget<OvertimeApprovalsPanel>(
      find.byType(OvertimeApprovalsPanel),
    );
    expect(panel.onBack, isNotNull);
    panel.onBack!();
    await _settle(tester);
    expect(find.text('Attendance, every punch counted'), findsOneWidget);
  });

  testWidgets('holidays are listed for the current year, grouped by month', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_hub(s));
    await _settle(tester);
    await _openTab(tester, 'Holidays');

    final req = s.requests.firstWhere((r) => r.path == '$_org/holidays');
    expect(req.query['from'], '2026-01-01');
    expect(req.query['to'], '2026-12-31');

    expect(find.text('Holidays 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('holiday-month-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('holiday-month-12')), findsOneWidget);
    expect(find.text('October'), findsOneWidget);
    expect(find.text('December'), findsOneWidget);
    expect(find.text('Gandhi Jayanti'), findsOneWidget);
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.text('Christmas'), findsOneWidget);
    // sorted by date inside a month
    expect(
      tester.getTopLeft(find.text('Gandhi Jayanti')).dy,
      lessThan(tester.getTopLeft(find.text('Diwali')).dy),
    );
  });

  testWidgets('a failed holidays load shows a fixed message and Retry', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(holidaysFail: true);
    await tester.pumpWidget(_hub(s));
    await _settle(tester);
    await _openTab(tester, 'Holidays');
    expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    final before = _paths(s).where((p) => p == '$_org/holidays').length;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(
      _paths(s).where((p) => p == '$_org/holidays').length,
      greaterThan(before),
    );
  });

  testWidgets('the menu opens the manager drawer, with Time', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_hub(s));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await _settle(tester);
    expect(find.text('Time'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // the drawer's logo timer
  });

  test(
    'the drawer\'s Time item opens the hub (behind the same manager gate)',
    () {
      final src = File('lib/widgets/manager_drawer.dart').readAsStringSync();
      final i = src.indexOf('label: "Time"');
      expect(i, greaterThan(0));
      final item = src.substring(i, i + 700);
      expect(item, contains('ManagerFeature.teamAttendance'));
      expect(item, contains('TimeHubScreen('));
      expect(item, isNot(contains('TeamAttendanceScreen(')));
    },
  );
}
