import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/tax_repository.dart';
import 'package:hrms_app/screens/tax_deduction_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _screen(TestSession s) => MaterialApp(
  home: TaxDeductionScreen(
    taxRepository: TaxRepository(auth: s.auth),
    employeeRepository: EmployeeRepository(auth: s.auth),
  ),
);

final _error = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);

/// [sensitive] / [meSalary] drive the two salary sources; [failing] is a set of paths that answer 500.
Future<TestSession> _session({
  Object? sensitive = const {'salary': '1200000.00'},
  Object? meSalary,
  String regime = 'new_regime',
  List<Map<String, dynamic>>? declarations,
  Object? config,
  Set<String> failing = const {},
  bool sensitiveMissing = false,
}) {
  return signedIn((req) async {
    final path = req.url.path;
    if (req.method != 'GET')
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    if (failing.contains(path)) return _error;
    switch (path) {
      case '$_org/employees/me':
        return ok({
          'id': testEmployeeId,
          'organizationId': testOrgId,
          'fullName': 'Asha Rao',
          'employeeId': 'EMP-001',
          'salary': meSalary,
        });
      case '$_org/payroll/me/sensitive-profile':
        return sensitiveMissing
            ? jsonResponse({
                'success': false,
                'error': {'message': 'not found'},
              }, 404)
            : ok(sensitive);
      case '$_org/payroll/tax-deduction-types':
        return ok([
          {
            'id': 't1',
            'code': '80C',
            'name': 'Savings 80C',
            'maxAmount': '150000.00',
            'appliesToRegime': ['old_regime'],
            'requiresProof': true,
            'isActive': true,
          },
        ]);
      case '$_org/payroll/tax-submission-window':
        return ok(null);
      case '$_org/payroll/income-tax-config':
        return ok(config);
      case '$_org/payroll/me/tax-regime':
        return ok({'regimeType': regime});
      case '$_org/payroll/me/tax-declarations':
        return ok(
          declarations ??
              [
                {
                  'id': 'd1',
                  'deductionTypeId': 't1',
                  'declaredAmount': '90000.00',
                  'isClaimed': true,
                  'employeeNotes': 'PPF',
                  'status': 'draft',
                },
              ],
        );
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  });
}

void main() {
  testWidgets(
    'loads every read from the AWS API with the financial year, and never touches Supabase',
    (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final calls = s.requests.map((r) => '${r.method} ${r.path}').toSet();
      expect(
        calls,
        containsAll([
          'GET $_org/employees/me',
          'GET $_org/payroll/tax-deduction-types',
          'GET $_org/payroll/tax-submission-window',
          'GET $_org/payroll/income-tax-config',
          'GET $_org/payroll/me/tax-regime',
          'GET $_org/payroll/me/tax-declarations',
        ]),
      );
      for (final p in [
        'tax-submission-window',
        'income-tax-config',
        'me/tax-regime',
        'me/tax-declarations',
      ]) {
        final q = s.requests
            .firstWhere((r) => r.path.endsWith('/payroll/$p'))
            .query;
        expect(q.keys, ['financialYear'], reason: p);
        expect(q['financialYear'], matches(r'^\d{4}-\d{2}$'), reason: '$p must use the canonical YYYY-YY year');
      }
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('EMP-001'), findsOneWidget);
      // salary arrived as the decimal string "1200000.00"
      expect(find.text('₹12,00,000'), findsNWidgets(2));
      expect(find.text('Not available'), findsNothing);
    },
  );

  testWidgets(
    'empty / null responses render with the built-in defaults and no error',
    (tester) async {
      _tall(tester);
      final s = await _session(declarations: [], config: null);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('New Regime'), findsWidgets);
    },
  );

  testWidgets(
    'decimal strings in the tax config are used by the (unchanged) formula',
    (tester) async {
      _tall(tester);
      // new regime: salary 1,200,000 - std deduction 75,000 = 1,125,000 taxable
      final s = await _session(
        config: {
          'standardDeductionNewRegime': '75000.00',
          'rebateLimitNewRegime': '700000.00',
          'cessRate': '4.00',
          'newRegimeSlabs': [
            {'minIncome': '0', 'maxIncome': '400000', 'rate': '0'},
            {'minIncome': '400001', 'maxIncome': '800000', 'rate': '5'},
            {'minIncome': '800001', 'maxIncome': '1200000', 'rate': '10'},
          ],
        },
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('₹11,25,000'), findsOneWidget); // taxable income
      expect(find.text('₹12,00,000'), findsNWidgets(2));
    },
  );

  group('salary safety', () {
    testWidgets(
      'zero salary from every source is "Not available", never a ₹0 tax result',
      (tester) async {
        _tall(tester);
        final s = await _session(sensitive: {'salary': '0.00'}, meSalary: 0);
        await tester.pumpWidget(_screen(s));
        await _settle(tester);

        expect(
          find.text('Not available'),
          findsNWidgets(6),
        ); // gross x2, taxable, annual tax, monthly TDS x2 (header + summary)
        expect(find.text('₹0'), findsNothing);
        expect(find.textContaining('cannot be calculated'), findsOneWidget);
        expect(find.textContaining("Couldn't load"), findsNothing);
      },
    );

    testWidgets(
      'missing salary (null everywhere, sensitive-profile absent on the server) is "Not available"',
      (tester) async {
        _tall(tester);
        final s = await _session(
          sensitive: {'salary': null},
          meSalary: null,
          sensitiveMissing: true,
        );
        await tester.pumpWidget(_screen(s));
        await _settle(tester);
        expect(find.text('Not available'), findsNWidgets(6));
        expect(find.text('₹0'), findsNothing);
      },
    );

    testWidgets('an encrypted / non-numeric placeholder is "Not available"', (
      tester,
    ) async {
      _tall(tester);
      final s = await _session(
        sensitive: {'salary': null},
        meSalary: 'gAAAAABencrypted==',
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('Not available'), findsNWidgets(6));
      expect(find.text('₹0'), findsNothing);
    });

    testWidgets(
      'a failed sensitive-profile falls back to the employee record salary',
      (tester) async {
        _tall(tester);
        final s = await _session(
          meSalary: '900000.00',
          failing: {'$_org/payroll/me/sensitive-profile'},
        );
        await tester.pumpWidget(_screen(s));
        await _settle(tester);
        expect(find.text('₹9,00,000'), findsNWidgets(2));
        expect(find.text('Not available'), findsNothing);
      },
    );
  });

  group('errors show a safe message, never the server text', () {
    for (final path in [
      'employees/me',
      'payroll/tax-deduction-types',
      'payroll/tax-submission-window',
      'payroll/income-tax-config',
      'payroll/me/tax-regime',
      'payroll/me/tax-declarations',
    ]) {
      testWidgets('GET $path fails', (tester) async {
        _tall(tester);
        final s = await _session(failing: {'$_org/$path'});
        await tester.pumpWidget(_screen(s));
        await _settle(tester);
        expect(
          find.text(
            "Couldn't load your tax information. Pull down to try again.",
          ),
          findsOneWidget,
        );
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(s.requests.every((r) => r.method == 'GET'), isTrue);
      });
    }

    testWidgets('a 403 says so without server text', (tester) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'secret detail'},
        }, 403),
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text('You do not have permission to view this information.'),
        findsOneWidget,
      );
      expect(find.textContaining('secret'), findsNothing);
    });
  });

  group(
    'writes: regime and draft saves only; submitting for review stays unavailable',
    () {
      Future<TestSession> writable(List<Map<String, dynamic>> puts) =>
          signedIn((req) async {
            final path = req.url.path;
            if (req.method == 'PUT') {
              puts.add({'path': path, 'body': req.body});
              return ok({'id': 'row1'});
            }
            switch (path) {
              case '$_org/employees/me':
                return ok({
                  'id': testEmployeeId,
                  'organizationId': testOrgId,
                  'fullName': 'Asha Rao',
                  'employeeId': 'EMP-001',
                  'salary': null,
                });
              case '$_org/payroll/me/sensitive-profile':
                return ok({'salary': '1200000.00'});
              case '$_org/payroll/tax-deduction-types':
                return ok([
                  {
                    'id': 't1',
                    'code': '80C',
                    'name': 'Savings 80C',
                    'maxAmount': '150000.00',
                    'appliesToRegime': ['old_regime'],
                    'requiresProof': true,
                    'isActive': true,
                  },
                ]);
              case '$_org/payroll/me/tax-regime':
                return ok({'regime_type': 'old_regime'});
              case '$_org/payroll/me/tax-declarations':
                return ok([]);
            }
            return ok(null);
          });

      testWidgets(
        'Submit Declarations for Review explains it is unavailable and sends nothing',
        (tester) async {
          _tall(tester);
          final puts = <Map<String, dynamic>>[];
          final s = await writable(puts);
          await tester.pumpWidget(_screen(s));
          await _settle(tester);
          await tester.tap(find.text('Submit Declarations for Review'));
          await tester.pump();
          expect(
            find.textContaining(
              "Submitting declarations for review isn't available yet",
            ),
            findsOneWidget,
          );
          expect(puts, isEmpty);
        },
      );

      testWidgets(
        'choosing the new regime and confirming PUTs only the session employee, the year and the regime',
        (tester) async {
          _tall(tester);
          final puts = <Map<String, dynamic>>[];
          final s = await writable(puts);
          await tester.pumpWidget(_screen(s));
          await _settle(tester);
          await tester.tap(find.text('New Regime').last);
          await tester.pump();
          await tester.tap(find.text('Update Confirmed Regime'));
          await _settle(tester);
          expect(puts, hasLength(1));
          expect(puts.single['path'], '$_org/payroll/tax-regime-selections');
          final body = jsonDecode(puts.single['body'] as String) as Map;
          expect(body['employeeId'], testEmployeeId);
          expect(body['regime_type'], 'new_regime');
          expect(body.keys.toSet(), {
            'employeeId',
            'financialYear',
            'regime_type',
            'selected_at',
          });
          expect(
            DateTime.tryParse(body['selected_at'] as String)?.isUtc,
            isTrue,
          );
        },
      );
    },
  );
}
