import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/loans_repository.dart';
import 'package:hrms_app/screens/loans_advances_screens.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _screen(TestSession s) => MaterialApp(
  home: LoansAdvancesScreen(
    userEmail: 'me@x.com',
    userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
    fetchHrmsContext: () async => {},
    loansRepository: LoansRepository(auth: s.auth),
  ),
);

Map<String, dynamic> _loan(
  String id, {
  Object? requested = '50000.00',
  String status = 'approved',
  String number = 'LOAN-202610-00001',
  Object? tenure = 12,
  String created = '2026-10-01T09:00:00.000Z',
}) => {
  'id': id,
  'loan_number': number,
  'loan_category': 'personal_loan',
  'requested_amount': requested,
  'tenure_months': tenure,
  'status': status,
  'created_at': created,
};

Map<String, dynamic> _emi(
  String id, {
  Object? emi = '4166.67',
  Object? outstanding = '45833.33',
  String due = '2026-11-05T00:00:00.000Z',
  String status = 'pending',
}) => {
  'id': id,
  'loan_id': 'l1',
  'emi_number': 1,
  'due_date': due,
  'emi_amount': emi,
  'outstanding_principal': outstanding,
  'status': status,
  'loans_advances': {'loan_number': 'LOAN-202610-00001'},
};

Future<TestSession> _session({
  List<Map<String, dynamic>> loans = const [],
  List<Map<String, dynamic>> emis = const [],
  bool loansFail = false,
  bool emiFail = false,
}) {
  return signedIn((req) async {
    if (req.method != 'GET')
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    switch (req.url.path) {
      case '$_org/loans':
        return loansFail
            ? jsonResponse({
                'success': false,
                'error': {'message': 'db exploded at https://api.hrtoffy.in'},
              }, 500)
            : ok({'items': loans, 'total': loans.length});
      case '$_org/loans/emi-schedule':
        return emiFail
            ? jsonResponse({
                'success': false,
                'error': {'message': 'db exploded at https://api.hrtoffy.in'},
              }, 500)
            : ok(emis);
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected ${req.url.path}'},
    }, 404);
  });
}

