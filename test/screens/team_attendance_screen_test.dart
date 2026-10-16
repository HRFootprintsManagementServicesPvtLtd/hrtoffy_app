import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hrms_app/models/work_site.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/manager_attendance_repository.dart';
import 'package:hrms_app/repositories/manager_repository.dart';
import 'package:hrms_app/screens/manager/team_attendance_screen.dart';
import 'package:hrms_app/screens/manager/widgets/attendance_muster_table.dart';
import 'package:hrms_app/screens/manager/widgets/employee_geo_dialog.dart';
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

Widget _screen(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: TeamAttendanceScreen(
      userEmail: 'm@x.com',
      userData: const {'id': 'e1', 'full_name': 'Maya Manager'},
      fetchHrmsContext: () async => {},
      managerRepository: ManagerRepository(auth: s.auth),
      attendanceRepository: ManagerAttendanceRepository(auth: s.auth),
      now: () => _now,
    ),
  ),
);

Map<String, dynamic> _emp(String id, String name, {String? managerId}) => {
  'id': id,
  'employeeId': 'E-$id',
  'fullName': name,
  'designation': 'Engineer',
  'managerId': managerId,
};

final _tree = [
  _emp('d1', 'Dev One', managerId: testEmployeeId),
  _emp('d2', 'Dev Two', managerId: testEmployeeId),
  _emp('i1', 'Indirect One', managerId: 'd1'),
];
final _reviewees = [_emp('r1', 'Review One', managerId: 'someone-else')];

Map<String, dynamic> _rec(
  String emp,
  String name,
  String date,
  String status, {
  Object? hours,
  String? punchIn,
}) => {
  'id': 'a-$emp-$date',
  'employee_id': emp,
  'date': '${date}T00:00:00.000Z',
  'status': status,
  'hours_worked': hours,
  'punch_in_time': punchIn,
  'work_type': 'on-duty',
  'employee_records': {'full_name': name, 'employee_id': 'E-$emp'},
};

final _october = [
  _rec(
    'd1',
    'Dev One',
    '2026-10-16',
    'present',
    hours: '8.5',
    punchIn: '2026-10-16T04:00:00Z',
  ),
  _rec('d2', 'Dev Two', '2026-10-16', 'late', hours: 6),
  _rec('d1', 'Dev One', '2026-10-15', 'absent'),
  _rec('d2', 'Dev Two', '2026-10-15', 'on_leave'),
  _rec('i1', 'Indirect One', '2026-10-15', 'half_day'),
];

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);
final _forbidden = jsonResponse({
  'success': false,
  'error': {'message': 'Permission denied: attendance:view_team'},
}, 403);

