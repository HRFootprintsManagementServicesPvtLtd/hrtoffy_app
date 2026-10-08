import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/leave_repository.dart';
import 'package:hrms_app/screens/leaves_screen.dart';
import 'package:hrms_app/services/leave_summary_service.dart';

import '../helpers/test_auth.dart';

const _leaves = '/organizations/$testOrgId/employees/$testEmployeeId/leaves';

/// Mid-month so the day number is never shown twice (adjacent-month overflow days are 1-6 / 25-31).
DateTime get _day => DateTime(DateTime.now().year, DateTime.now().month, 15);

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _row(String id, String status) => {
      'id': id,
      'leave_type': 'Casual Leave',
      'from_date': _ymd(_day),
      'to_date': _ymd(_day),
      'total_days': 1,
      'reason': 'trip',
      'status': status,
      'manager_name': 'Maya Manager',
      'manager_email': 'maya@x.test',
    };

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A tall screen so the day sheet shows every card (it is a lazily built list).
void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  // the skeleton animates forever, so settle in bounded steps
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  summaryTests();
  group('LeaveCalendarTab', () {
    testWidgets('day sheet: a pending request can be cancelled, a cancelled one is grey and has no cancel button', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async {
        if (req.method == 'PUT') return ok({'id': 'p1', 'status': 'cancelled'});
        return ok({'items': [_row('p1', 'pending'), _row('c1', 'cancelled')], 'total': 2, 'limit': 200, 'offset': 0});
      });
      var changed = 0;
      await tester.pumpWidget(_app(LeaveCalendarTab(
        email: 'me@x.com',
        reloadTrigger: 0,
        onChanged: () => changed++,
        repository: LeaveRepository(auth: s.auth),
      )));
      await _settle(tester);

      // calendar history is requested for the window, paged, with date-only bounds
      final call = s.apiCalls.first;
      expect(call.path, _leaves);
      expect(call.query['limit'], '200');
      expect(call.query['from'], matches(r'^\d{4}-\d{2}-\d{2}$'));

      await tester.tap(find.text('15'));
      await _settle(tester);

      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Manager Details'), findsNWidgets(2));
      expect(find.text('Name: Maya Manager'), findsNWidgets(2));
      // only the pending one offers Cancel
      expect(find.widgetWithText(OutlinedButton, 'Cancel request'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
      await _settle(tester);
      expect(find.text('Cancel leave request'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel request'));
      await _settle(tester);

      final put = s.requests.where((r) => r.method == 'PUT').single;
      expect(put.path, '/organizations/$testOrgId/leaves/applications/p1');
      expect(put.json, {'status': 'cancelled'});
      expect(changed, 1, reason: 'the Summary must refresh after a cancel');
      expect(find.text('Leave request cancelled'), findsOneWidget);
    });

    testWidgets('declining the confirmation sends nothing', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async => ok({'items': [_row('p1', 'pending')], 'total': 1, 'limit': 200, 'offset': 0}));
      await tester.pumpWidget(_app(LeaveCalendarTab(email: 'me@x.com', reloadTrigger: 0, repository: LeaveRepository(auth: s.auth))));
      await _settle(tester);
      await tester.tap(find.text('15'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
      await _settle(tester);
      await tester.tap(find.text('Keep it'));
      await _settle(tester);
      expect(s.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('a refused cancel shows a safe message and does not refresh', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async {
        if (req.method == 'PUT') {
          return jsonResponse({'success': false, 'error': {'code': 'FORBIDDEN', 'message': 'Only a pending leave request can be cancelled'}}, 403);
        }
        return ok({'items': [_row('p1', 'pending')], 'total': 1, 'limit': 200, 'offset': 0});
      });
      var changed = 0;
      await tester.pumpWidget(_app(LeaveCalendarTab(email: 'me@x.com', reloadTrigger: 0, onChanged: () => changed++, repository: LeaveRepository(auth: s.auth))));
      await _settle(tester);
      await tester.tap(find.text('15'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel request'));
      await _settle(tester);
      expect(changed, 0);
      expect(find.textContaining("You don't have permission"), findsOneWidget);
    });

    testWidgets('a load failure shows a message and Retry; Retry loads the calendar', (tester) async {
      _tall(tester);
      var calls = 0;
      final s = await signedIn((req) async {
        calls++;
        if (calls == 1) return jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'boom'}}, 500);
        return ok({'items': [_row('p1', 'approved')], 'total': 1, 'limit': 200, 'offset': 0});
      });
      await tester.pumpWidget(_app(LeaveCalendarTab(email: 'me@x.com', reloadTrigger: 0, repository: LeaveRepository(auth: s.auth))));
      await _settle(tester);
      expect(find.textContaining('server is busy'), findsOneWidget);
      expect(find.text('boom'), findsNothing, reason: 'raw server text is not shown for a 5xx');
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Approved'), findsOneWidget); // legend: the calendar is back
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });

  group('LeaveApplicationForm', () {
    testWidgets("lists the leave types from this year's balances as 'Name (N days)'", (tester) async {
      _tall(tester);
      final s = await signedIn((req) async => ok([
            {'leave_type_id': 'lt-1', 'leave_type_name': 'Casual Leave', 'allocated_days': '12.00', 'used_days': 2, 'remaining_days': 10, 'year': 2026},
            {'leave_type_id': 'lt-2', 'leave_type_name': 'Sick Leave', 'allocated_days': '6.00', 'used_days': 0, 'remaining_days': 5.5, 'year': 2026},
          ]));
      await tester.pumpWidget(_app(LeaveApplicationForm(email: 'me@x.com', repository: LeaveRepository(auth: s.auth))));
      await _settle(tester);
      expect(s.apiCalls.single.path, '/organizations/$testOrgId/employees/$testEmployeeId/leave-balances');
      await tester.tap(find.byType(DropdownButton2<String>));
      await _settle(tester);
      expect(find.text('Casual Leave (10 days)'), findsOneWidget);
      expect(find.text('Sick Leave (5.5 days)'), findsOneWidget);
    });

    testWidgets('a balances failure shows a safe message instead of silently offering nothing', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'raw'}}, 500));
      await tester.pumpWidget(_app(LeaveApplicationForm(email: 'me@x.com', repository: LeaveRepository(auth: s.auth))));
      await _settle(tester);
      expect(find.textContaining('server is busy'), findsOneWidget);
    });
  });
}

