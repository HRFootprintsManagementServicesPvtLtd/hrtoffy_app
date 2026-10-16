import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/expense_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart';
import 'package:hrms_app/screens/travel_expenses_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  // skeletons animate forever, so settle in bounded steps
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets(
    'travel list shows the own claims from the API (decimal strings are safe)',
    (tester) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => ok([
          {
            'id': 't1',
            'claim_number': 'TRV-0001',
            'trip_purpose': 'Client visit',
            'trip_destination': 'Pune',
            'trip_from_date': '2026-10-07T00:00:00.000Z',
            'trip_to_date': '2026-10-09T00:00:00.000Z',
            'total_amount': '5400.00',
            'status': 'pending',
            'created_at': '2026-10-01T10:00:00.000Z',
          },
        ]),
      );
      await tester.pumpWidget(
        _app(
          TravelClaimsList(
            email: 'me@x.com',
            userData: const {},
            repository: TravelRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);

      expect(s.apiCalls.single.path, '$_org/travel/claims');
      expect(s.apiCalls.single.query, {'employeeId': testEmployeeId});
      expect(find.text('TRV-0001'), findsOneWidget);
      expect(find.text('Client visit'), findsOneWidget);
      expect(find.textContaining('Pune'), findsOneWidget);
      expect(find.textContaining('5,400'), findsOneWidget);
      expect(find.textContaining('2026-10-07'), findsOneWidget);
    },
  );

  testWidgets('expense list shows the category name mapped from category_id', (
    tester,
  ) async {
    _tall(tester);
    final s = await signedIn((req) async {
      if (req.url.path == '$_org/expenses/categories') {
        return ok([
          {
            'id': 'c1',
            'name': 'Client Entertainment',
            'monthly_limit': '5000.00',
            'is_active': true,
          },
        ]);
      }
      return ok([
        {
          'id': 'e1',
          'title': 'Team lunch',
          'category_id': 'c1',
          'amount': '750.00',
          'status': 'pending',
          'created_at': '2026-10-01T10:00:00.000Z',
          'expense_date': '2026-10-05T00:00:00.000Z',
        },
      ]);
    });
    await tester.pumpWidget(
      _app(
        ExpenseClaimsList(
          email: 'me@x.com',
          userData: const {},
          repository: ExpenseRepository(auth: s.auth),
        ),
      ),
    );
    await _settle(tester);

    expect(
      s.apiCalls.map((r) => r.path),
      containsAll(['$_org/expenses/categories', '$_org/expenses']),
    );
    expect(s.apiCalls.firstWhere((r) => r.path == '$_org/expenses').query, {
      'employeeId': testEmployeeId,
    });
    expect(find.text('Team lunch'), findsOneWidget);
    expect(find.textContaining('Client Entertainment'), findsOneWidget);
    expect(find.textContaining('750'), findsOneWidget);
  });

  testWidgets(
    'expense list still works when the category list cannot be loaded',
    (tester) async {
      _tall(tester);
      final s = await signedIn((req) async {
        if (req.url.path == '$_org/expenses/categories')
          return jsonResponse({
            'success': false,
            'error': {'message': 'x'},
          }, 500);
        return ok([
          {
            'id': 'e1',
            'title': 'Taxi',
            'category_id': 'c1',
            'amount': 100,
            'status': 'pending',
            'created_at': '2026-10-01T10:00:00.000Z',
          },
        ]);
      });
      await tester.pumpWidget(
        _app(
          ExpenseClaimsList(
            email: 'me@x.com',
            userData: const {},
            repository: ExpenseRepository(auth: s.auth),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.textContaining('Uncategorized'), findsOneWidget);
    },
  );

  testWidgets('empty lists show the empty state', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async => ok([]));
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TravelClaimsList(
              email: 'me@x.com',
              userData: const {},
              repository: TravelRepository(auth: s.auth),
            ),
            ExpenseClaimsList(
              email: 'me@x.com',
              userData: const {},
              repository: ExpenseRepository(auth: s.auth),
            ),
          ],
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('No travel claims found'), findsOneWidget);
    expect(find.text('No expense claims found'), findsOneWidget);
  });
}
