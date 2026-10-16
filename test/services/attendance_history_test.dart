import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/attendance_repository.dart';
import 'package:hrms_app/services/attendance_service.dart';

import '../helpers/test_auth.dart';

const _recordsPath = '/organizations/$testOrgId/attendance/records';

Future<TestSession> _setup(
  Future<dynamic> Function(String path, Map<String, String> query) handler,
) async {
  final s = await signedIn(
    (req) async => await handler(req.url.path, req.url.queryParameters),
  );
  AttendanceService.debugOverride(
    repository: AttendanceRepository(auth: s.auth),
  );
  return s;
}

void main() {
  tearDown(AttendanceService.debugReset);

  group('getPunchLogs (My History)', () {
    test(
      'records for the date -> attendance id -> punch logs, in that order',
      () async {
        final s = await _setup((path, query) async {
          if (path == _recordsPath) {
            return ok([
              {
                'id': 'att-1',
                'date': '2026-10-08T00:00:00.000Z',
                'punch_in_time': 't',
              },
            ]);
          }
          if (path == '/organizations/$testOrgId/attendance/att-1/punch-logs') {
            return ok([
              {
                'id': 'l1',
                'punch_type': 'punch_in',
                'punch_time': '2026-10-08T08:39:00.000Z',
                'punch_lat': '12.97',
                'punch_address': 'A',
              },
              {
                'id': 'l2',
                'punch_type': 'punch_out',
                'punch_time': '2026-10-08T08:40:00.000Z',
                'punch_lat': '12.97',
                'punch_address': 'A',
              },
            ]);
          }
          return jsonResponse({'success': false}, 404);
        });

        final logs = await AttendanceService.getPunchLogs(
          employeeId: testEmployeeId,
          date: '2026-10-08',
        );

        expect(s.apiCalls.map((r) => '${r.method} ${r.path}'), [
          'GET $_recordsPath',
          'GET /organizations/$testOrgId/attendance/att-1/punch-logs',
        ]);
        expect(s.apiCalls.first.query, {
          'employeeId': testEmployeeId,
          'from': '2026-10-08',
          'to': '2026-10-08',
        });
        expect(logs.map((l) => l['punch_type']), ['punch_in', 'punch_out']);
        expect(logs.first['punch_lat'], 12.97);
        expect(logs.first['punch_address'], 'A');
      },
    );

    test(
      'no attendance row for the selected date -> empty, and no punch-logs request is made',
      () async {
        final s = await _setup((path, query) async => ok([]));
        final logs = await AttendanceService.getPunchLogs(
          employeeId: testEmployeeId,
          date: '2026-10-01',
        );
        expect(logs, isEmpty);
        expect(s.apiCalls, hasLength(1));
        expect(s.apiCalls.single.path, _recordsPath);
      },
    );

    test(
      'a failure reading the logs gives an empty list, not an exception',
      () async {
        await _setup((path, query) async {
          if (path == _recordsPath)
            return ok([
              {'id': 'att-1'},
            ]);
          return jsonResponse({
            'success': false,
            'error': {'code': 'X', 'message': 'boom'},
          }, 500);
        });
        expect(
          await AttendanceService.getPunchLogs(
            employeeId: testEmployeeId,
            date: '2026-10-08',
          ),
          isEmpty,
        );
      },
    );

    // History follows the attendance date the AWS backend recorded (the server's UTC day): an early-morning IST punch
    // can be listed under the previous date. The app applies no timezone conversion; the lookup is by that date as-is.
    test(
      'the date is sent exactly as selected (no timezone conversion in the app)',
      () async {
        final s = await _setup((path, query) async => ok([]));
        await AttendanceService.getPunchLogs(
          employeeId: testEmployeeId,
          date: '2026-10-08',
        );
        expect(s.apiCalls.single.query['from'], '2026-10-08');
        expect(s.apiCalls.single.query['to'], '2026-10-08');
      },
    );
  });

  group('getAttendanceRecordingMethod', () {
    test('returns the organization\'s method', () async {
      await _setup(
        (path, query) async => ok({'attendance_recording_method': 'biometric'}),
      );
      expect(
        await AttendanceService.getAttendanceRecordingMethod(),
        'biometric',
      );
    });

    test('defaults to in_system when none is set', () async {
      await _setup(
        (path, query) async => ok({'attendance_recording_method': null}),
      );
      expect(
        await AttendanceService.getAttendanceRecordingMethod(),
        'in_system',
      );
    });
  });
}
