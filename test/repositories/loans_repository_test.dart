import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/loans_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _loan(
  String id, {
  Object? requested = '50000.00',
  Object? approved,
  Object? emi,
  Object? tenure = 12,
  String status = 'pending',
  String created = '2026-10-01T09:00:00.000Z',
  Object? number = 'LOAN-202610-00001',
  bool encrypted = false,
}) => {
  'id': id,
  'loan_number': number,
  'employee_id': testEmployeeId,
  'loan_category': 'personal_loan',
  'purpose': 'Home repairs',
  'requested_amount': requested,
  'approved_amount': approved,
  'emi_amount': emi,
  'tenure_months': tenure,
  'status': status,
  'is_encrypted': encrypted,
  'created_at': created,
};

Map<String, dynamic> _emi(
  String id, {
  String due = '2026-11-05T00:00:00.000Z',
  Object? emi = '4166.67',
  Object? outstanding = '45833.33',
  String status = 'pending',
}) => {
  'id': id,
  'loan_id': 'l1',
  'employee_id': testEmployeeId,
  'emi_number': 1,
  'due_date': due,
  'principal_amount': '4166.67',
  'interest_amount': '0.00',
  'emi_amount': emi,
  'outstanding_principal': outstanding,
  'status': status,
  'paid_amount': '0.00',
  'loans_advances': {
    'loan_number': 'LOAN-202610-00001',
    'loan_category': 'personal_loan',
  },
};

