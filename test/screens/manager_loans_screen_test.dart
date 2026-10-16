import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/approvals_repository.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/screens/manager/manager_loans_screen.dart';

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

Widget _screen(TestSession s) => MaterialApp(
      home: ManagerLoansScreen(
        userEmail: 'm@x.com',
        userData: const {'id': testEmployeeId, 'organization_id': testOrgId, 'emp_role': 'admin'},
        fetchHrmsContext: () async => {},
        loansRepository: LoansRepository(auth: s.auth),
        approvalsRepository: ApprovalsRepository(auth: s.auth),
        employeeRepository: EmployeeRepository(auth: s.auth),
      ),
    );

final _boom = jsonResponse({'success': false, 'error': {'message': 'db exploded at https://api.hrtoffy.in'}}, 500);

Map<String, dynamic> _loan(String id, String number,
        {Object? requested = '50000.00', Object? emi, Object? tenure = 12, String status = 'pending', bool withRequested = true, String created = '2026-10-01T00:00:00.000Z'}) =>
    {
      'id': id,
      'loan_number': number,
      'employee_id': testEmployeeId,
      'loan_category': 'personal_loan',
      'purpose': 'Home repairs',
      if (withRequested) 'requested_amount': requested,
      'emi_amount': emi,
      'tenure_months': tenure,
      'status': status,
      'created_at': created,
    };

Map<String, dynamic> _emi(String id, {Object? emi = '4166.67', Object? outstanding = '45833.33', String status = 'pending'}) => {
      'id': id,
      'emi_number': 1,
      'due_date': '2026-11-05T00:00:00.000Z',
      'emi_amount': emi,
      'outstanding_principal': outstanding,
      'status': status,
      'loans_advances': {'loan_number': 'LOAN-1', 'loan_category': 'personal_loan'},
    };

Map<String, dynamic> _teamLoan(String id, String number, {String status = 'pending'}) => {
      'id': id,
      'loan_number': number,
      'employee_id': 'emp-$id',
      'loan_category': 'salary_advance',
      'purpose': 'Medical',
      'requested_amount': '20000.00',
      'tenure_months': 6,
      'status': status,
      'created_at': '2026-10-02T00:00:00.000Z',
      'employee_records_loans_advances_employee_idToemployee_records': {
        'full_name': 'Team $number',
        'employee_id': 'E-$id',
      },
    };

Future<TestSession> _session({
  bool failMeta = false,
  Set<String> failing = const {},
  Set<String> failingTeam = const {},
  List<Map<String, dynamic>>? team,
  List<Map<String, dynamic>>? loans,
  List<Map<String, dynamic>>? emis,
  Object? limit = const {'gradeCode': 'G3', 'loanMaxAmount': '200000.00'},
}) {
  return signedIn((req) async {
    final path = req.url.path;
    if (req.method == 'POST' && path == '$_org/loans/request') return ok({'loanId': 'new-1', 'message': 'Loan request created'}, 201);
    if (req.method == 'POST' && path == '$_org/workflows/module/loans/row-meta') {
      if (failMeta) return _boom;
      return ok({
        't1': {'canApprove': true, 'requiredRole': 'manager'},
        't2': {'canApprove': false, 'requiredRole': 'hr_manager'},
      });
    }
    if (req.method != 'GET') return jsonResponse({'success': false, 'error': {'message': 'unexpected write'}}, 500);
    if (failing.contains(path)) return _boom;
    switch (path) {
      case '$_org/employees/me':
        return ok({'id': testEmployeeId, 'organizationId': testOrgId, 'gradeCode': 'G3'});
      case '$_org/grade-structures/limits/G3':
        return ok(limit);
      case '$_org/loans':
        if (!req.url.queryParameters.containsKey('employeeId')) {
          if (failingTeam.contains(path)) return _boom;
          final t = team ?? [_teamLoan('t1', 'T-1'), _teamLoan('t2', 'T-2', status: 'manager_approved'), _teamLoan('t3', 'T-3', status: 'approved')];
          return ok({'items': t, 'total': t.length});
        }
        final rows = loans ?? [_loan('l1', 'LOAN-1', emi: '3750.04', tenure: 12)];
        return ok({'items': rows, 'total': rows.length});
      case '$_org/loans/emi-schedule':
        return ok(emis ?? [_emi('e1')]);
    }
    return jsonResponse({'success': false, 'error': {'message': 'unexpected $path'}}, 404);
  });
}

Future<void> _open(WidgetTester t, String card) async {
  await t.tap(find.text(card));
  await _settle(t);
}

