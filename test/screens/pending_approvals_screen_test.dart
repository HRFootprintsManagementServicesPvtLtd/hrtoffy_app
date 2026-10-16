import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart';
import 'package:hrms_app/screens/manager/widgets/benefit_claims_approvals.dart';
import 'package:hrms_app/screens/manager/widgets/loan_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/travel_approvals_panel.dart';
import 'package:hrms_app/screens/manager/pending_approvals_screen.dart';
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

Widget _screen(TestSession s) => MaterialApp(
  home: PendingApprovalsScreen(
    userEmail: 'm@x.com',
    userData: const {'full_name': 'Maya Manager'},
    repository: ApprovalsRepository(auth: s.auth),
    loansRepository: LoansRepository(auth: s.auth),
    travelRepository: TravelRepository(auth: s.auth),
    benefitsRepository: BenefitsRepository(auth: s.auth),
  ),
);

http.Response _fail(int status) => jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, status);

Future<TestSession> _session({
  Map<String, dynamic>? counts = const {
    'approvals-requests-leaves': 3,
    'approvals-regularization': 1,
  },
}) => signedIn((req) async {
  switch (req.url.path) {
    case '$_org/dashboard/approval-counts':
      return counts == null ? _fail(500) : ok(counts);
    case '$_org/approvals':
      return ok({
        'executions': [
          {
            'id': 'x1',
            'module_name': 'leaves',
            'record_id': 'r1',
            'record': {
              'employee_full_name': 'Dev One',
              'employee_code': 'E1',
              'leave_type': 'sick_leave',
            },
          },
        ],
        'total': 1,
      });
    case '$_org/attendance/regularization-requests':
      return ok({
        'requests': [
          {
            'id': 'g1',
            'status': 'pending',
            'date': '2026-10-12T00:00:00.000Z',
            'reason': 'Forgot',
            'employee_records': {'full_name': 'Dev Reg', 'employee_id': 'E2'},
          },
        ],
      });
    case '$_org/attendance/overtime/approvable':
      return ok([
        {
          'id': 'o1',
          'status': 'pending',
          'ot_date': '2026-10-10T00:00:00.000Z',
          'total_hours': '2',
          'employee_records': {'full_name': 'Dev OT', 'employee_id': 'E3'},
        },
      ]);
  }
  if (req.url.path == '$_org/loans') return ok({'items': [], 'total': 0});
  if (req.url.path == '$_org/travel/claims') return ok([]);
  if (req.url.path == '$_org/benefits/esi/claims') return ok([]);
  if (req.url.path.endsWith('/row-meta')) return ok({});
  return _fail(404);
}, empRole: 'manager');

const _tiles = [
  'Leave Requests',
  'Regularization',
  'Overtime',
  'Loan Requests',
  'Travel Claims',
  'General Requests',
  'Benefits Claims',
];

