import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/manager_attendance_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

void main() {
  group('holidays', () {
    test('asks for the window and returns yyyy-MM-dd dates', () async {
      final s = await signedIn((req) async {
        expect(req.url.path, '$_org/holidays');
        return ok([
          {
            'id': 'h1',
            'date': '2026-10-02T00:00:00.000Z',
            'name': 'Gandhi Jayanti',
          },
          {'id': 'h2', 'name': 'No date'},
        ]);
      });
      final list = await ManagerAttendanceRepository(
        auth: s.auth,
      ).holidays(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
      expect(s.apiCalls.single.query, {
        'from': '2026-10-01',
        'to': '2026-10-31',
      });
      expect(list.map((h) => h['date']), ['2026-10-02']);
      expect(list.single['name'], 'Gandhi Jayanti');
    });
  });

  group('workingDays', () {
    Future<Set<String>?> read(Object? value) async {
      final s = await signedIn((req) async {
        expect(req.url.path, _org);
        return ok({'id': testOrgId, 'working_days': value});
      });
      return ManagerAttendanceRepository(auth: s.auth).workingDays();
    }

    test('a list of names, any case or abbreviation', () async {
      expect(await read(['Monday', 'tue', 'WEDNESDAY']), {
        'monday',
        'tuesday',
        'wednesday',
      });
    });

    test('a map of day -> true', () async {
      expect(await read({'monday': true, 'tuesday': false, 'friday': true}), {
        'monday',
        'friday',
      });
    });

    test(
      'missing, empty or unrecognised means unknown, never a guess',
      () async {
        expect(await read(null), isNull);
        expect(await read([]), isNull);
        expect(await read([1, 2, 3]), isNull);
        expect(await read('mon-fri'), isNull);
      },
    );
  });

  group('upcomingLeaves', () {
    test(
      'reads the team summary for the caller and keeps the verified fields',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/leaves/team-summary');
          return ok([
            {
              'employee_id': 'd1',
              'employee_name': 'Dev One',
              'upcoming_leaves': [
                {
                  'from_date': '2026-10-20',
                  'to_date': '2026-10-22',
                  'leave_type': 'Casual',
                  'total_days': 3,
                },
              ],
            },
            {'employee_id': 'd2', 'upcoming_leaves': []},
          ]);
        });
        final map = await ManagerAttendanceRepository(
          auth: s.auth,
        ).upcomingLeaves();
        expect(s.apiCalls.single.query['managerId'], testEmployeeId);
        expect(map['d1']!.single.from, '2026-10-20');
        expect(map['d1']!.single.leaveType, 'Casual');
        expect(map['d1']!.single.covers('2026-10-21'), isTrue);
        expect(map['d1']!.single.covers('2026-10-23'), isFalse);
        expect(map['d2'], isEmpty);
      },
    );
  });

  group('dayPunches', () {
    test(
      'keeps rows with a position and splits track rows from punches',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/attendance/employees/d1/day-punch-logs');
          return ok([
            {
              'punch_type': 'in',
              'punch_time': '2026-10-16T04:00:00Z',
              'punch_lat': '17.38',
              'punch_lng': 78.48,
              'in_fence': true,
            },
            {
              'punch_type': 'track',
              'punch_time': '2026-10-16T05:00:00Z',
              'punch_lat': 17.39,
              'punch_lng': 78.49,
            },
            {
              'punch_type': 'out',
              'punch_time': '2026-10-16T12:00:00Z',
              'punch_lat': null,
              'punch_lng': null,
            },
          ]);
        });
        final d = await ManagerAttendanceRepository(
          auth: s.auth,
        ).dayPunches('d1', date: DateTime(2026, 10, 16));
        expect(s.apiCalls.single.query, {'date': '2026-10-16'});
        expect(d.punches.length, 1);
        expect(d.punches.single['punch_lat'], 17.38);
        expect(d.tracks.length, 1);
        expect(d.hasTrack, isTrue);
        expect(d.points, d.tracks);
      },
    );

    test('without track rows the punches are the points', () async {
      final s = await signedIn(
        (req) async => ok([
          {'punch_type': 'in', 'punch_lat': 1.0, 'punch_lng': 2.0},
        ]),
      );
      final d = await ManagerAttendanceRepository(
        auth: s.auth,
      ).dayPunches('d1', date: DateTime(2026, 10, 16));
      expect(d.hasTrack, isFalse);
      expect(d.points, d.punches);
    });
  });

  group('friendly errors', () {
    test('never contain server text, urls or ids', () {
      const raw = 'db exploded at https://api.hrtoffy.in id 123';
      for (final code in [0, 400, 401, 403, 404, 500, 503]) {
        final msg = friendlyManagerAttendanceError(ApiException(code, raw));
        expect(msg.contains('exploded'), isFalse, reason: '$code');
        expect(msg.contains('http'), isFalse, reason: '$code');
      }
      expect(
        friendlyManagerAttendanceError(const ApiException(403, 'x')),
        "Team attendance isn't available for your role.",
      );
      expect(
        friendlyManagerAttendanceError(StateError('boom')),
        isNot(contains('boom')),
      );
      expect(isRoleRefusal(const ApiException(403, 'x')), isTrue);
      expect(isRoleRefusal(const ApiException(500, 'x')), isFalse);
    });
  });
}