// Summary tab: error + retry, and the numbers it shows.
void summaryTests() {
  group('LeaveSummaryCards', () {
    testWidgets('shows the totals from the API', (tester) async {
      _tall(tester);
      final s = await signedIn((req) async {
        if (req.url.path.endsWith('/leave-balances')) {
          return ok([
            {'leave_type_id': 'lt-1', 'leave_type_name': 'Casual Leave', 'allocated_days': '12.00', 'used_days': 2, 'remaining_days': 10, 'year': 2026},
          ]);
        }
        return ok({'items': [], 'total': 4, 'limit': 1, 'offset': 0});
      });
      final svc = LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth));
      await tester.pumpWidget(_app(LeaveSummaryCards(email: 'me@x.com', reloadTrigger: 0, service: svc)));
      await _settle(tester);
      expect(find.text('Leaves Allocated'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('4'), findsWidgets); // pending requests
    });

    testWidgets('a failure shows a safe message and Retry reloads', (tester) async {
      _tall(tester);
      var failing = true;
      final s = await signedIn((req) async {
        if (failing) return jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'boom'}}, 500);
        if (req.url.path.endsWith('/leave-balances')) {
          return ok([
            {'leave_type_id': 'lt-1', 'leave_type_name': 'Casual Leave', 'allocated_days': 12, 'used_days': 2, 'remaining_days': 10, 'year': 2026},
          ]);
        }
        return ok({'items': [], 'total': 0, 'limit': 1, 'offset': 0});
      });
      final svc = LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth));
      await tester.pumpWidget(_app(LeaveSummaryCards(email: 'me@x.com', reloadTrigger: 0, service: svc)));
      await _settle(tester);
      expect(find.textContaining('server is busy'), findsOneWidget);
      expect(find.text('boom'), findsNothing);
      failing = false;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Leaves Allocated'), findsOneWidget);
    });
  });
}
