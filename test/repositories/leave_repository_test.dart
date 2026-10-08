import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/leave_repository.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/employees/$testEmployeeId';

Map<String, dynamic> _row(String id, String status, {String from = '2026-12-04', String to = '2026-12-05', Object? days = 2}) => {
      'id': id,
      'leave_type': 'Casual Leave',
      'from_date': from,
      'to_date': to,
      'total_days': days,
      'reason': 'trip',
      'status': status,
      'manager_name': 'Maya Manager',
      'manager_email': 'maya@x.test',
      'created_at': '2026-11-30T10:00:00.000Z',
    };

void main() {
  group('LeaveRepository.balances', () {
    test('GET /employees/:emp/leave-balances?year, session identity, decimal strings parsed', () async {
      final s = await signedIn((req) async => ok([
            {
              'id': 'b1',
              'employee_id': testEmployeeId,
              'leave_type_id': 'lt-1',
              'leave_type_name': 'Casual Leave',
              'allocated_days': '12.00',
              'used_days': 2,
              'remaining_days': 10,
              'year': 2026,
            },
          ]));
      final rows = await LeaveRepository(auth: s.auth).balances(year: 2026);
      expect(s.last.method, 'GET');
      expect(s.last.path, '$_base/leave-balances');
      expect(s.last.query, {'year': '2026'});
      expect(s.last.headers['Authorization'], 'Bearer acc');
      expect(rows, hasLength(1));
      expect(rows.first.leaveTypeId, 'lt-1');
      expect(rows.first.name, 'Casual Leave');
      expect(rows.first.allocated, 12);
      expect(rows.first.used, 2);
      expect(rows.first.remaining, 10);
      expect(rows.first.year, 2026);
    });

    test('defaults to the current year and tolerates an empty body', () async {
      final s = await signedIn((req) async => ok([]));
      final rows = await LeaveRepository(auth: s.auth).balances();
      expect(rows, isEmpty);
      expect(s.last.query['year'], DateTime.now().year.toString());
    });
  });

  group('LeaveRepository.pendingCount / policies', () {
    test('asks only for open statuses with limit 1 and reads the total', () async {
      final s = await signedIn((req) async => ok({'items': [_row('a', 'pending')], 'total': 3, 'limit': 1, 'offset': 0}));
      final n = await LeaveRepository(auth: s.auth).pendingCount();
      expect(n, 3);
      expect(s.last.path, '$_base/leaves');
      expect(s.last.query['status'], 'pending,manager_approved,reviewer_approved');
      expect(s.last.query['limit'], '1');
    });

    test('policies come from leave-balance-summary -> leavePolicies', () async {
      final s = await signedIn((req) async => ok({
            'leaveApplications': [],
            'leavePolicies': [
              {'id': 'p1', 'name': 'Casual', 'days_allowed': 12},
            ],
            'year': 2026,
          }));
      final p = await LeaveRepository(auth: s.auth).policies(year: 2026);
      expect(s.last.path, '$_base/leave-balance-summary');
      expect(s.last.query, {'year': '2026'});
      expect(p.single['name'], 'Casual');
    });
  });

  group('LeaveRepository.history', () {
    test('pages through the 200-row cap until total is reached, with date-only from/to', () async {
      final s = await signedIn((req) async {
        final offset = int.parse(req.url.queryParameters['offset']!);
        final n = offset == 400 ? 50 : 200;
        return ok({
          'items': [for (var i = 0; i < n; i++) _row('r${offset + i}', 'approved')],
          'total': 450,
          'limit': 200,
          'offset': offset,
        });
      });
      final all = await LeaveRepository(auth: s.auth).history(from: DateTime(2026, 1, 5), to: DateTime(2026, 12, 31));
      expect(all, hasLength(450));
      expect(s.requests.map((r) => r.query['offset']), ['0', '200', '400']);
      expect(s.requests.every((r) => r.path == '$_base/leaves'), isTrue);
      expect(s.requests.first.query['from'], '2026-01-05');
      expect(s.requests.first.query['to'], '2026-12-31');
      expect(s.requests.first.query['limit'], '200');
    });

    test('stops on an empty page even if total is larger (no endless loop)', () async {
      var calls = 0;
      final s = await signedIn((req) async {
        calls++;
        return ok({'items': [], 'total': 999, 'limit': 200, 'offset': 0});
      });
      expect(await LeaveRepository(auth: s.auth).history(), isEmpty);
      expect(calls, 1);
    });

    test('rows: flat manager fields become the nested manager map, status is lower-case, days numeric', () async {
      final s = await signedIn((req) async => ok({
            'items': [
              _row('a', 'PENDING', days: '2.5'),
              {..._row('b', 'approved'), 'manager_name': null, 'manager_email': null},
            ],
            'total': 2,
            'limit': 200,
            'offset': 0,
          }));
      final rows = await LeaveRepository(auth: s.auth).history();
      expect(rows[0]['status'], 'pending');
      expect(rows[0]['total_days'], 2.5);
      expect(rows[0]['manager'], {'full_name': 'Maya Manager', 'email': 'maya@x.test'});
      expect(rows[0]['from_date'], '2026-12-04');
      expect(rows[1]['manager'], isNull);
    });

    test('status filter is sent as a comma list', () async {
      final s = await signedIn((req) async => ok({'items': [], 'total': 0, 'limit': 200, 'offset': 0}));
      await LeaveRepository(auth: s.auth).history(statuses: ['pending', 'approved']);
      expect(s.last.query['status'], 'pending,approved');
    });
  });

  group('LeaveRepository.apply', () {
    test('POST record-application: camelCase body, leave type ID, date-only, no employee / day count sent', () async {
      final s = await signedIn((req) async => ok({'id': 'new1', 'status': 'pending'}, 201));
      final row = await LeaveRepository(auth: s.auth).apply(
        leaveTypeId: 'lt-1',
        from: DateTime(2026, 12, 4, 23, 59),
        to: DateTime(2026, 12, 7),
        reason: 'trip',
      );
      expect(s.last.method, 'POST');
      expect(s.last.path, '/organizations/$testOrgId/leaves/record-application');
      expect(s.last.json, {'leaveTypeId': 'lt-1', 'fromDate': '2026-12-04', 'toDate': '2026-12-07', 'reason': 'trip'});
      expect(row['status'], 'pending');
    });

    test('an attachment URL is sent only when given', () async {
      final s = await signedIn((req) async => ok({'id': 'x'}, 201));
      await LeaveRepository(auth: s.auth)
          .apply(leaveTypeId: 'lt-1', from: DateTime(2026, 1, 2), to: DateTime(2026, 1, 2), reason: 'r', attachmentUrl: 'https://f.test/a.pdf');
      expect(s.last.json['attachmentUrl'], 'https://f.test/a.pdf');
    });

    test('server refusals surface as ApiException with the backend message', () async {
      final s = await signedIn((req) async => jsonResponse({
            'success': false,
            'error': {'code': 'VALIDATION_ERROR', 'message': 'Insufficient leave balance'},
          }, 400));
      await expectLater(
        LeaveRepository(auth: s.auth).apply(leaveTypeId: 'lt-1', from: DateTime(2026, 1, 2), to: DateTime(2026, 1, 3), reason: 'r'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400).having((e) => e.message, 'message', 'Insufficient leave balance')),
      );
    });
  });

  group('LeaveRepository.cancel', () {
    test('PUT /leaves/applications/:id with {status: cancelled}', () async {
      final s = await signedIn((req) async => ok({'id': 'app-1', 'status': 'cancelled'}));
      final row = await LeaveRepository(auth: s.auth).cancel('app-1');
      expect(s.last.method, 'PUT');
      expect(s.last.path, '/organizations/$testOrgId/leaves/applications/app-1');
      expect(s.last.json, {'status': 'cancelled'});
      expect(row['status'], 'cancelled');
    });

    test('a refused cancel (not pending any more) is an ApiException 403', () async {
      final s = await signedIn((req) async => jsonResponse({
            'success': false,
            'error': {'code': 'FORBIDDEN', 'message': 'Only a pending leave request can be cancelled'},
          }, 403));
      await expectLater(LeaveRepository(auth: s.auth).cancel('app-1'), throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true)));
    });
  });

  group('LeaveStatus / helpers', () {
    test('pending-like statuses, rejected, approved and cancelled are grouped as decided', () {
      for (final p in ['pending', 'manager_approved', 'reviewer_approved', 'PENDING']) {
        expect(LeaveStatus.isPendingLike(p), isTrue, reason: p);
      }
      expect(LeaveStatus.isPendingLike('approved'), isFalse);
      expect(LeaveStatus.isPendingLike('cancelled'), isFalse);
      expect(LeaveStatus.isRejected('rejected'), isTrue);
      expect(LeaveStatus.isRejected('reviewer_rejected'), isTrue);
      expect(LeaveStatus.isApproved('approved'), isTrue);
      expect(LeaveStatus.isApproved('manager_approved'), isFalse);
      expect(LeaveStatus.isCancelled('cancelled'), isTrue);
    });

    test('only a pending request can be cancelled by the employee', () {
      expect(LeaveStatus.canCancel('pending'), isTrue);
      for (final s in ['manager_approved', 'reviewer_approved', 'approved', 'rejected', 'cancelled', '', null]) {
        expect(LeaveStatus.canCancel(s), isFalse, reason: '$s');
      }
    });

    test('friendlyLeaveError never leaks raw exception text, tokens or stack traces', () {
      expect(friendlyLeaveError(const ApiException(0, 'SocketException: x')), contains('Network problem'));
      expect(friendlyLeaveError(const ApiException(403, 'x')), contains('permission'));
      expect(friendlyLeaveError(const ApiException(401, 'x')), contains('Session expired'));
      expect(friendlyLeaveError(const ApiException(500, 'boom Bearer abc')), contains('busy'));
      expect(friendlyLeaveError(const ApiException(400, 'Insufficient leave balance')), 'Insufficient leave balance');
      expect(friendlyLeaveError(Exception('Bearer secret-token')), isNot(contains('secret-token')));
    });

    test('formatLeaveDays shows whole days without a decimal', () {
      expect(formatLeaveDays(7), '7');
      expect(formatLeaveDays(7.0), '7');
      expect(formatLeaveDays(7.5), '7.5');
    });
  });
}
