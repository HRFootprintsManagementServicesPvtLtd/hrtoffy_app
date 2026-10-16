import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/screens/benefits_screen.dart';

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
  home: BenefitsScreen(
    userEmail: 'me@x.com',
    userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
    fetchHrmsContext: () async => {},
    benefitsRepository: BenefitsRepository(auth: s.auth),
    employeeRepository: EmployeeRepository(auth: s.auth),
  ),
);

Map<String, dynamic> _me() => {
  'id': testEmployeeId,
  'organizationId': testOrgId,
  'gradeCode': 'G3',
  'managerId': 'mgr-1',
};

Map<String, dynamic> _claim(
  String id,
  String description, {
  String date = '2026-10-05T00:00:00.000Z',
  Object? claimed = '1250.00',
  Object? approved,
  String status = 'pending',
  String name = 'Medical',
}) => {
  'id': id,
  'description': description,
  'claim_date': date,
  'claim_year': 2026,
  'claimed_amount': claimed,
  'approved_amount': approved,
  'status': status,
  'created_at': '2026-10-05T09:00:00.000Z',
  'benefits_catalog': {'benefit_name': name, 'benefit_type': 'health'},
};

Future<TestSession> _session({
  List<Map<String, dynamic>> claims = const [],
  bool claimsFail = false,
  bool meFails = false,
}) {
  return signedIn((req) async {
    switch (req.url.path) {
      case '$_org/employees/me':
        return meFails
            ? jsonResponse({
                'success': false,
                'error': {'message': 'db exploded at https://api.hrtoffy.in'},
              }, 500)
            : ok(_me());
      case '$_org/benefits/claims':
        if (req.method != 'GET')
          return jsonResponse({
            'success': false,
            'error': {'message': 'unexpected write'},
          }, 500);
        return claimsFail
            ? jsonResponse({
                'success': false,
                'error': {'message': 'db exploded at https://api.hrtoffy.in'},
              }, 500)
            : ok({'items': claims, 'total': claims.length});
      case '$_org/benefits/catalog':
        return ok([
          {'id': 'b1', 'benefit_name': 'Medical', 'is_active': true},
        ]);
      case '$_org/grade-structures/limits/G3':
        return ok({'gradeCode': 'G3', 'benefitAnnualLimit': 50000});
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected ${req.url.path}'},
    }, 404);
  });
}

void main() {
  testWidgets(
    'loads the employee, claims, catalog and grade limit from the AWS API',
    (tester) async {
      _tall(tester);
      final s = await _session(
        claims: [
          _claim(
            'c2',
            'Dental check',
            date: '2026-10-07T00:00:00.000Z',
            claimed: '800.00',
            approved: '750.00',
            status: 'approved',
            name: 'Dental',
          ),
          _claim('c1', 'Glasses'),
        ],
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      final calls = s.requests.map((r) => '${r.method} ${r.path}').toList();
      expect(
        calls,
        containsAll([
          'GET $_org/employees/me',
          'GET $_org/benefits/claims',
          'GET $_org/benefits/catalog',
          'GET $_org/grade-structures/limits/G3',
        ]),
      );
      expect(
        s.requests.firstWhere((r) => r.path == '$_org/benefits/claims').query,
        {'employeeId': testEmployeeId},
      );
      expect(
        calls.where(
          (c) =>
              c.startsWith('POST') ||
              c.startsWith('PUT') ||
              c.startsWith('DELETE'),
        ),
        isEmpty,
      );

      expect(find.text('Dental check'), findsOneWidget);
      expect(find.text('Glasses'), findsOneWidget);
      expect(find.text('Dental'), findsOneWidget);
      expect(
        find.text('₹1250'),
        findsOneWidget,
      ); // not "₹1250.00" and not "₹1250.0"
      expect(find.text('₹800'), findsOneWidget);
      expect(find.text('Approved: ₹750'), findsOneWidget);
      expect(find.text('07 Oct 2026'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      // newest claim first
      expect(
        tester.getTopLeft(find.text('Dental check')).dy,
        lessThan(tester.getTopLeft(find.text('Glasses')).dy),
      );
    },
  );

  testWidgets('no claims shows the empty state', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No claims found.'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets('a failed claims load shows a safe message, not the raw error', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(claimsFail: true);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(
      find.text("Couldn't load your claims. Pull down to try again."),
      findsOneWidget,
    );
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('hrtoffy'), findsNothing);
  });

  testWidgets(
    'a failed employee load shows the same safe message and requests nothing else',
    (tester) async {
      _tall(tester);
      final s = await _session(meFails: true);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(
        find.text("Couldn't load your claims. Pull down to try again."),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
      expect(s.requests.map((r) => r.path), ['$_org/employees/me']);
    },
  );

  testWidgets(
    'claim submission is unavailable: the + button explains it and nothing is sent (and Supabase is never touched)',
    (tester) async {
      _tall(tester);
      final s = await _session(claims: [_claim('c1', 'Glasses')]);
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      final before = s.requests.length;

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(
        find.text(
          "Submitting benefit claims from the app isn't available yet. Please contact HR.",
        ),
        findsOneWidget,
      );
      expect(
        find.text('Submit Claim'),
        findsNothing,
      ); // the claim form is not opened
      expect(s.requests.length, before); // no request of any kind
    },
  );
}
