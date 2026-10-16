import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/leave_repository.dart';
import 'package:hrms_app/screens/leaves_screen.dart';

import '../helpers/test_auth.dart';

const _leaves = '/organizations/$testOrgId/employees/$testEmployeeId/leaves';

Future<void> _settle(WidgetTester t) async {
  // the skeleton animates forever, so settle in bounded steps
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, TestSession s) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: LeaveCalendarTab(email: 'me@x.com', reloadTrigger: 0, repository: LeaveRepository(auth: s.auth))),
  ));
  await _settle(tester);
}

void main() {
  group('leave history load error', () {
    testWidgets('a 404 shows the history-specific message and Retry, never the server text', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _leaves) return jsonResponse({'success': false, 'error': {'message': 'Route GET:/leaves not found'}}, 404);
        return jsonResponse({'success': false}, 404);
      });
      await _open(tester, s);

      expect(find.text("Leave history isn't available right now. Please try again later."), findsOneWidget);
      expect(find.textContaining('Route GET'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry after a 404 reloads the calendar', (tester) async {
      var calls = 0;
      final s = await signedIn((req) async {
        calls++;
        if (calls == 1) return jsonResponse({'success': false}, 404);
        return ok({'items': <dynamic>[], 'total': 0, 'limit': 200, 'offset': 0});
      });
      await _open(tester, s);
      expect(find.textContaining("Leave history isn't available"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.textContaining("Leave history isn't available"), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a history that loads and is EMPTY is a normal calendar with a plain note, not an error', (tester) async {
      final s = await signedIn((req) async => ok({'items': <dynamic>[], 'total': 0, 'limit': 200, 'offset': 0}));
      await _open(tester, s);

      expect(find.text('You have no leave applications in this period.'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget, reason: 'the calendar and its legend are shown');
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining("isn't available"), findsNothing);
    });

    testWidgets('a populated history shows the calendar without the empty note', (tester) async {
      final now = DateTime.now();
      final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-15';
      final s = await signedIn((req) async => ok({
            'items': [
              {'id': 'p1', 'leave_type': 'Casual Leave', 'from_date': day, 'to_date': day, 'total_days': 1, 'reason': 'trip', 'status': 'approved'},
            ],
            'total': 1,
            'limit': 200,
            'offset': 0,
          }));
      await _open(tester, s);
      expect(find.text('You have no leave applications in this period.'), findsNothing);
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('401 and 403 each say what happened, never the server text', (tester) async {
      for (final entry in {401: 'Session expired', 403: 'permission'}.entries) {
        final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'server text that must not be shown'}}, entry.key));
        await tester.pumpWidget(const SizedBox());
        await _open(tester, s);
        expect(find.textContaining(entry.value), findsOneWidget, reason: 'HTTP ${entry.key}');
        expect(find.textContaining('server text'), findsNothing);
        expect(find.textContaining("Leave history isn't available"), findsNothing, reason: 'that wording is only for a 404');
      }
    });

    testWidgets('other failures keep their existing messages (a 5xx still says the server is busy)', (tester) async {
      final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'boom'}}, 500));
      await _open(tester, s);

      expect(find.textContaining('server is busy'), findsOneWidget);
      expect(find.textContaining("Leave history isn't available"), findsNothing);
    });
  });

  group('leaveHistoryErrorMessage vs the shared friendlyLeaveError', () {
    test('only the history message changes for a 404', () {
      const notFound = ApiException(404, 'Leave application not found');
      expect(leaveHistoryErrorMessage(notFound), "Leave history isn't available right now. Please try again later.");
      // apply / cancel keep using the shared helper, which is unchanged: a 404 there still shows the server message
      expect(friendlyLeaveError(notFound), 'Leave application not found');
    });

    test('every other error is exactly what the shared helper returns', () {
      for (final e in <Object>[
        const ApiException(0, 'SocketException: x'),
        const ApiException(401, 'x'),
        const ApiException(403, 'x'),
        const ApiException(400, 'Insufficient leave balance'),
        const ApiException(500, 'boom Bearer abc'),
        Exception('Bearer secret-token'),
      ]) {
        expect(leaveHistoryErrorMessage(e), friendlyLeaveError(e));
      }
    });
  });
}
