import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/profile_repository.dart';
import 'package:hrms_app/screens/manager/manager_benefits_screen.dart';

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
      home: ManagerBenefitsScreen(
        userEmail: 'm@x.com',
        userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
        fetchHrmsContext: () async => {},
        benefitsRepository: BenefitsRepository(auth: s.auth),
        employeeRepository: EmployeeRepository(auth: s.auth),
        profileRepository: ProfileRepository(auth: s.auth),
      ),
    );

final _boom = jsonResponse({'success': false, 'error': {'message': 'db exploded at https://api.hrtoffy.in'}}, 500);
final _year = DateTime.now().year;

Map<String, dynamic> _claim(String id, String desc, {Object? claimed = '1250.00', Object? approved, String status = 'pending', String name = 'Medical'}) => {
      'id': id,
      'description': desc,
      'claim_date': '$_year-03-05T00:00:00.000Z',
      'claim_year': _year,
      'claimed_amount': claimed,
      'approved_amount': approved,
      'status': status,
      'created_at': '$_year-03-05T09:00:00.000Z',
      'benefits_catalog': {'benefit_name': name, 'benefit_type': 'health'},
    };

Map<String, dynamic> _esi(String id, String name, {String status = 'pending'}) => {
      'id': id,
      'employee_id': 'emp-$id',
      'employee_name': name,
      'employee_code': 'E-$id',
      'department': 'Ops',
      'claim_type': 'esi',
      'is_esi_claim': true,
      'esi_benefit_type': 'sickness',
      'esi_start_date': '2026-09-01T00:00:00.000Z',
      'esi_end_date': '2026-09-05T00:00:00.000Z',
      'esi_days_claimed': 5,
      'claimed_amount': '0.00',
      'description': 'Fever',
      'status': status,
      'created_at': '2026-09-06T09:00:00.000Z',
    };

