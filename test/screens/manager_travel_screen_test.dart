import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/travel_repository.dart';
import 'package:hrms_app/screens/manager/manager_travel_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _screen(TestSession s) => MaterialApp(
      home: ManagerTravelScreen(
        userEmail: 'm@x.com',
        userData: const {'id': testEmployeeId, 'organization_id': testOrgId, 'emp_role': 'admin'},
        fetchHrmsContext: () async => {},
        travelRepository: TravelRepository(auth: s.auth),
      ),
    );

final _boom = jsonResponse({'success': false, 'error': {'message': 'db exploded at https://api.hrtoffy.in'}}, 500);

Map<String, dynamic> _claim(String id, {String? number = 'TRV-0001', String purpose = 'Client visit', String? destination = 'Pune', Object? total = '5400.50', String status = 'pending', String created = '2026-10-01T10:00:00.000Z', bool withTotal = true}) => {
      'id': id,
      'claim_number': number,
      'employee_id': testEmployeeId,
      'trip_purpose': purpose,
      'trip_destination': destination,
      'trip_from_date': '2026-10-07T00:00:00.000Z',
      'trip_to_date': '2026-10-09T00:00:00.000Z',
      if (withTotal) 'total_amount': total,
      'status': status,
      'created_at': created,
    };

Map<String, dynamic> _loan(String id, String number, {String category = 'travel_advance', String status = 'pending', Object? amount = '10000.00', String created = '2026-10-04T10:00:00.000Z'}) => {
      'id': id,
      'loan_number': number,
      'employee_id': testEmployeeId,
      'loan_category': category,
      'purpose': 'Trip float $number',
      'requested_amount': amount,
      'tenure_months': 3,
      'status': status,
      'created_at': created,
    };

Future<TestSession> _session({bool fail = false, bool failLoans = false, List<Map<String, dynamic>>? claims, List<Map<String, dynamic>>? loans}) {
  return signedIn((req) async {
    if (req.method == 'POST' && req.url.path == '$_org/loans/request') return ok({'loanId': 'adv-1'}, 201);
    if (req.method != 'GET') return jsonResponse({'success': false, 'error': {'message': 'unexpected write'}}, 500);
    if (req.url.path == '$_org/loans') {
      if (failLoans) return _boom;
      final rows = loans ??
          [
            _loan('l1', 'ADV-1', status: 'disbursed', amount: '10000.00'),
            _loan('l2', 'ADV-2', status: 'pending', amount: '5000.00', created: '2026-10-05T10:00:00.000Z'),
            _loan('l3', 'LOAN-9', category: 'personal_loan', amount: '99999.00'),
          ];
      return ok({'items': rows, 'total': rows.length});
    }
    if (req.url.path == '$_org/travel/claims') {
      if (fail) return _boom;
      return ok(claims ??
          [
            _claim('a', number: 'TRV-0003', purpose: 'Client visit', total: '5400.50', status: 'pending', created: '2026-10-03T10:00:00.000Z'),
            _claim('b', number: 'TRV-0002', purpose: 'Conference', destination: 'Goa', total: '12000', status: 'approved', created: '2026-10-02T10:00:00.000Z'),
            _claim('c', number: 'TRV-0001', purpose: 'Site audit', destination: 'Chennai', total: '800.00', status: 'pending', created: '2026-10-01T10:00:00.000Z'),
          ]);
    }
    return jsonResponse({'success': false, 'error': {'message': 'unexpected ${req.url.path}'}}, 404);
  });
}

