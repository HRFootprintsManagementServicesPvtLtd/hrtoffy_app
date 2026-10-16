import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart';
import 'package:hrms_app/screens/manager/widgets/benefit_approvals_panel.dart';
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

// ------------------------------------------------------------------ loans

Map<String, dynamic> _loan(
  String id,
  String number, {
  String status = 'pending',
  Object? requested = '20000.00',
  String emp = 'emp-1',
  String created = '2026-10-02T00:00:00.000Z',
}) => {
  'id': id,
  'loan_number': number,
  'employee_id': emp,
  'loan_category': 'salary_advance',
  'purpose': 'Medical',
  'requested_amount': requested,
  'tenure_months': 6,
  'status': status,
  'created_at': created,
  'employee_records_loans_advances_employee_idToemployee_records': {
    'full_name': 'Asha Rao',
    'employee_id': 'E-100',
  },
};

/// A fake loans API: [rows] is what the next list returns; [onDecision] answers a POST (and may change [rows]).
Future<TestSession> _loanSession(
  List<Map<String, dynamic>> Function() rows, {
  http.Response Function(String path, String body)? onDecision,
  bool failList = false,
}) {
  return signedIn((req) async {
    if (req.method == 'GET' && req.url.path == '$_org/loans') {
      if (failList) return _boom;
      final r = rows();
      return ok({'items': r, 'total': r.length});
    }
    if (req.method == 'POST') return onDecision!(req.url.path, req.body);
    return _err(404, 'unexpected');
  }, empRole: 'manager');
}

