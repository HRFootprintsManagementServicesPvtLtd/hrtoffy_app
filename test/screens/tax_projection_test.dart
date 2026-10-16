import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/tax_repository.dart';
import 'package:hrms_app/screens/tax_deduction_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _projectionPath = '$_org/payroll/calc/tds/projection';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _screen(TestSession s) => MaterialApp(
      home: TaxDeductionScreen(
        taxRepository: TaxRepository(auth: s.auth),
        employeeRepository: EmployeeRepository(auth: s.auth),
      ),
    );

Map<String, dynamic> _regime({
  required String income,
  required String taxable,
  required String tax,
  required String monthly,
  required String std,
  List<Map<String, dynamic>> deductions = const [],
}) =>
    {
      'regime': 'x',
      'projectedAnnualIncome': income,
      'taxableIncome': taxable,
      'annualTax': tax,
      'monthlyTds': monthly,
      'standardDeduction': std,
      'deductions': deductions,
    };

Map<String, dynamic> _projection({
  bool applicable = true,
  String? reason,
  bool unverified = false,
  String recommended = 'new',
}) =>
    {
      'applicable': applicable,
      'reason': reason,
      'selectedRegime': 'new',
      'regimes': applicable
          ? {
              'new': _regime(income: '1622467.00', taxable: '1547467.00', tax: '112121.00', monthly: '15054.00', std: '75000.00'),
              'old': _regime(income: '1622467.00', taxable: '1525267.00', tax: '270081.00', monthly: '41380.00', std: '50000.00', deductions: [
                {'section': '80G', 'declared': '20000.00', 'allowed': '20000.00', 'disallowed': '0.00', 'cap': null},
                {'section': '80D', 'declared': '2200.00', 'allowed': '2200.00', 'disallowed': '0.00', 'cap': null},
              ]),
            }
          : {'old': null, 'new': null},
      'recommendedRegime': recommended,
      'annualSaving': '157960.00',
      'earnedToDate': [
        {'month': '2026-04', 'gross': '185408.00'},
        {'month': '2026-05', 'gross': '52708.00'},
      ],
      'tdsDeductedToDate': '93794.00',
      'warnings': <String>[],
      'usedUnverifiedRule': unverified,
    };

/// No salary anywhere (sensitive-profile 404, `salary` null on the employee) so ONLY the projection can supply figures.
Future<TestSession> _session({
  Object? projection,
  int? projectionStatus,
  List<Map<String, dynamic>>? puts,
  Object? sensitiveSalary,
}) {
  return signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'PUT') {
      puts?.add({'path': p, 'body': jsonDecode(req.body)});
      return ok({'regime_type': 'old_regime', 'financial_year': '2026-27'});
    }
    switch (p) {
      case '$_org/employees/me':
        return ok({'id': testEmployeeId, 'organizationId': testOrgId, 'fullName': 'Asha Rao', 'employeeId': 'EMP-001', 'salary': null});
      case '$_org/payroll/me/sensitive-profile':
        return sensitiveSalary == null ? jsonResponse({'success': false}, 404) : ok({'salary': sensitiveSalary});
      case '$_org/payroll/tax-deduction-types':
        return ok([
          {'id': 't1', 'code': '80C', 'name': 'Savings 80C', 'maxAmount': '150000.00', 'appliesToRegime': ['old_regime'], 'requiresProof': true, 'isActive': true},
        ]);
      case '$_org/payroll/tax-submission-window':
        return ok(null);
      case '$_org/payroll/income-tax-config':
        return ok(null);
      case '$_org/payroll/me/tax-regime':
        return ok({'regimeType': 'new_regime'});
      case '$_org/payroll/me/tax-declarations':
        return ok(<dynamic>[]);
      case _projectionPath:
        if (projectionStatus != null) {
          return jsonResponse({'success': false, 'error': {'message': 'server text that must not be shown'}}, projectionStatus);
        }
        return ok(projection ?? _projection());
    }
    return jsonResponse({'success': false}, 404);
  });
}