void main() {
  testWidgets('renders with Supabase uninitialised and requests only the signed-in employee\'s claims', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    expect(s.requests.map((r) => '${r.method} ${r.path}').toSet(), {'GET $_org/travel/claims', 'GET $_org/loans'});
    for (final r in s.requests) {
      expect(r.query, {'employeeId': testEmployeeId}, reason: r.path); // never unscoped
    }
    expect(find.text('Unified Travel Hub'), findsOneWidget);
  });

  testWidgets('claim fields, dates, decimal amounts and the claim count display correctly', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    expect(find.text('TRV-0003'), findsOneWidget);
    expect(find.text('Client visit'), findsOneWidget);
    expect(find.text('Pune'), findsOneWidget);
    expect(find.text('2026-10-07 to 2026-10-09'), findsNWidgets(3));
    expect(find.text('LOAN-9'), findsNothing); // a personal loan is not a travel advance
    expect(find.text('03 Oct 2026'), findsOneWidget);
    expect(find.text('₹5,400.50'), findsOneWidget);
    expect(find.text('₹12,000.00'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    // newest first (repository order)
    expect(tester.getTopLeft(find.text('TRV-0003')).dy, lessThan(tester.getTopLeft(find.text('TRV-0001')).dy));
  });

  testWidgets('KPIs: claims, pending, advances and the outstanding (disbursed/active) advance amount are computed', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    // 3 claims, 2 pending (the pending advance is not a claim); 2 travel advances; only ADV-1 (10,000) is disbursed
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2)); // Pending claims and Total Advances
    expect(find.text('₹10,000.00'), findsAtLeastNWidgets(2)); // the Outstanding KPI and the advance card
    expect(find.text('-'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('₹0'), findsNothing);
  });

  testWidgets('a failed advances load shows "-" for Total Advances and Outstanding; the claims stay', (tester) async {
    _tall(tester);
    final s = await _session(failLoans: true);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('TRV-0003'), findsOneWidget);
    expect(find.textContaining("advances couldn't be loaded"), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    await tester.tap(find.text('Advances'));
    await _settle(tester);
    expect(find.text(kTravelAdvancesLoadFailedMessage), findsOneWidget);
    expect(find.text('No travel records found'), findsNothing);
  });

  testWidgets('an advance with an unusable amount shows "-" and Outstanding is unknown, never ₹0', (tester) async {
    _tall(tester);
    final s = await _session(claims: [], loans: [_loan('l1', 'ADV-1', status: 'active', amount: 0)]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('ADV-1'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    expect(find.text('₹0.00'), findsNothing);
    expect(find.text('-'), findsNWidgets(2)); // the advance's amount and the Outstanding KPI
  });

  testWidgets('a missing or non-numeric amount shows "-", never a zero', (tester) async {
    _tall(tester);
    final s = await _session(claims: [
      _claim('a', withTotal: false),
      _claim('b', total: 'n/a', created: '2026-09-01T10:00:00.000Z'),
    ]);
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('₹0.00'), findsNothing);
    expect(find.text('₹0'), findsNothing);
    // two unusable claim amounts (the advances are loaded, so their KPIs are not "-")
    expect(find.text('-'), findsNWidgets(2));
  });

  testWidgets('loading, empty and failure states are distinct; a failure is not an empty list', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final e = await _session(claims: [], loans: []);
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    expect(find.text('No travel records found'), findsOneWidget);
    expect(find.text(kTravelLoadFailedMessage), findsNothing);
    expect(find.text('0'), findsNWidgets(3)); // a real empty list: Total Claims 0, Pending 0, Total Advances 0

    await tester.pumpWidget(const SizedBox());
    final f = await _session(fail: true, failLoans: true);
    await tester.pumpWidget(_screen(f));
    await _settle(tester);
    expect(find.text(kTravelLoadFailedMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No travel records found'), findsNothing);
    expect(find.text('0'), findsNothing); // unknown, not zero
    expect(find.text('-'), findsNWidgets(4)); // all four KPIs
    expect(find.textContaining('exploded'), findsNothing);
    expect(find.textContaining('hrtoffy'), findsNothing);
  });

  testWidgets('without a signed-in employee no request is made and a fixed error is shown', (tester) async {
    _tall(tester);
    final s = await _session();
    await s.auth.logout();
    s.requests.clear();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text(kTravelLoadFailedMessage), findsOneWidget);
    expect(s.requests, isEmpty);
  });

  testWidgets('the Advances tab lists the travel advances, Settlements is unavailable, the Claims tab keeps the claims', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final before = s.requests.length;

    await tester.tap(find.text('Advances'));
    await _settle(tester);
    expect(find.text('ADV-1'), findsOneWidget);
    expect(find.text('ADV-2'), findsOneWidget);
    expect(find.text('₹5,000.00'), findsOneWidget);
    expect(find.text('TRV-0003'), findsNothing);
    expect(find.text(kTravelUnavailableMessage), findsNothing);

    await tester.tap(find.text('Settlements'));
    await _settle(tester);
    expect(find.text(kTravelUnavailableMessage), findsOneWidget);
    expect(find.text('Settle'), findsNothing);

    await tester.tap(find.text('Claims'));
    await _settle(tester);
    expect(find.text('TRV-0003'), findsOneWidget);
    expect(find.text('ADV-1'), findsNothing);
    expect(find.text(kTravelUnavailableMessage), findsNothing);
    expect(s.requests.length, before); // switching tabs requests nothing
  });

  testWidgets('New Claim opens the claim form and requests nothing by itself', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    final before = s.requests.length;
    await tester.tap(find.text('New Claim'));
    await _settle(tester);
    expect(find.text('New Travel Claim'), findsWidgets);
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text(kTravelUnavailableMessage), findsNothing);
    expect(s.requests.length, before);
  });

  testWidgets('Request Advance posts a travel_advance loan request for the signed-in employee, then reloads', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await tester.tap(find.text('Request Advance'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount (₹)'), '7500');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Pune trip float');
    await tester.tap(find.text('Submit request'));
    await _settle(tester);
    final post = s.requests.firstWhere((r) => r.method == 'POST');
    expect(post.path, '$_org/loans/request');
    expect(post.json, {'employeeId': testEmployeeId, 'amount': 7500.0, 'reason': 'Pune trip float', 'loanCategory': 'travel_advance'});
    expect(find.textContaining('Advance request submitted'), findsOneWidget);
    expect(s.requests.where((r) => r.method == 'GET' && r.path == '$_org/loans'), hasLength(2)); // initial + reload
  });

  test('the screen has no Supabase, storage, edge function, RPC, write or exception logging', () {
    final src = File('lib/screens/manager/manager_travel_screen.dart').readAsStringSync();
    for (final banned in [
      'supabase',
      'Supabase',
      'storage',
      'file_picker',
      'dart:io',
      'dart:convert',
      'salary-encryption',
      'scan-receipt',
      'initialize_workflow',
      '.rpc(',
      '.functions',
      '.insert(',
      '.update(',
      '.upsert(',
      '.delete(',
      '.upload(',
      'base64',
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
