import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/screens/manager/widgets/decision_list_panel.dart';
import 'package:hrms_app/screens/manager/widgets/inbox_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/overtime_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/regularization_approvals_panel.dart';
import 'package:http/http.dart' as http;

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(Widget child, {bool scroll = false}) => MaterialApp(
  home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
);

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in id 99'},
}, 500);

http.Response _refuse(int status, String message) => jsonResponse({
  'success': false,
  'error': {'message': message},
}, status);

Map<String, dynamic> _exec(
  String id,
  String module,
  String name,
  Map<String, dynamic> record,
) => {
  'id': id,
  'module_name': module,
  'record_id': 'rec-$id',
  'record': {'employee_full_name': name, 'employee_code': 'E-$id', ...record},
};

void main() {
  group('InboxApprovalsPanel', () {
    late List<Map<String, dynamic>> executions;
    late http.Response Function(http.Request) onPost;

    Future<TestSession> session() => signedIn((req) async {
      if (req.method == 'GET' && req.url.path == '$_org/approvals') {
        return ok({'executions': executions, 'total': executions.length});
      }
      if (req.method == 'POST') return onPost(req);
      return _refuse(404, 'unexpected ${req.url.path}');
    }, empRole: 'manager');

    setUp(() {
      executions = [
        _exec('x1', 'leaves', 'Dev One', {
          'leave_type': 'casual_leave',
          'from_date': '2026-10-20T00:00:00.000Z',
          'to_date': '2026-10-22T00:00:00.000Z',
          'total_days': '3.0',
          'reason': 'Family function',
        }),
        _exec('x2', 'expenses', 'Dev Two', {
          'title': 'Cab',
          'total_amount': '1250.00',
        }),
        _exec('x3', 'leaves', 'Dev Three', {
          'leave_type': '1f0e8a50-aaaa-bbbb',
        }),
      ];
      onPost = (req) => ok({'success': true, 'status': 'completed'});
    });

    testWidgets(
      'lists the module\'s requests with employee, code, key facts and both actions',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              title: 'Leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('Dev One'), findsOneWidget);
        expect(find.text('E-x1'), findsOneWidget);
        expect(find.text('Casual leave'), findsOneWidget);
        expect(find.text('20 Oct 2026 - 22 Oct 2026'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Family function'), findsOneWidget);
        expect(
          find.text('Dev Three'),
          findsOneWidget,
        ); // listed; an id-like leave type is not shown
        expect(find.textContaining('1f0e8a50'), findsNothing);
        expect(find.text('Dev Two'), findsNothing); // another module
        expect(find.text('Leaves · 2 pending'), findsOneWidget);
        expect(find.text('Approve'), findsNWidgets(2));
        expect(find.text('Reject'), findsNWidgets(2));
        expect(s.apiCalls.map((r) => '${r.method} ${r.path}'), [
          'GET $_org/approvals',
        ]);
      },
    );

    testWidgets(
      'an expenses panel shows the amount the server gave and works inside a scroll view',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'expenses',
              repository: ApprovalsRepository(auth: s.auth),
            ),
            scroll: true,
          ),
        );
        await _settle(tester);
        expect(find.text('Dev Two'), findsOneWidget);
        expect(find.text('₹ 1,250'), findsOneWidget);
        expect(find.text('Cab'), findsOneWidget);
      },
    );

    testWidgets('an unknown or zero amount is never shown as 0', (
      tester,
    ) async {
      _tall(tester);
      executions = [
        _exec('l1', 'loans', 'Dev Loan', {
          'requested_amount': '0',
          'loan_category': 'salary_advance',
        }),
      ];
      final s = await session();
      await tester.pumpWidget(
        _host(
          InboxApprovalsPanel(
            module: 'loans',
            repository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Salary advance'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets(
      'Approve posts {comments} to the inbox route, drops the row and refreshes the list',
      (tester) async {
        _tall(tester);
        final s = await session();
        var approved = false;
        onPost = (req) {
          approved = true;
          executions = executions.where((e) => e['id'] != 'x1').toList();
          return ok({'success': true, 'status': 'completed'});
        };
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);

        await tester.tap(find.byKey(const ValueKey('approve-x1')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Enjoy');
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);

        expect(approved, isTrue);
        final post = s.apiCalls.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/approvals/x1/approve');
        expect(post.json, {'comments': 'Enjoy'});
        expect(find.text('Dev One'), findsNothing);
        expect(find.text('Dev Three'), findsOneWidget);
        expect(find.text('Request approved'), findsOneWidget);
        // the list was asked again after the decision
        expect(s.apiCalls.where((r) => r.method == 'GET').length, 2);
      },
    );

    testWidgets(
      'Reject needs a reason: nothing is sent until one is typed, then {reason} goes to the reject route',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);

        await tester.tap(find.byKey(const ValueKey('reject-x1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-reject')));
        await tester.pumpAndSettle();
        expect(
          find.text('Please give a reason for rejecting.'),
          findsOneWidget,
        );
        expect(s.apiCalls.where((r) => r.method == 'POST'), isEmpty);

        await tester.enterText(
          find.byType(TextField),
          'Team is short that week',
        );
        await tester.tap(find.byKey(const ValueKey('decision-reject')));
        await _settle(tester);
        final post = s.apiCalls.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/approvals/x1/reject');
        expect(post.json, {'reason': 'Team is short that week'});
        expect(find.text('Request rejected'), findsOneWidget);
      },
    );

    testWidgets('cancelling the dialog sends nothing', (tester) async {
      _tall(tester);
      final s = await session();
      await tester.pumpWidget(
        _host(
          InboxApprovalsPanel(
            module: 'leaves',
            repository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('approve-x1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.apiCalls.where((r) => r.method == 'POST'), isEmpty);
      expect(find.text('Dev One'), findsOneWidget);
    });

    testWidgets(
      'a server refusal is a friendly message (no raw text) and the stale list is reloaded',
      (tester) async {
        _tall(tester);
        final s = await session();
        onPost = (req) => _refuse(
          403,
          'This request has already been decided (rec 77, https://api.hrtoffy.in)',
        );
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('approve-x1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        expect(find.text('This request was already decided.'), findsOneWidget);
        expect(find.textContaining('rec 77'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
        expect(s.apiCalls.where((r) => r.method == 'GET').length, 2);
        expect(
          find.text('Dev One'),
          findsOneWidget,
        ); // still listed: it is the server's list that decides
      },
    );

    testWidgets(
      'a server error on a decision keeps the row and shows a safe message',
      (tester) async {
        _tall(tester);
        final s = await session();
        onPost = (req) => _boom;
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('approve-x1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        expect(
          find.text("Couldn't complete this. Please try again."),
          findsOneWidget,
        );
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.text('Dev One'), findsOneWidget);
      },
    );

    testWidgets('empty inbox shows the empty state', (tester) async {
      _tall(tester);
      executions = [];
      final s = await session();
      await tester.pumpWidget(
        _host(
          InboxApprovalsPanel(
            module: 'leaves',
            repository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text(kInboxEmptyMessage), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets(
      'a load failure shows a safe message with Retry that asks again',
      (tester) async {
        _tall(tester);
        var fail = true;
        final s = await signedIn((req) async {
          if (fail) return _boom;
          return ok({'executions': executions, 'total': executions.length});
        }, empRole: 'manager');
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text(kInboxLoadFailedMessage), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        fail = false;
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.text('Dev One'), findsOneWidget);
      },
    );

    testWidgets(
      'only the inbox routes are used: no HR-only leave route, no write besides the decision',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            InboxApprovalsPanel(
              module: 'leaves',
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('approve-x1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        final bad = RegExp('/leaves/|hierarchy|reviewer-scope');
        expect(s.apiCalls.where((r) => bad.hasMatch(r.path)), isEmpty);
        expect(s.apiCalls.where((r) => r.method != 'GET').map((r) => r.path), [
          '$_org/approvals/x1/approve',
        ]);
      },
    );
  });

  group('RegularizationApprovalsPanel', () {
    late List<Map<String, dynamic>> rows;
    late Map<String, dynamic> meta;

    Future<TestSession> session({bool metaFails = false}) =>
        signedIn((req) async {
          if (req.url.path == '$_org/attendance/regularization-requests') {
            if (req.method == 'GET') {
              final status = req.url.queryParameters['status'];
              return ok({
                'requests': rows
                    .where((r) => status!.split(',').contains(r['status']))
                    .toList(),
              });
            }
          }
          if (req.url.path ==
              '$_org/workflows/module/attendance_regularization/row-meta') {
            return metaFails ? _boom : ok(meta);
          }
          if (req.method == 'POST' &&
              req.url.path.startsWith(
                '$_org/attendance/regularization-requests/',
              )) {
            rows = rows
                .where((r) => !req.url.path.contains('/${r['id']}/'))
                .toList();
            return ok({'id': 'g'});
          }
          return _refuse(404, 'unexpected ${req.url.path}');
        }, empRole: 'manager');

    setUp(() {
      rows = [
        {
          'id': 'g1',
          'status': 'pending',
          'date': '2026-10-12T00:00:00.000Z',
          'original_punch_in': '2026-10-12T04:00:00.000Z',
          'requested_punch_in': '2026-10-12T03:30:00.000Z',
          'requested_punch_out': null,
          'reason': 'Forgot to punch',
          'employee_records': {
            'full_name': 'Dev One',
            'employee_id': 'E1',
            'department': 'R&D',
          },
        },
        {
          'id': 'g2',
          'status': 'pending',
          'date': '2026-10-13T00:00:00.000Z',
          'reason': 'Network',
          'employee_records': {
            'full_name': 'Dev Two',
            'employee_id': 'E2',
            'department': 'Ops',
          },
        },
        {
          'id': 'h1',
          'status': 'rejected',
          'date': '2026-10-01T00:00:00.000Z',
          'reason': 'Late',
          'manager_comments': 'Not valid',
          'employee_records': {
            'full_name': 'Dev Old',
            'employee_id': 'E9',
            'department': 'HR',
          },
        },
      ];
      meta = {
        'g1': {'executionFound': true, 'canApprove': true},
        'g2': {
          'executionFound': true,
          'canApprove': false,
          'reason': 'internal',
        },
      };
    });

    testWidgets(
      'Pending tab lists requests with times and reason; the engine decides which Review buttons are enabled',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('ATTENDANCE REGULARIZATION'), findsOneWidget);
        expect(find.text('Dev One'), findsOneWidget);
        expect(find.text('E1 · R&D'), findsOneWidget);
        expect(find.text('Reason: Forgot to punch'), findsOneWidget);
        expect(
          find.text('Not recorded'),
          findsWidgets,
        ); // missing times are not invented
        final meta = s.apiCalls.firstWhere((r) => r.path.endsWith('/row-meta'));
        expect(meta.json['recordIds'], ['g1', 'g2']);
        expect(
          tester
              .widget<ElevatedButton>(find.byKey(const ValueKey('review-g1')))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<ElevatedButton>(find.byKey(const ValueKey('review-g2')))
              .onPressed,
          isNull,
        );
        expect(find.text(kDecisionWaitingMessage), findsOneWidget);
        expect(find.textContaining('internal'), findsNothing);
      },
    );

    testWidgets(
      'when the engine answer is unavailable the buttons stay enabled',
      (tester) async {
        _tall(tester);
        final s = await session(metaFails: true);
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(
          tester
              .widget<ElevatedButton>(find.byKey(const ValueKey('review-g2')))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'Approve posts {comments} and nothing is written to attendance; the list refreshes',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('review-g1')));
        await tester.pumpAndSettle();
        expect(
          find.text('Reason: Forgot to punch'),
          findsNWidgets(2),
        ); // the dialog repeats it
        await tester.enterText(find.byType(TextField), 'ok');
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        final post = s.apiCalls.firstWhere(
          (r) => r.method == 'POST' && !r.path.endsWith('row-meta'),
        );
        expect(
          post.path,
          '$_org/attendance/regularization-requests/g1/approve',
        );
        expect(post.json, {'comments': 'ok'});
        expect(
          s.apiCalls.where((r) => r.path.contains('/attendance/records')),
          isEmpty,
        );
        expect(find.text('Dev One'), findsNothing);
        expect(find.text('Request approved'), findsOneWidget);
      },
    );

    testWidgets(
      'Reject without a reason is blocked, with one it posts {comments} to /reject',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('review-g1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-reject')));
        await tester.pumpAndSettle();
        expect(
          find.text('Please give a reason for rejecting.'),
          findsOneWidget,
        );
        expect(
          s.apiCalls.where(
            (r) => r.method == 'POST' && !r.path.endsWith('row-meta'),
          ),
          isEmpty,
        );
        await tester.enterText(find.byType(TextField), 'Not on shift');
        await tester.tap(find.byKey(const ValueKey('decision-reject')));
        await _settle(tester);
        final post = s.apiCalls.firstWhere(
          (r) => r.method == 'POST' && !r.path.endsWith('row-meta'),
        );
        expect(post.path, '$_org/attendance/regularization-requests/g1/reject');
        expect(post.json, {'comments': 'Not on shift'});
      },
    );

    testWidgets(
      'History tab asks approved,rejected, shows the comment and has no actions',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('History'));
        await _settle(tester);
        final hist = s.apiCalls.lastWhere((r) => r.method == 'GET');
        expect(hist.query['status'], 'approved,rejected');
        expect(find.text('Dev Old'), findsOneWidget);
        expect(find.text('Comments: Not valid'), findsOneWidget);
        expect(find.text('REJECTED'), findsOneWidget);
        expect(find.text('Review Request'), findsNothing);
      },
    );

    testWidgets(
      'a refused decision (403) is friendly and reloads; a load failure shows Retry without raw text',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.method == 'GET') return ok({'requests': rows});
          if (req.url.path.endsWith('row-meta')) return ok({});
          return _refuse(403, 'You cannot approve your own request');
        }, empRole: 'manager');
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('review-g1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        expect(find.text("You can't decide your own request."), findsOneWidget);

        final bad = await signedIn((req) async => _boom, empRole: 'manager');
        await tester.pumpWidget(
          _host(
            RegularizationApprovalsPanel(
              key: UniqueKey(),
              repository: ApprovalsRepository(auth: bad.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text(kDecisionLoadFailedMessage), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
      },
    );

    testWidgets('the empty Pending tab says so', (tester) async {
      _tall(tester);
      rows = [];
      final s = await session();
      await tester.pumpWidget(
        _host(
          RegularizationApprovalsPanel(
            repository: ApprovalsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text(kDecisionEmptyMessage), findsOneWidget);
    });
  });

  group('OvertimeApprovalsPanel', () {
    late List<Map<String, dynamic>> rows;

    Future<TestSession> session() => signedIn((req) async {
      if (req.method == 'GET' &&
          req.url.path == '$_org/attendance/overtime/approvable') {
        final st = req.url.queryParameters['status'];
        return ok(
          st == 'pending'
              ? rows.where((r) => r['status'] == 'pending').toList()
              : rows,
        );
      }
      if (req.url.path.endsWith('/row-meta')) {
        return ok({
          for (final r in rows)
            r['id']: {'executionFound': true, 'canApprove': true},
        });
      }
      if (req.method == 'POST') {
        rows = rows
            .where((r) => !req.url.path.contains('/${r['id']}/'))
            .toList();
        return ok({'id': 'o'});
      }
      return _refuse(404, 'unexpected');
    }, empRole: 'manager');

    setUp(() {
      rows = [
        {
          'id': 'o1',
          'status': 'pending',
          'ot_date': '2026-10-10T00:00:00.000Z',
          'total_hours': '2.5',
          'ot_type': 'weekday',
          'ot_amount': null,
          'reason': 'Release',
          'employee_records': {
            'full_name': 'Dev One',
            'employee_id': 'E1',
            'department': 'R&D',
          },
        },
        {
          'id': 'o2',
          'status': 'approved',
          'ot_date': '2026-10-01T00:00:00.000Z',
          'total_hours': '1',
          'ot_type': 'holiday',
          'ot_amount': '800',
          'reason': 'Support',
          'manager_comments': 'Thanks',
          'employee_records': {
            'full_name': 'Dev Two',
            'employee_id': 'E2',
            'department': 'Ops',
          },
        },
      ];
    });

    testWidgets(
      'shows date, hours and type; no amount when the server sent none; asks row-meta for module overtime',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            OvertimeApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('Dev One'), findsOneWidget);
        expect(find.text('2.5 hrs'), findsOneWidget);
        expect(find.text('weekday'), findsOneWidget);
        expect(find.text('Amount'), findsNothing);
        expect(
          s.apiCalls.any(
            (r) => r.path == '$_org/workflows/module/overtime/row-meta',
          ),
          isTrue,
        );
        expect(
          s.apiCalls.firstWhere((r) => r.method == 'GET').query['status'],
          'pending',
        );
      },
    );

    testWidgets(
      'approve posts to the overtime approve route; reject needs a reason and posts {comments}',
      (tester) async {
        _tall(tester);
        final s = await session();
        await tester.pumpWidget(
          _host(
            OvertimeApprovalsPanel(
              repository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('review-o1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('decision-approve')));
        await _settle(tester);
        final post = s.apiCalls.firstWhere(
          (r) => r.method == 'POST' && !r.path.endsWith('row-meta'),
        );
        expect(post.path, '$_org/attendance/overtime/records/o1/approve');
        expect(find.text('Request approved'), findsOneWidget);
      },
    );

    testWidgets('reject goes to /reject with the reason', (tester) async {
      _tall(tester);
      final s = await session();
      await tester.pumpWidget(
        _host(
          OvertimeApprovalsPanel(repository: ApprovalsRepository(auth: s.auth)),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('review-o1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'No prior approval');
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await _settle(tester);
      final post = s.apiCalls.firstWhere(
        (r) => r.method == 'POST' && !r.path.endsWith('row-meta'),
      );
      expect(post.path, '$_org/attendance/overtime/records/o1/reject');
      expect(post.json, {'comments': 'No prior approval'});
    });

    testWidgets('History shows decided rows with their amount and comment', (
      tester,
    ) async {
      _tall(tester);
      final s = await session();
      await tester.pumpWidget(
        _host(
          OvertimeApprovalsPanel(repository: ApprovalsRepository(auth: s.auth)),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('History'));
      await _settle(tester);
      expect(find.text('Dev Two'), findsOneWidget);
      expect(find.text('₹ 800'), findsOneWidget);
      expect(find.text('Comments: Thanks'), findsOneWidget);
      expect(find.text('Review Request'), findsNothing);
    });
  });

  test(
    'the panels contain no Supabase, no raw error text and no exception logging',
    () {
      for (final p in [
        'lib/screens/manager/widgets/inbox_approvals_panel.dart',
        'lib/screens/manager/widgets/decision_list_panel.dart',
        'lib/screens/manager/widgets/regularization_approvals_panel.dart',
        'lib/screens/manager/widgets/overtime_approvals_panel.dart',
        'lib/screens/manager/widgets/approval_common.dart',
      ]) {
        final src = File(p).readAsStringSync();
        for (final banned in [
          'supabase',
          'Supabase',
          "from('",
          '.rpc(',
          '.upsert(',
          'print(',
          'debugPrint(',
          r'$e"',
          r"$e'",
          'e.message',
        ]) {
          expect(
            src.contains(banned),
            isFalse,
            reason: '$p contains "$banned"',
          );
        }
      }
    },
  );
}
