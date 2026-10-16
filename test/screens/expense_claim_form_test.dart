import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/expense_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart' show ReceiptFile;
import 'package:hrms_app/repositories/workflow_repository.dart';
import 'package:hrms_app/screens/travel_expenses_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Finder _field(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);
Finder _labelled(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

class _Env {
  _Env(this.session, this.posts, this.workflowCalls);
  final TestSession session;
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> workflowCalls;
}

/// A server with one category 'Office Supplies' and the employee's own earlier claims. [requiresReceipt] defaults to
/// false so that a plain claim raises no policy warning; tests turn it on where the warning is the point.
Future<_Env> _env({
  int? postStatus,
  int? workflowStatus,
  bool requiresReceipt = false,
  double? monthlyLimit,
  List<Map<String, dynamic>> ownClaims = const [],
}) async {
  final posts = <Map<String, dynamic>>[];
  final workflowCalls = <Map<String, dynamic>>[];
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'GET' && p == '$_org/expenses/categories') {
      return ok([
        {
          'id': 'cat1',
          'name': 'Office Supplies',
          'is_active': true,
          'requires_receipt': requiresReceipt,
          'monthly_limit': monthlyLimit?.toStringAsFixed(2),
        },
      ]);
    }
    if (req.method == 'GET' && p == '$_org/expenses') return ok(ownClaims);
    if (req.method == 'POST' && p == '$_org/expenses') {
      posts.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
      if (postStatus != null) {
        return jsonResponse({'success': false, 'error': {'message': 'server text that must not be shown'}}, postStatus);
      }
      return ok({'id': 'claim1'}, 201);
    }
    if (req.method == 'POST' && p == '$_org/workflows/initialize') {
      workflowCalls.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
      if (workflowStatus != null) return jsonResponse({'success': false, 'error': {'message': 'x'}}, workflowStatus);
      return ok({'id': 'exec1'});
    }
    return jsonResponse({'success': false}, 404);
  });
  return _Env(s, posts, workflowCalls);
}

class _Result {
  int successes = 0;
}

Future<_Result> _pump(WidgetTester tester, _Env e) async {
  _tall(tester);
  final r = _Result();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ExpenseClaimForm(
          email: 'me@x.com',
          userData: const {},
          onCancel: () {},
          onSuccess: () => r.successes++,
          repository: ExpenseRepository(auth: e.session.auth),
          workflowRepository: WorkflowRepository(auth: e.session.auth),
        ),
      ),
    ),
  ));
  await _settle(tester);
  return r;
}

Future<void> _chooseCategory(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Office Supplies').last);
  await tester.pumpAndSettle();
}

/// Fills the same claim as the failing phone test: category, title, one line.
Future<void> _fill(WidgetTester tester, {String amount = '50000', bool category = true}) async {
  await tester.enterText(_labelled('Claim Title *'), 'test');
  if (category) await _chooseCategory(tester);
  await tester.enterText(_field('Amount'), amount);
  await tester.enterText(_field('Item description'), 'test');
  await tester.pump();
}

/// Presses Submit Claim. When the policy warning appears, [confirm] decides: "Submit anyway" or "Review".
Future<void> _submit(WidgetTester tester, {bool confirm = true}) async {
  final btn = find.text('Submit Claim');
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  // the submit spinner animates forever, so bounded pumps instead of pumpAndSettle
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (find.text('Check before submitting').evaluate().isNotEmpty) {
    await tester.tap(find.text(confirm ? 'Submit anyway' : 'Review'));
  }
  await _settle(tester);
}

