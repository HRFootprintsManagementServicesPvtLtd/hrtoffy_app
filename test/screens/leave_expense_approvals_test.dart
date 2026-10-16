import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/repositories/expense_repository.dart';
import 'package:hrms_app/screens/manager/widgets/expense_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/leave_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/partitioned_approvals.dart';
import 'package:http/http.dart' as http;

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

http.Response _fail(
  int status, [
  String msg = 'db exploded at https://x.in id 99',
]) => jsonResponse({
  'success': false,
  'error': {'message': msg},
}, status);

Map<String, dynamic> _leave(
  String id,
  String name,
  String status, {
  String? employeeId,
}) => {
  'id': id,
  'employee_id': employeeId ?? 'emp-$id',
  'leave_type': 'casual_leave',
  'from_date': '2026-10-20T00:00:00.000Z',
  'to_date': '2026-10-22T00:00:00.000Z',
  'total_days': '3.0',
  'reason': 'Family function $id',
  'status': status,
  'employee_records': {
    'id': 'emp-$id',
    'full_name': name,
    'employee_id': 'E-$id',
    'department': 'Ops',
  },
};

Map<String, dynamic> _claim(
  String id,
  String name,
  String status, {
  String? employeeId,
  Object? amount = '1250.00',
}) => {
  'id': id,
  'employee_id': employeeId ?? 'emp-$id',
  'title': 'Claim $id',
  'status': status,
  'amount': amount,
  'category_id': 'c1',
  'expense_date': '2026-10-05T00:00:00.000Z',
  'employee_records': {
    'full_name': name,
    'employee_id': 'E-$id',
    'department': 'Ops',
  },
};

class _Server {
  _Server({
    this.leaves = const [],
    this.history = const [],
    this.claims = const [],
    this.meta = const {},
    this.metaStatus = 200,
    this.writeStatus = 200,
    this.writeMessage = 'x',
  });
  List<Map<String, dynamic>> leaves;
  List<Map<String, dynamic>> history;
  List<Map<String, dynamic>> claims;
  Map<String, Map<String, dynamic>> meta;
  int metaStatus;
  int writeStatus;
  String writeMessage;
  int leaveListCalls = 0;

  Future<TestSession> session() => signedIn((req) async {
    final p = req.url.path;
    if (p == '$_org/leaves/team-applications') {
      leaveListCalls++;
      final hist = req.url.queryParameters['status']!.startsWith('approved');
      return ok(hist ? history : leaves);
    }
    if (p == '$_org/expenses' && req.method == 'GET') return ok(claims);
    if (p == '$_org/expenses/categories') {
      return ok([
        {'id': 'c1', 'name': 'Travel', 'is_active': true},
      ]);
    }
    if (p.endsWith('/row-meta')) {
      return metaStatus == 200 ? ok(meta) : _fail(metaStatus);
    }
    if (req.method == 'PUT' || req.method == 'POST') {
      return writeStatus == 200
          ? ok({'id': 'x'})
          : _fail(writeStatus, writeMessage);
    }
    return _fail(404);
  }, empRole: 'manager');
}

Map<String, dynamic> _can(String role) => {
  'executionFound': true,
  'canApprove': true,
  'requiredRole': role,
};
Map<String, dynamic> _cannot(String role) => {
  'executionFound': true,
  'canApprove': false,
  'requiredRole': role,
  'reason': 'NOT_ALLOWED',
};