void main() {
  group('loans()', () {
    test(
      'GET /loans?employeeId=<own>, reads data.items; amounts become numbers, tenure an int; newest first',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _loan(
                'old',
                created: '2026-08-01T00:00:00.000Z',
                requested: '10000.00',
                tenure: '6',
              ),
              _loan(
                'new',
                requested: '50000.00',
                approved: '45000.50',
                emi: '3750.04',
              ),
            ],
            'total': 2,
          }),
        );
        final rows = await LoansRepository(auth: s.auth).loans();
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/loans');
        expect(s.last.query, {'employeeId': testEmployeeId});
        expect(s.last.headers['Authorization'], 'Bearer acc');

        expect(rows.map((r) => r['id']), ['new', 'old']);
        expect(rows.first['requested_amount'], 50000);
        expect(rows.first['approved_amount'], 45000.5);
        expect(rows.first['emi_amount'], 3750.04);
        expect(rows.first['loan_number'], 'LOAN-202610-00001');
        expect(rows.last['tenure_months'], 6);
        expect(rows.last['tenure_months'], isA<int>());
      },
    );

    test(
      'missing, null and non-numeric amounts do not crash and become null',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _loan(
                'a',
                requested: null,
                approved: 'n/a',
                emi: '',
                tenure: null,
                number: null,
              ),
              _loan('b', requested: 0, encrypted: true),
            ],
            'total': 2,
          }),
        );
        final rows = await LoansRepository(auth: s.auth).loans();
        final a = rows.firstWhere((r) => r['id'] == 'a');
        expect(a['requested_amount'], isNull);
        expect(a['approved_amount'], isNull);
        expect(a['emi_amount'], isNull);
        expect(a['tenure_months'], isNull);
        expect(a['loan_number'], isNull);
        // a zero stays a number: deciding that it is not usable is the UI's job (isUsableAmount)
        expect(rows.firstWhere((r) => r['id'] == 'b')['requested_amount'], 0);
      },
    );

    test('an {items} body, a bare list and an empty result', () async {
      final bare = await signedIn((req) async => ok([_loan('x')]));
      expect(
        (await LoansRepository(auth: bare.auth).loans()).single['id'],
        'x',
      );
      final empty = await signedIn(
        (req) async => ok({'items': [], 'total': 0}),
      );
      expect(await LoansRepository(auth: empty.auth).loans(), isEmpty);
    });

    test('API errors surface as ApiException', () async {
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'db exploded'},
        }, 500),
      );
      await expectLater(
        LoansRepository(auth: f.auth).loans(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isServerError,
            'server error',
            true,
          ),
        ),
      );
      final n = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'Organization membership not found'},
        }, 404),
      );
      await expectLater(
        LoansRepository(auth: n.auth).loans(),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'not found', true),
        ),
      );
    });
  });

  group('emiSchedule()', () {
    test(
      'GET /loans/emi-schedule?employeeId=<own>; amounts numbers, due_date yyyy-MM-dd, sorted by due date',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _emi('later', due: '2026-12-05T00:00:00.000Z'),
            _emi('sooner', due: '2026-11-05T00:00:00.000Z'),
          ]),
        );
        final rows = await LoansRepository(auth: s.auth).emiSchedule();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/loans/emi-schedule');
        expect(s.last.query, {'employeeId': testEmployeeId});
        expect(rows.map((r) => r['id']), ['sooner', 'later']);
        expect(rows.first['due_date'], '2026-11-05');
        expect(rows.first['emi_amount'], 4166.67);
        expect(rows.first['outstanding_principal'], 45833.33);
        expect(rows.first['paid_amount'], 0);
        expect(
          (rows.first['loans_advances'] as Map)['loan_number'],
          'LOAN-202610-00001',
        );
      },
    );

    test(
      'null or non-numeric amounts become null; empty and error cases',
      () async {
        final s = await signedIn(
          (req) async => ok([_emi('a', emi: null, outstanding: 'x')]),
        );
        final r = (await LoansRepository(auth: s.auth).emiSchedule()).single;
        expect(r['emi_amount'], isNull);
        expect(r['outstanding_principal'], isNull);
        final e = await signedIn((req) async => ok([]));
        expect(await LoansRepository(auth: e.auth).emiSchedule(), isEmpty);
        final f = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'no'},
          }, 403),
        );
        await expectLater(
          LoansRepository(auth: f.auth).emiSchedule(),
          throwsA(
            isA<ApiException>().having((x) => x.isForbidden, 'forbidden', true),
          ),
        );
      },
    );
  });

  group('loanMaxAmount()', () {
    test(
      'GET /grade-structures/limits/:gradeCode -> loanMaxAmount as a number; encoded code; null cases',
      () async {
        final s = await signedIn(
          (req) async => ok({'gradeCode': 'G 3', 'loanMaxAmount': '200000.00'}),
        );
        expect(
          await LoansRepository(auth: s.auth).loanMaxAmount('G 3'),
          200000,
        );
        expect(s.last.path, '$_org/grade-structures/limits/G%203');
        final none = await signedIn((req) async => ok(null));
        expect(
          await LoansRepository(auth: none.auth).loanMaxAmount('G9'),
          isNull,
        );
        final nolimit = await signedIn(
          (req) async => ok({'gradeCode': 'G1', 'loanMaxAmount': null}),
        );
        expect(
          await LoansRepository(auth: nolimit.auth).loanMaxAmount('G1'),
          isNull,
        );
      },
    );
  });

  group('amount safety helpers', () {
    test('isUsableAmount: only a real number above zero', () {
      expect(LoansRepository.isUsableAmount(50000), isTrue);
      expect(LoansRepository.isUsableAmount(0.5), isTrue);
      expect(LoansRepository.isUsableAmount(0), isFalse);
      expect(LoansRepository.isUsableAmount(-5), isFalse);
      expect(LoansRepository.isUsableAmount(null), isFalse);
    });

    test(
      'usedAgainstLimit counts active, approved and pending loans and flags unusable amounts',
      () {
        final r = LoansRepository.usedAgainstLimit([
          {'status': 'approved', 'requested_amount': 1000},
          {'status': 'PENDING', 'requested_amount': 500},
          {'status': 'rejected', 'requested_amount': 9999},
          {'status': 'closed', 'requested_amount': 8888},
        ]);
        expect(r.total, 1500);
        expect(r.incomplete, isFalse);

        final bad = LoansRepository.usedAgainstLimit([
          {'status': 'active', 'requested_amount': 0},
          {'status': 'approved', 'requested_amount': 700},
          {'status': 'pending', 'requested_amount': null},
        ]);
        expect(bad.total, 700);
        expect(bad.incomplete, isTrue);
      },
    );
  });

  group('requestLoan()', () {
    test(
      'POSTs only the verified fields, with the session employee, and returns the loanId',
      () async {
        final s = await signedIn(
          (req) async =>
              ok({'loanId': 'L1', 'message': 'Loan request created'}, 201),
        );
        final id = await LoansRepository(
          auth: s.auth,
        ).requestLoan(amount: 1500.5, reason: '  Fees ', repaymentMonths: 6);
        expect(id, 'L1');
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/loans/request');
        expect(s.last.json, {
          'employeeId': testEmployeeId,
          'amount': 1500.5,
          'reason': 'Fees',
          'repaymentMonths': 6,
        });
      },
    );

    test(
      'leaves repaymentMonths out when not given; a response without a loanId is an error',
      () async {
        final s = await signedIn((req) async => ok({'message': 'x'}, 201));
        await expectLater(
          LoansRepository(auth: s.auth).requestLoan(amount: 10, reason: 'r'),
          throwsA(isA<ApiException>()),
        );
        expect((s.last.json as Map).containsKey('repaymentMonths'), isFalse);
      },
    );
  });
}
