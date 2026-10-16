import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/repositories/manager_repository.dart';
import 'package:hrms_app/repositories/organization_repository.dart';
import 'package:hrms_app/screens/manager/manager_dashboard_screen.dart';
import 'package:hrms_app/screens/manager/widgets/engagement_section.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _screen(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: ManagerDashboardScreen(
      userEmail: 'm@x.com',
      employeeRepository: EmployeeRepository(auth: s.auth),
      organizationRepository: OrganizationRepository(auth: s.auth),
      engagementRepository: EngagementRepository(auth: s.auth),
      managerRepository: ManagerRepository(auth: s.auth),
    ),
  ),
);

Map<String, dynamic> _emp(String id, String name, {String? managerId}) => {
  'id': id,
  'employeeId': 'E-$id',
  'fullName': name,
  'designation': 'Engineer',
  'employmentStatus': 'active',
  'managerId': managerId,
};

final _tree = [
  _emp('d1', 'Dev One', managerId: testEmployeeId),
  _emp('d2', 'Dev Two', managerId: testEmployeeId),
  _emp('i1', 'Indirect One', managerId: 'd1'),
  _emp(
    testEmployeeId,
    'Maya Manager',
  ), // the caller is never counted as a report
];
final _reviewees = [_emp('r1', 'Review One', managerId: 'someone-else')];
final _attendance = [
  {
    'id': 'a1',
    'date': '2026-10-14T00:00:00.000Z',
    'status': 'present',
    'employee_records': {'full_name': 'Dev One'},
  },
  {
    'id': 'a2',
    'date': '2026-10-15T00:00:00.000Z',
    'status': 'half_day',
    'employee_records': {'full_name': 'Dev Two'},
  },
];
final _onLeave = [
  {'id': 'l1', 'employee_id': 'd1', 'status': 'approved'},
  {
    'id': 'l2',
    'employee_id': 'd1',
    'status': 'approved',
  }, // the same person twice counts once
  {'id': 'l3', 'employee_id': 'i1', 'status': 'approved'},
];
final _birthdays = [
  {
    'id': 'b1',
    'full_name': 'Bina Birthday',
    'department': 'Finance',
    'avatar_url': null,
  },
];

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);

