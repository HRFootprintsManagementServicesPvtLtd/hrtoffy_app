import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/approval_errors.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _loanRow(
  String id,
  String empId, {
  String status = 'pending',
  Object? requested = '20000.00',
  String created = '2026-10-01T00:00:00.000Z',
}) => {
  'id': id,
  'loan_number': 'L-$id',
  'employee_id': empId,
  'loan_category': 'salary_advance',
  'purpose': 'Medical',
  'requested_amount': requested,
  'tenure_months': '6',
  'status': status,
  'created_at': created,
  'employee_records_loans_advances_employee_idToemployee_records': {
    'full_name': 'Name $id',
    'employee_id': 'E-$id',
    'department': 'Ops',
  },
};

void main() {
  group('LoansRepository approvals', () {
    test(
      'approvalLoans: GET /loans with no employeeId, own loans left out, every status kept, newest first, employee attached',
      () async {
        final s = await signedIn((req) async {
          expect(req.url.path, '$_org/loans');
          return ok({
            'items': [
              _loanRow('a', 'emp-a', created: '2026-10-01T00:00:00.000Z'),
              _loanRow('mine', testEmployeeId),
              _loanRow(
                'b',
                'emp-b',
                status: 'manager_approved',
                created: '2026-10-03T00:00:00.000Z',
              ),
              _loanRow(
                'c',
                'emp-c',
                status: 'approved',
                requested: null,
                created: '2026-10-02T00:00:00.000Z',
              ),
            ],
            'total': 4,
          });
        }, empRole: 'manager');
        final rows = await LoansRepository(auth: s.auth).approvalLoans();
        expect(s.requests.single.query, isEmpty);
        expect(rows.map((r) => r['id']), ['b', 'c', 'a']);
        expect(rows.first['status'], 'manager_approved');
        expect(rows.first['requested_amount'], 20000);
        expect(rows.first['tenure_months'], 6);
        expect(rows.first['employee'], {
          'full_name': 'Name b',
          'employee_id': 'E-b',
          'department': 'Ops',
        });
        expect(
          rows[1]['requested_amount'],
          isNull,
        ); // unknown stays null, never 0
        expect(rows.where(LoansRepository.isOpen).map((r) => r['id']), [
          'b',
          'a',
        ]);
      },
    );

    test(
      'approveLoan sends NO body; rejectLoan sends the reason only when given',
      () async {
        final s = await signedIn(
          (req) async => ok(_loanRow('x', 'emp-x', status: 'approved')),
        );
        final repo = LoansRepository(auth: s.auth);
        await repo.approveLoan('l 1');
        await repo.rejectLoan('l2', reason: '  Not eligible  ');
        await repo.rejectLoan('l3');
        final calls = s.apiCalls;
        expect(calls[0].method, 'POST');
        expect(calls[0].path, '$_org/loans/l%201/approve');
        expect(calls[0].body, isEmpty);
        expect(calls[1].path, '$_org/loans/l2/reject');
        expect(calls[1].json, {'reason': 'Not eligible'});
        expect(calls[2].json, <String, dynamic>{});
      },
    );

    test('requestLoan sends loanCategory only when given', () async {
      final s = await signedIn((req) async => ok({'loanId': 'n1'}, 201));
      final repo = LoansRepository(auth: s.auth);
      await repo.requestLoan(amount: 100, reason: 'r');
      await repo.requestLoan(
        amount: 100,
        reason: 'r',
        loanCategory: 'travel_advance',
      );
      expect(s.apiCalls[0].json, {
        'employeeId': testEmployeeId,
        'amount': 100.0,
        'reason': 'r',
      });
      expect(s.apiCalls[1].json['loanCategory'], 'travel_advance');
    });
  });

  group('TravelRepository approvals', () {
    Map<String, dynamic> claim(
      String id,
      String empId, {
      String status = 'pending',
      String created = '2026-10-01T00:00:00.000Z',
      List<Map<String, dynamic>>? lines,
    }) => {
      'id': id,
      'claim_number': 'TRV-$id',
      'employee_id': empId,
      'trip_destination': 'Pune',
      'total_amount': '5400.50',
      'status': status,
      'created_at': created,
      'trip_from_date': '2026-10-07T00:00:00.000Z',
      'employee_records_travel_claims_employee_idToemployee_records': {
        'full_name': 'T $id',
        'employee_id': 'E-$id',
        'designation': 'Engineer',
      },
      'travel_expenses':
          lines ??
          [
            {
              'id': 'x',
              'expense_type': 'Hotel',
              'amount': '3000.00',
              'expense_date': '2026-10-07T00:00:00.000Z',
            },
          ],
    };

    test(
      'approvalClaims: no employeeId, own left out, employee and expenses attached, amounts numeric',
      () async {
        final s = await signedIn(
          (req) async => ok([
            claim('a', 'emp-a', created: '2026-10-01T00:00:00.000Z'),
            claim('mine', testEmployeeId),
            claim(
              'b',
              'emp-b',
              status: 'manager_approved',
              created: '2026-10-02T00:00:00.000Z',
              lines: [],
            ),
          ]),
        );
        final rows = await TravelRepository(auth: s.auth).approvalClaims();
        expect(s.requests.single.path, '$_org/travel/claims');
        expect(s.requests.single.query, isEmpty);
        expect(rows.map((r) => r['id']), ['b', 'a']);
        expect(rows[1]['employee']['designation'], 'Engineer');
        expect(rows[1]['total_amount'], 5400.5);
        expect(rows[1]['expenses'].single['amount'], 3000);
        expect(rows[1]['expenses'].single['expense_date'], '2026-10-07');
        expect(rows[0]['expenses'], isEmpty);
        expect(TravelRepository.isOpen(rows[0]), isTrue);
      },
    );

    test(
      'approve sends {} (or the amount); reject sends the reason only when given',
      () async {
        final s = await signedIn((req) async => ok(claim('x', 'e')));
        final repo = TravelRepository(auth: s.auth);
        await repo.approveClaim('c1');
        await repo.approveClaim('c2', approvedAmount: 900);
        await repo.rejectClaim('c3', reason: 'Too high');
        await repo.rejectClaim('c4');
        final c = s.apiCalls;
        expect(c[0].path, '$_org/travel/claims/c1/approve');
        expect(c[0].json, <String, dynamic>{});
        expect(c[1].json, {'approvedAmount': 900.0});
        expect(c[2].path, '$_org/travel/claims/c3/reject');
        expect(c[2].json, {'reason': 'Too high'});
        expect(c[3].json, <String, dynamic>{});
      },
    );

    test(
      'advances are the own loans in the travel_advance category; requestAdvance posts that category',
      () async {
        final s = await signedIn((req) async {
          if (req.method == 'POST') return ok({'loanId': 'a1'}, 201);
          return ok({
            'items': [
              {
                'id': '1',
                'loan_category': 'travel_advance',
                'status': 'active',
                'created_at': '2026-10-01T00:00:00.000Z',
              },
              {
                'id': '2',
                'loan_category': 'personal_loan',
                'status': 'active',
                'created_at': '2026-10-02T00:00:00.000Z',
              },
            ],
          });
        });
        final repo = TravelRepository(auth: s.auth);
        expect((await repo.advances()).map((a) => a['id']), ['1']);
        expect(s.requests.single.query, {'employeeId': testEmployeeId});
        await repo.requestAdvance(
          amount: 50,
          reason: 'Float',
          repaymentMonths: 2,
        );
        expect(s.requests.last.json, {
          'employeeId': testEmployeeId,
          'amount': 50.0,
          'reason': 'Float',
          'repaymentMonths': 2,
          'loanCategory': 'travel_advance',
        });
      },
    );
  });

  group('BenefitsRepository ESI approvals', () {
    Map<String, dynamic> esi(
      String id,
      String empId, {
      String created = '2026-09-06T09:00:00.000Z',
    }) => {
      'id': id,
      'employee_id': empId,
      'employee_name': 'N $id',
      'employee_code': 'E-$id',
      'esi_benefit_type': 'sickness',
      'esi_start_date': '2026-09-01T00:00:00.000Z',
      'esi_end_date': '2026-09-05T00:00:00.000Z',
      'esi_days_claimed': '5',
      'claimed_amount': '0.00',
      'status': 'pending',
      'created_at': created,
    };

    test(
      'esiApprovalClaims: GET /benefits/esi/claims, own left out, dates and days normalised',
      () async {
        final s = await signedIn(
          (req) async => ok([
            esi('a', 'emp-a', created: '2026-09-01T00:00:00.000Z'),
            esi('mine', testEmployeeId),
            esi('b', 'emp-b', created: '2026-09-02T00:00:00.000Z'),
          ]),
        );
        final rows = await BenefitsRepository(auth: s.auth).esiApprovalClaims();
        expect(s.requests.single.path, '$_org/benefits/esi/claims');
        expect(s.requests.single.query, isEmpty);
        expect(rows.map((r) => r['id']), ['b', 'a']);
        expect(rows.first['esi_start_date'], '2026-09-01');
        expect(rows.first['esi_days_claimed'], 5);
      },
    );

    test(
      'approve and reject ALWAYS send a JSON body: {} or {comments}',
      () async {
        final s = await signedIn((req) async => ok({'id': 'x'}));
        final repo = BenefitsRepository(auth: s.auth);
        await repo.approveEsiClaim('e1');
        await repo.rejectEsiClaim('e2');
        await repo.rejectEsiClaim('e3', comments: ' Missing certificate ');
        final c = s.apiCalls;
        expect(c[0].path, '$_org/benefits/esi/claims/e1/approve');
        expect(c[0].body, '{}');
        expect(c[0].headers['content-type'], contains('application/json'));
        expect(c[1].path, '$_org/benefits/esi/claims/e2/reject');
        expect(c[1].body, '{}');
        expect(c[2].json, {'comments': 'Missing certificate'});
      },
    );
  });

  group('approvalErrorText', () {
    const fb = 'FALLBACK';
    String t(ApiException e) => approvalErrorText(e, fallback: fb);

    test('maps the engine and HTTP failures to short fixed sentences', () {
      expect(
        t(const ApiException(0, 'Network error: SocketException')),
        contains('No connection'),
      );
      expect(t(const ApiException(401, 'x')), contains('session has expired'));
      expect(
        t(const ApiException(500, 'db exploded at https://api.hrtoffy.in')),
        fb,
      );
      expect(
        t(const ApiException(403, 'You cannot approve your own loan')),
        contains('own request'),
      );
      expect(
        t(const ApiException(403, 'x', code: 'SELF_APPROVAL')),
        contains('own request'),
      );
      expect(
        t(const ApiException(403, 'nope', code: 'NOT_ALLOWED')),
        contains("can't decide this request"),
      );
      expect(
        t(const ApiException(403, 'nope')),
        contains("can't decide this request"),
      );
      expect(
        t(const ApiException(404, 'Loan not found')),
        contains('no longer available'),
      );
      expect(
        t(
          const ApiException(
            400,
            "Cannot approve a loan with status 'approved'",
          ),
        ),
        contains('already been decided'),
      );
      expect(
        t(const ApiException(400, 'x', code: 'NOT_PENDING')),
        contains('already been decided'),
      );
      expect(
        t(const ApiException(400, 'x', code: 'AMOUNT_ABOVE_CLAIM')),
        contains("amount can't be approved"),
      );
      expect(t(const ApiException(418, 'teapot')), fb);
      expect(approvalErrorText(StateError('boom at /x'), fallback: fb), fb);
    });

    test('never repeats the server text', () {
      for (final code in [400, 403, 404, 409, 418, 500, 503]) {
        final text = t(
          ApiException(
            code,
            'secret-detail https://api.hrtoffy.in id 11111111-1111',
          ),
        );
        expect(text.contains('secret-detail'), isFalse, reason: '$code');
        expect(text.contains('hrtoffy'), isFalse, reason: '$code');
      }
    });
  });
}
