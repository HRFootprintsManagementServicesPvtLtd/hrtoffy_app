import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/compliance_repository.dart';
import 'package:hrms_app/screens/manager/manager_compliance_screen.dart';
import 'package:hrms_app/screens/manager/widgets/manager_state_views.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _emp1 = 'e0000000-0000-0000-0000-000000000001';
const _emp2 = 'e0000000-0000-0000-0000-000000000002';

Widget _screen(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: ManagerComplianceScreen(
      userEmail: 'm@x.com',
      userData: const {
        'id': 'e1',
        'organization_id': testOrgId,
        'emp_role': 'manager',
      },
      fetchHrmsContext: () async => {},
      complianceRepository: ComplianceRepository(auth: s.auth),
    ),
  ),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _tabs = [
  'Wage Registers',
  'Statutory Returns',
  'Factories Act',
  'Shops & Estb.',
  'Statutory Bonus',
  'Gratuity',
];
const _quickLinks = [
  'POSH',
  'Maternity',
  'CLRA',
  'Pay Equity',
  'Apprentices',
  'Auditor Pack',
];

final _forbidden = jsonResponse({
  'success': false,
  'error': {'message': 'Permission denied: compliance.view'},
}, 403);
final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);

class _Server {
  Object? health = {
    'org_id': 'o',
    'overall_score': 85,
    'snapshot_date': '2026-10-01',
  };
  Set<String> forbidden = {};
  Set<String> failing = {};
  bool namesFail = false;
}

Future<TestSession> _session(_Server srv) {
  return signedIn((req) async {
    final path = req.url.path;
    if (req.method != 'GET') {
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    }
    if (srv.forbidden.contains(path)) return _forbidden;
    if (srv.failing.contains(path)) return _boom;
    switch (path) {
      case '$_org/compliance/health':
        return ok(srv.health);
      case '$_org/employees/summaries':
        if (srv.namesFail) return _boom;
        return ok([
          {
            'id': _emp1,
            'employeeId': 'E001',
            'fullName': 'Asha Rao',
            'email': 'a@x.com',
          },
        ]);
      case '$_org/compliance/wage-register/fines':
        return ok([
          {
            'id': 'f1',
            'employee_id': _emp1,
            'offense_description': 'Late arrival',
            'fine_amount': '1500.00',
          },
          {
            'id': 'f2',
            'employee_id': _emp2,
            'offense_description': 'Safety breach',
            'fine_amount': null,
          },
        ]);
      case '$_org/compliance/wage-register/deductions':
        return ok([
          {
            'id': 'd1',
            'employee_id': _emp1,
            'damage_description': 'Broken screen',
            'deduction_amount': '2500',
          },
        ]);
      case '$_org/compliance/wage-register/advances':
        return ok([
          {
            'id': 'a1',
            'employee_id': _emp1,
            'purpose': 'Medical',
            'advance_amount': '12000',
          },
        ]);
      case '$_org/compliance/returns':
        return ok({
          'items': [
            {
              'id': 'r1',
              'return_type': 'PF ECR',
              'period_month': 9,
              'period_year': 2026,
              'due_date': '2026-10-15T00:00:00.000Z',
              'status': 'overdue',
              'challan_amount': '45000',
            },
          ],
          'total': 1,
          'page': 1,
          'limit': 200,
        });
      case '$_org/compliance/factory-accidents':
        return ok([
          {
            'id': 'x1',
            'injury_type': 'Burn',
            'accident_location': 'Plant 2',
            'status': 'open',
          },
        ]);
      case '$_org/compliance/shops-certs':
        return ok([
          {
            'id': 's1',
            'establishment_name': 'Head Office',
            'valid_until': '2030-01-01T00:00:00.000Z',
          },
          {'id': 's2', 'establishment_name': 'Old Branch', 'valid_until': null},
        ]);
      case '$_org/bonus-runs':
        return ok([
          {
            'id': 'b1',
            'accounting_year': '2025-26',
            'status': 'posted',
            'total_eligible_employees': 40,
            'total_payout_amount': '1234567.00',
            'bonus_pct_applied': '8.33',
          },
          {
            'id': 'b2',
            'accounting_year': '2024-25',
            'status': 'draft',
            'total_eligible_employees': null,
            'total_payout_amount': null,
            'bonus_pct_applied': null,
          },
        ]);
      case '$_org/gratuity/provisions':
        return ok([
          {
            'id': 'g1',
            'employee_id': _emp1,
            'eligible_service_years': '6.50',
            'provision_amount': '88000',
          },
        ]);
      case '$_org/posh/complaints':
        return ok({
          'items': [
            {
              'id': 'p1',
              'case_number': 'POSH-2026-0001',
              'status': 'open',
              'complainant_name': 'Secret Person',
            },
          ],
          'total': 1,
        });
      case '$_org/maternity/cases':
        return ok([
          {
            'id': 'm1',
            'employee_name': 'Neha Jain',
            'leave_type': 'maternity',
            'expected_delivery_date': '2026-12-01',
          },
        ]);
      case '$_org/locum/contractors':
        return ok({
          'items': [
            {'id': 'c1', 'name': 'ABC Contractors', 'license_number': 'LIC-77'},
          ],
          'total': 1,
        });
      case '$_org/compliance/apprentices':
        return ok([
          {'id': 'ap1', 'apprentice_name': 'Ravi', 'trade': 'Fitter'},
        ]);
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  }, empRole: 'hr_manager');
}

Future<(_Server, TestSession)> _open(
  WidgetTester tester, {
  void Function(_Server)? setup,
}) async {
  _tall(tester);
  final srv = _Server();
  setup?.call(srv);
  final s = await _session(srv);
  await tester.pumpWidget(_screen(s));
  await _settle(tester);
  return (srv, s);
}

List<String> _calls(TestSession s) =>
    s.requests.map((r) => '${r.method} ${r.path}').toList();

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await _settle(t);
}

