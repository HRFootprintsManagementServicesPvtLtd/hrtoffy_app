import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/attendance_repository.dart';

import '../helpers/test_auth.dart';

const _punchPath = '/organizations/$testOrgId/attendance/punch';

Map<String, dynamic> _punchData({bool success = true}) => {
  'success': success,
  'punch_log_id': 'log-1',
  'attendance_id': 'att-1',
  'punch_time': '2026-10-08T04:30:00.000Z',
  'punch_type': 'punch_in',
  'in_fence': true,
  'distance_m': '12.5',
  'site_id': 'site-1',
  'is_suspicious': false,
  'suspicion_reasons': <String>[],
};

void main() {
  group('AttendanceRepository.punch', () {
    test(
      'Punch In: POST /attendance/punch with the bearer token and exactly the agreed body',
      () async {
        final s = await signedIn((req) async => ok(_punchData(), 200));
        final result = await AttendanceRepository(auth: s.auth).punch(
          punchType: 'punch_in',
          workType: 'on-duty',
          latitude: 12.9716,
          longitude: 77.5946,
          accuracy: 8.5,
          address: 'MG Road, Bengaluru',
          siteId: 'site-1',
          inFence: true,
          distanceM: 42.0,
        );
        expect(s.last.method, 'POST');
        expect(s.last.path, _punchPath);
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(s.last.json, {
          'employeeId': testEmployeeId,
          'punchType': 'punch_in',
          'workType': 'on-duty',
          'punchSource': 'mobile',
          'latitude': 12.9716,
          'longitude': 77.5946,
          'accuracy': 8.5,
          'address': 'MG Road, Bengaluru',
          'siteId': 'site-1',
          'inFence': true,
          'distanceM': 42.0,
          'clientSignals': null,
        });
        // the device clock and date are never sent: the server decides both
        for (final k in [
          'punchTime',
          'punch_time',
          'date',
          'punch_in_time',
          'timestamp',
        ]) {
          expect((s.last.json as Map).containsKey(k), isFalse, reason: k);
        }
        expect(result.attendanceId, 'att-1');
        expect(result.punchLogId, 'log-1');
        expect(result.punchType, 'punch_in');
        expect(result.inFence, true);
        expect(result.distanceM, 12.5);
        expect(result.siteId, 'site-1');
        expect(result.isSuspicious, false);
        expect(result.punchTime, DateTime.utc(2026, 10, 8, 4, 30));
      },
    );

    test(
      'Punch Out: same endpoint, punch_out and the selected work type',
      () async {
        final s = await signedIn(
          (req) async => ok({..._punchData(), 'punch_type': 'punch_out'}),
        );
        final result = await AttendanceRepository(auth: s.auth).punch(
          punchType: 'punch_out',
          workType: 'work-from-home',
          latitude: 1.5,
          longitude: 2.5,
          accuracy: 5,
          address: 'a',
        );
        final body = s.last.json as Map;
        expect(s.last.path, _punchPath);
        expect(body['punchType'], 'punch_out');
        expect(body['workType'], 'work-from-home');
        expect(body['punchSource'], 'mobile');
        expect(result.punchType, 'punch_out');
      },
    );

    test(
      'no site evaluated: siteId, inFence and distanceM go out as null (the server resolves the fence)',
      () async {
        final s = await signedIn((req) async => ok(_punchData()));
        await AttendanceRepository(auth: s.auth).punch(
          punchType: 'punch_in',
          workType: 'on-site',
          latitude: 1,
          longitude: 2,
          accuracy: 3,
          address: 'x',
        );
        final body = s.last.json as Map<String, dynamic>;
        expect(body.containsKey('siteId') && body['siteId'] == null, isTrue);
        expect(body.containsKey('inFence') && body['inFence'] == null, isTrue);
        expect(
          body.containsKey('distanceM') && body['distanceM'] == null,
          isTrue,
        );
        expect(body['clientSignals'], isNull);
      },
    );

    test(
      'success:false inside an HTTP 200 is a failed punch with the server reason',
      () async {
        final s = await signedIn(
          (req) async => ok({'success': false, 'error': 'Already punched in'}),
        );
        await expectLater(
          AttendanceRepository(auth: s.auth).punch(
            punchType: 'punch_in',
            workType: 'on-duty',
            latitude: 1,
            longitude: 2,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', 'Already punched in')
                .having((e) => e.code, 'code', 'PUNCH_REJECTED'),
          ),
        );
      },
    );

    test(
      'success missing or not exactly true is also a failure; a reason-less failure gets a safe default',
      () async {
        final s = await signedIn((req) async => ok({'attendance_id': 'att-1'}));
        await expectLater(
          AttendanceRepository(
            auth: s.auth,
          ).punch(punchType: 'punch_in', workType: 'on-duty'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Your punch could not be recorded.',
            ),
          ),
        );
      },
    );

    test('a non-object response is rejected', () async {
      final s = await signedIn((req) async => ok(null));
      await expectLater(
        AttendanceRepository(
          auth: s.auth,
        ).punch(punchType: 'punch_in', workType: 'on-duty'),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'an API error surfaces as ApiException (403 biometric-only org keeps its message)',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {
              'code': 'FORBIDDEN',
              'message':
                  'Attendance is recorded from biometric devices only for this organization',
            },
          }, 403),
        );
        final err = await AttendanceRepository(auth: s.auth)
            .punch(punchType: 'punch_in', workType: 'on-duty')
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(err, isA<ApiException>());
        expect(
          friendlyAttendanceError(err!),
          contains('biometric devices only'),
        );
      },
    );

    test('a 500 never leaks server or database text', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {
            'code': 'INTERNAL_SERVER_ERROR',
            'message':
                'permission denied for function get_current_employee_ids',
          },
        }, 500),
      );
      final err = await AttendanceRepository(auth: s.auth)
          .punch(punchType: 'punch_in', workType: 'on-duty')
          .then<Object?>((_) => null, onError: (Object e) => e);
      final msg = friendlyAttendanceError(err!);
      expect(msg, isNot(contains('permission denied')));
      expect(msg, isNot(contains('get_current_employee_ids')));
      expect(msg, contains('try again'));
    });
  });

  group('AttendanceRepository reads', () {
    test(
      'punchStatus: GET /employees/:emp/punch-status, shape normalised',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'latestPunch': {
              'punch_type': 'punch_in',
              'punch_time': 't',
              'created_at': 'c',
            },
            'attendance': {'id': 'att-1', 'work_type': 'on-duty'},
            'punchLogs': [
              {
                'punch_time': 't',
                'punch_type': 'punch_in',
                'work_type': 'on-duty',
                'punch_source': 'mobile',
              },
            ],
            'today': '2026-10-08',
          }),
        );
        final st = await AttendanceRepository(auth: s.auth).punchStatus();
        expect(
          s.last.path,
          '/organizations/$testOrgId/employees/$testEmployeeId/punch-status',
        );
        expect((st['attendance'] as Map)['work_type'], 'on-duty');
        expect((st['punchLogs'] as List), hasLength(1));
        expect(st['today'], '2026-10-08');
      },
    );

    test('punchStatus with nothing today', () async {
      final s = await signedIn(
        (req) async => ok({
          'latestPunch': null,
          'attendance': null,
          'punchLogs': [],
          'today': '2026-10-08',
        }),
      );
      final st = await AttendanceRepository(auth: s.auth).punchStatus();
      expect(st['attendance'], isNull);
      expect(st['latestPunch'], isNull);
      expect(st['punchLogs'], isEmpty);
    });

    test('attendanceRecords: employeeId, from and to as query', () async {
      final s = await signedIn(
        (req) async => ok([
          {'id': 'a1', 'date': '2026-10-08'},
        ]),
      );
      final rows = await AttendanceRepository(
        auth: s.auth,
      ).attendanceRecords(from: '2026-10-08', to: '2026-10-08');
      expect(s.last.path, '/organizations/$testOrgId/attendance/records');
      expect(s.last.query, {
        'employeeId': testEmployeeId,
        'from': '2026-10-08',
        'to': '2026-10-08',
      });
      expect(rows.single['id'], 'a1');
    });

    test(
      'dayPunchLogs: date (+ attendanceId) query, decimal fields become numbers',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 'l1',
              'punch_type': 'punch_in',
              'punch_lat': '12.9716000',
              'punch_lng': '77.5946000',
              'distance_m': 12.5,
              'accuracy_m': '8.50',
              'site_name': null,
            },
          ]),
        );
        final rows = await AttendanceRepository(
          auth: s.auth,
        ).dayPunchLogs(date: '2026-10-08', attendanceId: 'att-1');
        expect(
          s.last.path,
          '/organizations/$testOrgId/attendance/employees/$testEmployeeId/day-punch-logs',
        );
        expect(s.last.query, {'date': '2026-10-08', 'attendanceId': 'att-1'});
        expect(rows.single['punch_lat'], 12.9716);
        expect(rows.single['punch_lng'], 77.5946);
        expect(rows.single['accuracy_m'], 8.5);
        expect(rows.single['distance_m'], 12.5);
      },
    );

    test('geoPolicy: API camelCase -> the keys the screens read', () async {
      final s = await signedIn(
        (req) async => ok({
          'enabled': true,
          'defaultRadiusMeters': 150,
          'mode': 'lenient',
          'onlyForOffice': true,
          'trackAllPunches': false,
        }),
      );
      final p = await AttendanceRepository(auth: s.auth).geoPolicy();
      expect(s.last.path, '/organizations/$testOrgId/geo-fencing-policy');
      expect(p['geo_fencing_enabled'], true);
      expect(p['geo_fencing_mode'], 'lenient');
      expect(p['geo_only_for_office'], true);
      expect(p['geo_track_all_punches'], false);
      expect(p['geo_fencing_radius'], 150);
    });

    test(
      'workSites: strict query params, camelCase -> snake_case maps',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 'w1',
              'name': 'HQ',
              'latitude': 12.9,
              'longitude': 77.5,
              'radiusMeters': 200,
              'isActive': true,
              'branchId': 'b1',
              'entityId': 'e1',
            },
          ]),
        );
        final sites = await AttendanceRepository(
          auth: s.auth,
        ).workSites(isActive: true);
        expect(s.last.path, '/organizations/$testOrgId/work-sites');
        expect(s.last.query, {'isActive': 'true'});
        expect(sites.single['radius_meters'], 200);
        expect(sites.single['branch_id'], 'b1');
        expect(sites.single['is_active'], true);
      },
    );

    test('workSiteAssignments: filtered to the employee', () async {
      final s = await signedIn(
        (req) async => ok([
          {'id': 'x', 'workSiteId': 'w1', 'employeeId': testEmployeeId},
        ]),
      );
      final rows = await AttendanceRepository(
        auth: s.auth,
      ).workSiteAssignments();
      expect(s.last.path, '/organizations/$testOrgId/work-site-assignments');
      expect(s.last.query, {'employeeId': testEmployeeId});
      expect(rows.single['work_site_id'], 'w1');
    });
  });
}