void main() {
  group('LoanApprovalsPanel', () {
    testWidgets(
      'queue: pending and manager_approved are actionable, decided ones are in History, own loans are not listed',
      (tester) async {
        _tall(tester);
        final s = await _loanSession(
          () => [
            _loan('a', 'L-1'),
            _loan('b', 'L-2', status: 'manager_approved'),
            _loan('c', 'L-3', status: 'approved'),
            _loan('d', 'L-4', status: 'rejected'),
            _loan('m', 'L-MINE', emp: testEmployeeId),
          ],
        );
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: s.auth)),
          ),
        );
        await _settle(tester);

        expect(
          s.requests.single.query,
          isEmpty,
        ); // not own-scoped, and no status filter that would hide manager_approved
        expect(find.text('Needs My Action (2)'), findsOneWidget);
        expect(find.text('History (2)'), findsOneWidget);
        expect(find.text('L-1'), findsOneWidget);
        expect(find.text('L-2'), findsOneWidget);
        expect(find.text('MANAGER APPROVED'), findsOneWidget);
        expect(find.text('L-3'), findsNothing);
        expect(find.text('L-MINE'), findsNothing);
        expect(find.text('Asha Rao'), findsNWidgets(2));
        expect(find.text('₹20,000'), findsNWidgets(2));
        expect(find.text('Review'), findsNWidgets(2));

        await tester.tap(find.text('History (2)'));
        await _settle(tester);
        expect(find.text('L-3'), findsOneWidget);
        expect(find.text('L-4'), findsOneWidget);
        expect(find.text('L-1'), findsNothing);
        expect(find.text('View'), findsNWidgets(2));
      },
    );

    testWidgets(
      'approve: POST with no body, success message, the list is reloaded',
      (tester) async {
        _tall(tester);
        var rows = [_loan('a', 'L-1'), _loan('b', 'L-2')];
        final s = await _loanSession(
          () => rows,
          onDecision: (path, body) {
            rows = [_loan('a', 'L-1', status: 'approved'), _loan('b', 'L-2')];
            return ok({'id': 'a', 'status': 'approved'});
          },
        );
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: s.auth)),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text('Review').first);
        await _settle(tester);
        expect(find.text('Review Loan Request'), findsOneWidget);
        expect(
          find.text('Approving sanctions the requested amount.'),
          findsOneWidget,
        );
        expect(
          find.byType(TextField),
          findsNothing,
        ); // no comment field on approve: the route takes none
        await tester.tap(find.text('Approve'));
        await _settle(tester);

        final post = s.requests.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/loans/a/approve');
        expect(post.body, isEmpty);
        expect(find.text('Loan approved'), findsOneWidget);
        expect(
          s.requests.where((r) => r.method == 'GET'),
          hasLength(2),
        ); // initial + reload
        expect(find.text('Needs My Action (1)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'reject: the reason is asked only on Reject and is sent as {reason}',
      (tester) async {
        _tall(tester);
        final s = await _loanSession(
          () => [_loan('a', 'L-1')],
          onDecision: (path, body) => ok({'id': 'a'}),
        );
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: s.auth)),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('Review'));
        await _settle(tester);
        expect(find.byKey(const Key('reject-reason')), findsNothing);
        await tester.tap(find.text('Reject'));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('reject-reason')),
          'Over the limit',
        );
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        final post = s.requests.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/loans/a/reject');
        expect(post.json, {'reason': 'Over the limit'});
        expect(find.text('Loan rejected'), findsOneWidget);
      },
    );

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
        'a ${c.$1} refusal shows a friendly message, never the server text, and reloads the list',
        (tester) async {
          _tall(tester);
          final s = await _loanSession(
            () => [_loan('a', 'L-1')],
            onDecision: (path, body) => _err(c.$1, c.$2, code: c.$3),
          );
          await tester.pumpWidget(
            _host(
              LoanApprovalsPanel(
                loansRepository: LoansRepository(auth: s.auth),
              ),
            ),
          );
          await _settle(tester);
          await tester.tap(find.text('Review'));
          await _settle(tester);
          await tester.tap(find.text('Approve'));
          await _settle(tester);
          expect(find.textContaining(c.$4), findsOneWidget);
          expect(find.textContaining('exploded'), findsNothing);
          expect(find.textContaining('hrtoffy'), findsNothing);
          expect(find.textContaining('Not the approver'), findsNothing);
          expect(
            s.requests.where((r) => r.method == 'GET'),
            hasLength(2),
          ); // reloaded after the refusal too
          expect(
            find.text('L-1'),
            findsOneWidget,
          ); // still listed: nothing was changed
        },
      );
    }

    testWidgets('decided loans can be viewed but not decided', (tester) async {
      _tall(tester);
      final s = await _loanSession(
        () => [_loan('c', 'L-3', status: 'approved')],
      );
      await tester.pumpWidget(
        _host(
          LoanApprovalsPanel(loansRepository: LoansRepository(auth: s.auth)),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('History (1)'));
      await _settle(tester);
      await tester.tap(find.text('View'));
      await _settle(tester);
      expect(find.text('Loan Request'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets(
      'empty queue, empty history and a failed load are distinct; an unknown amount is never ₹0',
      (tester) async {
        _tall(tester);
        final e = await _loanSession(() => []);
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: e.auth)),
          ),
        );
        await _settle(tester);
        expect(find.text('No loan requests need your action.'), findsOneWidget);
        await tester.tap(find.text('History (0)'));
        await _settle(tester);
        expect(find.text('No decided loan requests yet.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        final f = await _loanSession(() => [], failList: true);
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: f.auth)),
          ),
        );
        await _settle(tester);
        expect(find.text(kLoanApprovalsLoadFailed), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No loan requests need your action.'), findsNothing);
        expect(find.textContaining('exploded'), findsNothing);
        expect(
          find.text('Needs My Action'),
          findsOneWidget,
        ); // no count while unknown

        await tester.pumpWidget(const SizedBox());
        final z = await _loanSession(
          () => [
            _loan('a', 'L-1', requested: 0),
            _loan('b', 'L-2', requested: null),
          ],
        );
        await tester.pumpWidget(
          _host(
            LoanApprovalsPanel(loansRepository: LoansRepository(auth: z.auth)),
          ),
        );
        await _settle(tester);
        expect(find.text('Not available'), findsNWidgets(2));
        expect(find.text('₹0'), findsNothing);
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

  Future<TestSession> travelSession(
    List<Map<String, dynamic>> Function() rows, {
    http.Response Function(String path, String body)? onDecision,
    bool failList = false,
  }) {
    return signedIn((req) async {
      if (req.method == 'GET' && req.url.path == '$_org/travel/claims') {
        return failList ? _boom : ok(rows());
      }
      if (req.method == 'POST') return onDecision!(req.url.path, req.body);
      return _err(404, 'unexpected');
    }, empRole: 'manager');
  }

  group('TravelApprovalsPanel', () {
    testWidgets(
      'queue, History, own claims left out, amounts and the expense breakdown',
      (tester) async {
        _tall(tester);
        final s = await travelSession(
          () => [
            claim('a', 'TRV-1'),
            claim('b', 'TRV-2', status: 'manager_approved'),
            claim('c', 'TRV-3', status: 'approved'),
            claim('m', 'TRV-MINE', emp: testEmployeeId),
          ],
        );
        await tester.pumpWidget(
          _host(
            TravelApprovalsPanel(
              travelRepository: TravelRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(s.requests.single.query, isEmpty);
        expect(find.text('Needs My Action (2)'), findsOneWidget);
        expect(find.text('History (1)'), findsOneWidget);
        expect(find.text('TRV-1'), findsOneWidget);
        expect(find.text('TRV-2'), findsOneWidget);
        expect(find.text('TRV-MINE'), findsNothing);
        expect(find.text('Ben Roy • Engineer'), findsNWidgets(2));
        expect(find.text('₹5,400.50'), findsNWidgets(2));

        await tester.tap(find.text('Review').first);
        await _settle(tester);
        expect(find.text('Expense breakdown'), findsOneWidget);
        expect(find.text('₹3,000.00'), findsOneWidget);
        expect(
          find.text('-'),
          findsWidgets,
        ); // the taxi line has no amount: "-", never ₹0
        expect(find.text('₹0.00'), findsNothing);
        expect(
          find.text('Approving approves the claimed total.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('approve posts {} and reloads; reject posts {reason}', (
      tester,
    ) async {
      _tall(tester);
      var rows = [claim('a', 'TRV-1')];
      final s = await travelSession(
        () => rows,
        onDecision: (path, body) {
          rows = [
            claim(
              'a',
              'TRV-1',
              status: path.endsWith('approve') ? 'approved' : 'rejected',
            ),
          ];
          return ok(claim('a', 'TRV-1'));
        },
      );
      await tester.pumpWidget(
        _host(
          TravelApprovalsPanel(
            travelRepository: TravelRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Review'));
      await _settle(tester);
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      var post = s.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, '$_org/travel/claims/a/approve');
      expect(post.json, <String, dynamic>{});
      expect(find.text('Claim approved'), findsOneWidget);
      expect(find.text('Needs My Action (0)'), findsOneWidget);
      expect(find.text('History (1)'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'GET'), hasLength(2));

      await tester.pumpWidget(const SizedBox());
      rows = [claim('a', 'TRV-1')];
      final r = await travelSession(
        () => rows,
        onDecision: (path, body) => ok(claim('a', 'TRV-1')),
      );
      await tester.pumpWidget(
        _host(
          TravelApprovalsPanel(
            travelRepository: TravelRepository(auth: r.auth),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Review'));
      await _settle(tester);
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('reject-reason')),
        'Receipts missing',
      );
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      post = r.requests.firstWhere((x) => x.method == 'POST');
      expect(post.path, '$_org/travel/claims/a/reject');
      expect(post.json, {'reason': 'Receipts missing'});
      expect(find.text('Claim rejected'), findsOneWidget);
    });

    for (final c in [
      (
        403,
        'You cannot approve or reject your own claim',
        null,
        "You can't approve or reject your own request.",
      ),
      (
        403,
        'forbidden',
        'FORBIDDEN',
        "You can't decide this request right now",
      ),
      (
        404,
        'Travel claim not found',
        null,
        'This request is no longer available to you.',
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
        final s = await travelSession(
          () => [claim('a', 'TRV-1')],
          onDecision: (path, body) => _err(c.$1, c.$2, code: c.$3),
        );
        await tester.pumpWidget(
          _host(
            TravelApprovalsPanel(
              travelRepository: TravelRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('Review'));
        await _settle(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        expect(find.textContaining(c.$4), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
        expect(s.requests.where((r) => r.method == 'GET'), hasLength(2));
      });
    }

    testWidgets(
      'empty states, a failed load, and an unknown total shown as "-"',
      (tester) async {
        _tall(tester);
        final e = await travelSession(() => []);
        await tester.pumpWidget(
          _host(
            TravelApprovalsPanel(
              travelRepository: TravelRepository(auth: e.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(
          find.text('No claims require your action at this time.'),
          findsOneWidget,
        );
        await tester.tap(find.text('History (0)'));
        await _settle(tester);
        expect(find.text('No decided travel claims yet.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        final f = await travelSession(() => [], failList: true);
        await tester.pumpWidget(
          _host(
            TravelApprovalsPanel(
              travelRepository: TravelRepository(auth: f.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text(kTravelApprovalsLoadFailed), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        final z = await travelSession(() => [claim('a', 'TRV-1', total: null)]);
        await tester.pumpWidget(
          _host(
            TravelApprovalsPanel(
              travelRepository: TravelRepository(auth: z.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('₹0.00'), findsNothing);
        expect(find.text('₹0'), findsNothing);
        expect(find.text('-'), findsOneWidget);
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
      if (req.method == 'GET' &&
          req.url.path == '$_org/benefits/esi/claims') {
        return failList ? _boom : ok(rows());
      }
      if (req.method == 'POST') return onDecision!(req.url.path, req.body);
      return _err(404, 'unexpected');
    }, empRole: 'manager');
  }

  group('BenefitApprovalsPanel', () {
    testWidgets(
      'lists the waiting ESI claims, shows no amount, keeps the LEAD-INTEGRATES slot',
      (tester) async {
        _tall(tester);
        final s = await esiSession(
          () => [
            esi('a', 'Asha Rao'),
            esi('b', 'Ben Roy', status: 'manager_approved'),
            esi('m', 'Me', emp: testEmployeeId),
          ],
        );
        await tester.pumpWidget(
          _host(
            BenefitApprovalsPanel(
              benefitsRepository: BenefitsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        expect(s.requests.single.path, '$_org/benefits/esi/claims');
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(find.text('Ben Roy'), findsOneWidget);
        expect(find.text('Me'), findsNothing);
        expect(find.text('MANAGER APPROVED'), findsOneWidget);
        expect(find.text('Sickness'), findsNWidgets(2));
        expect(
          find.textContaining('01 Sep 2026 - 05 Sep 2026'),
          findsNWidgets(2),
        );
        expect(
          find.textContaining('₹'),
          findsNothing,
        ); // ESI claims carry no claimed amount: none is shown, never ₹0
        expect(
          find.byKey(const Key('general-benefit-approvals-slot')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Decided claims are not listed here'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'approve and reject always send a JSON body; approve has no comment field; the list reloads',
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
        await tester.pumpWidget(
          _host(
            BenefitApprovalsPanel(
              benefitsRepository: BenefitsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text('Review').first);
        await _settle(tester);
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        var post = s.requests.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/benefits/esi/claims/a/approve');
        expect(
          post.body,
          '{}',
        ); // the route destructures the body: it must exist
        expect(find.text('ESI claim approved'), findsOneWidget);
        expect(find.text('Asha Rao'), findsNothing);
        expect(s.requests.where((r) => r.method == 'GET'), hasLength(2));

        await tester.tap(find.text('Review'));
        await _settle(tester);
        await tester.tap(find.text('Reject'));
        await _settle(tester);
        await tester.tap(find.text('Confirm reject'));
        await _settle(tester);
        post = s.requests.where((r) => r.method == 'POST').last;
        expect(post.path, '$_org/benefits/esi/claims/b/reject');
        expect(post.body, '{}'); // no reason typed: still a body
        expect(find.text('No ESI claims need your action.'), findsOneWidget);
      },
    );

    testWidgets('a rejection reason is sent as {comments}', (tester) async {
      _tall(tester);
      final s = await esiSession(
        () => [esi('a', 'Asha Rao')],
        onDecision: (path, body) => ok({'id': 'a'}),
      );
      await tester.pumpWidget(
        _host(
          BenefitApprovalsPanel(
            benefitsRepository: BenefitsRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Review'));
      await _settle(tester);
      await tester.tap(find.text('Reject'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('reject-reason')),
        'Certificate missing',
      );
      await tester.tap(find.text('Confirm reject'));
      await _settle(tester);
      expect(s.requests.firstWhere((r) => r.method == 'POST').json, {
        'comments': 'Certificate missing',
      });
    });

    for (final c in [
      (
        403,
        'You are not authorized to approve this claim',
        null,
        "You can't decide this request right now",
      ),
      (
        404,
        'ESI claim not found',
        null,
        'This request is no longer available to you.',
      ),
      (
        400,
        "Cannot approve claim with status 'approved'",
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
      testWidgets('a ${c.$1} refusal is friendly and the list is reloaded', (
        tester,
      ) async {
        _tall(tester);
        final s = await esiSession(
          () => [esi('a', 'Asha Rao')],
          onDecision: (path, body) => _err(c.$1, c.$2, code: c.$3),
        );
        await tester.pumpWidget(
          _host(
            BenefitApprovalsPanel(
              benefitsRepository: BenefitsRepository(auth: s.auth),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('Review'));
        await _settle(tester);
        await tester.tap(find.text('Approve'));
        await _settle(tester);
        expect(find.textContaining(c.$4), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
        expect(s.requests.where((r) => r.method == 'GET'), hasLength(2));
      });
    }

    testWidgets('empty and failed states are distinct', (tester) async {
      _tall(tester);
      final e = await esiSession(() => []);
      await tester.pumpWidget(
        _host(
          BenefitApprovalsPanel(
            benefitsRepository: BenefitsRepository(auth: e.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('No ESI claims need your action.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final f = await esiSession(() => [], failList: true);
      await tester.pumpWidget(
        _host(
          BenefitApprovalsPanel(
            benefitsRepository: BenefitsRepository(auth: f.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text(kBenefitApprovalsLoadFailed), findsOneWidget);
      expect(find.text('No ESI claims need your action.'), findsNothing);
      expect(find.textContaining('exploded'), findsNothing);
      expect(
        find.byKey(const Key('general-benefit-approvals-slot')),
        findsOneWidget,
      );
    });
  });

  test(
    'the panels and repositories contain no Supabase, direct status or approver writes',
    () {
      final files = [
        'lib/screens/manager/widgets/loan_approvals_panel.dart',
        'lib/screens/manager/widgets/travel_approvals_panel.dart',
        'lib/screens/manager/widgets/benefit_approvals_panel.dart',
        'lib/screens/manager/widgets/approval_review.dart',
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
