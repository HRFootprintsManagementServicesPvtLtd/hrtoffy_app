import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/attendance_repository.dart';

import '../helpers/test_auth.dart';

void main() {
  group('attendanceRecordingMethod', () {
    test(
      'GET /organizations/:orgId and reads attendance_recording_method',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'id': testOrgId,
            'name': 'Goodclap',
            'attendance_recording_method': 'both',
          }),
        );
        final method = await AttendanceRepository(
          auth: s.auth,
        ).attendanceRecordingMethod();
        expect(s.last.method, 'GET');
        expect(s.last.path, '/organizations/$testOrgId');
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(method, 'both');
      },
    );

    test('null when the organization has none set', () async {
      final s = await signedIn(
        (req) async =>
            ok({'id': testOrgId, 'attendance_recording_method': null}),
      );
      expect(
        await AttendanceRepository(auth: s.auth).attendanceRecordingMethod(),
        isNull,
      );
    });
  });

  group('attendancePunchLogs', () {
    test(
      'GET /attendance/:id/punch-logs, decimal strings become numbers',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 'l1',
              'attendance_id': 'att-1',
              'punch_type': 'punch_in',
              'punch_time': '2026-10-08T08:39:00.000Z',
              'punch_lat': '12.9716000',
              'punch_lng': '77.5946000',
              'punch_address': 'MG Road',
              'in_fence': true,
              'distance_m': '12.50',
              'accuracy_m': '8.50',
            },
          ]),
        );
        final rows = await AttendanceRepository(
          auth: s.auth,
        ).attendancePunchLogs('att-1');
        expect(
          s.last.path,
          '/organizations/$testOrgId/attendance/att-1/punch-logs',
        );
        expect(rows.single['punch_lat'], 12.9716);
        expect(rows.single['punch_lng'], 77.5946);
        expect(rows.single['distance_m'], 12.5);
        expect(rows.single['accuracy_m'], 8.5);
        expect(rows.single['punch_address'], 'MG Road');
      },
    );
  });

  group('submitRegularization', () {
    test(
      'POST /attendance/regularizations with only date, times and reason (no employeeId / managerId)',
      () async {
        final s = await signedIn(
          (req) async => ok({'id': 'reg-1', 'status': 'pending'}, 201),
        );
        final row = await AttendanceRepository(auth: s.auth)
            .submitRegularization(
              date: '2026-10-07',
              requestedPunchIn: '2026-10-07T03:30:00.000Z',
              requestedPunchOut: '2026-10-07T12:30:00.000Z',
              reason: 'Forgot to punch',
            );
        expect(s.last.method, 'POST');
        expect(
          s.last.path,
          '/organizations/$testOrgId/attendance/regularizations',
        );
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(s.last.json, {
          'date': '2026-10-07',
          'requestedPunchIn': '2026-10-07T03:30:00.000Z',
          'requestedPunchOut': '2026-10-07T12:30:00.000Z',
          'reason': 'Forgot to punch',
        });
        for (final k in [
          'employeeId',
          'employee_id',
          'managerId',
          'manager_id',
          'status',
          'organizationId',
        ]) {
          expect((s.last.json as Map).containsKey(k), isFalse, reason: k);
        }
        expect(row['status'], 'pending');
      },
    );

    test('the optional punch-out is omitted when not given', () async {
      final s = await signedIn((req) async => ok({'id': 'reg-1'}, 201));
      await AttendanceRepository(auth: s.auth).submitRegularization(
        date: '2026-10-07',
        requestedPunchIn: '2026-10-07T03:30:00.000Z',
        reason: 'r',
      );
      expect((s.last.json as Map).containsKey('requestedPunchOut'), isFalse);
    });

    test(
      'a rejected request surfaces as ApiException with the server message',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'code': 'NOT_FOUND', 'message': 'Employee not found'},
          }, 404),
        );
        await expectLater(
          AttendanceRepository(auth: s.auth).submitRegularization(
            date: '2026-10-07',
            requestedPunchIn: '2026-10-07T03:30:00.000Z',
            reason: 'r',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Employee not found',
            ),
          ),
        );
      },
    );

    test('a server error gives a safe message', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {
            'code': 'INTERNAL_SERVER_ERROR',
            'message': 'An unexpected error occurred',
          },
        }, 500),
      );
      final err = await AttendanceRepository(auth: s.auth)
          .submitRegularization(date: 'x', requestedPunchIn: 'y', reason: 'r')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(friendlyAttendanceError(err!), contains('try again'));
    });
  });
}