String _badge(WidgetTester t, String tab) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('badge-$tab')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets(
    'the title and every category tile are kept; Overtime is a tile of its own',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('Approvals'), findsOneWidget);
      expect(
        find.textContaining('Decisions', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('MAYA'), findsOneWidget);
      for (final t in _tiles) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    },
  );

  testWidgets(
    'badges: the server count for leaves and regularization, "-" for queues the server does not count for a manager',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(_badge(tester, 'leaves'), '3');
      expect(_badge(tester, 'regularization'), '1');
      for (final tab in [
        'overtime',
        'loans',
        'travel',
        'general',
        'benefits',
      ]) {
        expect(_badge(tester, tab), kApprovalsCountUnknown, reason: tab);
      }
      expect(s.apiCalls.map((r) => r.path), [
        '$_org/dashboard/approval-counts',
      ]);
    },
  );

  testWidgets(
    'loans, benefits and travel badges show the server count when it sends one and "-" when it does not',
    (tester) async {
      _tall(tester);
      final s = await _session(
        counts: {
          'approvals-requests-leaves': 1,
          'approvals-loans': 4,
          'approvals-travel': 2,
        },
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(_badge(tester, 'loans'), '4');
      expect(_badge(tester, 'travel'), '2');
      expect(_badge(tester, 'benefits'), kApprovalsCountUnknown);
    },
  );

  testWidgets(
    'a queue the server left out of the counts is a real 0 once it answered',
    (tester) async {
      _tall(tester);
      final s = await _session(counts: {'approvals-requests-leaves': 2});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(_badge(tester, 'leaves'), '2');
      expect(_badge(tester, 'regularization'), '0');
    },
  );

  testWidgets(
    'when counts cannot be read every badge shows "-", never 0, and no raw error appears',
    (tester) async {
      _tall(tester);
      final s = await _session(counts: null);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      for (final tab in [
        'leaves',
        'regularization',
        'overtime',
        'loans',
        'travel',
        'general',
        'benefits',
      ]) {
        expect(_badge(tester, tab), '-', reason: tab);
      }
      expect(find.text('0'), findsNothing);
      expect(find.textContaining('exploded'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Leave Requests opens the inbox panel for leaves and back returns to the inbox and refreshes the counts',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('Leave Requests'));
      await _settle(tester);
      expect(find.text('Leave Requests'), findsOneWidget); // app-bar title
      expect(find.text('Dev One'), findsOneWidget);
      expect(find.text('Sick leave'), findsOneWidget);
      expect(find.byKey(const ValueKey('approve-x1')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await _settle(tester);
      expect(find.text('Approvals'), findsOneWidget);
      expect(
        s.apiCalls.where((r) => r.path.endsWith('/approval-counts')).length,
        2,
      );
    },
  );

  testWidgets(
    'Regularization opens its Pending/History panel; Overtime opens the overtime panel',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('Regularization'));
      await _settle(tester);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Dev Reg'), findsOneWidget);
      await tester.tap(find.text('Back to inbox'));
      await _settle(tester);
      expect(find.text('Approvals'), findsOneWidget);

      await tester.tap(find.text('Overtime'));
      await _settle(tester);
      expect(find.text('OVERTIME'), findsOneWidget);
      expect(find.text('Dev OT'), findsOneWidget);
    },
  );

  testWidgets(
    'Loans, Travel and Benefits open their approval panels; General shows "This isn\'t available yet" with a way back',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      final panels = {
        'Loan Requests': find.byType(LoanApprovalsPanel),
        'Travel Claims': find.byType(TravelApprovalsPanel),
        'Benefits Claims': find.byType(BenefitClaimsApprovals),
      };
      for (final e in panels.entries) {
        await tester.tap(find.text(e.key));
        await tester.pumpAndSettle();
        expect(e.value, findsOneWidget, reason: e.key);
        expect(
          find.text('Approve'),
          findsNothing,
        ); // nothing is waiting: no decision buttons
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('General Requests'));
      await tester.pumpAndSettle();
      expect(find.text(kApprovalsUnavailableMessage), findsOneWidget);
      await tester.tap(find.text('Back to inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Approvals'), findsOneWidget);
    },
  );

  testWidgets(
    'a full tour makes no request to an HR-only leave route and no write',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      for (final t in ['Leave Requests', 'Regularization', 'Overtime']) {
        await tester.tap(find.text(t));
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await _settle(tester);
      }
      final bad = RegExp('/leaves/|hierarchy|reviewer-scope|/employees');
      expect(s.apiCalls.where((r) => bad.hasMatch(r.path)), isEmpty);
      expect(
        s.apiCalls.where(
          (r) => r.method != 'GET' && !r.path.endsWith('/row-meta'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'the screen has no Supabase, no table or hierarchy call, no exception logging and no raw errors',
    () {
      final src = File(
        'lib/screens/manager/pending_approvals_screen.dart',
      ).readAsStringSync();
      for (final banned in [
        'supabase',
        'Supabase',
        "from('",
        '.rpc(',
        '.update(',
        '.upsert(',
        '.insert(',
        'get_manager_full_hierarchy',
        'leave_applications',
        'attendance_regularization_requests',
        'employee_records',
        'print(',
        'debugPrint(',
        r'$e"',
        r"$e'",
        'Error: ',
      ]) {
        expect(src.contains(banned), isFalse, reason: 'found "$banned"');
      }
      expect(src.contains('LEAD-INTEGRATES'), isFalse); // every tab is wired
    },
  );
}
