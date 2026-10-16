import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/benefits_repository.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/workflow_repository.dart';
import 'package:hrms_app/screens/benefits_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Env {
  _Env(this.session, this.events);
  final TestSession session;

  /// Every write in the order it happened: 'claim' then 'workflow'.
  final List<String> events;
}

final _bodies = <String, Map<String, dynamic>>{};

Future<_Env> _env({int? claimStatus, int? workflowStatus, Object? claimBody}) async {
  final events = <String>[];
  _bodies.clear();
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (p == '$_org/employees/me') {
      return ok({'id': testEmployeeId, 'organizationId': testOrgId, 'gradeCode': 'G3', 'managerId': 'mgr-1'});
    }
    if (p == '$_org/benefits/claims') {
      if (req.method == 'POST') {
        events.add('claim');
        _bodies['claim'] = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        if (claimStatus != null) {
          return jsonResponse({'success': false, 'error': {'message': 'server text that must not be shown'}}, claimStatus);
        }
        return ok(claimBody ?? {'claimId': 'claim-9'}, 201);
      }
      return ok({'items': <dynamic>[], 'total': 0});
    }
    if (p == '$_org/benefits/catalog') {
      return ok([
        {'id': 'b1', 'benefit_name': 'Meal Vouchers', 'is_active': true},
      ]);
    }
    if (p == '$_org/grade-structures/limits/G3') return ok({'gradeCode': 'G3', 'benefitAnnualLimit': 50000});
    if (p == '$_org/workflows/initialize' && req.method == 'POST') {
      events.add('workflow');
      _bodies['workflow'] = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      if (workflowStatus != null) return jsonResponse({'success': false, 'error': {'message': 'x'}}, workflowStatus);
      return ok({'id': 'exec-1'});
    }
    return jsonResponse({'success': false}, 404);
  });
  return _Env(s, events);
}

Future<void> _openAndSubmit(WidgetTester tester, _Env e) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: BenefitsScreen(
      userEmail: 'me@x.com',
      userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
      fetchHrmsContext: () async => {},
      benefitsRepository: BenefitsRepository(auth: e.session.auth),
      employeeRepository: EmployeeRepository(auth: e.session.auth),
      workflowRepository: WorkflowRepository(auth: e.session.auth),
      claimSubmissionEnabled: true, // tests only
    ),
  ));
  await _settle(tester);
  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Meal Vouchers').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Claim Amount (₹)'), '100');
  await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Team lunch with client');
  await tester.pump();
  final submit = find.widgetWithText(ElevatedButton, 'Submit Claim');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pump();
  await _settle(tester);
}

void main() {
  test('the + button is OFF in the app until the staging deployment has been verified (guard against enabling by accident)', () {
    expect(kBenefitClaimSubmissionEnabled, isFalse);
  });

  testWidgets('a stored claim gets its approval chain started, after it, for THAT claim id; the server sets the payroll fields', (tester) async {
    final e = await _env();
    await _openAndSubmit(tester, e);

    expect(e.events, ['claim', 'workflow'], reason: 'the claim is stored first, then its approval chain is started');
    expect(_bodies['claim'], {'employeeId': testEmployeeId, 'benefitId': 'b1', 'claimedAmount': 100, 'description': 'Team lunch with client'});
    expect(_bodies['claim']!.keys.any((k) => k.toLowerCase().contains('month') || k.toLowerCase().contains('year') || k == 'paymentMode'), isFalse,
        reason: 'claim month/year/payment mode belong to the server');
    expect(_bodies['workflow'], {'moduleName': 'benefits', 'recordId': 'claim-9'});
    expect(find.text('Claim submitted.'), findsOneWidget);
  });

  testWidgets('a failure to start the approval chain does NOT report the claim as failed', (tester) async {
    final e = await _env(workflowStatus: 500);
    await _openAndSubmit(tester, e);

    expect(e.events, ['claim', 'workflow']);
    expect(find.textContaining("Claim submitted. We couldn't confirm that approval routing started"), findsOneWidget);
    expect(find.text(kBenefitSubmitFailedMessage), findsNothing);
  });

  testWidgets('a claim the server refused never starts an approval chain and says so without the server text', (tester) async {
    final e = await _env(claimStatus: 400);
    await _openAndSubmit(tester, e);

    expect(e.events, ['claim']);
    expect(find.text(kBenefitSubmitFailedMessage), findsOneWidget);
    expect(find.textContaining('server text'), findsNothing);
    expect(find.text('Claim submitted.'), findsNothing);
  });

  testWidgets('a response without a claim id is a failed submission (no id means nothing can be tracked or approved)', (tester) async {
    final e = await _env(claimBody: {'ok': true});
    await _openAndSubmit(tester, e);
    expect(e.events, ['claim']);
    expect(find.text(kBenefitSubmitFailedMessage), findsOneWidget);
  });
}
