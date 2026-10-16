import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/attendance_repository.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/screens/attendance_screen.dart';
import 'package:hrms_app/services/attendance_service.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../helpers/test_auth.dart';

final _employee = <String, dynamic>{
  'id': testEmployeeId,
  'organization_id': testOrgId,
  'branch_id': 'b1',
  'entity_id': 'e1',
};

const _org = '/organizations/$testOrgId';

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Removes the screen so its timers are cancelled before the test ends.
Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
}

Map<String, dynamic> _meDto() => {
  'id': testEmployeeId,
  'organizationId': testOrgId,
  'branchId': 'b1',
  'entityId': 'e1',
  'managerId': 'mgr-1',
  'fullName': 'Asha Rao',
};

/// Answers every call the Attendance screen can make (all through the API).
Future<http.Response> _api(
  http.Request req, {
  String method = 'in_system',
  List<Map<String, dynamic>> records = const [],
  List<Map<String, dynamic>> logs = const [],
}) async {
  final path = req.url.path;
  if (path == '$_org/employees/me') return ok(_meDto());
  if (path == '$_org/employees/$testEmployeeId/punch-status') {
    return ok({
      'latestPunch': null,
      'attendance': null,
      'punchLogs': [],
      'today': '2026-10-08',
    });
  }
  if (path == '$_org/geo-fencing-policy') {
    return ok({
      'enabled': false,
      'defaultRadiusMeters': 100,
      'mode': 'strict',
      'onlyForOffice': false,
      'trackAllPunches': false,
    });
  }
  if (path == '$_org/work-sites' || path == '$_org/work-site-assignments')
    return ok([]);
  if (path == _org)
    return ok({'id': testOrgId, 'attendance_recording_method': method});
  if (path == '$_org/attendance/records') return ok(records);
  if (path.endsWith('/punch-logs')) return ok(logs);
  return jsonResponse({
    'success': false,
    'error': {'code': 'NOT_FOUND', 'message': 'unexpected $path'},
  }, 404);
}

Future<TestSession> _setup(
  Future<http.Response> Function(http.Request req) handler,
) async {
  final s = await signedIn(handler);
  AttendanceService.debugOverride(
    repository: AttendanceRepository(auth: s.auth),
  );
  return s;
}

