import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/overtime_repository.dart';
import 'package:hrms_app/screens/overtime_screen.dart';

import '../helpers/test_auth.dart';

Future<void> _settle(WidgetTester t) async {
  // the skeleton animates forever, so settle in bounded steps
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _screen(TestSession s) => MaterialApp(
  home: OvertimeScreen(
    email: 'me@x.com',
    userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
    fetchHrmsContext: () async => {},
    repository: OvertimeRepository(auth: s.auth),
  ),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('shows the overtime records from the API', (tester) async {
    _tall(tester);
    final s = await signedIn(
      (req) async => ok([
        {
          'id': 'o1',
          'ot_date': '2026-10-07T00:00:00.000Z',
          'total_hours': '2.50',
          'rate_multiplier': '1.50',
          'ot_amount': '1250.00',
          'ot_type': 'weekday_overtime',
          'status': 'approved',
        },
      ]),
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    expect(
      s.apiCalls.single.path,
      '/organizations/$testOrgId/employees/$testEmployeeId/overtime/records',
    );
    expect(find.text('07 Oct 2026'), findsOneWidget);
    expect(find.text('2.50 hrs'), findsOneWidget);
    expect(find.text('1.50x'), findsOneWidget);
    expect(find.text('₹1250.00'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('Type: WEEKDAY OVERTIME'), findsOneWidget);
  });

  testWidgets('empty list shows the empty state', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async => ok([]));
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No overtime records found'), findsOneWidget);
  });

  testWidgets('an API error shows the empty state and no raw error text', (
    tester,
  ) async {
    _tall(tester);
    final s = await signedIn(
      (req) async => jsonResponse({
        'success': false,
        'error': {'message': 'db exploded at host x'},
      }, 500),
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No overtime records found'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('api.hrtoffy'), findsNothing);
  });
}