void main() {
  testWidgets('renders with Supabase uninitialised; the approvals badge counts the requests waiting for the caller or others', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    for (final c in ['My Loans', 'Apply for Loan', 'EMI Schedule', 'Approvals', 'All Loans', 'HR Submit']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(find.text('2'), findsOneWidget); // T-1 may be decided and T-2 waits for HR (both pending); T-3 is decided
    expect(find.text('-'), findsNothing);
  });

  testWidgets('the approvals badge is "-" while the team list cannot be loaded, never 0', (tester) async {
    _tall(tester);
    final s = await _session(failingTeam: {'$_org/loans'});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the approvals badge is the waiting count when the engine answer fails, never "-" or 0', (tester) async {
    _tall(tester);
    final s = await _session(failMeta: true);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('2'), findsOneWidget); // T-1 and T-2 are still waiting
    expect(find.text('-'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('no open requests: no badge and no 0', (tester) async {
    _tall(tester);
    final s = await _session(team: [_teamLoan('t3', 'T-3', status: 'approved')]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('0'), findsNothing);
    expect(find.text('-'), findsNothing);
  });

  testWidgets('own loans, grade limit and EMI schedule use the repositories with the signed-in employee id', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    expect(s.requests.map((r) => '${r.method} ${r.path}').toSet(), {
      'GET $_org/employees/me',
      'GET $_org/grade-structures/limits/G3',
      'GET $_org/loans',
      'POST $_org/workflows/module/loans/row-meta',
    });
    final loanQueries = s.requests.where((r) => r.path == '$_org/loans').map((r) => r.query).toList();
    expect(loanQueries.where((q) => q.length == 1 && q['employeeId'] == testEmployeeId), hasLength(1)); // My Loans: own only
    expect(loanQueries.where((q) => q.isEmpty), hasLength(1)); // the approvals badge: the team list, no employeeId

    await _open(tester, 'EMI Schedule');
    final emi = s.requests.firstWhere((r) => r.path == '$_org/loans/emi-schedule');
    expect(emi.method, 'GET');
    expect(emi.query, {'employeeId': testEmployeeId});
    expect(s.requests.every((r) => r.method == 'GET' || r.path.endsWith('/row-meta')), isTrue);
  });

  testWidgets('valid decimal amounts show; placeholder zero, null and missing amounts are "Not available", never ₹0', (tester) async {
    _tall(tester);
    final s = await _session(loans: [
      _loan('a', 'LOAN-A', requested: '50000.00', emi: '3750.04'),
      _loan('b', 'LOAN-B', requested: 0, emi: 0),
      _loan('c', 'LOAN-C', requested: null, emi: null),
      _loan('d', 'LOAN-D', withRequested: false),
    ]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Loans');

    expect(find.text('₹50,000'), findsNWidgets(2)); // the loan's amount and the "used (at least)" figure
    expect(find.text('₹3,750.04'), findsOneWidget);
    // b: 2 unusable, c: 2, d: requested missing + emi null = 2  -> 6 loan fields (+ the limit card's own handling below)
    expect(find.text(kLoanAmountUnavailable), findsAtLeastNWidgets(6));
    expect(find.text('₹0'), findsNothing);
    expect(find.text('₹0.00'), findsNothing);
  });

  testWidgets('loan limit and utilization: complete data shows used amount and percent', (tester) async {
    _tall(tester);
    final s = await _session(loans: [
      _loan('a', 'LOAN-A', requested: '50000.00', status: 'pending'),
      _loan('b', 'LOAN-B', requested: '50000.00', status: 'approved', created: '2026-09-01T00:00:00.000Z'),
      _loan('c', 'LOAN-C', requested: '99999.00', status: 'rejected', created: '2026-08-01T00:00:00.000Z'),
    ]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text('₹2,00,000'), findsOneWidget); // limit
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('₹1,00,000'), findsOneWidget); // 50,000 + 50,000 (rejected loans do not count)
    expect(find.text('50% of your limit'), findsOneWidget);
    expect(find.textContaining('Incomplete'), findsNothing);
  });

  testWidgets('incomplete utilization is labelled as such and shows no percent', (tester) async {
    _tall(tester);
    final s = await _session(loans: [
      _loan('a', 'LOAN-A', requested: '50000.00', status: 'pending'),
      _loan('b', 'LOAN-B', requested: 0, status: 'active', created: '2026-09-01T00:00:00.000Z'),
    ]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text('Used (at least)'), findsOneWidget);
    expect(find.textContaining('Incomplete'), findsOneWidget);
    expect(find.textContaining('% of your limit'), findsNothing);
  });

  testWidgets('an unknown loan limit is "Not available" and a failed limit lookup does not hide the loans', (tester) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/grade-structures/limits/G3'});
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text('Loan limit'), findsOneWidget);
    expect(find.text('LOAN-1'), findsOneWidget);
    expect(find.textContaining('% of your limit'), findsNothing);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.text('₹0'), findsNothing);
  });

  testWidgets('EMI schedule: valid amounts, and a missing/zero EMI shows "Not available" without a balance', (tester) async {
    _tall(tester);
    final s = await _session(emis: [_emi('e1'), _emi('e2', emi: 0, outstanding: '1000.00')]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'EMI Schedule');
    await tester.tap(find.text('LOAN-1'));
    await tester.pumpAndSettle();
    expect(find.text('₹4,166.67'), findsOneWidget);
    expect(find.text('Outstanding: ₹45,833.33'), findsOneWidget);
    expect(find.text(kLoanAmountUnavailable), findsOneWidget);
    expect(find.text('Outstanding: ₹1,000'), findsNothing); // hidden with an unusable EMI
  });

  testWidgets('loading, empty and fixed-error states are distinct', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);

    await tester.pumpWidget(const SizedBox());
    final e = await _session(loans: [], emis: []);
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text('No loans found'), findsOneWidget);
    expect(find.text(kLoansLoadFailedMessage), findsNothing);
    await tester.tap(find.text('Back to overview'));
    await _settle(tester);
    await _open(tester, 'EMI Schedule');
    expect(find.text('No EMI schedules found'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final f = await _session(failing: {'$_org/loans', '$_org/loans/emi-schedule'});
    await tester.pumpWidget(_screen(f));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text(kLoansLoadFailedMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No loans found'), findsNothing);
    await tester.tap(find.text('Back to overview'));
    await _settle(tester);
    await _open(tester, 'EMI Schedule');
    expect(find.textContaining("Couldn't load your EMI schedule"), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('hrtoffy'), findsNothing);
  });

  testWidgets('without a signed-in employee no loan or EMI request is made', (tester) async {
    _tall(tester);
    final s = await _session();
    await s.auth.logout();
    s.requests.clear();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Loans');
    expect(find.text(kLoansLoadFailedMessage), findsOneWidget);
    await tester.tap(find.text('Back to overview'));
    await _settle(tester);
    await _open(tester, 'EMI Schedule');
    expect(find.textContaining("Couldn't load your EMI schedule"), findsOneWidget);
    expect(s.requests, isEmpty);
  });

  testWidgets('Approvals opens the approvals panel with the team queue', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'Approvals');
    expect(find.text('Pending (2)'), findsOneWidget);
    expect(find.text('T-1'), findsOneWidget);
    expect(find.text('T-2'), findsOneWidget); // waiting at HR: in Pending, without a Review button
    expect(find.text('Waiting on HR manager'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget); // T-1 only
    expect(find.text(kLoansUnavailableMessage), findsNothing);
    expect(s.requests.every((r) => r.method == 'GET' || r.path.endsWith('/row-meta')), isTrue); // opening decides nothing
  });

  testWidgets('Apply for Loan posts the request for the signed-in employee (no category) and reloads', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'Apply for Loan');
    expect(find.text('Apply for a loan'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount (₹)'), '15000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Laptop');
    await tester.tap(find.text('Submit request'));
    await _settle(tester);
    final post = s.requests.firstWhere((r) => r.method == 'POST' && !r.path.endsWith('/row-meta'));
    expect(post.path, '$_org/loans/request');
    expect(post.json, {'employeeId': testEmployeeId, 'amount': 15000.0, 'reason': 'Laptop'});
    expect(find.textContaining('Loan request submitted'), findsOneWidget);
  });

  testWidgets('All Loans and HR Submit are unavailable; nothing is written', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final before = s.requests.length;

    for (final card in ['All Loans', 'HR Submit']) {
      await _open(tester, card);
      expect(find.text(kLoansUnavailableMessage), findsOneWidget, reason: card);
      expect(find.byType(TextFormField), findsNothing, reason: card);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing, reason: card);
      for (final label in ['Approve', 'Reject', 'Submit', 'Upload Document (PDF/JPG)']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      await tester.tap(find.text('Back to overview'));
      await _settle(tester);
    }
    // Going back only refreshes the approvals badge (the team list); nothing else is requested.
    expect(s.requests.skip(before).every((r) => (r.method == 'GET' && r.path == '$_org/loans') || r.path.endsWith('/row-meta')), isTrue);
    expect(s.requests.every((r) => r.method == 'GET' || r.path.endsWith('/row-meta')), isTrue);
  });

  test('the screen has no Supabase, storage, edge function, workflow RPC, write or exception logging', () {
    final src = File('lib/screens/manager/manager_loans_screen.dart').readAsStringSync();
    for (final banned in [
      'supabase',
      'Supabase',
      'storage',
      'file_picker',
      'dart:io',
      'salary-encryption',
      'initialize_workflow',
      'process_workflow_step',
      'get_manager_full_hierarchy',
      '.rpc(',
      '.functions',
      '.insert(',
      '.update(',
      '.upsert(',
      '.delete(',
      '.upload(',
      'print(',
      'debugPrint(',
      r'$e"',
      r"$e'",
      'catch (e)',
    ]) {
      expect(src.contains(banned), isFalse, reason: 'found "$banned"');
    }
  });
}
