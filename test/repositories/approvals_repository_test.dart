import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _exec(String id, String module, {String? name}) => {
  'id': id,
  'module_name': module,
  'record_id': 'rec-$id',
  'status': 'in_progress',
  'current_step_index': 0,
  'record': {
    'id': 'rec-$id',
    'employee_full_name': name ?? 'Dev $id',
    'employee_code': 'E-$id',
  },
};

_err(int status, String message, {String? code}) => jsonResponse({
  'success': false,
  'error': {'message': message, if (code != null) 'code': code},
}, status);

void main() {
  group('inbox', () {
    test(
      'a manager reads GET /approvals only, 100 per page, snake_case, and can narrow to one module',
      () async {
        final s = await signedIn((req) async {
          expect(req.method, 'GET');
          expect(req.url.path, '$_org/approvals');
          expect(req.url.queryParameters['limit'], '100');
          return ok({
            'executions': [
              _exec('1', 'leaves'),
              _exec('2', 'expenses'),
              _exec('3', 'travel_claims'),
            ],
            'total': 3,
          });
        }, empRole: 'manager');
        final repo = ApprovalsRepository(auth: s.auth);
        expect((await repo.inbox()).length, 3);
        final travel = await repo.inbox(module: 'travel');
        expect(travel.map((e) => e['id']), ['3']); // alias -> canonical
        expect(travel.single['record']['employee_full_name'], 'Dev 3');
        expect(s.apiCalls.every((r) => r.path == '$_org/approvals'), isTrue);
      },
    );

    test('pages until the total is reached', () async {
      final offsets = <String>[];
      final s = await signedIn((req) async {
        final off = int.parse(req.url.queryParameters['offset']!);
        offsets.add('$off');
        final n = off == 0 ? 100 : 20;
        return ok({
          'executions': [
            for (var i = 0; i < n; i++) _exec('p${off + i}', 'leaves'),
          ],
          'total': 120,
        });
      }, empRole: 'manager');
      final all = await ApprovalsRepository(auth: s.auth).inbox();
      expect(offsets, ['0', '100']);
      expect(all.length, 120);
    });

    test(
      'a reviewer also reads /reviewer-queue; the same execution is listed once; a failing second queue does not hide the first',
      () async {
        var queueFails = false;
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/approvals') {
            return ok({
              'executions': [_exec('1', 'leaves')],
              'total': 1,
            });
          }
          expect(req.url.path, '$_org/reviewer-queue');
          if (queueFails) return _err(500, 'boom');
          return ok({
            'executions': [_exec('1', 'leaves'), _exec('9', 'leaves')],
            'total': 2,
          });
        }, empRole: 'reviewer');
        final repo = ApprovalsRepository(auth: s.auth);
        expect((await repo.inbox(module: 'leaves')).map((e) => e['id']), [
          '1',
          '9',
        ]);
        queueFails = true;
        expect((await repo.inbox(module: 'leaves')).map((e) => e['id']), ['1']);
      },
    );

    test('a failing /approvals is passed on', () async {
      final s = await signedIn(
        (req) async => _err(500, 'db exploded'),
        empRole: 'manager',
      );
      await expectLater(
        ApprovalsRepository(auth: s.auth).inbox(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('decisions', () {
    test(
      'inbox approve posts {comments} to /approvals/:id/approve and inbox reject posts {reason} (never a status)',
      () async {
        final s = await signedIn((req) async {
          return ok({'success': true, 'status': 'completed'});
        });
        final repo = ApprovalsRepository(auth: s.auth);
        await repo.approveInbox('x1', comments: ' ok ');
        await repo.approveInbox('x2');
        await repo.rejectInbox('x3', reason: ' too many days ');
        final calls = s.apiCalls;
        expect(calls.map((r) => '${r.method} ${r.path}'), [
          'POST $_org/approvals/x1/approve',
          'POST $_org/approvals/x2/approve',
          'POST $_org/approvals/x3/reject',
        ]);
        expect(calls[0].json, {'comments': 'ok'});
        expect(
          calls[1].json,
          {},
        ); // the route destructures its body: always an object
        expect(calls[2].json, {'reason': 'too many days'});
        for (final r in calls) {
          expect(r.body.contains('status'), isFalse);
          expect(r.body.contains('approved_by'), isFalse);
        }
      },
    );

    test(
      'an inbox decision the server answers with no data is "not found"',
      () async {
        final s = await signedIn((req) async => ok(null));
        final repo = ApprovalsRepository(auth: s.auth);
        await expectLater(
          repo.approveInbox('x'),
          throwsA(
            isA<ApiException>().having((e) => e.isNotFound, 'notFound', true),
          ),
        );
      },
    );

    test(
      'a rejection without a reason is refused before any request',
      () async {
        final s = await signedIn((req) async => fail('no request expected'));
        final repo = ApprovalsRepository(auth: s.auth);
        await expectLater(
          repo.rejectInbox('x', reason: '  '),
          throwsArgumentError,
        );
        await expectLater(
          repo.rejectWorkflow('leaves', 'r', comments: ''),
          throwsArgumentError,
        );
        await expectLater(
          repo.rejectRegularization('r', comments: ''),
          throwsArgumentError,
        );
        await expectLater(
          repo.rejectOvertime('r', comments: ' '),
          throwsArgumentError,
        );
        expect(s.apiCalls, isEmpty);
      },
    );

    test(
      'workflow approve/reject post to /workflows/module/:module/:record/... with comments and an optional approved amount',
      () async {
        final s = await signedIn((req) async => ok(null));
        final repo = ApprovalsRepository(auth: s.auth);
        await repo.approveWorkflow(
          'travel',
          'r1',
          comments: 'fine',
          approvedAmount: 900,
        );
        await repo.approveWorkflow('expenses', 'r2');
        await repo.rejectWorkflow('benefits', 'r3', comments: 'no proof');
        final c = s.apiCalls;
        expect(c[0].path, '$_org/workflows/module/travel_claims/r1/approve');
        expect(c[0].json, {
          'comments': 'fine',
          'decision': {'approved_amount': 900},
        });
        expect(c[1].path, '$_org/workflows/module/expenses/r2/approve');
        expect(c[1].json, {});
        expect(c[2].path, '$_org/workflows/module/benefits/r3/reject');
        expect(c[2].json, {'comments': 'no proof'});
      },
    );

    test(
      'row-meta posts {recordIds} and reads the engine answer (camelCase from the server)',
      () async {
        final s = await signedIn((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '$_org/workflows/module/overtime/row-meta');
          return ok({
            'a': {
              'executionFound': true,
              'canApprove': true,
              'requiredRole': 'manager',
            },
            'b': {
              'executionFound': true,
              'canApprove': false,
              'reason': 'internal words',
            },
          });
        });
        final meta = await ApprovalsRepository(
          auth: s.auth,
        ).rowMeta('ot', ['a', 'b']);
        expect(s.last.json, {
          'recordIds': ['a', 'b'],
        });
        expect(meta['a']!.canApprove, isTrue);
        expect(meta['a']!.requiredRole, 'manager');
        expect(meta['b']!.canApprove, isFalse);
        expect(
          await ApprovalsRepository(auth: s.auth).rowMeta('overtime', []),
          isEmpty,
        );
        expect(s.apiCalls.length, 1); // no ids, no request
      },
    );

    test('can-approve reads GET .../:record/can-approve', () async {
      final s = await signedIn((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '$_org/workflows/module/loans/r1/can-approve');
        return ok({'canApprove': true, 'mode': 'owner'});
      });
      expect(
        (await ApprovalsRepository(
          auth: s.auth,
        ).canApprove('loans', 'r1')).canApprove,
        isTrue,
      );
    });
  });

  group('regularization and overtime', () {
    test(
      'regularization lists pending (100) and history (approved,rejected; 50) from the time service route',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/attendance/regularization-requests');
          return ok({
            'requests': [
              {
                'id': 'g1',
                'status': 'pending',
                'employeeRecords': {'fullName': 'Dev'},
              },
            ],
          });
        });
        final repo = ApprovalsRepository(auth: s.auth);
        final pending = await repo.regularizations(history: false);
        expect(pending.single['employee_records']['full_name'], 'Dev');
        await repo.regularizations(history: true);
        expect(s.apiCalls[0].query, {'status': 'pending', 'limit': '100'});
        expect(s.apiCalls[1].query, {
          'status': 'approved,rejected',
          'limit': '50',
        });
      },
    );

    test(
      'regularization decisions post {comments} to .../:id/approve|reject, nothing is written to attendance',
      () async {
        final s = await signedIn((req) async => ok({'id': 'g1'}));
        final repo = ApprovalsRepository(auth: s.auth);
        await repo.approveRegularization('g1', comments: 'ok');
        await repo.rejectRegularization('g2', comments: 'no');
        expect(s.apiCalls.map((r) => '${r.method} ${r.path}'), [
          'POST $_org/attendance/regularization-requests/g1/approve',
          'POST $_org/attendance/regularization-requests/g2/reject',
        ]);
        expect(s.apiCalls[0].json, {'comments': 'ok'});
        expect(s.apiCalls[1].json, {'comments': 'no'});
        expect(
          s.apiCalls.any((r) => r.path.contains('/attendance/records')),
          isFalse,
        );
      },
    );

    test(
      'overtime: pending asks status=pending; history asks all and keeps decided rows, newest first, at most 50',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/attendance/overtime/approvable');
          return ok([
            for (var i = 0; i < 60; i++) {'id': 'o$i', 'status': 'approved'},
            {'id': 'p', 'status': 'pending'},
            {'id': 'r', 'status': 'rejected'},
          ]);
        });
        final repo = ApprovalsRepository(auth: s.auth);
        final hist = await repo.overtime(history: true);
        expect(hist.length, 50);
        expect(hist.every((r) => r['status'] != 'pending'), isTrue);
        await repo.overtime(history: false);
        expect(s.apiCalls[0].query['status'], 'all');
        expect(s.apiCalls[1].query['status'], 'pending');
      },
    );

    test('overtime decisions use the records routes', () async {
      final s = await signedIn((req) async => ok({'id': 'o1'}));
      final repo = ApprovalsRepository(auth: s.auth);
      await repo.approveOvertime('o1');
      await repo.rejectOvertime('o2', comments: 'not authorised');
      expect(
        s.apiCalls[0].path,
        '$_org/attendance/overtime/records/o1/approve',
      );
      expect(s.apiCalls[0].json, {});
      expect(s.apiCalls[1].path, '$_org/attendance/overtime/records/o2/reject');
      expect(s.apiCalls[1].json, {'comments': 'not authorised'});
    });
  });

  test('counts keeps what the dashboard route sent', () async {
    final s = await signedIn((req) async {
      expect(req.url.path, '$_org/dashboard/approval-counts');
      return ok({'approvals-requests-leaves': 4});
    });
    expect(await ApprovalsRepository(auth: s.auth).counts(), {
      'approvals-requests-leaves': 4,
    });
  });

  group('approvalsErrorText', () {
    const raw = 'prisma P2002 at https://api.hrtoffy.in id 1234-uuid';

    String text(int status, {String message = raw, String? code}) =>
        approvalsErrorText(ApiException(status, message, code: code));

    test('known engine refusals read as friendly sentences', () {
      expect(
        text(403, message: 'You cannot approve your own request'),
        "You can't decide your own request.",
      );
      expect(
        text(403, code: 'SELF_APPROVAL'),
        "You can't decide your own request.",
      );
      expect(
        text(403, message: 'This request has already been decided'),
        'This request was already decided.',
      );
      expect(
        text(400, code: 'NOT_PENDING'),
        'This request was already decided.',
      );
      expect(
        text(400, message: 'override_reason required'),
        'A reason is needed to decide this request.',
      );
      expect(
        text(403, code: 'NOT_ALLOWED'),
        "You can't decide this request. It is waiting for another approver.",
      );
      expect(text(403), "You can't decide this request.");
      expect(text(404), 'This request is no longer available.');
      expect(text(401), 'Your session has expired. Please sign in again.');
      expect(
        text(0),
        'No connection. Please check your internet and try again.',
      );
      expect(text(500), "Couldn't complete this. Please try again.");
      expect(
        text(400),
        "This request couldn't be processed. Please refresh and try again.",
      );
    });

    test('raw server text, urls and ids never reach the user', () {
      for (final status in [0, 400, 401, 403, 404, 409, 500]) {
        final t = text(status);
        expect(t.contains('prisma'), isFalse);
        expect(t.contains('http'), isFalse);
        expect(t.contains('uuid'), isFalse);
      }
      expect(
        approvalsErrorText(StateError('secret internals')),
        "Couldn't complete this. Please try again.",
      );
    });

    test('stale-list detection', () {
      expect(approvalIsStale(const ApiException(403, 'x')), isTrue);
      expect(approvalIsStale(const ApiException(404, 'x')), isTrue);
      expect(approvalIsStale(const ApiException(500, 'x')), isFalse);
      expect(approvalIsStale(const ApiException(0, 'x')), isFalse);
    });
  });

  test(
    'the repository has no Supabase, no direct status write and no HR-only leave route',
    () {
      final src = File(
        'lib/repositories/approvals_repository.dart',
      ).readAsStringSync();
      for (final banned in [
        'supabase',
        'Supabase',
        '.update(',
        '.upsert(',
        'approved_by',
        '/leaves/reviewer-scope',
        '/leaves/manager-hierarchy',
        'print(',
      ]) {
        expect(src.contains(banned), isFalse, reason: 'found "$banned"');
      }
      // the one leave write is the decision route, sent through the approval engine by the time service
      expect("orgPath('/leaves/applications".allMatches(src).length, 1);
      expect(src.contains('api.put('), isTrue);
    },
  );
}