void main() {
  testWidgets(
    'My Loans: lists the employee\'s loans from GET /loans?employeeId=<own>, nothing else, no writes',
    (tester) async {
      _tall(tester);
      final s = await _session(
        loans: [
          _loan(
            'l2',
            number: 'LOAN-202610-00002',
            requested: '120000.00',
            status: 'pending',
            tenure: 24,
          ),
          _loan('l1', created: '2026-09-01T09:00:00.000Z'),
        ],
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final loansCall = s.requests.firstWhere((r) => r.path == '$_org/loans');
      expect(loansCall.query, {'employeeId': testEmployeeId});
      expect(s.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(find.text('LOAN-202610-00002'), findsOneWidget);
      expect(find.text('LOAN-202610-00001'), findsOneWidget);
      expect(find.text('₹1,20,000'), findsOneWidget);
      expect(find.text('₹50,000'), findsOneWidget);
      expect(find.text('24 months'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('LOAN-202610-00002')).dy,
        lessThan(tester.getTopLeft(find.text('LOAN-202610-00001')).dy),
      );
    },
  );

  testWidgets(
    'My Loans: a missing, zero or invalid amount is "Not available", never "₹0"',
    (tester) async {
      _tall(tester);
      final s = await _session(
        loans: [
          _loan('a', requested: null, number: 'LOAN-A', tenure: null),
          _loan('b', requested: 0, number: 'LOAN-B'),
          _loan('c', requested: 'garbage', number: 'LOAN-C'),
        ],
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(find.text('Not available'), findsNWidgets(3));
      expect(find.text('₹0'), findsNothing);
      expect(find.text('-'), findsOneWidget); // tenure of the loan without one
    },
  );

  testWidgets('My Loans: no loans shows the empty state', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No loans found'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets(
    'My Loans: an API error shows a safe message, not the raw error',
    (tester) async {
      _tall(tester);
      final s = await _session(loansFail: true);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text("Couldn't load your loans. Please try again later."),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.textContaining('hrtoffy'), findsNothing);
    },
  );

  testWidgets(
    'EMI Schedule: lists the instalments from GET /loans/emi-schedule?employeeId=<own>',
    (tester) async {
      _tall(tester);
      final s = await _session(
        emis: [
          _emi('e1', emi: '4166.67', outstanding: '45833.33'),
          _emi(
            'e2',
            due: '2026-12-05T00:00:00.000Z',
            emi: 4166.67,
            outstanding: 41666.66,
            status: 'paid',
          ),
        ],
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('EMI Schedule'));
      await _settle(tester);

      final call = s.requests.firstWhere(
        (r) => r.path == '$_org/loans/emi-schedule',
      );
      expect(call.query, {'employeeId': testEmployeeId});
      expect(find.text('Due Date: 2026-11-05'), findsOneWidget);
      expect(find.text('Due Date: 2026-12-05'), findsOneWidget);
      expect(find.text('EMI Amount: ₹4,167'), findsNWidgets(2));
      expect(find.text('Outstanding: ₹45,833'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(s.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );

  testWidgets(
    'EMI Schedule: an unusable EMI amount shows "Not available" and hides the balance',
    (tester) async {
      _tall(tester);
      final s = await _session(
        emis: [
          _emi('e1', emi: 0, outstanding: 0),
          _emi(
            'e2',
            emi: null,
            outstanding: null,
            due: '2026-12-05T00:00:00.000Z',
          ),
        ],
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.text('EMI Schedule'));
      await _settle(tester);
      expect(find.text('EMI Amount: Not available'), findsNWidgets(2));
      expect(find.textContaining('Outstanding'), findsNothing);
      expect(find.text('EMI Amount: ₹0'), findsNothing);
    },
  );

  testWidgets('EMI Schedule: empty and error states', (tester) async {
    _tall(tester);
    final empty = await _session();
    await tester.pumpWidget(_screen(empty));
    await _settle(tester);
    await tester.tap(find.text('EMI Schedule'));
    await _settle(tester);
    expect(find.text('No EMI schedules found.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final failing = await _session(emiFail: true);
    await tester.pumpWidget(_screen(failing));
    await _settle(tester);
    await tester.tap(find.text('EMI Schedule'));
    await _settle(tester);
    expect(
      find.text("Couldn't load your EMI schedule. Please try again later."),
      findsOneWidget,
    );
    expect(find.textContaining('exploded'), findsNothing);
  });

  testWidgets(
    'applying for a loan: validates, sends only the verified fields with the session employee, then reloads the list',
    (tester) async {
      _tall(tester);
      var posted = 0;
      final s = await signedIn((req) async {
        if (req.method == 'POST' && req.url.path == '$_org/loans/request') {
          posted++;
          return ok({
            'loanId': 'new-loan',
            'message': 'Loan request created',
          }, 201);
        }
        if (req.url.path == '$_org/loans')
          return ok({
            'items': [_loan('l1')],
            'total': 1,
          });
        if (req.url.path == '$_org/loans/emi-schedule') return ok([]);
        return jsonResponse({'success': false}, 404);
      });
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester);
      expect(find.text('Apply for a loan'), findsOneWidget);

      // nothing valid yet: nothing is sent
      await tester.tap(find.text('Submit request'));
      await tester.pump();
      expect(posted, 0);
      expect(find.text('Reason is required'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (₹)'),
        '20000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        ' Medical ',
      );
      await tester.tap(find.text('Submit request'));
      await _settle(tester);

      expect(posted, 1);
      final post = s.requests.firstWhere((r) => r.method == 'POST');
      expect(post.json, {
        'employeeId': testEmployeeId,
        'amount': 20000.0,
        'reason': 'Medical',
      });
      expect(
        find.text('Loan request submitted. It is pending review.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a failed loan request shows a fixed message, keeps the form and does not leak the server text',
    (tester) async {
      _tall(tester);
      final s = await signedIn((req) async {
        if (req.method == 'POST')
          return jsonResponse({
            'success': false,
            'error': {'message': 'db exploded'},
          }, 500);
        if (req.url.path == '$_org/loans') return ok({'items': [], 'total': 0});
        return ok([]);
      });
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (₹)'),
        '500',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        'Advance',
      );
      await tester.tap(find.text('Submit request'));
      await _settle(tester);

      expect(find.text(kLoanRequestFailedMessage), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.text('Apply for a loan'), findsOneWidget);
    },
  );
}