void main() {
  tearDown(AttendanceService.debugReset);

  group('Attendance screen: employee loading', () {
    testWidgets(
      'loads the employee through getMe() (no email lookup) and shows the tabs',
      (tester) async {
        _tall(tester);
        final s = await _setup((req) => _api(req));
        await tester.pumpWidget(
          MaterialApp(
            home: TimeAttendanceScreen(
              userEmail: 'me@x.com',
              userData: _employee,
              fetchHrmsContext: () async => {},
              employeeRepository: EmployeeRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('Employee data not found'), findsNothing);
        expect(find.text('Attendance'), findsWidgets);
        expect(find.text('My History'), findsOneWidget);
        expect(find.text('Regularize'), findsOneWidget);
        expect(
          s.apiCalls.where((r) => r.path == '$_org/employees/me'),
          hasLength(1),
        );
        expect(
          s.apiCalls.any((r) => r.path.contains('/employee_records')),
          isFalse,
        );
        await _unmount(tester);
      },
    );

    testWidgets(
      'a failure to load the employee keeps the existing "Employee data not found" state',
      (tester) async {
        _tall(tester);
        final s = await _setup(
          (req) async => jsonResponse({
            'success': false,
            'error': {'code': 'X', 'message': 'boom'},
          }, 500),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: TimeAttendanceScreen(
              userEmail: 'me@x.com',
              userData: _employee,
              fetchHrmsContext: () async => {},
              employeeRepository: EmployeeRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('Employee data not found'), findsOneWidget);
        await _unmount(tester);
      },
    );
  });

  group('Attendance tab: organization recording method', () {
    testWidgets('biometric-only organizations show the biometric card', (
      tester,
    ) async {
      _tall(tester);
      await _setup((req) => _api(req, method: 'biometric'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttendanceTab(employee: _employee)),
        ),
      );
      await _settle(tester);
      expect(find.text('Biometric Only'), findsOneWidget);
      expect(find.text('Punch In Now'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('in_system organizations show the punch control', (
      tester,
    ) async {
      _tall(tester);
      final s = await _setup((req) => _api(req));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttendanceTab(employee: _employee)),
        ),
      );
      await _settle(tester);
      expect(find.text('Punch In Now'), findsOneWidget);
      expect(find.text('Biometric Only'), findsNothing);
      expect(
        s.apiCalls.any((r) => r.path == _org),
        isTrue,
        reason: 'recording method read from GET /organizations/:orgId',
      );
      await _unmount(tester);
    });

    testWidgets(
      'if the method cannot be read the punch control is not hidden',
      (tester) async {
        _tall(tester);
        await _setup((req) async {
          if (req.url.path == _org)
            return jsonResponse({
              'success': false,
              'error': {'code': 'X', 'message': 'boom'},
            }, 500);
          return _api(req);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AttendanceTab(employee: _employee)),
          ),
        );
        await _settle(tester);
        expect(find.text('Punch In Now'), findsOneWidget);
        await _unmount(tester);
      },
    );
  });

  group('My History tab', () {
    testWidgets(
      'selecting a date: records -> attendance id -> punch logs, shown as cards',
      (tester) async {
        _tall(tester);
        final now = DateTime.now();
        final selected = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime(now.year, now.month, 15));
        final s = await _setup((req) async {
          if (req.url.path == '$_org/attendance/records') {
            return ok(
              req.url.queryParameters['from'] == selected
                  ? [
                      {'id': 'att-15', 'date': '${selected}T00:00:00.000Z'},
                    ]
                  : [],
            );
          }
          if (req.url.path == '$_org/attendance/att-15/punch-logs') {
            return ok([
              {
                'id': 'l1',
                'punch_type': 'punch_in',
                'punch_time': '${selected}T08:39:00.000Z',
                'punch_address': 'MG Road, Bengaluru',
              },
            ]);
          }
          return _api(req);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MyHistoryTab(employee: _employee)),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text('15'));
        await _settle(tester);

        final recordCalls = s.apiCalls
            .where((r) => r.path == '$_org/attendance/records')
            .toList();
        expect(recordCalls.last.query, {
          'employeeId': testEmployeeId,
          'from': selected,
          'to': selected,
        });
        expect(
          s.apiCalls.any((r) => r.path == '$_org/attendance/att-15/punch-logs'),
          isTrue,
        );
        expect(find.text('PUNCH IN'), findsOneWidget);
        expect(find.text('MG Road, Bengaluru'), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets(
      'a date without an attendance row shows the empty state and requests no logs',
      (tester) async {
        _tall(tester);
        final s = await _setup((req) => _api(req, records: const []));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MyHistoryTab(employee: _employee)),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('15'));
        await _settle(tester);
        expect(find.text('No punches for selected date'), findsOneWidget);
        expect(s.apiCalls.any((r) => r.path.endsWith('/punch-logs')), isFalse);
        await _unmount(tester);
      },
    );
  });

  group('Regularization tab', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.tap(find.text('Pick a date'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.tap(find.text('Select time').first);
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Forgot to punch');
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await _settle(tester);
    }

    testWidgets(
      'submits date, requested times and reason; no employee or manager id; success message',
      (tester) async {
        _tall(tester);
        final s = await _setup((req) async {
          if (req.method == 'POST')
            return ok({'id': 'reg-1', 'status': 'pending'}, 201);
          return _api(req);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RegularizationTab(employee: _employee)),
          ),
        );
        await _settle(tester);
        await fillAndSubmit(tester);

        final post = s.requests.where((r) => r.method == 'POST').single;
        expect(post.path, '$_org/attendance/regularizations');
        final body = post.json as Map<String, dynamic>;
        expect(body.keys.toSet(), {'date', 'requestedPunchIn', 'reason'});
        expect(body['date'], DateFormat('yyyy-MM-dd').format(DateTime.now()));
        expect(
          body['requestedPunchIn'],
          matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'),
        );
        expect(body['reason'], 'Forgot to punch');
        expect(
          find.textContaining('Regularization request submitted'),
          findsOneWidget,
        );
        await _unmount(tester);
      },
    );

    testWidgets(
      'a rejected request shows the server message and keeps the form',
      (tester) async {
        _tall(tester);
        await _setup((req) async {
          if (req.method == 'POST') {
            return jsonResponse({
              'success': false,
              'error': {'code': 'NOT_FOUND', 'message': 'Employee not found'},
            }, 404);
          }
          return _api(req);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RegularizationTab(employee: _employee)),
          ),
        );
        await _settle(tester);
        await fillAndSubmit(tester);

        expect(find.text('Employee not found'), findsOneWidget);
        expect(
          find.textContaining('Regularization request submitted'),
          findsNothing,
        );
        expect(
          find.text('Forgot to punch'),
          findsOneWidget,
          reason: 'the form is not cleared on failure',
        );
        await _unmount(tester);
      },
    );

    testWidgets('a server error shows a safe message, not server text', (
      tester,
    ) async {
      _tall(tester);
      await _setup((req) async {
        if (req.method == 'POST') {
          return jsonResponse({
            'success': false,
            'error': {
              'code': 'INTERNAL_SERVER_ERROR',
              'message':
                  'permission denied for function get_current_employee_ids',
            },
          }, 500);
        }
        return _api(req);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RegularizationTab(employee: _employee)),
        ),
      );
      await _settle(tester);
      await fillAndSubmit(tester);
      expect(find.textContaining('permission denied'), findsNothing);
      expect(find.textContaining('try again'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('missing fields are refused before any request', (
      tester,
    ) async {
      _tall(tester);
      final s = await _setup((req) => _api(req));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RegularizationTab(employee: _employee)),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Submit'));
      await _settle(tester);
      expect(find.text('Please fill all required fields'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
      await _unmount(tester);
    });
  });
}