void main() {
  group('submitting an expense claim', () {
    testWidgets('sends the contract the backend reads, then starts the approval chain for the stored claim', (tester) async {
      final e = await _env();
      final r = await _pump(tester, e);
      await _fill(tester);
      await _submit(tester);

      expect(e.posts, hasLength(1));
      final b = e.posts.single;
      expect(b['employeeId'], testEmployeeId);
      expect(b['title'], 'test');
      expect(b['categoryId'], 'cat1');
      final item = (b['items'] as List).single as Map;
      expect(item['description'], 'test');
      expect(item['amount'], 50000);
      expect(item['expense_date'], matches(r'^\d{4}-\d{2}-\d{2}$'));
      expect(item.containsKey('receipt_url'), isTrue);

      expect(e.workflowCalls, [
        {'moduleName': 'expenses', 'recordId': 'claim1'},
      ]);
      expect(r.successes, 1, reason: 'success is reported only after the server accepted the claim');
      expect(find.textContaining("couldn't confirm"), findsNothing);
    });

    testWidgets('the approval chain is started only AFTER the claim is stored, and never for a claim that failed', (tester) async {
      final e = await _env(postStatus: 500);
      final r = await _pump(tester, e);
      await _fill(tester);
      await _submit(tester);
      expect(e.workflowCalls, isEmpty);
      expect(r.successes, 0);
    });

    testWidgets('a failure to start the approval chain does NOT make the stored claim a failed submission', (tester) async {
      final e = await _env(workflowStatus: 500);
      final r = await _pump(tester, e);
      await _fill(tester);
      await _submit(tester);

      expect(e.posts, hasLength(1));
      expect(r.successes, 1, reason: 'the claim exists, so it is a success');
      expect(find.textContaining("couldn't confirm that approval routing started"), findsOneWidget);
      expect(find.textContaining('Failed to submit'), findsNothing);
    });

    testWidgets('a refusal (5xx, the database policy) says what to check, never the raw error or a bare "failed"', (tester) async {
      final e = await _env(postStatus: 500);
      await _pump(tester, e);
      await _fill(tester);
      await _submit(tester);
      expect(find.textContaining('may need a receipt'), findsOneWidget);
      expect(find.textContaining('server text'), findsNothing);
      expect(find.text('Failed to submit expense claim. Please try again.'), findsNothing);
    });

    testWidgets('404, 403, 400 and 401 each get their own plain message', (tester) async {
      final expected = {
        404: 'category is no longer available',
        403: "can't submit this claim",
        400: 'check the claim details',
        401: 'Session expired',
      };
      for (final entry in expected.entries) {
        final e = await _env(postStatus: entry.key);
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, e);
        await _fill(tester);
        await _submit(tester);
        expect(find.textContaining(entry.value), findsOneWidget, reason: 'HTTP ${entry.key}');
        expect(find.textContaining('server text'), findsNothing);
      }
    });
  });

  group('policy pre-check on the real category data', () {
    testWidgets('a category that requires a receipt warns before sending; "Review" sends nothing', (tester) async {
      final e = await _env(requiresReceipt: true);
      await _pump(tester, e);
      await _fill(tester);
      await _submit(tester, confirm: false);

      expect(find.text('Check before submitting'), findsNothing, reason: 'the dialog closed after Review');
      expect(e.posts, isEmpty);
      expect(e.workflowCalls, isEmpty);
    });

    testWidgets('the warning names the rule and says receipts can only be attached when the service is available', (tester) async {
      final e = await _env(requiresReceipt: true);
      await _pump(tester, e);
      await _fill(tester);
      final btn = find.text('Submit Claim');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check before submitting'), findsOneWidget);
      expect(find.textContaining('A receipt is required for "Office Supplies"'), findsWidgets);
      expect(find.textContaining('Receipts can only be attached when the receipt service is available'), findsOneWidget);
    });

    testWidgets('"Submit anyway" lets the server decide: the claim is sent', (tester) async {
      final e = await _env(requiresReceipt: true);
      final r = await _pump(tester, e);
      await _fill(tester);
      await _submit(tester, confirm: true);
      expect(e.posts, hasLength(1));
      expect(r.successes, 1);
    });

    testWidgets('the monthly limit counts what the employee already claimed in the category this month', (tester) async {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1).toIso8601String();
      final e = await _env(monthlyLimit: 10000, ownClaims: [
        {'id': 'c1', 'category_id': 'cat1', 'status': 'approved', 'approved_amount': 7000, 'amount': 7000, 'expense_date': thisMonth},
        {'id': 'c2', 'category_id': 'cat1', 'status': 'rejected', 'amount': 9999, 'expense_date': thisMonth},
        {'id': 'c3', 'category_id': 'other', 'status': 'approved', 'amount': 9999, 'expense_date': thisMonth},
      ]);
      await _pump(tester, e);
      await _fill(tester, amount: '4000');
      // 7000 already (the rejected and other-category claims do not count) + 4000 > 10000
      expect(find.textContaining('already 7000 this month'), findsOneWidget);
      await _submit(tester, confirm: false);
      expect(e.posts, isEmpty);
    });

    testWidgets('a claim inside the limit, in a category without a receipt rule, raises no warning', (tester) async {
      final e = await _env(monthlyLimit: 100000);
      final r = await _pump(tester, e);
      await _fill(tester, amount: '4000');
      await _submit(tester);
      expect(find.text('Check before submitting'), findsNothing);
      expect(e.posts, hasLength(1));
      expect(r.successes, 1);
    });

    testWidgets('no category chosen while the organization has categories: the policy requires one', (tester) async {
      final e = await _env();
      await _pump(tester, e);
      await _fill(tester, category: false);
      final btn = find.text('Submit Claim');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check before submitting'), findsOneWidget);
      expect(find.textContaining('Select an expense category'), findsWidgets);
    });
  });

  group('expensePolicyIssue / expenseUsedThisMonth (the website\'s expensePolicyBlock)', () {
    final cats = [
      {'id': 'a', 'name': 'Travel', 'is_active': true, 'requires_receipt': true, 'monthly_limit': 5000},
      {'id': 'b', 'name': 'Old', 'is_active': false},
      {'id': 'c', 'name': 'Free', 'is_active': true, 'requires_receipt': false},
    ];
    String? issue({String? cat, double total = 100, double used = 0, bool receipt = false, List<Map<String, dynamic>>? categories}) =>
        expensePolicyIssue(categories: categories ?? cats, categoryId: cat, total: total, usedThisMonth: used, hasReceipt: receipt);

    test('category rules', () {
      expect(issue(cat: null), contains('Select an expense category'));
      expect(issue(cat: null, categories: const []), isNull, reason: 'an organization without categories needs none');
      expect(issue(cat: 'b'), contains('not active'));
      expect(issue(cat: 'zzz'), contains('not active'));
    });

    test('monthly limit counts what is already used and the whole claim', () {
      expect(issue(cat: 'a', total: 4000, used: 900, receipt: true), isNull);
      expect(issue(cat: 'a', total: 4000, used: 1001, receipt: true), contains('monthly limit'));
      expect(issue(cat: 'a', total: 5001, receipt: true), contains('monthly limit'));
    });

    test('receipt rule', () {
      expect(issue(cat: 'a', total: 100), contains('A receipt is required for "Travel"'));
      expect(issue(cat: 'a', total: 100, receipt: true), isNull);
      expect(issue(cat: 'c', total: 100), isNull);
    });

    test('used this month: same category and month, approved amount first, draft/rejected/cancelled ignored', () {
      final d = DateTime(2026, 10, 14);
      final claims = [
        {'category_id': 'a', 'status': 'approved', 'approved_amount': 300, 'amount': 500, 'expense_date': '2026-10-02'},
        {'category_id': 'a', 'status': 'pending', 'amount': 200, 'expense_date': '2026-10-20'},
        {'category_id': 'a', 'status': 'draft', 'amount': 999, 'expense_date': '2026-10-05'},
        {'category_id': 'a', 'status': 'Rejected', 'amount': 999, 'expense_date': '2026-10-05'},
        {'category_id': 'a', 'status': 'cancelled', 'amount': 999, 'expense_date': '2026-10-05'},
        {'category_id': 'a', 'status': 'approved', 'amount': 999, 'expense_date': '2026-09-30'},
        {'category_id': 'b', 'status': 'approved', 'amount': 999, 'expense_date': '2026-10-05'},
      ];
      expect(expenseUsedThisMonth(claims, categoryId: 'a', date: d), 500);
    });
  });

  group('receipts: nothing is faked while the receipt service is unavailable', () {
    test('a receipt upload that fails stops the claim: no POST, and the failure says the receipt service is missing', () async {
      final posts = <String>[];
      final s = await signedIn((req) async {
        if (req.url.path == '$_org/files') return jsonResponse({'success': false}, 404);
        if (req.method == 'POST') posts.add(req.url.path);
        return ok({'id': 'x'});
      });
      final repo = ExpenseRepository(auth: s.auth);
      Object? err;
      try {
        await repo.createClaim(
          title: 't',
          lines: [
            ExpenseLine(
              expenseDate: '2026-10-14',
              description: 'd',
              amount: 10,
              receipt: ReceiptFile(name: 'r.jpg', bytes: const [1, 2, 3], contentType: 'image/jpeg'),
            ),
          ],
        );
      } catch (e) {
        err = e;
      }
      expect(err, isA<ReceiptUploadException>());
      expect((err as ReceiptUploadException).serviceUnavailable, isTrue);
      expect(posts, isEmpty, reason: 'the claim is never created without its receipt');
      expect(expenseSubmitErrorMessage(err), contains("receipt service isn't available"));
      expect(expenseSubmitErrorMessage(err), contains('was not submitted'));
    });

    test('other upload failures are worded as a receipt problem, not as a claim problem', () {
      expect(expenseSubmitErrorMessage(const ReceiptUploadException(500)), contains("receipt couldn't be uploaded"));
      expect(expenseSubmitErrorMessage(const ReceiptUploadException(0)), contains('No connection'));
      expect(expenseSubmitErrorMessage(const ReceiptUploadException(404)), isNot(contains('category')));
    });

    test('a successful upload stores the bucket/path reference the Files API returned', () async {
      final bodies = <Map<String, dynamic>>[];
      final s = await signedIn((req) async {
        if (req.url.path == '$_org/files') {
          return ok({'bucket': 'expense-receipts', 'path': 'p/r.jpg', 'ref': 'expense-receipts/p/r.jpg', 'size': 3});
        }
        if (req.method == 'POST' && req.url.path == '$_org/expenses') {
          bodies.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
          return ok({'id': 'c1'}, 201);
        }
        return jsonResponse({'success': false}, 404);
      });
      await ExpenseRepository(auth: s.auth).createClaim(
        title: 't',
        lines: [
          ExpenseLine(
            expenseDate: '2026-10-14',
            description: 'd',
            amount: 10,
            receipt: ReceiptFile(name: 'r.jpg', bytes: const [1, 2, 3], contentType: 'image/jpeg'),
          ),
        ],
      );
      expect(((bodies.single['items'] as List).single as Map)['receipt_url'], 'expense-receipts/p/r.jpg');
    });
  });

  test('WorkflowRepository: posts {moduleName, recordId}, never throws, and does nothing without a record id', () async {
    final calls = <Map<String, dynamic>>[];
    final ok1 = await signedIn((req) async {
      calls.add({'path': req.url.path, 'body': jsonDecode(req.body)});
      return ok({'id': 'e'});
    });
    expect(await WorkflowRepository(auth: ok1.auth).initialize(WorkflowRepository.leaves, 'l1'), isTrue);
    expect(calls.single, {'path': '$_org/workflows/initialize', 'body': {'moduleName': 'leaves', 'recordId': 'l1'}});

    final bad = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'x'}}, 500));
    expect(await WorkflowRepository(auth: bad.auth).initialize(WorkflowRepository.benefits, 'b1'), isFalse);

    final failedEnvelope = await signedIn((req) async => jsonResponse({'success': false, 'error': 'not started'}, 200));
    expect(await WorkflowRepository(auth: failedEnvelope.auth).initialize(WorkflowRepository.expenses, 'x1'), isFalse);

    calls.clear();
    expect(await WorkflowRepository(auth: ok1.auth).initialize(WorkflowRepository.leaves, null), isFalse);
    expect(await WorkflowRepository(auth: ok1.auth).initialize(WorkflowRepository.leaves, ''), isFalse);
    expect(calls, isEmpty);
    expect(const ApiException(0, ''), isA<Exception>());
  });
}
