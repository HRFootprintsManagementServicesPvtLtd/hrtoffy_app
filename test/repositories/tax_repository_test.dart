import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/tax_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _fy = '2026-2027';

void main() {
  group('TaxRepository reads', () {
    test('employee: GET /employees/me, camelCase -> snake_case', () async {
      final s = await signedIn(
        (req) async => ok({
          'id': testEmployeeId,
          'fullName': 'Asha Rao',
          'employeeId': 'EMP-1',
        }),
      );
      final e = await TaxRepository(auth: s.auth).employee();
      expect(s.last.method, 'GET');
      expect(s.last.path, '$_org/employees/me');
      expect(s.last.headers['Authorization'], 'Bearer acc');
      expect(e['full_name'], 'Asha Rao');
      expect(e['employee_id'], 'EMP-1');
    });

    test(
      'deductionTypes: GET, decimal strings -> numbers, inactive dropped, ordered by code',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 't2',
              'code': '80D',
              'name': 'Health',
              'maxAmount': '25000.00',
              'appliesToRegime': ['old_regime'],
              'isActive': true,
            },
            {
              'id': 't1',
              'code': '80C',
              'name': 'Savings',
              'maxAmount': '150000.00',
              'appliesToRegime': ['old_regime'],
              'isActive': true,
            },
            {
              'id': 't3',
              'code': '80Z',
              'name': 'Old',
              'maxAmount': 1,
              'isActive': false,
            },
          ]),
        );
        final rows = await TaxRepository(auth: s.auth).deductionTypes();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/payroll/tax-deduction-types');
        expect(s.last.query, isEmpty);
        expect(rows.map((r) => r['id']), ['t1', 't2']);
        expect(rows.first['max_amount'], 150000);
        expect(rows.first['applies_to_regime'], ['old_regime']);
      },
    );

    test(
      'deductionTypes: {items: []}, null and empty list give an empty list',
      () async {
        for (final body in <Object?>[
          {'items': []},
          null,
          [],
          {},
        ]) {
          final s = await signedIn((req) async => ok(body));
          expect(await TaxRepository(auth: s.auth).deductionTypes(), isEmpty);
        }
      },
    );

    test(
      'submissionWindow: GET with financialYear; null/empty -> null',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'declarationStartDate': '2026-04-01T00:00:00.000Z',
            'declarationEndDate': '2027-01-31T00:00:00.000Z',
          }),
        );
        final w = await TaxRepository(auth: s.auth).submissionWindow(_fy);
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/payroll/tax-submission-window');
        expect(s.last.query, {'financialYear': '2026-27'}); // the legacy YYYY-YYYY input goes out canonical
        expect(w!['declaration_start_date'], '2026-04-01T00:00:00.000Z');

        for (final body in <Object?>[null, {}, []]) {
          final e = await signedIn((req) async => ok(body));
          expect(
            await TaxRepository(auth: e.auth).submissionWindow(_fy),
            isNull,
          );
        }
      },
    );

    test(
      'incomeTaxConfig: GET with financialYear; decimal strings (also inside slabs) -> numbers',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'standardDeductionOldRegime': '50000.00',
            'standardDeductionNewRegime': '75000.00',
            'rebateLimitOldRegime': '500000',
            'rebateLimitNewRegime': '700000',
            'cessRate': '4.00',
            'oldRegimeSlabs': [
              {'minIncome': '0', 'maxIncome': '250000', 'rate': '0'},
              {'minIncome': '1000001', 'maxIncome': null, 'rate': '30.5'},
            ],
            'newRegimeSlabs': [],
          }),
        );
        final c = await TaxRepository(auth: s.auth).incomeTaxConfig(_fy);
        expect(s.last.path, '$_org/payroll/income-tax-config');
        expect(s.last.query, {'financialYear': '2026-27'}); // the legacy YYYY-YYYY input goes out canonical
        expect(c!['standard_deduction_new_regime'], 75000);
        expect(c['cess_rate'], 4);
        final slabs = c['old_regime_slabs'] as List;
        expect(slabs[0], {'min_income': 0, 'max_income': 250000, 'rate': 0});
        expect(slabs[1]['max_income'], isNull);
        expect(slabs[1]['rate'], 30.5);
        expect(c['new_regime_slabs'], isEmpty);
      },
    );

    test('incomeTaxConfig: null / empty -> null', () async {
      for (final body in <Object?>[null, {}]) {
        final s = await signedIn((req) async => ok(body));
        expect(await TaxRepository(auth: s.auth).incomeTaxConfig(_fy), isNull);
      }
    });

    test(
      'taxRegime: token-derived GET /payroll/me/tax-regime with financialYear (no employee id sent)',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'regimeType': 'old_regime',
            'annualTaxLiability': '120000.50',
            'monthlyTds': '10000.04',
          }),
        );
        final r = await TaxRepository(auth: s.auth).taxRegime(_fy);
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/payroll/me/tax-regime');
        expect(s.last.query, {'financialYear': '2026-27'}); // the legacy YYYY-YYYY input goes out canonical
        expect(r!['regime_type'], 'old_regime');
        expect(r['annual_tax_liability'], 120000.5);
        expect(r['monthly_tds'], 10000.04);
      },
    );

    test(
      'taxRegime: a one-element list is unwrapped; null / [] -> null',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {'regimeType': 'new_regime'},
          ]),
        );
        expect(
          (await TaxRepository(auth: s.auth).taxRegime(_fy))!['regime_type'],
          'new_regime',
        );
        for (final body in <Object?>[null, [], {}]) {
          final e = await signedIn((req) async => ok(body));
          expect(await TaxRepository(auth: e.auth).taxRegime(_fy), isNull);
        }
      },
    );

    test(
      'taxDeclarations: token-derived GET with financialYear; amounts -> numbers; empty -> []',
      () async {
        final s = await signedIn(
          (req) async => ok([
            {
              'id': 'd1',
              'deductionTypeId': 't1',
              'declaredAmount': '90000.00',
              'isClaimed': true,
              'status': 'draft',
            },
          ]),
        );
        final rows = await TaxRepository(auth: s.auth).taxDeclarations(_fy);
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/payroll/me/tax-declarations');
        expect(s.last.query, {'financialYear': '2026-27'}); // the legacy YYYY-YYYY input goes out canonical
        expect(rows.single['deduction_type_id'], 't1');
        expect(rows.single['declared_amount'], 90000);

        for (final body in <Object?>[
          null,
          [],
          {'items': []},
        ]) {
          final e = await signedIn((req) async => ok(body));
          expect(
            await TaxRepository(auth: e.auth).taxDeclarations(_fy),
            isEmpty,
          );
        }
      },
    );

    test(
      'API errors surface as typed ApiException (403, 500, network)',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'code': 'FORBIDDEN', 'message': 'nope'},
          }, 403),
        );
        await expectLater(
          TaxRepository(auth: s.auth).taxRegime(_fy),
          throwsA(
            isA<ApiException>().having((e) => e.isForbidden, '403', true),
          ),
        );
        final e = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'boom'},
          }, 500),
        );
        await expectLater(
          TaxRepository(auth: e.auth).taxDeclarations(_fy),
          throwsA(
            isA<ApiException>().having((x) => x.isServerError, '5xx', true),
          ),
        );
      },
    );
  });

  group('usableSalary', () {
    test('accepts positive numbers and decimal strings', () {
      expect(TaxRepository.usableSalary(1200000), 1200000);
      expect(TaxRepository.usableSalary('1200000.50'), 1200000.5);
    });

    test(
      'null, zero, negative, blank, non-numeric and non-finite are unavailable',
      () {
        for (final v in <Object?>[
          null,
          0,
          0.0,
          '0',
          '0.00',
          -5,
          '',
          '  ',
          'gAAAAABencrypted==',
          'NaN',
          double.infinity,
        ]) {
          expect(TaxRepository.usableSalary(v), isNull, reason: '$v');
        }
      },
    );
  });
}