void main() {
  testWidgets(
    'shows the score, the six tabs and six quick links; reads health only on open',
    (tester) async {
      final (_, s) = await _open(tester);
      expect(find.text('Compliance Health Score'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('Your organization is well-guarded'), findsOneWidget);
      for (final t in _tabs) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      for (final q in _quickLinks) {
        expect(find.text(q), findsOneWidget, reason: q);
      }
      // the first tab (wage registers, fines) loads with it
      expect(_calls(s).first, 'GET $_org/compliance/health');
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets('no snapshot yet: "-", never 0 or a verdict', (tester) async {
    await _open(
      tester,
      setup: (s) => s.health = {
        'org_id': 'o',
        'overall_score': null,
        'snapshot_date': null,
      },
    );
    expect(find.text('-'), findsWidgets);
    expect(find.text('No score recorded yet'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('well-guarded'), findsNothing);
    expect(find.textContaining('Action required'), findsNothing);
  });

  testWidgets('a low score asks for action', (tester) async {
    await _open(tester, setup: (s) => s.health = {'overall_score': 40});
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Action required to improve score'), findsOneWidget);
  });

  testWidgets('403 on health: ONE friendly state, no tabs, no other request', (
    tester,
  ) async {
    final (_, s) = await _open(
      tester,
      setup: (s) => s.forbidden = {'$_org/compliance/health'},
    );
    expect(find.text(kComplianceHrOnlyMessage), findsOneWidget);
    expect(
      find.text('Compliance is available to HR managers and above'),
      findsOneWidget,
    );
    for (final t in _tabs) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.text('Compliance Health Score'), findsNothing);
    expect(find.textContaining('Permission denied'), findsNothing);
    expect(find.textContaining('compliance.view'), findsNothing);
    expect(_calls(s), ['GET $_org/compliance/health']);
  });

  testWidgets('a failed health load keeps the rest and shows "-"', (
    tester,
  ) async {
    await _open(tester, setup: (s) => s.failing = {'$_org/compliance/health'});
    expect(find.text('Not available right now'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
    for (final t in _tabs) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.textContaining('exploded'), findsNothing);
  });

  testWidgets(
    'Wage registers: fines, deductions, advances, with names looked up once',
    (tester) async {
      final (_, s) = await _open(tester);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Late arrival'), findsOneWidget);
      expect(find.text('₹1,500'), findsOneWidget);
      // unknown employee: "Employee", unknown amount: "-"
      expect(find.text('Employee'), findsOneWidget);
      expect(find.text('Safety breach'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);

      await _tab(tester, 'Deductions');
      expect(find.text('Broken screen'), findsOneWidget);
      expect(find.text('₹2,500'), findsOneWidget);
      await _tab(tester, 'Advances');
      expect(find.text('Medical'), findsOneWidget);
      expect(find.text('₹12,000'), findsOneWidget);

      final calls = _calls(s);
      expect(
        calls,
        containsAll([
          'GET $_org/compliance/wage-register/fines',
          'GET $_org/compliance/wage-register/deductions',
          'GET $_org/compliance/wage-register/advances',
        ]),
      );
      expect(calls.where((c) => c.endsWith('/employees/summaries')).length, 1);
    },
  );

  testWidgets(
    'Wage registers: when names cannot be looked up, rows say "Employee"',
    (tester) async {
      await _open(tester, setup: (s) => s.namesFail = true);
      expect(find.text('Employee'), findsNWidgets(2));
      expect(find.text('Late arrival'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    },
  );

  testWidgets(
    'Statutory returns, Factories Act, Shops & Estb., Bonus and Gratuity read their routes',
    (tester) async {
      final (_, s) = await _open(tester);

      await _tab(tester, 'Statutory Returns');
      expect(find.text('PF ECR'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('Period: Sep 2026'), findsOneWidget);
      expect(find.text('Due Date: 15 Oct 2026'), findsOneWidget);
      expect(find.text('Amount: ₹45,000'), findsOneWidget);

      await _tab(tester, 'Factories Act');
      expect(find.text('Burn'), findsOneWidget);
      expect(find.text('Location: Plant 2 • Status: open'), findsOneWidget);

      await _tab(tester, 'Shops & Estb.');
      expect(find.text('Head Office'), findsOneWidget);
      expect(find.text('Valid until: 01 Jan 2030'), findsOneWidget);
      expect(find.text('Validity not set'), findsOneWidget);

      await _tab(tester, 'Statutory Bonus');
      expect(find.text('Bonus Year: 2025-26'), findsOneWidget);
      expect(find.text('₹12,34,567'), findsOneWidget);
      expect(find.text('8.33%'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      // a run with unknown figures shows "-", not 0
      expect(find.text('-'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);

      await _tab(tester, 'Gratuity');
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Eligible Years: 6.5'), findsOneWidget);
      expect(find.text('₹88,000'), findsOneWidget);
      await _tab(tester, 'Payouts');
      expect(find.text(kComplianceUnavailableMessage), findsOneWidget);

      expect(
        _calls(s),
        containsAll([
          'GET $_org/compliance/returns',
          'GET $_org/compliance/factory-accidents',
          'GET $_org/compliance/shops-certs',
          'GET $_org/bonus-runs',
          'GET $_org/gratuity/provisions',
        ]),
      );
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'quick links read POSH, Maternity, CLRA and Apprentices; Pay Equity and Auditor Pack are unavailable',
    (tester) async {
      final (_, s) = await _open(tester);
      final expected = {
        'POSH': ['POSH-2026-0001', 'open', '$_org/posh/complaints'],
        'Maternity': [
          'Neha Jain - maternity',
          '01 Dec 2026',
          '$_org/maternity/cases',
        ],
        'CLRA': ['ABC Contractors', 'LIC-77', '$_org/locum/contractors'],
        'Apprentices': ['Ravi', 'Fitter', '$_org/compliance/apprentices'],
      };
      for (final e in expected.entries) {
        await _tab(tester, e.key);
        expect(find.text(e.value[0]), findsOneWidget, reason: e.key);
        expect(find.text(e.value[1]), findsOneWidget, reason: e.key);
        expect(_calls(s), contains('GET ${e.value[2]}'));
        await _tab(tester, 'Back');
      }
      // the complainant is never shown
      expect(find.text('Secret Person'), findsNothing);

      for (final q in ["Pay Equity", "Auditor Pack"]) {
        final before = s.requests.length;
        await _tab(tester, q);
        expect(
          find.text(kComplianceUnavailableMessage),
          findsOneWidget,
          reason: q,
        );
        expect(s.requests.length, before, reason: q);
        await _tab(tester, "Back");
      }
    },
  );

  group('one part refused (403) or failing does not take the others down', () {
    testWidgets('403 on a tab shows the HR-only state in that tab', (
      tester,
    ) async {
      await _open(tester, setup: (s) => s.forbidden = {'$_org/bonus-runs'});
      await _tab(tester, 'Statutory Bonus');
      expect(find.text(kComplianceHrOnlyMessage), findsOneWidget);
      await _tab(tester, 'Statutory Returns');
      expect(find.text('PF ECR'), findsOneWidget);
    });

    testWidgets('a failing tab shows the fixed message and Retry', (
      tester,
    ) async {
      await _open(
        tester,
        setup: (s) => s.failing = {'$_org/compliance/returns'},
      );
      await _tab(tester, 'Statutory Returns');
      expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.textContaining('hrtoffy'), findsNothing);
    });

    testWidgets('a failing quick link shows the fixed message', (tester) async {
      await _open(tester, setup: (s) => s.failing = {'$_org/posh/complaints'});
      await _tab(tester, 'POSH');
      expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });
  });

  testWidgets('empty lists say so', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async {
      if (req.url.path == '$_org/compliance/health') {
        return ok({'overall_score': null});
      }
      if (req.url.path == '$_org/compliance/returns') {
        return ok({'items': [], 'total': 0, 'page': 1, 'limit': 200});
      }
      return ok([]);
    }, empRole: 'hr_manager');
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No records found'), findsOneWidget);
    await _tab(tester, 'Statutory Returns');
    expect(find.text('No filings found'), findsOneWidget);
  });

  testWidgets('the drawer opens', (tester) async {
    await _open(tester);
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openEndDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Approvals'), findsOneWidget);
  });

  test(
    'no Supabase, table names, raw error text or exception logging in the screen; reads only in the repository',
    () {
      final src = File(
        'lib/screens/manager/manager_compliance_screen.dart',
      ).readAsStringSync();
      for (final banned in [
        'supabase',
        'Supabase',
        '.from(',
        '.select(',
        'org_id',
        'compliance_health_snapshots',
        'employee_records',
        'snapshot.error',
        'Data fetch error',
        'print(',
        'debugPrint(',
        r'$e"',
        r"$e'",
        'FutureBuilder',
      ]) {
        expect(src.contains(banned), isFalse, reason: 'found "$banned"');
      }
      final repo = File(
        'lib/repositories/compliance_repository.dart',
      ).readAsStringSync();
      expect(RegExp(r'api\.(post|put|patch|delete)').hasMatch(repo), isFalse);
    },
  );
}
