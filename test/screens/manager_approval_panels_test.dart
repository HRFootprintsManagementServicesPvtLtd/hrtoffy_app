import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart';
import 'package:hrms_app/screens/manager/widgets/approval_split_panel.dart';
import 'package:hrms_app/screens/manager/widgets/benefit_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/benefit_claims_approvals.dart';
import 'package:hrms_app/screens/manager/widgets/benefit_general_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/loan_approvals_panel.dart';
import 'package:hrms_app/screens/manager/widgets/travel_approvals_panel.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);

http.Response _err(int status, String message, {String? code}) => jsonResponse({
  'success': false,
  'error': {'message': message, if (code != null) 'code': code},
}, status);

/// What the engine answers for one row.
Map<String, dynamic> _can([String role = 'manager']) => {
  'canApprove': true,
  'executionFound': true,
  'requiredRole': role,
  'directMode': false,
};

Map<String, dynamic> _cannot([String role = 'hr_manager']) => {
  'canApprove': false,
  'executionFound': true,
  'requiredRole': role,
  'reason': 'NOT_ALLOWED',
};

/// A fake API for one module: GET [listPath] returns [rows()]; POST .../row-meta answers [meta()] (null = the call fails);
/// any other POST is a decision answered by [onDecision].
Future<TestSession> _session(
  String listPath,
  List<Map<String, dynamic>> Function() rows, {
  Map<String, dynamic>? Function()? meta,
  http.Response Function(String path, String body)? onDecision,
  bool failList = false,
}) {
  return signedIn((req) async {
    if (req.method == 'GET' && req.url.path == '$_org$listPath') {
      if (failList) return _boom;
      final r = rows();
      return ok({'items': r, 'total': r.length});
    }
    if (req.method == 'POST' && req.url.path.endsWith('/row-meta')) {
      final m = (meta ?? () => <String, dynamic>{})();
      return m == null ? _boom : ok(m);
    }
    if (req.method == 'POST') return onDecision!(req.url.path, req.body);
    return _err(404, 'unexpected');
  }, empRole: 'manager');
}

List<Recorded> _gets(TestSession s) =>
    s.requests.where((r) => r.method == 'GET').toList();
List<Recorded> _metaCalls(TestSession s) =>
    s.requests.where((r) => r.path.endsWith('/row-meta')).toList();
Recorded _decisionPost(TestSession s) => s.requests.firstWhere(
  (r) => r.method == 'POST' && !r.path.endsWith('/row-meta'),
);

// ------------------------------------------------------------------ loans

Map<String, dynamic> _loan(
  String id,
  String number, {
  String status = 'pending',
  Object? requested = '20000.00',
  String emp = 'emp-1',
}) => {
  'id': id,
  'loan_number': number,
  'employee_id': emp,
  'loan_category': 'salary_advance',
  'purpose': 'Medical',
  'requested_amount': requested,
  'tenure_months': 6,
  'status': status,
  'created_at': '2026-10-02T00:00:00.000Z',
  'employee_records_loans_advances_employee_idToemployee_records': {
    'full_name': 'Asha Rao',
    'employee_id': 'E-100',
  },
};

Widget _loanPanel(TestSession s) => _host(
  LoanApprovalsPanel(
    loansRepository: LoansRepository(auth: s.auth),
    approvalsRepository: ApprovalsRepository(auth: s.auth),
  ),
);

Future<void> _pumpAndTapReview(WidgetTester tester) async {
  await _settle(tester);
  await tester.tap(find.text('Review').first);
  await _settle(tester);
}

