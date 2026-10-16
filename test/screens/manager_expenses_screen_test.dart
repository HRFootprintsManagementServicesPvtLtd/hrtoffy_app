import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/expense_repository.dart';
import 'package:hrms_app/screens/manager/manager_expenses_screen.dart';

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

Widget _screen(ExpenseRepository repo) => MaterialApp(
      home: ManagerExpensesScreen(
        userEmail: 'm@x.com',
        userData: const {'id': testEmployeeId, 'organization_id': testOrgId, 'emp_role': 'admin'},
        fetchHrmsContext: () async => {},
        expenseRepository: repo,
      ),
    );

final _boom = jsonResponse({'success': false, 'error': {'message': 'db exploded at https://api.hrtoffy.in'}}, 500);

Map<String, dynamic> _claim(String id, String title, {String? categoryId, Object? amount, Object? total, String status = 'pending', String? number}) => {
      'id': id,
      'claim_number': number,
      'title': title,
      'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (total != null) 'total_amount': total,
      'status': status,
      'expense_date': '2026-10-05T00:00:00.000Z',
      'created_at': '2026-10-0${id.length}T10:00:00.000Z',
    };

Future<TestSession> _session({
  Set<String> failing = const {},
  List<Map<String, dynamic>>? claims,
}) {
  return signedIn((req) async {
    if (req.method != 'GET') return jsonResponse({'success': false, 'error': {'message': 'unexpected write'}}, 500);
    final path = req.url.path;
    if (failing.contains(path)) return _boom;
    switch (path) {
      case '$_org/expenses/categories':
        return ok([
          {'id': 'c1', 'name': 'Travel', 'monthly_limit': '5000.00', 'is_active': true},
          {'id': 'c2', 'name': 'Food', 'monthly_limit': null, 'is_active': true},
        ]);
      case '$_org/expenses':
        return ok(claims ??
            [
              _claim('a', 'Client lunch', categoryId: 'c2', amount: '750.50', number: 'EXP-001'),
              _claim('bb', 'Cab to airport', categoryId: 'c1', total: '1250.00', status: 'approved'),
            ]);
    }
    return jsonResponse({'success': false, 'error': {'message': 'unexpected $path'}}, 404);
  });
}

Future<void> _open(WidgetTester t, String card) async {
  await t.tap(find.text(card));
  await _settle(t);
}

void main() {
  testWidgets('renders with Supabase uninitialised; the overview cards are kept and the approvals badge is "-"', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    for (final c in ['My Expenses', 'Submit Claim', 'Approvals', 'All Claims']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('categories and the signed-in employee\'s own claims load through the repository, always scoped', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);

    expect(s.requests.map((r) => '${r.method} ${r.path}'), ['GET $_org/expenses/categories', 'GET $_org/expenses']);
    final claimsReq = s.requests.firstWhere((r) => r.path == '$_org/expenses');
    expect(claimsReq.query, {'employeeId': testEmployeeId}); // never unscoped

    await _open(tester, 'My Expenses');
    expect(find.text('Client lunch'), findsOneWidget);
    expect(find.text('Cab to airport'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget); // category names from category_id
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('EXP-001'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
  });

  testWidgets('decimal-string amounts display correctly (amount or total_amount), unknown is "-" not zero', (tester) async {
    _tall(tester);
    final s = await _session(claims: [
      _claim('a', 'Client lunch', amount: '750.50'),
      _claim('bb', 'Cab', total: '1250.00'),
      _claim('ccc', 'No amount yet'),
    ]);
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');

    for (final title in ['Client lunch', 'Cab', 'No amount yet']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    expect(find.text('₹750.50'), findsOneWidget);
    expect(find.text('₹1,250.00'), findsOneWidget);
    expect(find.text('₹0.00'), findsNothing);
    expect(find.text('-'), findsWidgets);
  });

  testWidgets('line items and receipts show an unavailable note and make no request', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');
    final before = s.requests.length;
    await tester.tap(find.text('Client lunch'));
    await tester.pumpAndSettle();
    expect(find.text("Line items and receipts aren't available yet"), findsOneWidget);
    expect(s.requests.length, before);
    expect(s.requests.any((r) => RegExp('items|files|receipt', caseSensitive: false).hasMatch(r.path)), isFalse);
  });

  testWidgets('loading, empty and failure states are distinct', (tester) async {
    _tall(tester);
    // loading
    final s = await _session();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // empty
    final e = await _session(claims: []);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_screen(ExpenseRepository(auth: e.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');
    expect(find.text('No expense claims found'), findsOneWidget);
    expect(find.text(kExpensesLoadFailedMessage), findsNothing);

    // failure
    final f = await _session(failing: {'$_org/expenses'});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_screen(ExpenseRepository(auth: f.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');
    expect(find.text(kExpensesLoadFailedMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No expense claims found'), findsNothing);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('hrtoffy'), findsNothing);
  });

  testWidgets('a failed category list only drops the names', (tester) async {
    _tall(tester);
    final s = await _session(failing: {'$_org/expenses/categories'});
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');
    expect(find.text('Client lunch'), findsOneWidget);
    expect(find.text(kExpensesLoadFailedMessage), findsNothing);
  });

  testWidgets('without a signed-in employee no (unscoped) request is made and a fixed error is shown', (tester) async {
    _tall(tester);
    final s = await _session();
    await s.auth.logout();
    s.requests.clear();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    await _open(tester, 'My Expenses');
    expect(find.text(kExpensesLoadFailedMessage), findsOneWidget);
    expect(s.requests.where((r) => r.path.endsWith('/expenses')), isEmpty);
    expect(s.requests, isEmpty);
  });

  testWidgets('Submit Claim and All Claims are unavailable and trigger no request', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(ExpenseRepository(auth: s.auth)));
    await _settle(tester);
    final before = s.requests.length;

    for (final card in ['Submit Claim', 'All Claims']) {
      await _open(tester, card);
      expect(find.text(kExpensesUnavailableMessage), findsOneWidget, reason: card);
      expect(find.byType(TextFormField), findsNothing, reason: card);
      for (final label in ['Approve', 'Reject', 'Review', 'Submit', 'Save Draft']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      await tester.tap(find.text('Back to overview'));
      await _settle(tester);
    }
    expect(s.requests.length, before);
    expect(s.requests.every((r) => r.method == 'GET'), isTrue);
    // the only claims request is the scoped one made at start-up
    expect(s.requests.where((r) => r.path == '$_org/expenses').length, 1);
  });

  test('the screen has no Supabase, storage, upload, write or exception logging', () {
    final src = File('lib/screens/manager/manager_expenses_screen.dart').readAsStringSync();
    for (final banned in [
      'supabase',
      'Supabase',
      'storage',
      'file_picker',
      'dart:io',
      '.insert(',
      '.update(',
      '.upsert(',
      '.delete(',
      '.upload(',
      'createClaim',
      'uploadReceipt',
      'hierarchy',
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
