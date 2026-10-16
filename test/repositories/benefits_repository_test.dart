import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _claim(
  String id, {
  String date = '2026-10-05T00:00:00.000Z',
  String created = '2026-10-05T09:00:00.000Z',
  Object? claimed = '1250.00',
  Object? approved,
  String status = 'pending',
  Object? year = 2026,
  Object? month = 10,
}) => {
  'id': id,
  'employee_id': testEmployeeId,
  'benefit_id': 'b1',
  'description': 'Glasses',
  'claim_date': date,
  'claim_month': month,
  'claim_year': year,
  'claimed_amount': claimed,
  'approved_amount': approved,
  'status': status,
  'payment_mode': 'payroll',
  'created_at': created,
  'benefits_catalog': {'benefit_name': 'Medical', 'benefit_type': 'health'},
};

void main() {
  group('claims()', () {
    test(
      'GET /benefits/claims?employeeId=<own>, reads data.items; decimals become numbers, dates yyyy-MM-dd',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [_claim('c1', claimed: '1250.00', approved: '1000.50')],
            'total': 1,
          }),
        );
        final rows = await BenefitsRepository(auth: s.auth).claims();
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/benefits/claims');
        expect(s.last.query, {'employeeId': testEmployeeId});
        expect(s.last.headers['Authorization'], 'Bearer acc');

        final c = rows.single;
        expect(
          c['claimed_amount'],
          1250,
        ); // "1250.00" -> 1250 (whole amounts have no ".0")
        expect(c['claimed_amount'], isA<int>());
        expect(c['approved_amount'], 1000.5);
        expect(c['claim_date'], '2026-10-05');
        expect(c['claim_month'], 10);
        expect(c['claim_year'], 2026);
        expect(c['status'], 'pending');
        expect((c['benefits_catalog'] as Map)['benefit_name'], 'Medical');
      },
    );

    test(
      'no approved amount stays null; claims are sorted newest claim_date first, then newest created_at',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _claim('old', date: '2026-08-01T00:00:00.000Z'),
              _claim(
                'new-a',
                date: '2026-10-05T00:00:00.000Z',
                created: '2026-10-05T08:00:00.000Z',
              ),
              _claim(
                'new-b',
                date: '2026-10-05T00:00:00.000Z',
                created: '2026-10-05T11:00:00.000Z',
              ),
            ],
            'total': 3,
          }),
        );
        final rows = await BenefitsRepository(auth: s.auth).claims();
        expect(rows.map((r) => r['id']), ['new-b', 'new-a', 'old']);
        expect(rows.first['approved_amount'], isNull);
      },
    );

    test(
      'a claim created before the backend fix (no month, year or date) does not break parsing',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _claim(
                'legacy',
                year: null,
                month: null,
                date: '2026-09-30T00:00:00.000Z',
              ),
            ],
            'total': 1,
          }),
        );
        final c = (await BenefitsRepository(auth: s.auth).claims()).single;
        expect(c['claim_year'], isNull);
        expect(c['claim_month'], isNull);
      },
    );

    test('empty result', () async {
      final s = await signedIn((req) async => ok({'items': [], 'total': 0}));
      expect(await BenefitsRepository(auth: s.auth).claims(), isEmpty);
    });

    test('API errors surface as ApiException', () async {
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'db exploded'},
        }, 500),
      );
      await expectLater(
        BenefitsRepository(auth: f.auth).claims(),
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
        BenefitsRepository(auth: n.auth).claims(),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'not found', true),
        ),
      );
    });
  });

  group('catalog()', () {
    test('GET /benefits/catalog', () async {
      final s = await signedIn(
        (req) async => ok([
          {
            'id': 'b1',
            'benefit_name': 'Medical',
            'benefit_type': 'health',
            'is_active': true,
          },
          {
            'id': 'b2',
            'benefit_name': 'Meal',
            'benefit_type': 'allowance',
            'is_active': true,
          },
        ]),
      );
      final list = await BenefitsRepository(auth: s.auth).catalog();
      expect(s.last.method, 'GET');
      expect(s.last.path, '$_org/benefits/catalog');
      expect(s.last.query, isEmpty);
      expect(list.map((b) => b['benefit_name']), ['Medical', 'Meal']);
      expect(list.first['id'], 'b1');
    });

    test('empty catalog and errors', () async {
      final s = await signedIn((req) async => ok([]));
      expect(await BenefitsRepository(auth: s.auth).catalog(), isEmpty);
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'no'},
        }, 403),
      );
      await expectLater(
        BenefitsRepository(auth: f.auth).catalog(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('gradeLimit()', () {
    test(
      'GET /grade-structures/limits/:gradeCode; keys snake_cased, amounts are numbers',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'gradeCode': 'G3',
            'gradeName': 'Senior',
            'benefitAnnualLimit': 50000,
            'loanMaxAmount': '200000.00',
            'travelPerTripLimit': null,
          }),
        );
        final g = await BenefitsRepository(auth: s.auth).gradeLimit('G3');
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/grade-structures/limits/G3');
        expect(g!['benefit_annual_limit'], 50000);
        expect(g['loan_max_amount'], 200000);
        expect(g['travel_per_trip_limit'], isNull);
        expect(g['grade_name'], 'Senior');
      },
    );

    test('the grade code is URL-encoded', () async {
      final s = await signedIn(
        (req) async => ok({'gradeCode': 'L 1/2', 'benefitAnnualLimit': 1}),
      );
      await BenefitsRepository(auth: s.auth).gradeLimit('L 1/2');
      expect(s.last.path, '$_org/grade-structures/limits/L%201%2F2');
    });

    test('no grade row (data: null) gives null', () async {
      final s = await signedIn((req) async => ok(null));
      expect(await BenefitsRepository(auth: s.auth).gradeLimit('G9'), isNull);
    });

    test('errors surface as ApiException', () async {
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'x'},
        }, 500),
      );
      await expectLater(
        BenefitsRepository(auth: f.auth).gradeLimit('G1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('claimedTotalForYear', () {
    test(
      'sums approved (else claimed) amounts of this year, skipping rejected claims and claims without a year',
      () {
        final claims = [
          {
            'claim_year': 2026,
            'status': 'approved',
            'approved_amount': 800,
            'claimed_amount': 1000,
          },
          {
            'claim_year': 2026,
            'status': 'pending',
            'approved_amount': null,
            'claimed_amount': 500,
          },
          {
            'claim_year': 2026,
            'status': 'rejected',
            'approved_amount': null,
            'claimed_amount': 9999,
          },
          {
            'claim_year': 2025,
            'status': 'approved',
            'approved_amount': 700,
            'claimed_amount': 700,
          },
          {
            'claim_year': null,
            'status': 'pending',
            'approved_amount': null,
            'claimed_amount': 123,
          },
        ];
        expect(BenefitsRepository.claimedTotalForYear(claims, 2026), 1300);
        expect(BenefitsRepository.claimedTotalForYear(claims, 2024), 0);
        expect(BenefitsRepository.claimedTotalForYear(const [], 2026), 0);
      },
    );
  });
}