Future<TestSession> _session({
  int announcements = 2,
  int events = 1,
  int surveys = 3,
  Set<String> failing = const {},
  List<Map<String, dynamic>>? tree,
  List<Map<String, dynamic>>? reviewees,
  List<Map<String, dynamic>>? attendance,
  List<Map<String, dynamic>>? birthdays,
  List<Map<String, dynamic>>? onLeave,
}) {
  List<Map<String, dynamic>> rows(int n) => [
    for (var i = 0; i < n; i++)
      {'id': 'r$i', 'is_active': true, 'status': 'published'},
  ];
  return signedIn((req) async {
    if (req.method != 'GET')
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    final path = req.url.path;
    if (failing.contains(path)) return _boom;
    switch (path) {
      case '$_org/employees':
        final list = req.url.queryParameters.containsKey('managerId')
            ? (tree ?? _tree)
            : (reviewees ?? _reviewees);
        return ok({
          'items': list,
          'total': list.length,
          'page': 1,
          'limit': 100,
        });
      case '$_org/attendance/records':
        return ok(attendance ?? _attendance);
      case '$_org/leaves/team-applications':
        return ok(onLeave ?? _onLeave);
      case '$_org/dashboard/celebrations':
        return ok({'birthdays': birthdays ?? _birthdays, 'anniversaries': []});
      case '$_org/employees/me':
        return ok({
          'id': testEmployeeId,
          'organizationId': testOrgId,
          'fullName': 'Maya Manager',
          'employeeId': 'EMP-009',
          'designation': 'Lead',
          'department': 'R&D',
        });
      case '$_org/info':
        return ok({
          'organization_id': testOrgId,
          'organization_name': 'Goodclap',
        });
      case '$_org/branding':
        return ok({'logoUrl': 'https://cdn.example/logo.png'});
      case '$_org/engagement/announcements':
        return ok({'items': rows(announcements), 'total': announcements});
      case '$_org/engagement/events':
        return ok({'items': rows(events), 'total': events});
      case '$_org/engagement/surveys':
        return ok({'items': rows(surveys), 'total': surveys});
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  });
}

Finder _eng(String t) =>
    find.descendant(of: find.byType(EngagementSection), matching: find.text(t));

Finder _engagementDash() => find.descendant(
  of: find.byType(EngagementSection),
  matching: find.text('-'),
);

void main() {
  testWidgets(
    'profile, organization, engagement, team, attendance and birthdays load from the AWS repositories (Supabase is never touched)',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(s.requests.map((r) => '${r.method} ${r.path}').toSet(), {
        'GET $_org/employees/me',
        'GET $_org/info',
        'GET $_org/branding',
        'GET $_org/engagement/announcements',
        'GET $_org/engagement/events',
        'GET $_org/engagement/surveys',
        'GET $_org/employees',
        'GET $_org/attendance/records',
        'GET $_org/dashboard/celebrations',
        'GET $_org/leaves/team-applications',
      });
      expect(
        s.requests
            .firstWhere((r) => r.path.endsWith('/surveys'))
            .query['status'],
        'active',
      );

      expect(find.text('Maya Manager'), findsWidgets);
      expect(
        find.text('Goodclap'),
        findsWidgets,
      ); // organization name reaches the profile snapshot
      expect(_eng('2'), findsOneWidget);
      expect(_eng('1'), findsOneWidget);
      expect(_eng('3'), findsOneWidget);
    },
  );

  testWidgets(
    'the team is the server-scoped reporting tree: direct, indirect and reviewees, never the caller',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final listCalls = s.requests
          .where((r) => r.path == '$_org/employees')
          .toList();
      expect(listCalls.length, 2);
      expect(
        listCalls
            .map(
              (r) =>
                  r.query.containsKey('managerId') ? 'managerId' : 'reviewerId',
            )
            .toSet(),
        {'managerId', 'reviewerId'},
      );
      expect(
        listCalls.every(
          (r) =>
              r.query['managerId'] == testEmployeeId ||
              r.query['reviewerId'] == testEmployeeId,
        ),
        isTrue,
      );

      expect(find.text('Direct Reports'), findsOneWidget);
      expect(find.text('Dev One'), findsWidgets);
      expect(find.text('Indirect One'), findsWidgets);
      expect(find.text('Review One'), findsWidgets);
      expect(
        find.text('All Team Members (4)'),
        findsOneWidget,
      ); // tree (3, the caller excluded) + 1 reviewee
    },
  );

  testWidgets(
    'the On Leave card counts the team members on approved leave today (each person once) from the team leave route',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      final call = s.requests.firstWhere(
        (r) => r.path == '$_org/leaves/team-applications',
      );
      expect(call.query['status'], 'approved');
      expect(call.query['from'], call.query['to']);
      final card = find
          .ancestor(of: find.text('On Leave'), matching: find.byType(Container))
          .first;
      expect(
        find.descendant(of: card, matching: find.text('2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the On Leave card is a dash, never a 0, when the team leave route is not available',
    (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/leaves/team-applications'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      final card = find
          .ancestor(of: find.text('On Leave'), matching: find.byType(Container))
          .first;
      expect(
        find.descendant(of: card, matching: find.text('-')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the tabs filter the list to direct reports, indirect reports or reviewees',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      await tester.tap(find.text('Direct (2)'));
      await tester.pump();
      expect(find.text('All Team Members (2)'), findsOneWidget);
      await tester.tap(find.text('Indirect (1)'));
      await tester.pump();
      expect(find.text('All Team Members (1)'), findsOneWidget);
      expect(find.text('Indirect One'), findsWidgets);
    },
  );

  testWidgets(
    'attendance is asked for the reporting tree only (reviewees are not sent) over the last 30 days, newest first, with readable status',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final call = s.requests.firstWhere(
        (r) => r.path == '$_org/attendance/records',
      );
      expect(call.query['employeeIds']!.split(',').toSet(), {'d1', 'd2', 'i1'});
      final from = DateTime.parse(call.query['from']!);
      final to = DateTime.parse(call.query['to']!);
      expect(to.difference(from).inDays, 30);

      expect(find.text('2026-10-15'), findsOneWidget);
      expect(find.text('2026-10-14'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('2026-10-15')).dy,
        lessThan(tester.getTopLeft(find.text('2026-10-14')).dy),
      );
      expect(find.text('HALF DAY'), findsOneWidget); // not "HALF_DAY"
      expect(find.text('PRESENT'), findsOneWidget);
    },
  );

  testWidgets("today's birthdays come from the dashboard celebrations route", (
    tester,
  ) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('Bina Birthday'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
  });

  testWidgets(
    'a team failure makes the team and attendance sections unavailable (no raw error) and leaves the rest of the screen',
    (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/employees'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text(kTeamDataUnavailableMessage),
        findsNWidgets(2),
      ); // team + attendance
      expect(find.text('Direct Reports'), findsNothing);
      expect(find.text('Bina Birthday'), findsOneWidget);
      expect(_eng('2'), findsOneWidget); // engagement still loads
      expect(find.textContaining('exploded'), findsNothing);
      expect(
        s.requests.any((r) => r.path.endsWith('/attendance/records')),
        isFalse,
      );
    },
  );

  testWidgets('an attendance failure leaves the team visible', (tester) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/attendance/records'});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text(kTeamDataUnavailableMessage), findsOneWidget);
    expect(find.text('Dev One'), findsWidgets);
    expect(find.textContaining('exploded'), findsNothing);
  });

  testWidgets('a birthdays failure is unavailable (no raw error)', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/dashboard/celebrations'});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text(kTeamDataUnavailableMessage), findsOneWidget);
    expect(find.text('Celebrations Today'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
  });

  testWidgets('everything the dashboard asks for is a read', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(s.requests.every((r) => r.method == 'GET'), isTrue);
    final bad = RegExp(
      'hierarchy|approval|chat/employees|/employees/(?!me)',
      caseSensitive: false,
    );
    expect(
      s.requests.where(
        (r) => bad.hasMatch(r.path) && r.path != '$_org/employees',
      ),
      isEmpty,
    );
  });

  testWidgets('empty engagement lists are real zeros', (tester) async {
    _tall(tester);
    final s = await _session(announcements: 0, events: 0, surveys: 0);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(_eng('0'), findsNWidgets(3));
    expect(_engagementDash(), findsNothing);
  });

  testWidgets('an engagement failure shows "-" (not 0) and a safe screen', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(
      failing: {'$_org/engagement/events', '$_org/engagement/surveys'},
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(_eng('2'), findsOneWidget);
    expect(_engagementDash(), findsNWidgets(2));
    expect(_eng('0'), findsNothing);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.text('Maya Manager'), findsWidgets);
  });

  testWidgets('an organization failure is ignored', (tester) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/info'});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('Maya Manager'), findsWidgets);
    expect(find.textContaining("Couldn't load"), findsNothing);
    expect(find.textContaining('exploded'), findsNothing);
  });

  testWidgets(
    'a profile failure is a safe message with Retry and requests nothing else',
    (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/employees/me'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text("Couldn't load your profile. Pull down to try again."),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
      expect(s.requests.map((r) => r.path), ['$_org/employees/me']);
    },
  );

  testWidgets(
    'the manager drawer makes no request and shows a neutral "-" for approvals, not a 0',
    (tester) async {
      _tall(tester);
      final s = await _session(
        failing: {'$_org/branding'},
      ); // no logo image to fetch over the network
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      final before = s.requests.length;

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffold.openEndDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Approvals'), findsOneWidget);
      expect(
        find.byTooltip("Approval count isn't available yet"),
        findsOneWidget,
      );
      expect(s.requests.length, before);
    },
  );

  test(
    'the dashboard and drawer contain no Supabase code and no identity/exception logging',
    () {
      for (final path in [
        'lib/screens/manager/manager_dashboard_screen.dart',
        'lib/widgets/manager_drawer.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final banned in [
          'supabase',
          'Supabase',
          'print(',
          'debugPrint(',
          'full_name}',
        ]) {
          expect(
            src.contains(banned),
            isFalse,
            reason: '$path contains "$banned"',
          );
        }
      }
    },
  );
}
