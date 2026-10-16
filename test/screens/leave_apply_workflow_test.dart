import 'dart:convert';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/leave_repository.dart';
import 'package:hrms_app/repositories/workflow_repository.dart';
import 'package:hrms_app/screens/leaves_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Env {
  _Env(this.session, this.applied, this.workflowCalls);
  final TestSession session;
  final List<Map<String, dynamic>> applied;
  final List<Map<String, dynamic>> workflowCalls;
}

Future<_Env> _env({int? applyStatus, int? workflowStatus, Object? applyBody}) async {
  final applied = <Map<String, dynamic>>[];
  final workflowCalls = <Map<String, dynamic>>[];
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'GET' && p.endsWith('/leave-balances')) {
      return ok([
        {'leave_type_id': 'lt-1', 'leave_type_name': 'Casual Leave', 'allocated_days': '12.00', 'used_days': 2, 'remaining_days': 10, 'year': DateTime.now().year},
      ]);
    }
    if (req.method == 'POST' && p == '$_org/leaves/record-application') {
      applied.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
      if (applyStatus != null) {
        return jsonResponse({'success': false, 'error': {'message': 'Insufficient leave balance (server text)'}}, applyStatus);
      }
      return ok(applyBody ?? {'id': 'leave-1', 'status': 'pending'}, 201);
    }
    if (req.method == 'POST' && p == '$_org/workflows/initialize') {
      workflowCalls.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
      if (workflowStatus != null) return jsonResponse({'success': false, 'error': {'message': 'x'}}, workflowStatus);
      return ok({'id': 'exec-1'});
    }
    return jsonResponse({'success': false}, 404);
  });
  return _Env(s, applied, workflowCalls);
}

/// Opens the application form and applies for one day today.
Future<int> _applyOneDay(WidgetTester tester, _Env e) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var submittedCallbacks = 0;
  // The form is pushed on top of a parent screen, as in the app: it closes itself after a successful submit.
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: LeaveApplicationForm(
                    email: 'me@x.com',
                    onSubmitted: () => submittedCallbacks++,
                    repository: LeaveRepository(auth: e.session.auth),
                    workflowRepository: WorkflowRepository(auth: e.session.auth),
                  ),
                ),
              ),
            ),
            child: const Text('open form'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();

  await tester.tap(find.byType(DropdownButton2<String>));
  await _settle(tester);
  await tester.tap(find.text('Casual Leave (10 days)'));
  await _settle(tester);

  await tester.tap(find.text('From Date *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('To Date *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Reason *'), 'family function');
  await tester.pump();
  final submit = find.text('Submit Leave Application');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return submittedCallbacks;
}

void main() {
  testWidgets('after the application is stored, its approval chain is started for THAT application', (tester) async {
    final e = await _env();
    final callbacks = await _applyOneDay(tester, e);

    expect(e.applied, hasLength(1));
    expect(e.applied.single['leaveTypeId'], 'lt-1');
    expect(e.workflowCalls, [
      {'moduleName': 'leaves', 'recordId': 'leave-1'},
    ]);
    expect(find.text('Leave application submitted!'), findsOneWidget);
    expect(callbacks, 1);
  });

  testWidgets('a failure to start the approval chain does NOT report the application as failed', (tester) async {
    final e = await _env(workflowStatus: 500);
    final callbacks = await _applyOneDay(tester, e);

    expect(e.applied, hasLength(1), reason: 'the application was stored');
    expect(find.textContaining("Leave application submitted. We couldn't confirm that approval routing started"), findsOneWidget);
    expect(find.textContaining('Error:'), findsNothing);
    expect(callbacks, 1, reason: 'the leave list is refreshed: the application exists');
  });

  testWidgets('a rejected application never starts an approval chain', (tester) async {
    final e = await _env(applyStatus: 400);
    final callbacks = await _applyOneDay(tester, e);

    expect(e.workflowCalls, isEmpty);
    expect(find.textContaining('Error:'), findsOneWidget);
    expect(callbacks, 0);
  });

  testWidgets('when the server answers without an application id nothing is initialized and the application is still a success', (tester) async {
    final e = await _env(applyBody: {'status': 'pending'});
    final callbacks = await _applyOneDay(tester, e);

    expect(e.workflowCalls, isEmpty, reason: 'there is no record id to initialize');
    expect(find.textContaining("couldn't confirm that approval routing started"), findsOneWidget);
    expect(callbacks, 1);
  });
}