Future<TestSession> _session({
  Map<String, _Fail> failing = const {},
  List<Map<String, dynamic>>? tree,
  List<Map<String, dynamic>>? reviewees,
  List<Map<String, dynamic>>? records,
  Object? workingDays = const [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
  ],
  Object? leaves,
  List<Map<String, dynamic>>? punchLogs,
}) {
  return signedIn((req) async {
    if (req.method != 'GET') {
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    }
    final path = req.url.path;
    final fail = failing[path];
    if (fail != null) return fail == _Fail.forbidden ? _forbidden : _boom;
    switch (path) {
      case '$_org/employees':
        final list = req.url.queryParameters.containsKey('managerId')
            ? (tree ?? _tree)
            : (reviewees ?? _reviewees);
        return ok({'items': list, 'total': list.length});
      case '$_org/attendance/records':
        final from = req.url.queryParameters['from']!;
        final to = req.url.queryParameters['to']!;
        final all = records ?? _october;
        return ok([
          for (final r in all)
            if ((r['date'] as String).substring(0, 10).compareTo(from) >= 0 &&
                (r['date'] as String).substring(0, 10).compareTo(to) <= 0)
              r,
        ]);
      case '$_org/holidays':
        return ok([
          {
            'id': 'h1',
            'date': '2026-10-02T00:00:00.000Z',
            'name': 'Gandhi Jayanti',
          },
        ]);
      case _org:
        return ok({'id': testOrgId, 'working_days': workingDays});
      case '$_org/leaves/team-summary':
        return ok(
          leaves ??
              [
                {
                  'employee_id': 'i1',
                  'employee_name': 'Indirect One',
                  'upcoming_leaves': [
                    {
                      'from_date': '2026-10-20',
                      'to_date': '2026-10-21',
                      'leave_type': 'Casual',
                      'total_days': 2,
                    },
                  ],
                },
              ],
        );
      case '$_org/attendance/employees/d1/day-punch-logs':
        return ok(punchLogs ?? []);
      case '$_org/work-sites':
        return ok([
          {
            'id': 's1',
            'name': 'HQ',
            'latitude': '17.38',
            'longitude': '78.48',
            'radiusMeters': 100,
          },
        ]);
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  });
}

enum _Fail { forbidden, server }

Iterable<String> _paths(TestSession s) => s.requests.map((r) => r.path);

void main() {
  testWidgets(
    'loads the reporting tree, then attendance for the tree only over the last 30 days',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final records = s.requests.firstWhere(
        (r) =>
            r.path == '$_org/attendance/records' &&
            r.query['from'] == '2026-09-16',
      );
      expect(records.query['employeeIds']!.split(',').toSet(), {
        'd1',
        'd2',
        'i1',
      }); // r1 (reviewee) is not sent
      expect(records.query['to'], '2026-10-16');
      final team = s.requests
          .where((r) => r.path == '$_org/employees')
          .toList();
      expect(team.length, 2);
      expect(
        team.every(
          (r) =>
              r.query['managerId'] == testEmployeeId ||
              r.query['reviewerId'] == testEmployeeId,
        ),
        isTrue,
      );
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
      expect(find.textContaining('MAYA'), findsOneWidget);
      expect(find.text('Attendance, every punch counted'), findsOneWidget);
      expect(find.text('Team Overview'), findsOneWidget);
      expect(find.text('Attendance Muster'), findsOneWidget);
    },
  );

  testWidgets(
    'KPIs for today come from the rows: present, absent, late, average hours, not checked in',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      // today (16 Oct): d1 present 8.5h, d2 late 6h, i1 no record yet
      expect(find.text('PRESENT TODAY'), findsOneWidget);
      expect(find.text('ABSENT TODAY'), findsOneWidget);
      expect(find.text('LATE TODAY'), findsOneWidget);
      expect(find.text('7.3 h'), findsOneWidget); // (8.5 + 6) / 2
      String small(String label) {
        final card = find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first;
        return tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .whereType<String>()
            .firstWhere((t) => t != label);
      }

      expect(small('Team Members'), '3');
      expect(small('Present'), '2');
      expect(small('Not Checked In'), '1');
      expect(
        small('On Leave'),
        '0',
      ); // the leave summary loaded: a real zero for today
      expect(
        find.text('NOT CHECKED IN'),
        findsOneWidget,
      ); // i1's badge, not a guessed absence
    },
  );

  testWidgets('the previous day shows that day: absent, on leave, half day', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('day-prev')));
    await tester.pump();
    expect(
      find.text('ABSENT'),
      findsWidgets,
    ); // the KPI label and Dev One's badge
    expect(find.text('PRESENT TODAY'), findsNothing);
    expect(find.text('Status on 15 Oct 2026'), findsOneWidget);
    expect(find.text('ON LEAVE'), findsWidgets);
    expect(find.text('HALF DAY'), findsWidgets);
    expect(find.text('Present Today'), findsNothing);
  });

  testWidgets(
    'the tracker lists records newest first with readable status, hours and a search',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text('Team Attendance & Leave Tracker (Last 30 Days)'),
        findsOneWidget,
      );
      expect(find.text('16 Oct 2026'), findsWidgets);
      expect(find.text('8.5h'), findsOneWidget);
      expect(find.text('HALF DAY'), findsWidgets); // not HALF_DAY
      expect(find.text('ON LEAVE'), findsWidgets);
      expect(find.textContaining('half_day'), findsNothing);
      expect(
        tester.getTopLeft(find.text('16 Oct 2026').first).dy,
        lessThan(tester.getTopLeft(find.text('15 Oct 2026').first).dy),
      );

      await tester.enterText(find.byType(TextField), 'indirect');
      await tester.pump();
      expect(find.text('Dev Two'), findsNothing);
      expect(find.text('Indirect One'), findsWidgets);
    },
  );

  testWidgets(
    'upcoming leave comes from the verified team summary and shows in the list',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('Upcoming Leaves'), findsOneWidget);
      expect(find.textContaining('20 Oct 2026 - 21 Oct 2026'), findsOneWidget);
      expect(find.text(kLeaveUnavailableMessage), findsNothing);
    },
  );

  testWidgets(
    'without the leave summary the leave parts say "not available yet" and On Leave is "-" (not 0)',
    (tester) async {
      _tall(tester);
      final s = await _session(
        failing: {'$_org/leaves/team-summary': _Fail.server},
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text(kLeaveUnavailableMessage), findsOneWidget);
      final card = find
          .ancestor(of: find.text('On Leave'), matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: card, matching: find.text('-')),
        findsOneWidget,
      );
      expect(
        find.text('AVAILABLE'),
        findsNothing,
      ); // never claimed without the data
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.text('Dev One'), findsWidgets); // the rest still shows
    },
  );

  testWidgets(
    'the muster asks for the whole month, marks holidays, weekly offs, no-record days and never guesses absence',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('Attendance Muster'));
      await _settle(tester);

      final call = s.requests.lastWhere(
        (r) => r.path == '$_org/attendance/records',
      );
      expect(call.query['from'], '2026-10-01');
      expect(call.query['to'], '2026-10-31');
      expect(call.query['employeeIds']!.split(',').toSet(), {'d1', 'd2', 'i1'});
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(
        find.text('H'),
        findsWidgets,
      ); // 2 Oct holiday (and the H column header)
      expect(find.text('OFF'), findsWidgets); // weekends
      expect(
        find.text('NR'),
        findsWidgets,
      ); // past days with no record, not "A"
      expect(find.text('P'), findsWidgets);
      expect(find.text('LT'), findsWidgets);
      expect(find.text('HD'), findsWidgets);
      expect(find.text('L'), findsWidgets);
      // d1: only one absence was recorded (15 Oct); every other past working day without a row is NR
      final d1 = MusterRow([
        for (var d = 1; d <= 31; d++)
          musterCellFor(
            day: DateTime(2026, 10, d),
            today: _now,
            record: {
              '2026-10-16': _october[0],
              '2026-10-15': _october[2],
            }['2026-10-${d.toString().padLeft(2, '0')}'],
            holidays: const {'2026-10-02': 'Gandhi Jayanti'},
            workingDays: const {
              'monday',
              'tuesday',
              'wednesday',
              'thursday',
              'friday',
            },
          ),
      ]);
      expect(d1.absent, 1);
      expect(d1.present, 1);
      expect(d1.holidays, 1);
      expect(d1.noRecord, 9); // past working days 1, 5-9 and 12-14 have no row
    },
  );

  testWidgets('changing the month asks for that month', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await tester.tap(find.text('Attendance Muster'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('month-prev')));
    await _settle(tester);
    final call = s.requests.lastWhere(
      (r) => r.path == '$_org/attendance/records',
    );
    expect(call.query['from'], '2026-09-01');
    expect(call.query['to'], '2026-09-30'); // 30 days in September
    expect(find.text('September 2026'), findsOneWidget);
    // the current month is the last one: no next
    await tester.tap(find.byKey(const ValueKey('month-next')));
    await _settle(tester);
    expect(find.text('October 2026'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('month-next')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'unknown working days: no weekly off is assumed and the muster says so',
    (tester) async {
      _tall(tester);
      final s = await _session(workingDays: null);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('Attendance Muster'));
      await _settle(tester);
      expect(find.text('OFF'), findsNothing);
      expect(find.textContaining("Weekly offs aren't marked"), findsOneWidget);
    },
  );

  testWidgets(
    'an empty team is a clear message and no attendance is requested',
    (tester) async {
      _tall(tester);
      final s = await _session(tree: [], reviewees: []);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text(kNoTeamMessage), findsOneWidget);
      expect(_paths(s).contains('$_org/attendance/records'), isFalse);
      expect(find.text('PRESENT TODAY'), findsNothing); // no KPI, no zero
    },
  );

  testWidgets(
    'a role without team access (403) gets a friendly message, not the server text',
    (tester) async {
      _tall(tester);
      final s = await _session(
        failing: {'$_org/attendance/records': _Fail.forbidden},
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text("Team attendance isn't available for your role."),
        findsOneWidget,
      );
      expect(find.textContaining('Permission denied'), findsNothing);
      final present = find
          .ancestor(
            of: find.text('PRESENT TODAY'),
            matching: find.byType(Column),
          )
          .first;
      expect(
        find.descendant(of: present, matching: find.text('-')),
        findsOneWidget,
      ); // unknown, not 0
    },
  );

  testWidgets('a team failure (5xx) is a safe message with Retry', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/employees': _Fail.server});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(
      find.text("Attendance can't be loaded right now. Please try again."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('http'), findsNothing);
  });

  testWidgets('an attendance failure (5xx) keeps the page and offers Retry', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(
      failing: {'$_org/attendance/records': _Fail.server},
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(
      find.text("Attendance can't be loaded right now. Please try again."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.text('Attendance, every punch counted'), findsOneWidget);
  });

  testWidgets(
    'only team-scoped read routes are used: no geo-trail, leave applications, reviewer scope or manager hierarchy',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('Attendance Muster'));
      await _settle(tester);
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
      final bad = RegExp(
        'geo-trail|location-trail|leaves/applications|reviewer-scope|hierarchy|approval',
        caseSensitive: false,
      );
      expect(s.requests.where((r) => bad.hasMatch(r.path)), isEmpty);
      expect(
        _paths(s).toSet().difference({
          '$_org/employees',
          '$_org/attendance/records',
          '$_org/holidays',
          _org,
          '$_org/leaves/team-summary',
        }),
        isEmpty,
      );
    },
  );

  testWidgets(
    'the location icon opens the dialog; a day with no positions says so',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('member-location-d1')));
      await _settle(tester);
      expect(find.byType(EmployeeGeoDialog), findsOneWidget);
      expect(find.text('Dev One - Location'), findsOneWidget);
      final call = s.requests.firstWhere(
        (r) => r.path == '$_org/attendance/employees/d1/day-punch-logs',
      );
      expect(call.query['date'], '2026-10-16');
      expect(
        find.text('No location was recorded for this date.'),
        findsOneWidget,
      );
      expect(
        _paths(
          s,
        ).any((p) => p.contains('geo-trail') || p.contains('location-trail')),
        isFalse,
      );
    },
  );

  testWidgets(
    'a location failure in the dialog is friendly (403/404 for a person outside the team)',
    (tester) async {
      _tall(tester);
      final s = await _session(
        failing: {'$_org/attendance/employees/d1/day-punch-logs': _Fail.server},
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('member-location-d1')));
      await _settle(tester);
      expect(
        find.text("Attendance can't be loaded right now. Please try again."),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
    },
  );

  testWidgets(
    'with tracking points the dialog labels them and measures the distance; with only punches it says it is not a trail',
    (tester) async {
      _tall(tester);
      Widget fake(
        List<Map<String, dynamic>> points,
        List<WorkSite> sites,
        void Function(GoogleMapController) _,
      ) => Text('MAP ${points.length} points ${sites.length} sites');
      for (final withTrack in [true, false]) {
        final s = await _session(
          punchLogs: [
            {
              'punch_type': 'in',
              'punch_time': '2026-10-16T04:00:00Z',
              'punch_lat': 17.38,
              'punch_lng': 78.48,
              'in_fence': true,
            },
            if (withTrack) ...[
              {
                'punch_type': 'track',
                'punch_time': '2026-10-16T05:00:00Z',
                'punch_lat': 17.39,
                'punch_lng': 78.49,
                'in_fence': false,
              },
              {
                'punch_type': 'track',
                'punch_time': '2026-10-16T06:00:00Z',
                'punch_lat': 17.40,
                'punch_lng': 78.50,
                'in_fence': true,
              },
            ] else
              {
                'punch_type': 'out',
                'punch_time': '2026-10-16T12:00:00Z',
                'punch_lat': 17.39,
                'punch_lng': 78.49,
                'in_fence': false,
              },
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmployeeGeoDialog(
                key: ValueKey(withTrack),
                employeeId: 'd1',
                employeeName: 'Dev One',
                repository: ManagerAttendanceRepository(auth: s.auth),
                initialDate: DateTime(2026, 10, 16),
                mapBuilder: fake,
              ),
            ),
          ),
        );
        await _settle(tester);
        if (withTrack) {
          expect(find.text('2 tracking points'), findsOneWidget);
          expect(find.text('MAP 2 points 1 sites'), findsOneWidget);
          expect(
            find.text('Tracking points recorded during the day.'),
            findsOneWidget,
          );
        } else {
          expect(find.text('2 punches'), findsOneWidget);
          expect(
            find.textContaining('A continuous trail is not available'),
            findsOneWidget,
          );
        }
        expect(find.textContaining(' km'), findsOneWidget);
        expect(
          find.textContaining('outside the work-site fence'),
          findsOneWidget,
        );
      }
    },
  );

  test(
    'the screen, dialog and muster contain no Supabase and no logging of identities or errors',
    () {
      for (final path in [
        'lib/screens/manager/team_attendance_screen.dart',
        'lib/screens/manager/widgets/employee_geo_dialog.dart',
        'lib/screens/manager/widgets/attendance_muster_table.dart',
        'lib/repositories/manager_attendance_repository.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final banned in [
          'supabase',
          'Supabase',
          'print(',
          'debugPrint(',
          'e.message',
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