void main() {
  group('ApprovalsRepository additions', () {
    test(
      'leaveApplications, decideLeave and the expense routes use exact routes and bodies',
      () async {
        final srv = _Server(
          leaves: [_leave('a', 'A', 'pending')],
          claims: [_claim('e1', 'E', 'pending')],
        );
        final s = await srv.session();
        final repo = ApprovalsRepository(auth: s.auth);
        await repo.leaveApplications(history: false);
        await repo.leaveApplications(history: true);
        await repo.decideLeave('L1', approve: true);
        await repo.decideLeave('L1', approve: true, comments: ' ok ');
        await repo.decideLeave('L2', approve: false, comments: ' no ');
        await repo.approveExpense('E1');
        await repo.rejectExpense('E2', reason: ' bad ');
        final calls = s.apiCalls;
        expect(calls[0].path, '$_org/leaves/team-applications');
        expect(calls[0].query, {
          'status': 'pending,manager_approved,reviewer_approved',
        });
        expect(calls[1].query, {
          'status': 'approved,rejected,reviewer_rejected,cancelled',
        });
        expect(
          '${calls[2].method} ${calls[2].path}',
          'PUT $_org/leaves/applications/L1',
        );
        expect(calls[2].json, {'status': 'approved'});
        expect(calls[3].json, {'status': 'approved', 'manager_comments': 'ok'});
        expect(
          '${calls[4].method} ${calls[4].path}',
          'PUT $_org/leaves/applications/L2',
        );
        expect(calls[4].json, {'status': 'rejected', 'manager_comments': 'no'});
        expect(
          '${calls[5].method} ${calls[5].path}',
          'POST $_org/expenses/E1/approve',
        );
        expect(calls[5].json, <String, dynamic>{});
        expect(
          '${calls[6].method} ${calls[6].path}',
          'POST $_org/expenses/E2/reject',
        );
        expect(calls[6].json, {'reason': 'bad'});
      },
    );

    test(
      'a rejection without a reason is refused before any request',
      () async {
        final s = await _Server().session();
        final repo = ApprovalsRepository(auth: s.auth);
        await expectLater(
          repo.decideLeave('L', approve: false, comments: ' '),
          throwsArgumentError,
        );
        await expectLater(
          repo.rejectExpense('E', reason: ''),
          throwsArgumentError,
        );
        expect(s.apiCalls, isEmpty);
      },
    );

    test(
      'teamExpenseClaims reads either name of the claimant relation',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 'e1',
              'employeeRecordsExpenseClaimsEmployeeIdToemployeeRecords': {
                'fullName': 'Long Key',
              },
            },
          ]),
        );
        final rows = await ApprovalsRepository(
          auth: s.auth,
        ).teamExpenseClaims();
        expect(
          (rows.single['employee_records'] as Map)['full_name'],
          'Long Key',
        );
        expect(s.apiCalls.single.query, isEmpty); // never narrowed
      },
    );

    test('waiting-on words come from the required role', () {
      String w(String? r) => approvalWaitingOnText(
        ApprovalMeta(canApprove: false, requiredRole: r),
      );
      expect(w('hr_manager'), 'Waiting on HR manager');
      expect(w('hr_head'), 'Waiting on HR head');
      expect(w('manager'), 'Waiting on manager');
      expect(w(null), 'Waiting on someone else');
      expect(w('weird_role'), 'Waiting on someone else');
      expect(approvalWaitingOnText(null), 'Waiting on someone else');
    });
  });

  group('LeaveApprovalsPanel', () {
    testWidgets(
      'splits into needs action / waiting on others / history and drops own rows',
      (tester) async {
        _tall(tester);
        final srv = _Server(
          leaves: [
            _leave('a', 'Ann Action', 'pending'),
            _leave('b', 'Bob Blocked', 'manager_approved'),
            _leave('m', 'Me Myself', 'pending', employeeId: testEmployeeId),
            _leave('c', 'Cy Meta', 'pending'),
          ],
          history: [
            _leave('h', 'Hal History', 'approved'),
            _leave('mh', 'Mine Old', 'rejected', employeeId: testEmployeeId),
          ],
          meta: {'a': _can('manager'), 'b': _cannot('hr_manager')},
        );
        final s = await srv.session();
        await tester.pumpWidget(
          _host(
            LeaveApprovalsPanel(
              approvalsRepository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Waiting on others (2)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
        expect(find.text('Ann Action'), findsOneWidget);
        expect(find.byKey(const ValueKey('approve-a')), findsOneWidget);
        expect(find.byKey(const ValueKey('reject-a')), findsOneWidget);
        expect(find.text('Me Myself'), findsNothing);
        expect(find.text('Casual leave'), findsOneWidget);
        expect(find.text('20 Oct 2026 - 22 Oct 2026'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);

        await tester.tap(find.text('Waiting on others (2)'));
        await _settle(tester);
        expect(find.text('Bob Blocked'), findsOneWidget);
        expect(find.text('Cy Meta'), findsOneWidget);
        expect(find.text('Waiting on HR manager'), findsOneWidget);
        expect(find.text('Waiting on someone else'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Reject'), findsNothing);

        await tester.tap(find.text('History (1)'));
        await _settle(tester);
        expect(find.text('Hal History'), findsOneWidget);
        expect(find.text('Mine Old'), findsNothing);
        expect(find.text('Approve'), findsNothing);

        final rm = s.apiCalls.where((r) => r.path.endsWith('/row-meta')).single;
        expect(rm.path, '$_org/workflows/module/leaves/row-meta');
        expect((rm.json['recordIds'] as List).toSet(), {
          'a',
          'b',
          'c',
        }); // own row not asked about
      },
    );

    testWidgets(
      'row-meta failure: no buttons, a short note, nothing guessed, no raw text',
      (tester) async {
        _tall(tester);
        final srv = _Server(
          leaves: [_leave('a', 'Ann Action', 'pending')],
          metaStatus: 500,
        );
        final s = await srv.session();
        await tester.pumpWidget(
          _host(
            LeaveApprovalsPanel(
              approvalsRepository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text(kPartitionMetaFailedNote), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        await tester.tap(find.textContaining('Waiting on others'));
        await _settle(tester);
        expect(find.text('Ann Action'), findsOneWidget);
        expect(find.text(kPartitionMetaFailedNote), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Reject'), findsNothing);
        expect(find.textContaining('exploded'), findsNothing);
      },
    );

    testWidgets('list failure shows a fixed message and Retry', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async => _fail(500), empRole: 'manager');
      await tester.pumpWidget(
        _host(
          LeaveApprovalsPanel(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text(kPartitionLoadFailedMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('approve sends PUT {status: approved}, then reloads', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        leaves: [_leave('a', 'Ann Action', 'pending')],
        meta: {'a': _can('manager')},
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(
          LeaveApprovalsPanel(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      final before = srv.leaveListCalls;
      await tester.tap(find.byKey(const ValueKey('approve-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-approve')));
      await _settle(tester);
      final put = s.apiCalls.singleWhere((r) => r.method == 'PUT');
      expect(put.path, '$_org/leaves/applications/a');
      expect(put.json, {'status': 'approved'});
      expect(srv.leaveListCalls, greaterThan(before)); // reloaded
      expect(find.text('Request approved'), findsOneWidget);
    });

    testWidgets('reject needs a reason, then sends it as manager_comments', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        leaves: [_leave('a', 'Ann Action', 'pending')],
        meta: {'a': _can('manager')},
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(
          LeaveApprovalsPanel(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('reject-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await tester.pumpAndSettle();
      expect(find.text('Please give a reason for rejecting.'), findsOneWidget);
      expect(s.apiCalls.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(find.byType(TextField), 'Team is short');
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await _settle(tester);
      final put = s.apiCalls.singleWhere((r) => r.method == 'PUT');
      expect(put.json, {
        'status': 'rejected',
        'manager_comments': 'Team is short',
      });
    });

    for (final c in <(int, String, String)>[
      (
        403,
        'You cannot approve or reject your own leave request',
        "You can't decide your own request.",
      ),
      (
        403,
        'This leave request has already been decided',
        'This request was already decided.',
      ),
      (
        404,
        'Leave application not found',
        'This request is no longer available.',
      ),
      (
        409,
        'conflict at https://x.in',
        "This request couldn't be processed. Please refresh and try again.",
      ),
      (
        500,
        'db exploded at https://x.in id 99',
        "Couldn't complete this. Please try again.",
      ),
      (
        400,
        'NOT_ALLOWED',
        "You can't decide this request. It is waiting for another approver.",
      ),
    ]) {
      testWidgets(
        'a refused decision (${c.$1} ${c.$2}) shows friendly text and reloads',
        (tester) async {
          _tall(tester);
          final srv = _Server(
            leaves: [_leave('a', 'Ann Action', 'pending')],
            meta: {'a': _can('manager')},
            writeStatus: c.$1,
            writeMessage: c.$2,
          );
          final s = await srv.session();
          await tester.pumpWidget(
            _host(
              LeaveApprovalsPanel(
                approvalsRepository: ApprovalsRepository(auth: s.auth),
              ),
            ),
          );
          await _settle(tester);
          final before = srv.leaveListCalls;
          await tester.tap(find.byKey(const ValueKey('approve-a')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('decision-approve')));
          await _settle(tester);
          expect(find.text(c.$3), findsOneWidget);
          expect(find.textContaining('exploded'), findsNothing);
          expect(find.textContaining('https'), findsNothing);
          expect(srv.leaveListCalls, greaterThan(before));
        },
      );
    }

    test(
      'countActionable counts only the rows the caller may decide; throws when unknown',
      () async {
        final srv = _Server(
          leaves: [
            _leave('a', 'A', 'pending'),
            _leave('b', 'B', 'pending'),
            _leave('m', 'M', 'pending', employeeId: testEmployeeId),
          ],
          meta: {'a': _can('manager'), 'b': _cannot('hr_head')},
        );
        final s = await srv.session();
        expect(
          await LeaveApprovalsPanel.countActionable(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
          1,
        );

        srv.metaStatus = 500;
        await expectLater(
          LeaveApprovalsPanel.countActionable(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
          throwsA(isA<Object>()),
        );
        srv.leaves = [];
        srv.metaStatus = 200;
        expect(
          await LeaveApprovalsPanel.countActionable(
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
          0,
        );
      },
    );
  });

  group('ExpenseApprovalsPanel', () {
    Widget panel(TestSession s) => _host(
      ExpenseApprovalsPanel(
        approvalsRepository: ApprovalsRepository(auth: s.auth),
        expenseRepository: ExpenseRepository(auth: s.auth),
      ),
    );

    testWidgets(
      'three-way split, own claims excluded, amounts hidden when missing or zero',
      (tester) async {
        _tall(tester);
        final srv = _Server(
          claims: [
            _claim('a', 'Ann Action', 'pending'),
            _claim('b', 'Bob Blocked', 'manager_approved'),
            _claim('m', 'Me Myself', 'pending', employeeId: testEmployeeId),
            _claim('d', 'Dee Draft', 'draft'),
            _claim('h', 'Hal History', 'approved', amount: '0'),
            _claim('r', 'Rae Rejected', 'rejected', amount: null),
          ],
          meta: {'a': _can('manager'), 'b': _cannot('hr_manager')},
        );
        final s = await srv.session();
        await tester.pumpWidget(panel(s));
        await _settle(tester);
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Waiting on others (1)'), findsOneWidget);
        expect(find.text('History (2)'), findsOneWidget);
        expect(find.text('₹ 1,250'), findsOneWidget);
        expect(find.text('Travel'), findsOneWidget); // category name
        expect(find.text('Me Myself'), findsNothing);
        expect(find.text('Dee Draft'), findsNothing);
        await tester.tap(find.text('Waiting on others (1)'));
        await _settle(tester);
        expect(find.text('Waiting on HR manager'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        await tester.tap(find.text('History (2)'));
        await _settle(tester);
        expect(find.text('Hal History'), findsOneWidget);
        expect(find.text('Rae Rejected'), findsOneWidget);
        expect(find.textContaining('₹ 0'), findsNothing);
        expect(
          s.apiCalls.where((r) => r.path == '$_org/expenses').single.query,
          isEmpty,
        );
        expect(
          s.apiCalls.firstWhere((r) => r.path.endsWith('/row-meta')).path,
          '$_org/workflows/module/expenses/row-meta',
        );
      },
    );

    testWidgets('approve and reject post to the expense routes and reload', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        claims: [
          _claim('a', 'Ann Action', 'pending'),
          _claim('b', 'Bob', 'pending'),
        ],
        meta: {'a': _can('manager'), 'b': _can('manager')},
      );
      final s = await srv.session();
      await tester.pumpWidget(panel(s));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('approve-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-approve')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('reject-b')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'No receipt');
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await _settle(tester);
      final posts = s.apiCalls
          .where((r) => r.method == 'POST' && !r.path.endsWith('/row-meta'))
          .toList();
      expect(posts[0].path, '$_org/expenses/a/approve');
      expect(posts[0].json, <String, dynamic>{});
      expect(posts[1].path, '$_org/expenses/b/reject');
      expect(posts[1].json, {'reason': 'No receipt'});
      expect(
        s.apiCalls.where((r) => r.path == '$_org/expenses').length,
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets('SELF_APPROVAL refusal is friendly and reloads', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        claims: [_claim('a', 'Ann Action', 'pending')],
        meta: {'a': _can('manager')},
        writeStatus: 403,
        writeMessage:
            'SELF_APPROVAL: You cannot approve your own expense claim',
      );
      final s = await srv.session();
      await tester.pumpWidget(panel(s));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('approve-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-approve')));
      await _settle(tester);
      expect(find.text("You can't decide your own request."), findsOneWidget);
    });

    test(
      'countActionable: count on success (a real 0 too), throws on row-meta or list failure',
      () async {
        final srv = _Server(
          claims: [_claim('a', 'A', 'pending'), _claim('b', 'B', 'pending')],
          meta: {'a': _can('manager'), 'b': _cannot('hr_manager')},
        );
        final s = await srv.session();
        final repo = ApprovalsRepository(auth: s.auth);
        expect(
          await ExpenseApprovalsPanel.countActionable(
            approvalsRepository: repo,
          ),
          1,
        );
        srv.claims = [];
        expect(
          await ExpenseApprovalsPanel.countActionable(
            approvalsRepository: repo,
          ),
          0,
        );
        srv.claims = [_claim('a', 'A', 'pending')];
        srv.metaStatus = 500;
        await expectLater(
          ExpenseApprovalsPanel.countActionable(approvalsRepository: repo),
          throwsA(isA<Object>()),
        );
      },
    );
  });

  test('no direct status writes anywhere in lib', () {
    final bad = RegExp(
      r"""\.rpc\(|supabase|\.update\(\{\s*'status'""",
      caseSensitive: false,
    );
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      expect(bad.hasMatch(src), isFalse, reason: f.path);
    }
    // the panels only call decision routes
    for (final p in [
      'lib/screens/manager/widgets/leave_approvals_panel.dart',
      'lib/screens/manager/widgets/expense_approvals_panel.dart',
      'lib/screens/manager/widgets/partitioned_approvals.dart',
    ]) {
      final src = File(p).readAsStringSync();
      expect(src.contains("'status':"), isFalse, reason: p);
      expect(src.contains('api.'), isFalse, reason: p);
      expect(jsonEncode(src).contains('print('), isFalse);
    }
  });
}
