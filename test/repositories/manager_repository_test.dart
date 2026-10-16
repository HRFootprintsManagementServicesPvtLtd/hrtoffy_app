import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/manager_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _emp(String id, {String? managerId}) => {
  'id': id,
  'employeeId': 'E-$id',
  'fullName': 'Person $id',
  'managerId': managerId,
  'employmentStatus': 'active',
};

void main() {
  group('ManagerRepository.team', () {
    test(
      'lists the tree and the reviewees from the employees route, snake_case, and splits direct from indirect without counting the caller',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/employees');
          if (req.url.queryParameters['managerId'] == testEmployeeId) {
            return ok({
              'items': [
                _emp('d1', managerId: testEmployeeId),
                _emp('i1', managerId: 'd1'),
                _emp(testEmployeeId),
              ],
              'total': 3,
            });
          }
          expect(req.url.queryParameters['reviewerId'], testEmployeeId);
          return ok({
            'items': [_emp('r1', managerId: 'x')],
            'total': 1,
          });
        });
        final team = await ManagerRepository(auth: s.auth).team();
        expect(team.direct.map((m) => m['id']), ['d1']);
        expect(team.indirect.map((m) => m['id']), ['i1']);
        expect(team.reviewees.map((m) => m['id']), ['r1']);
        expect(
          team.direct.single['full_name'],
          'Person d1',
        ); // camelCase from the server, snake_case for the UI
        expect(team.direct.single['employee_id'], 'E-d1');
        expect(team.treeIds, ['d1', 'i1']);
        expect(team.all.map((m) => m['id']), ['d1', 'i1', 'r1']);
      },
    );

    test(
      'everyone with this manager on record is on the team, whatever their status (as on the website)',
      () async {
        final s = await signedIn((req) async {
          if (req.url.queryParameters.containsKey('managerId')) {
            return ok({
              'items': [
                {..._emp('d1', managerId: testEmployeeId), 'status': 'active'},
                {
                  ..._emp('d2', managerId: testEmployeeId),
                  'status': 'inactive',
                },
              ],
              'total': 2,
            });
          }
          return ok({'items': [], 'total': 0});
        });
        final team = await ManagerRepository(auth: s.auth).team();
        expect(team.direct.map((m) => m['id']), ['d1', 'd2']);
        expect(team.treeIds, ['d1', 'd2']);
      },
    );

    test(
      'a person who is both on the tree and a reviewee is listed once in "all"',
      () async {
        final s = await signedIn((req) async {
          final both = _emp('d1', managerId: testEmployeeId);
          return ok({
            'items': [both],
            'total': 1,
          });
        });
        final team = await ManagerRepository(auth: s.auth).team();
        expect(team.all.length, 1);
      },
    );

    test(
      'pages through the server in hundreds until the total is reached',
      () async {
        final pages = <String>[];
        final s = await signedIn((req) async {
          final page = int.parse(req.url.queryParameters['page']!);
          expect(req.url.queryParameters['limit'], '100');
          if (req.url.queryParameters.containsKey('managerId')) {
            pages.add('$page');
            final start = (page - 1) * 100;
            final count = page == 1 ? 100 : 20;
            return ok({
              'items': [
                for (var i = 0; i < count; i++)
                  _emp('e${start + i}', managerId: testEmployeeId),
              ],
              'total': 120,
            });
          }
          return ok({'items': [], 'total': 0});
        });
        final team = await ManagerRepository(auth: s.auth).team();
        expect(pages, ['1', '2']);
        expect(team.direct.length, 120);
      },
    );

    test(
      'a server error is passed on (the screen shows its own safe text)',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'db exploded'},
          }, 500),
        );
        await expectLater(
          ManagerRepository(auth: s.auth).team(),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('ManagerRepository.teamAttendance', () {
    test(
      'asks in chunks of 40 ids with a yyyy-MM-dd window, normalises date and status, newest first',
      () async {
        final calls = <Map<String, String>>[];
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/attendance/records');
          calls.add(req.url.queryParameters);
          final first = req.url.queryParameters['employeeIds']!
              .split(',')
              .first;
          return ok([
            {
              'id': 'a-$first',
              'date': first == 'e0'
                  ? '2026-10-10T00:00:00.000Z'
                  : '2026-10-12T00:00:00.000Z',
              'status': 'half_day',
              'employee_records': {'full_name': 'X'},
            },
          ]);
        });
        final ids = [for (var i = 0; i < 90; i++) 'e$i'];
        final rows = await ManagerRepository(auth: s.auth).teamAttendance(
          ids,
          from: DateTime(2026, 9, 15),
          to: DateTime(2026, 10, 15),
        );
        expect(calls.length, 3);
        expect(calls.map((c) => c['employeeIds']!.split(',').length), [
          40,
          40,
          10,
        ]);
        expect(calls.first['from'], '2026-09-15');
        expect(calls.first['to'], '2026-10-15');
        expect(rows.first['date'], '2026-10-12');
        expect(rows.last['date'], '2026-10-10');
        expect(rows.every((r) => r['status'] == 'half day'), isTrue);
      },
    );

    test('no ids means no request', () async {
      final s = await signedIn((req) async => fail('no request expected'));
      expect(
        await ManagerRepository(
          auth: s.auth,
        ).teamAttendance([], from: DateTime(2026), to: DateTime(2026, 2)),
        isEmpty,
      );
      expect(s.apiCalls, isEmpty);
    });
  });

  group('ManagerRepository celebrations and counts', () {
    test(
      "birthdaysToday reads the celebrations route and shows the department where there is no designation",
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/dashboard/celebrations');
          return ok({
            'birthdays': [
              {'id': 'b1', 'full_name': 'Bina', 'department': 'Finance'},
              {
                'id': 'b2',
                'full_name': 'Raj',
                'department': 'HR',
                'designation': 'Lead',
              },
            ],
            'anniversaries': [],
          });
        });
        final list = await ManagerRepository(auth: s.auth).birthdaysToday();
        expect(list.map((b) => b['designation']), ['Finance', 'Lead']);
      },
    );

    test('approvalCounts keeps only what the server sent', () async {
      final s = await signedIn((req) async {
        expect(req.url.path, '$_org/dashboard/approval-counts');
        return ok({
          'approvals-requests-leaves': 3,
          'approvals-regularization': 1,
        });
      });
      expect(await ManagerRepository(auth: s.auth).approvalCounts(), {
        'approvals-requests-leaves': 3,
        'approvals-regularization': 1,
      });
    });
  });
}