void main() {
  group('LoanApprovalsPanel', () {
    testWidgets(
      'three-way split by the engine answer; own loans are listed nowhere; the row-meta call is exact',
      (tester) async {
        _tall(tester);
        final s = await _session(
          '/loans',
          () => [
            _loan('a', 'L-1'),
            _loan('b', 'L-2', status: 'manager_approved'),
            _loan('c', 'L-3', status: 'approved'),
            _loan('d', 'L-4', status: 'rejected'),
            _loan('m', 'L-MINE', emp: testEmployeeId),
          ],
          meta: () => {'a': _can(), 'b': _cannot('hr_head')},
        );
        await tester.pumpWidget(_loanPanel(s));
        await _settle(tester);

        expect(_gets(s).single.query, isEmpty);
        final meta = _metaCalls(s).single;
        expect(meta.path, '$_org/workflows/module/loans/row-meta');
        expect(meta.json, {
          'recordIds': ['a', 'b'],
        });
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Waiting on others (1)'), findsOneWidget);
        expect(find.text('History (2)'), findsOneWidget);
        expect(find.text('L-1'), findsOneWidget);
        expect(find.text('L-2'), findsNothing);
        expect(find.text('Review'), findsOneWidget);

        await tester.tap(find.text('Waiting on others (1)'));
        await _settle(tester);
        expect(find.text('L-2'), findsOneWidget);
        expect(find.text('Waiting on HR head'), findsOneWidget);
        expect(find.text('Review'), findsNothing);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('View'), findsOneWidget);

        await tester.tap(find.text('History (2)'));
        await _settle(tester);
        expect(find.text('L-3'), findsOneWidget);
        expect(find.text('L-4'), findsOneWidget);
        expect(find.text('L-MINE'), findsNothing);
      },
    );

    testWidgets('only own loans: nothing needs action, no meta call at all', (
      tester,
    ) async {
      _tall(tester);
      final s = await _session(
        '/loans',
        () => [
          _loan('m', 'L-MINE', emp: testEmployeeId),
          _loan('n', 'L-MINE2', status: 'approved', emp: testEmployeeId),
        ],
      );
      await tester.pumpWidget(_loanPanel(s));
      await _settle(tester);
      expect(find.text('Needs my action (0)'), findsOneWidget);
      expect(find.text('History (0)'), findsOneWidget);
      expect(find.text('No loan requests need your action.'), findsOneWidget);
      expect(find.text('L-MINE'), findsNothing);
      expect(_metaCalls(s), isEmpty);
    });

    testWidgets(
      'approve: POST with no body, success message, the list and the engine answer are reloaded',
      (tester) async {
        _tall(tester);
        var rows = [_loan('a', 'L-1'), _loan('b', 'L-2')];
        final s = await _session(
          '/loans',
          () => rows,
          meta: () => {
            for (final r in rows)
              if (r['status'] == 'pending') r['id'] as String: _can(),
          },
          onDecision: (path, body) {
            rows = [_loan('a', 'L-1', status: 'approved'), _loan('b', 'L-2')];
            return ok({'id': 'a', 'status': 'approved'});
          },
        );
        await tester.pumpWidget(_loanPanel(s));
        await _pumpAndTapReview(tester);
        expect(find.text('Review Loan Request'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.text('Approve'));
        await _settle(tester);

        final post = _decisionPost(s);
        expect(post.path, '$_org/loans/a/approve');
        expect(post.body, isEmpty);
        expect(find.text('Loan approved'), findsOneWidget);
        expect(_gets(s), hasLength(2));
        expect(_metaCalls(s), hasLength(2));
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
      },
    );

    testWidgets('reject needs a reason, then sends {reason}', (tester) async {
      _tall(tester);
      final s = await _session(
        '/loans',
        () => [_loan('a', 'L-1')],
        meta: () => {'a': _can()},
        onDecision: (path, body) => ok({'id': 'a'}),
      );
      await tester.pumpWidget(_loanPanel(s));
      await _pumpAndTapReview(tester);
      expect(find.byKey(const Key('reject-reason')), findsNothing);
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      expect(find.text('Please give a reason for rejecting.'), findsOneWidget);
      expect(
        s.requests.where(
          (r) => r.method == 'POST' && !r.path.endsWith('/row-meta'),
        ),
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('reject-reason')),
        'Over the limit',
      );
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      final post = _decisionPost(s);
      expect(post.path, '$_org/loans/a/reject');
      expect(post.json, {'reason': 'Over the limit'});
      expect(find.text('Loan rejected'), findsOneWidget);
    });

    for (final c in [
      (
        403,
        'You cannot approve your own loan',
        null,
        "You can't approve or reject your own request.",
      ),
      (
        403,
        'Not the approver',
        'NOT_ALLOWED',
        "You can't decide this request right now",
      ),
      (
        404,
        'Loan not found',
        null,
        'This request is no longer available to you.',
      ),
      (
        400,
        "Cannot approve a loan with status 'approved'",
        null,
        'This request has already been decided.',
      ),
      (
        500,
        'db exploded at https://api.hrtoffy.in',
        null,
        "Couldn't complete this right now. Please try again.",
      ),
    ]) {
      testWidgets(
        'a ${c.$1} refusal is friendly, never the server text, and reloads',
        (tester) async {
          _tall(tester);
          final s = await _session(
            '/loans',
            () => [_loan('a', 'L-1')],
            meta: () => {'a': _can()},
            onDecision: (path, body) => _err(c.$1, c.$2, code: c.$3),
          );
          await tester.pumpWidget(_loanPanel(s));
          await _pumpAndTapReview(tester);
          await tester.tap(find.text('Approve'));
          await _settle(tester);
          expect(find.textContaining(c.$4), findsOneWidget);
          expect(find.textContaining('exploded'), findsNothing);
          expect(find.textContaining('hrtoffy'), findsNothing);
          expect(find.textContaining('Not the approver'), findsNothing);
          expect(_gets(s), hasLength(2));
          expect(find.text('L-1'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'a failing row-meta shows the waiting rows without buttons and a short note',
      (tester) async {
        _tall(tester);
        final s = await _session(
          '/loans',
          () => [_loan('a', 'L-1'), _loan('c', 'L-3', status: 'approved')],
          meta: () => null,
        );
        await tester.pumpWidget(_loanPanel(s));
        await _settle(tester);
        expect(find.text(kApprovalMetaFailed), findsOneWidget);
        expect(find.text('Needs my action'), findsOneWidget); // no count
        expect(find.text('Review'), findsNothing);
        await tester.tap(find.text('Waiting on others (1)'));
        await _settle(tester);
        expect(find.text(kApprovalMetaFailed), findsOneWidget);
        expect(find.text('L-1'), findsOneWidget);
        expect(find.text('Review'), findsNothing);
        expect(find.textContaining('exploded'), findsNothing);
      },
    );

    testWidgets('empty, failed list and unknown amounts (never ₹0)', (
      tester,
    ) async {
      _tall(tester);
      final f = await _session('/loans', () => [], failList: true);
      await tester.pumpWidget(_loanPanel(f));
      await _settle(tester);
      expect(find.text(kLoanApprovalsLoadFailed), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final z = await _session(
        '/loans',
        () => [
          _loan('a', 'L-1', requested: 0),
          _loan('b', 'L-2', requested: null),
        ],
        meta: () => {'a': _can(), 'b': _can()},
      );
      await tester.pumpWidget(_loanPanel(z));
      await _settle(tester);
      expect(find.text('Not available'), findsNWidgets(2));
      expect(find.text('₹0'), findsNothing);
    });

    test(
      'countActionable counts the rows the engine allows; throws on failure',
      () async {
        final s = await _session(
          '/loans',
          () => [
            _loan('a', 'L-1'),
            _loan('b', 'L-2'),
            _loan('c', 'L-3', status: 'approved'),
            _loan('m', 'L-M', emp: testEmployeeId),
          ],
          meta: () => {'a': _can(), 'b': _cannot()},
        );
        expect(
          await LoanApprovalsPanel.countActionable(
            loansRepository: LoansRepository(auth: s.auth),
            approvalsRepository: ApprovalsRepository(auth: s.auth),
          ),
          1,
        );
        final bad = await _session(
          '/loans',
          () => [_loan('a', 'L-1')],
          meta: () => null,
        );
        expect(
          LoanApprovalsPanel.countActionable(
            loansRepository: LoansRepository(auth: bad.auth),
            approvalsRepository: ApprovalsRepository(auth: bad.auth),
          ),
          throwsA(anything),
        );
        final failList = await _session('/loans', () => [], failList: true);
        expect(
          LoanApprovalsPanel.countActionable(
            loansRepository: LoansRepository(auth: failList.auth),
            approvalsRepository: ApprovalsRepository(auth: failList.auth),
          ),
          throwsA(anything),
        );
        final none = await _session('/loans', () => []);
        expect(
          await LoanApprovalsPanel.countActionable(
            loansRepository: LoansRepository(auth: none.auth),
            approvalsRepository: ApprovalsRepository(auth: none.auth),
          ),
          0,
        );
      },
    );
  });

  // ---------------------------------------------------------------- travel

  Map<String, dynamic> claim(
    String id,
    String number, {
    String status = 'pending',
    Object? total = '5400.50',
    String emp = 'emp-1',
  }) => {
    'id': id,
    'claim_number': number,
    'employee_id': emp,
    'trip_destination': 'Pune',
    'trip_purpose': 'Client visit',
    'trip_from_date': '2026-10-07T00:00:00.000Z',
    'trip_to_date': '2026-10-09T00:00:00.000Z',
    'total_amount': total,
    'status': status,
    'created_at': '2026-10-02T00:00:00.000Z',
    'employee_records_travel_claims_employee_idToemployee_records': {
      'full_name': 'Ben Roy',
      'employee_id': 'E-200',
      'designation': 'Engineer',
    },
    'travel_expenses': [
      {
        'id': 'x1',
        'expense_type': 'Hotel',
        'amount': '3000.00',
        'expense_date': '2026-10-07T00:00:00.000Z',
      },
      {
        'id': 'x2',
        'expense_type': 'Taxi/Cab',
        'amount': null,
        'expense_date': '2026-10-08T00:00:00.000Z',
      },
    ],
  };

  Widget travelPanel(TestSession s) => _host(
    TravelApprovalsPanel(
      travelRepository: TravelRepository(auth: s.auth),
      approvalsRepository: ApprovalsRepository(auth: s.auth),
    ),
  );

  group('TravelApprovalsPanel', () {
    testWidgets(
      'claims waiting at another role have no buttons; the engine decides (module travel_claims)',
      (tester) async {
        _tall(tester);
        final s = await _session(
          '/travel/claims',
          () => [
            claim('a', 'TRV-1'),
            claim('b', 'TRV-2'),
            claim('c', 'TRV-3', status: 'approved'),
            claim('m', 'TRV-MINE', emp: testEmployeeId),
          ],
          meta: () => {'a': _can(), 'b': _cannot('hr_manager')},
        );
        await tester.pumpWidget(travelPanel(s));
        await _settle(tester);
        expect(_gets(s).single.query, isEmpty);
        expect(
          _metaCalls(s).single.path,
          '$_org/workflows/module/travel_claims/row-meta',
        );
        expect(_metaCalls(s).single.json, {
          'recordIds': ['a', 'b'],
        });
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Waiting on others (1)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
        expect(find.text('TRV-1'), findsOneWidget);
        expect(find.text('TRV-2'), findsNothing);
        expect(find.text('TRV-MINE'), findsNothing);
        expect(find.text('Ben Roy • Engineer'), findsOneWidget);

        await tester.tap(find.text('Review'));
        await _settle(tester);
        expect(find.text('Expense breakdown'), findsOneWidget);
        expect(find.text('₹3,000.00'), findsOneWidget);
        expect(find.text('₹0.00'), findsNothing);
        expect(
          find.text('Approving approves the claimed total.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('waiting tab names who it waits for, with no buttons', (
      tester,
    ) async {
      _tall(tester);
      final s = await _session(
        '/travel/claims',
        () => [claim('b', 'TRV-2'), claim('d', 'TRV-4')],
        meta: () => {'b': _cannot('hr_manager'), 'd': _cannot('weird_role')},
      );
      await tester.pumpWidget(travelPanel(s));
      await _settle(tester);
      expect(find.text('Needs my action (0)'), findsOneWidget);
      expect(
        find.text('No claims require your action at this time.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Waiting on others (2)'));
      await _settle(tester);
      expect(find.text('Waiting on HR manager'), findsOneWidget);
      expect(find.text('Waiting on someone else'), findsOneWidget);
      expect(find.text('weird_role'), findsNothing);
      expect(find.text('Review'), findsNothing);
    });

    testWidgets(
      'approve posts {} and reloads; reject needs a reason and posts {reason}',
      (tester) async {
        _tall(tester);
        var rows = [claim('a', 'TRV-1')];
        final s = await _session(
          '/travel/claims',
          () => rows,
          meta: () => {'a': _can()},
          onDecision: (path, body) {
            rows = [claim('a', 'TRV-1', status: 'approved')];
            return ok(claim('a', 'TRV-1'));
          },
        );
        await tester.pumpWidget(travelPanel(s));
        await _pumpAndTapReview(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        final post = _decisionPost(s);
        expect(post.path, '$_org/travel/claims/a/approve');
        expect(post.json, <String, dynamic>{});
        expect(find.text('Claim approved'), findsOneWidget);
        expect(find.text('Needs my action (0)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
        expect(_gets(s), hasLength(2));

        await tester.pumpWidget(const SizedBox());
        final r = await _session(
          '/travel/claims',
          () => [claim('a', 'TRV-1')],
          meta: () => {'a': _can()},
          onDecision: (path, body) => ok(claim('a', 'TRV-1')),
        );
        await tester.pumpWidget(travelPanel(r));
        await _pumpAndTapReview(tester);
        await tester.tap(find.text('Reject'));
        await _settle(tester);
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        expect(
          find.text('Please give a reason for rejecting.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('reject-reason')),
          'Receipts missing',
        );
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        final rp = _decisionPost(r);
        expect(rp.path, '$_org/travel/claims/a/reject');
        expect(rp.json, {'reason': 'Receipts missing'});
        expect(find.text('Claim rejected'), findsOneWidget);
      },
    );

    for (final c in [
      (
        403,
        'forbidden',
        'FORBIDDEN',
        "You can't decide this request right now",
      ),
      (
        500,
        'db exploded at https://api.hrtoffy.in',
        null,
        "Couldn't complete this right now. Please try again.",
      ),
    ]) {
      testWidgets('a ${c.$1} refusal is friendly and the list is reloaded', (
        tester,
      ) async {
        _tall(tester);
        final s = await _session(
          '/travel/claims',
          () => [claim('a', 'TRV-1')],
          meta: () => {'a': _can()},
          onDecision: (path, body) => _err(c.$1, c.$2, code: c.$3),
        );
        await tester.pumpWidget(travelPanel(s));
        await _pumpAndTapReview(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        expect(find.textContaining(c.$4), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        expect(_gets(s), hasLength(2));
      });
    }

    testWidgets(
      'failing row-meta: no buttons plus the note; failed list; unknown total is "-"',
      (tester) async {
        _tall(tester);
        final m = await _session(
          '/travel/claims',
          () => [claim('a', 'TRV-1', total: null)],
          meta: () => null,
        );
        await tester.pumpWidget(travelPanel(m));
        await _settle(tester);
        expect(find.text(kApprovalMetaFailed), findsOneWidget);
        await tester.tap(find.text('Waiting on others (1)'));
        await _settle(tester);
        expect(find.text('Review'), findsNothing);
        expect(find.text('₹0.00'), findsNothing);
        expect(find.text('₹0'), findsNothing);
        expect(find.text('-'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        final f = await _session('/travel/claims', () => [], failList: true);
        await tester.pumpWidget(travelPanel(f));
        await _settle(tester);
        expect(find.text(kTravelApprovalsLoadFailed), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
      },
    );

    test('countActionable', () async {
      final s = await _session(
        '/travel/claims',
        () => [
          for (var i = 0; i < 6; i++) claim('w$i', 'W$i'),
          claim('a', 'TRV-1'),
        ],
        meta: () => {'a': _can(), for (var i = 0; i < 6; i++) 'w$i': _cannot()},
      );
      expect(
        await TravelApprovalsPanel.countActionable(
          travelRepository: TravelRepository(auth: s.auth),
          approvalsRepository: ApprovalsRepository(auth: s.auth),
        ),
        1,
      );
      final bad = await _session(
        '/travel/claims',
        () => [claim('a', 'T')],
        meta: () => null,
      );
      expect(
        TravelApprovalsPanel.countActionable(
          travelRepository: TravelRepository(auth: bad.auth),
          approvalsRepository: ApprovalsRepository(auth: bad.auth),
        ),
        throwsA(anything),
      );
    });
  });

  // ------------------------------------------------- benefits (general claims)

  Map<String, dynamic> gen(
    String id,
    String name, {
    String status = 'pending',
    Object? amount = '1250.00',
    String emp = 'emp-1',
    bool esi = false,
  }) => {
    'id': id,
    'employee_id': emp,
    'claimed_amount': amount,
    'approved_amount': null,
    'description': 'Gym membership',
    'status': status,
    'claim_date': '2026-10-01T00:00:00.000Z',
    'created_at': '2026-10-01T09:00:00.000Z',
    'is_esi_claim': esi,
    'claim_type': esi ? 'esi' : 'general',
    'benefits_catalog': {'benefit_name': 'Wellness', 'benefit_type': 'health'},
    'employee_records_benefit_claims_employee_idToemployee_records': {
      'full_name': name,
      'employee_id': 'E-$id',
    },
  };

  Widget genPanel(TestSession s) => _host(
    BenefitGeneralApprovalsPanel(
      benefitsRepository: BenefitsRepository(auth: s.auth),
      approvalsRepository: ApprovalsRepository(auth: s.auth),
    ),
  );

  group('BenefitGeneralApprovalsPanel', () {
    testWidgets(
      'lists GET /benefits/claims without ESI and own rows, split by the engine (module benefits)',
      (tester) async {
        _tall(tester);
        final s = await _session(
          '/benefits/claims',
          () => [
            gen('a', 'Asha Rao'),
            gen('b', 'Ben Roy', status: 'manager_approved'),
            gen('c', 'Cara Das', status: 'approved'),
            gen('e', 'Esi Person', esi: true),
            gen('m', 'Me', emp: testEmployeeId),
          ],
          meta: () => {'a': _can(), 'b': _cannot('hr_manager')},
        );
        await tester.pumpWidget(genPanel(s));
        await _settle(tester);
        expect(_gets(s).single.path, '$_org/benefits/claims');
        expect(_gets(s).single.query, isEmpty);
        expect(
          _metaCalls(s).single.path,
          '$_org/workflows/module/benefits/row-meta',
        );
        expect(_metaCalls(s).single.json, {
          'recordIds': ['a', 'b'],
        });
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Waiting on others (1)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(find.text('Esi Person'), findsNothing);
        expect(find.text('Me'), findsNothing);
        expect(find.text('₹1,250'), findsOneWidget);
        await tester.tap(find.text('Waiting on others (1)'));
        await _settle(tester);
        expect(find.text('Waiting on HR manager'), findsOneWidget);
        expect(find.text('Review'), findsNothing);
      },
    );

    testWidgets('approve sends {approvedAmount: claimed}; the list reloads', (
      tester,
    ) async {
      _tall(tester);
      var rows = [gen('a', 'Asha Rao')];
      final s = await _session(
        '/benefits/claims',
        () => rows,
        meta: () => {'a': _can()},
        onDecision: (path, body) {
          rows = [gen('a', 'Asha Rao', status: 'approved')];
          return ok({'id': 'a'});
        },
      );
      await tester.pumpWidget(genPanel(s));
      await _pumpAndTapReview(tester);
      expect(
        find.text('Approving approves the claimed amount.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      final post = _decisionPost(s);
      expect(post.path, '$_org/benefits/claims/a/approve');
      expect(post.json, {'approvedAmount': 1250});
      expect(find.text('Claim approved'), findsOneWidget);
      expect(_gets(s), hasLength(2));
      expect(find.text('Needs my action (0)'), findsOneWidget);
    });

    testWidgets('reject needs a reason and sends {comments}', (tester) async {
      _tall(tester);
      final s = await _session(
        '/benefits/claims',
        () => [gen('a', 'Asha Rao')],
        meta: () => {'a': _can()},
        onDecision: (path, body) => ok({'id': 'a'}),
      );
      await tester.pumpWidget(genPanel(s));
      await _pumpAndTapReview(tester);
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      expect(find.text('Please give a reason for rejecting.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reject-reason')),
        'Not covered',
      );
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      final post = _decisionPost(s);
      expect(post.path, '$_org/benefits/claims/a/reject');
      expect(post.json, {'comments': 'Not covered'});
      expect(find.text('Claim rejected'), findsOneWidget);
    });

    testWidgets(
      'a refusal is friendly and reloads; no amount is never shown as ₹0 and cannot be approved',
      (tester) async {
        _tall(tester);
        final s = await _session(
          '/benefits/claims',
          () => [gen('a', 'Asha Rao')],
          meta: () => {'a': _can()},
          onDecision: (path, body) =>
              _err(403, 'forbidden', code: 'NOT_ALLOWED'),
        );
        await tester.pumpWidget(genPanel(s));
        await _pumpAndTapReview(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        expect(
          find.textContaining("You can't decide this request"),
          findsWidgets,
        );
        expect(_gets(s), hasLength(2));

        await tester.pumpWidget(const SizedBox());
        final z = await _session(
          '/benefits/claims',
          () => [gen('a', 'Asha Rao', amount: null)],
          meta: () => {'a': _can()},
        );
        await tester.pumpWidget(genPanel(z));
        await _pumpAndTapReview(tester);
        expect(find.text('₹0'), findsNothing);
        expect(find.text('Not available'), findsWidgets);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Close'), findsOneWidget);
      },
    );

    testWidgets('failing meta, failing list, and empty states', (tester) async {
      _tall(tester);
      final m = await _session(
        '/benefits/claims',
        () => [gen('a', 'Asha Rao')],
        meta: () => null,
      );
      await tester.pumpWidget(genPanel(m));
      await _settle(tester);
      expect(find.text(kApprovalMetaFailed), findsOneWidget);
      expect(find.text('Review'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final f = await _session('/benefits/claims', () => [], failList: true);
      await tester.pumpWidget(genPanel(f));
      await _settle(tester);
      expect(find.text(kBenefitGeneralApprovalsLoadFailed), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final e = await _session('/benefits/claims', () => []);
      await tester.pumpWidget(genPanel(e));
      await _settle(tester);
      expect(find.text('No benefit claims need your action.'), findsOneWidget);
    });

    test(
      'countActionable for the general list and for ESI plus general',
      () async {
        final s = await signedIn((req) async {
          if (req.method == 'GET' && req.url.path == '$_org/benefits/claims') {
            return ok({
              'items': [gen('a', 'A'), gen('b', 'B'), gen('e', 'E', esi: true)],
              'total': 3,
            });
          }
          if (req.method == 'GET' &&
              req.url.path == '$_org/benefits/esi/claims') {
            return ok([
              {'id': 'x1', 'employee_id': 'emp-9', 'status': 'pending'},
              {'id': 'x2', 'employee_id': 'emp-8', 'status': 'pending'},
            ]);
          }
          if (req.url.path.endsWith('/row-meta')) {
            return ok({'a': _can(), 'b': _cannot()});
          }
          return _err(404, 'unexpected');
        }, empRole: 'manager');
        final repo = BenefitsRepository(auth: s.auth);
        final approvals = ApprovalsRepository(auth: s.auth);
        expect(
          await BenefitGeneralApprovalsPanel.countActionable(
            benefitsRepository: repo,
            approvalsRepository: approvals,
          ),
          1,
        );
        expect(
          await BenefitApprovalsPanel.countActionable(benefitsRepository: repo),
          2,
        );
        expect(
          await BenefitClaimsApprovals.countActionable(
            benefitsRepository: repo,
            approvalsRepository: approvals,
          ),
          3,
        );
      },
    );

    testWidgets(
      'BenefitClaimsApprovals has an ESI tab and an Other claims tab with the new panel',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.method == 'GET' && req.url.path == '$_org/benefits/claims') {
            return ok({
              'items': [gen('a', 'Asha Rao')],
              'total': 1,
            });
          }
          if (req.method == 'GET' &&
              req.url.path == '$_org/benefits/esi/claims') {
            return ok([]);
          }
          if (req.url.path.endsWith('/row-meta')) return ok({'a': _can()});
          return _err(404, 'unexpected');
        }, empRole: 'manager');
        await tester.pumpWidget(
          _host(
            BenefitClaimsApprovals(
              benefitsRepository: BenefitsRepository(auth: s.auth),
              approvalsRepository: ApprovalsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('ESI claims'), findsOneWidget);
        expect(find.text('No ESI claims need your action.'), findsOneWidget);
        await tester.tap(find.text('Other claims'));
        await _settle(tester);
        expect(find.text('Needs my action (1)'), findsOneWidget);
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(
          find.byKey(const Key('general-benefit-approvals-slot')),
          findsNothing,
        );
      },
    );
  });

  // ---------------------------------------------------------------- benefits (ESI)

  Map<String, dynamic> esi(
    String id,
    String name, {
    String emp = 'emp-1',
    String status = 'pending',
  }) => {
    'id': id,
    'employee_id': emp,
    'employee_name': name,
    'employee_code': 'E-$id',
    'department': 'Ops',
    'esi_benefit_type': 'sickness',
    'esi_start_date': '2026-09-01T00:00:00.000Z',
    'esi_end_date': '2026-09-05T00:00:00.000Z',
    'esi_days_claimed': 5,
    'claimed_amount': '0.00',
    'description': 'Fever',
    'status': status,
    'created_at': '2026-09-06T09:00:00.000Z',
  };

  Future<TestSession> esiSession(
    List<Map<String, dynamic>> Function() rows, {
    http.Response Function(String path, String body)? onDecision,
    bool failList = false,
  }) {
    return signedIn((req) async {
      if (req.method == 'GET' && req.url.path == '$_org/benefits/esi/claims') {
        return failList ? _boom : ok(rows());
      }
      if (req.method == 'POST') return onDecision!(req.url.path, req.body);
      return _err(404, 'unexpected');
    }, empRole: 'manager');
  }

  Widget esiPanel(TestSession s) => _host(
    BenefitApprovalsPanel(benefitsRepository: BenefitsRepository(auth: s.auth)),
  );

  group('BenefitApprovalsPanel (ESI)', () {
    testWidgets(
      'lists the waiting ESI claims, shows no amount and no general note',
      (tester) async {
        _tall(tester);
        final s = await esiSession(
          () => [
            esi('a', 'Asha Rao'),
            esi('b', 'Ben Roy', status: 'manager_approved'),
            esi('m', 'Me', emp: testEmployeeId),
          ],
        );
        await tester.pumpWidget(esiPanel(s));
        await _settle(tester);
        expect(s.requests.single.path, '$_org/benefits/esi/claims');
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(find.text('Ben Roy'), findsOneWidget);
        expect(find.text('Me'), findsNothing);
        expect(find.textContaining('₹'), findsNothing);
        expect(
          find.byKey(const Key('general-benefit-approvals-slot')),
          findsNothing,
        );
        expect(
          find.textContaining("General benefit claims aren't available"),
          findsNothing,
        );
      },
    );

    testWidgets(
      'approve sends {}; reject needs a reason and sends {comments}; the list reloads',
      (tester) async {
        _tall(tester);
        var rows = [esi('a', 'Asha Rao'), esi('b', 'Ben Roy')];
        final s = await esiSession(
          () => rows,
          onDecision: (path, body) {
            rows = rows.where((r) => !path.contains('/${r['id']}/')).toList();
            return ok({'id': 'x'});
          },
        );
        await tester.pumpWidget(esiPanel(s));
        await _settle(tester);
        await tester.tap(find.text('Review').first);
        await _settle(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        var post = s.requests.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/benefits/esi/claims/a/approve');
        expect(post.body, '{}');
        expect(find.text('ESI claim approved'), findsOneWidget);
        expect(s.requests.where((r) => r.method == 'GET'), hasLength(2));

        await tester.tap(find.text('Review'));
        await _settle(tester);
        await tester.tap(find.text('Reject'));
        await _settle(tester);
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        expect(
          find.text('Please give a reason for rejecting.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('reject-reason')),
          'Certificate missing',
        );
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        post = s.requests.where((r) => r.method == 'POST').last;
        expect(post.path, '$_org/benefits/esi/claims/b/reject');
        expect(post.json, {'comments': 'Certificate missing'});
        expect(find.text('No ESI claims need your action.'), findsOneWidget);
      },
    );

    testWidgets('a refusal is friendly; empty and failed states are distinct', (
      tester,
    ) async {
      _tall(tester);
      final s = await esiSession(
        () => [esi('a', 'Asha Rao')],
        onDecision: (path, body) =>
            _err(500, 'db exploded at https://api.hrtoffy.in'),
      );
      await tester.pumpWidget(esiPanel(s));
      await _settle(tester);
      await tester.tap(find.text('Review'));
      await _settle(tester);
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      expect(
        find.textContaining("Couldn't complete this right now"),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final f = await esiSession(() => [], failList: true);
      await tester.pumpWidget(esiPanel(f));
      await _settle(tester);
      expect(find.text(kBenefitApprovalsLoadFailed), findsOneWidget);
      expect(find.text('No ESI claims need your action.'), findsNothing);
    });
  });

  test('approvalWaitingText names roles in words', () {
    expect(approvalWaitingText(null), 'Waiting on someone else');
    expect(
      approvalWaitingText(
        const ApprovalMeta(canApprove: false, requiredRole: 'hr_manager'),
      ),
      'Waiting on HR manager',
    );
    expect(
      approvalWaitingText(
        const ApprovalMeta(canApprove: false, requiredRole: 'hr_head'),
      ),
      'Waiting on HR head',
    );
    expect(
      approvalWaitingText(
        const ApprovalMeta(canApprove: false, requiredRole: 'manager'),
      ),
      'Waiting on manager',
    );
    expect(
      approvalWaitingText(
        const ApprovalMeta(canApprove: false, requiredRole: 'xyz_role'),
      ),
      'Waiting on someone else',
    );
  });

  test(
    'the panels and repositories contain no Supabase, direct status or approver writes',
    () {
      final files = [
        'lib/screens/manager/widgets/loan_approvals_panel.dart',
        'lib/screens/manager/widgets/travel_approvals_panel.dart',
        'lib/screens/manager/widgets/benefit_approvals_panel.dart',
        'lib/screens/manager/widgets/benefit_general_approvals_panel.dart',
        'lib/screens/manager/widgets/benefit_claims_approvals.dart',
        'lib/screens/manager/widgets/approval_review.dart',
        'lib/screens/manager/widgets/approval_split_panel.dart',
        'lib/screens/manager/manager_loans_screen.dart',
        'lib/screens/manager/manager_travel_screen.dart',
        'lib/screens/manager/manager_benefits_screen.dart',
      ];
      for (final f in files) {
        final src = File(f).readAsStringSync();
        for (final banned in [
          'supabase',
          'Supabase',
          '.rpc(',
          '.update(',
          '.insert(',
          'manager_comments:',
          "'status':",
          'approver',
          'print(',
          'debugPrint(',
          r"$e'",
          r'$e"',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$f has "$banned"');
        }
      }
    },
  );
}