void main() {
  group('TaxRepository year key', () {
    test('canonicalFinancialYear turns the legacy YYYY-YYYY into YYYY-YY and leaves the canonical form alone', () {
      expect(TaxRepository.canonicalFinancialYear('2026-2027'), '2026-27');
      expect(TaxRepository.canonicalFinancialYear('2026-27'), '2026-27');
      expect(TaxRepository.canonicalFinancialYear(' 2025-2026 '), '2025-26');
      expect(TaxRepository.canonicalFinancialYear('FY2026'), 'FY2026');
    });

    test('projection asks for the caller\'s own employee id and the canonical year, and parses decimal strings', () async {
      final s = await _session();
      final p = await TaxRepository(auth: s.auth).projection('2026-2027');
      final r = s.requests.single;
      expect(r.method, 'GET');
      expect(r.path, _projectionPath);
      expect(r.query, {'employeeId': testEmployeeId, 'financialYear': '2026-27'});
      expect(p!.applicable, isTrue);
      expect(p.newRegime!.annualTax, 112121.0);
      expect(p.oldRegime!.allowedDeductions, 22200.0);
      expect(p.earnedToDate.length, 2);
      expect(p.tdsDeductedToDate, 93794.0);
      expect(p.recommendedRegime, 'new');
    });
  });

  group('Tax screen with the server projection', () {
    testWidgets('shows the server figures when no salary can be read, and never says the salary is unavailable', (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final asked = s.requests.where((r) => r.path == _projectionPath).single;
      expect(asked.query['financialYear'], matches(r'^\d{4}-\d{2}$'));
      expect(asked.query['employeeId'], testEmployeeId);

      expect(find.text('Projected Annual Income'), findsWidgets);
      expect(find.textContaining('16,22,467'), findsWidgets);
      expect(find.textContaining('15,47,467'), findsWidgets); // new-regime taxable income
      expect(find.textContaining('1,12,121'), findsWidgets); // annual tax
      expect(find.textContaining('15,054'), findsWidgets); // monthly TDS
      expect(find.text('Not available'), findsNothing);
      expect(find.textContaining('annual salary is not available'), findsNothing);
      expect(find.textContaining('Calculated by the payroll server'), findsOneWidget);
    });

    testWidgets('selecting the Old Regime switches to the server\'s own old-regime figures', (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      await tester.tap(find.text('Old Regime').first);
      await _settle(tester);
      expect(find.textContaining('15,25,267'), findsWidgets); // old-regime taxable income
      expect(find.textContaining('2,70,081'), findsWidgets);
      expect(find.textContaining('41,380'), findsWidgets);
    });

    testWidgets('paid months, TDS already deducted and the two-regime comparison with the recommendation are shown', (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(find.textContaining('Income counted for FY'), findsOneWidget);
      expect(find.text('Paid 2026-04'), findsOneWidget);
      expect(find.textContaining('1,85,408'), findsOneWidget);
      expect(find.text('TDS already deducted this year'), findsOneWidget);
      expect(find.text('Compare both regimes'), findsOneWidget);
      expect(find.textContaining('Lower estimated tax: New Regime'), findsOneWidget);
      expect(find.textContaining('1,57,960'), findsOneWidget);
    });

    testWidgets('a rule the server says is unverified is flagged as an estimate', (tester) async {
      _tall(tester);
      final s = await _session(projection: _projection(unverified: true));
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.textContaining('has not been verified'), findsOneWidget);
    });

    testWidgets('a route that is not there (404) falls back to the previous behavior: salary unavailable, no invented figures', (tester) async {
      _tall(tester);
      final s = await _session(projectionStatus: 404);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(find.textContaining('annual salary is not available'), findsOneWidget);
      expect(find.text('Not available'), findsWidgets);
      expect(find.textContaining('Income counted for FY'), findsNothing);
      expect(find.textContaining('server text'), findsNothing);
    });

    testWidgets('a server error on the projection does not break the screen', (tester) async {
      _tall(tester);
      final s = await _session(projectionStatus: 500);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('Tax Summary'), findsOneWidget);
      expect(find.textContaining('annual salary is not available'), findsOneWidget);
    });

    testWidgets('when the server does not compute TDS for the employee, its reason is shown and no figures are', (tester) async {
      _tall(tester);
      final s = await _session(projection: _projection(applicable: false, reason: 'the employee is exempted from TDS'));
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(find.textContaining('Tax is not calculated for you: the employee is exempted from TDS'), findsOneWidget);
      expect(find.textContaining('Income counted for FY'), findsNothing);
      expect(find.text('Compare both regimes'), findsNothing);
    });

    testWidgets('a salary from another source never produces a tax figure when the server says TDS does not apply', (tester) async {
      _tall(tester);
      final s = await _session(
        projection: _projection(applicable: false, reason: 'the employee is exempted from TDS'),
        sensitiveSalary: '1200000.00',
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(find.textContaining('Tax is not calculated for you'), findsOneWidget);
      expect(find.text('Not available'), findsWidgets);
      expect(find.textContaining('12,00,000'), findsNothing, reason: 'no figure derived from the other salary source');
    });

    testWidgets('confirming a regime saves under the canonical year and re-reads the projection', (tester) async {
      _tall(tester);
      final puts = <Map<String, dynamic>>[];
      final s = await _session(puts: puts);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      await tester.tap(find.text('Old Regime').first);
      await _settle(tester);
      await tester.ensureVisible(find.text('Update Confirmed Regime'));
      await tester.tap(find.text('Update Confirmed Regime'));
      await _settle(tester);

      expect(puts, hasLength(1));
      expect(puts.single['path'], '$_org/payroll/tax-regime-selections');
      expect(puts.single['body']['financialYear'], matches(r'^\d{4}-\d{2}$'));
      expect(puts.single['body']['regime_type'], 'old_regime');
      expect(s.requests.where((r) => r.path == _projectionPath).length, 2, reason: 'read once at start and again after the save');
    });
  });
}