Future<TestSession> _session({
  Set<String> failing = const {},
  List<Map<String, dynamic>>? esi,
  List<Map<String, dynamic>>? claims,
  List<Map<String, dynamic>>? insurance,
  Object? gradeLimit = const {'gradeCode': 'G3', 'benefitAnnualLimit': '50000.00'},
}) {
  return signedIn((req) async {
    final path = req.url.path;
    if (req.method == 'POST' && path.startsWith('$_org/benefits/esi/claims/')) return ok({'id': 'x', 'status': 'manager_approved'});
    if (req.method != 'GET') return jsonResponse({'success': false, 'error': {'message': 'unexpected write'}}, 500);
    if (failing.contains(path)) return _boom;
    switch (path) {
      case '$_org/benefits/esi/claims':
        return ok(esi ?? [_esi('e1', 'Asha Rao'), _esi('e2', 'Ben Roy')]);
      case '$_org/employees/me':
        return ok({'id': testEmployeeId, 'organizationId': testOrgId, 'gradeCode': 'G3'});
      case '$_org/benefits/claims':
        final rows = claims ?? [_claim('c1', 'Glasses'), _claim('c2', 'Dental check', claimed: '800.00', approved: '750.00', status: 'approved', name: 'Dental')];
        return ok({'items': rows, 'total': rows.length});
      case '$_org/benefits/catalog':
        return ok([
          {'id': 'b1', 'benefit_name': 'Medical Reimbursement', 'is_active': true},
        ]);
      case '$_org/grade-structures/limits/G3':
        return ok(gradeLimit);
      case '$_org/insurance/policies':
        return ok(insurance ??
            [
              {'id': 'p1', 'insurance_type': 'health', 'provider_name': 'Star Health', 'policy_number': 'POL-77', 'sum_insured': '500000.00'},
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
  testWidgets('renders with Supabase uninitialised; the overview and cards are kept', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    for (final c in ['My Benefits', 'Submit Claim', 'LTA Claim', 'ESI Claims', 'ESI Guide', 'Approvals', 'ESI Approvals', 'My Insurance']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  testWidgets('own claims, catalog, grade limit and annual total come from the existing repositories', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    final calls = s.requests.map((r) => '${r.method} ${r.path}').toSet();
    expect(calls, {
      'GET $_org/employees/me',
      'GET $_org/benefits/claims',
      'GET $_org/benefits/esi/claims',
      'GET $_org/benefits/catalog',
      'GET $_org/grade-structures/limits/G3',
      'GET $_org/insurance/policies',
    });
    expect(s.requests.firstWhere((r) => r.path.endsWith('/benefits/claims')).query, {'employeeId': testEmployeeId});
    expect(s.requests.firstWhere((r) => r.path.endsWith('/benefits/esi/claims')).query, isEmpty); // the approvals queue is not own-scoped

    await _open(tester, 'My Benefits');
    expect(find.text('Glasses'), findsOneWidget);
    expect(find.text('Dental check'), findsOneWidget);
    expect(find.text('Medical Reimbursement'), findsOneWidget); // catalog
    expect(find.text('₹50,000'), findsOneWidget); // annual limit (decimal string from the API)
    expect(find.text('₹2,000'), findsOneWidget); // 1250 (claimed) + 750 (approved), per claimedTotalForYear
    expect(find.text('₹1,250'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
  });

  testWidgets('insurance is the signed-in employee\'s own, via the existing repository contract', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final q = s.requests.firstWhere((r) => r.path.endsWith('/insurance/policies')).query;
    expect(q, {'employeeId': testEmployeeId}); // never an organization-wide listing

    await _open(tester, 'My Insurance');
    expect(find.text('Star Health'), findsOneWidget);
    expect(find.text('POL-77'), findsOneWidget);
    expect(find.text('₹5,00,000'), findsOneWidget);
  });

  testWidgets('no claims and no policies are shown as empty, not as errors', (tester) async {
    _tall(tester);
    final s = await _session(claims: [], insurance: []);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _open(tester, 'My Benefits');
    expect(find.text('No benefit claims yet'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
    await tester.tap(find.text('Back to overview'));
    await _settle(tester);
    await _open(tester, 'My Insurance');
    expect(find.text('No Active Policies'), findsOneWidget);
  });

  testWidgets('unsupported sections show the unavailable state and trigger no write or upload', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final before = s.requests.length;

    for (final card in ['Submit Claim', 'LTA Claim', 'ESI Claims']) {
      await _open(tester, card);
      expect(find.text(kBenefitsUnavailableMessage), findsOneWidget, reason: card);
      expect(find.byType(TextFormField), findsNothing, reason: card); // no claim form
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      await tester.tap(find.text('Back to overview'));
      await _settle(tester);
    }
    expect(s.requests.skip(before).every((r) => r.method == 'GET' && r.path.endsWith('/benefits/esi/claims')), isTrue); // only the badge refresh
  });

  testWidgets('ESI Approvals badge is the real count; the general Approvals badge stays "-"; never a 0', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('2'), findsOneWidget); // two pending ESI claims
    expect(find.text('-'), findsOneWidget); // general benefit approvals have no route
    expect(find.text('0'), findsNothing);
  });

  testWidgets('ESI Approvals badge is "-" when the ESI list cannot be loaded, and absent for an empty queue', (tester) async {
    _tall(tester);
    final f = await _session(failing: {'$_org/benefits/esi/claims'});
    await tester.pumpWidget(_screen(f));
    await _settle(tester);
    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final e = await _session(esi: []);
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('ESI Approvals and Approvals open the benefit approvals: ESI claims and the other claims in two tabs', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    for (final card in ['ESI Approvals', 'Approvals']) {
      await _open(tester, card);
      expect(find.text('Asha Rao'), findsOneWidget, reason: card);
      expect(find.text('Ben Roy'), findsOneWidget, reason: card);
      expect(find.text('ESI claims'), findsOneWidget, reason: card);
      expect(find.text('Other claims'), findsOneWidget, reason: card);
      expect(find.text(kBenefitsUnavailableMessage), findsNothing);
      await tester.tap(find.text('Back to overview'));
      await _settle(tester);
    }
    expect(s.requests.every((r) => r.method == 'GET'), isTrue); // opening decides nothing
  });

  testWidgets('the ESI guide is static and no longer claims the user is (not) eligible', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final before = s.requests.length;
    await _open(tester, 'ESI Guide');
    expect(find.text('Types of ESI Benefits'), findsOneWidget);
    expect(find.textContaining('Eligible for ESI'), findsNothing);
    expect(s.requests.length, before);
  });

  group('errors show a fixed message, never the server text', () {
    testWidgets('claims', (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/benefits/claims'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await _open(tester, 'My Benefits');
      expect(find.text(kBenefitsLoadFailedMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.textContaining('₹0'), findsNothing);
    });

    testWidgets('insurance', (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/insurance/policies'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await _open(tester, 'My Insurance');
      expect(find.text(kBenefitsLoadFailedMessage), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('grade limit, catalog and profile failures show "-"/a fixed message, not zeros', (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/grade-structures/limits/G3', '$_org/benefits/catalog'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      await _open(tester, 'My Benefits');
      expect(find.textContaining(kBenefitsLoadFailedMessage), findsOneWidget); // the catalog line
      expect(find.text('-'), findsWidgets); // the annual limit is unknown
      expect(find.text('₹0'), findsNothing);
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.text('₹2,000'), findsOneWidget); // claims still load
    });

    testWidgets('an employee-profile failure leaves the limit unknown, not zero', (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/employees/me'});
      await tester.pumpWidget(_screen(s));
      await _settle(tester);
      expect(s.requests.any((r) => r.path.contains('grade-structures')), isFalse);
      await _open(tester, 'My Benefits');
      expect(find.text('₹50,000'), findsNothing);
      expect(find.text('₹0'), findsNothing);
    });
  });

  test('the screen has no Supabase, storage, upload, write or exception logging', () {
    final src = File('lib/screens/manager/manager_benefits_screen.dart').readAsStringSync();
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
      'BenefitApprovalPanel',
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
