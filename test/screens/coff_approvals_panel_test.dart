import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/coff_repository.dart';
import 'package:hrms_app/screens/manager/widgets/coff_approvals_panel.dart';
import 'package:http/http.dart' as http;

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

http.Response _fail(int status, [String msg = 'db exploded at https://x.in']) =>
    jsonResponse({
      'success': false,
      'error': {'message': msg},
    }, status);

Map<String, dynamic> _row(
  String id,
  String name,
  String status, {
  bool canDecide = false,
  String? role,
  String workType = 'holiday',
}) => {
  'id': id,
  'employee_id': 'emp-$id',
  'work_date': '2026-10-02',
  'work_type': workType,
  'holiday_name': workType == 'holiday' ? 'Gandhi Jayanti' : null,
  'hours_worked': '8.5',
  'status': status,
  'reason': 'Covered the release $id',
  'review_comments': status == 'pending' ? null : 'Noted $id',
  'credit_id': null,
  'employee_records': {
    'full_name': name,
    'employee_id': 'E-$id',
    'department': 'Ops',
  },
  'can_decide': canDecide,
  'required_role': role,
};

class _Server {
  _Server({
    this.pending = const [],
    this.history = const [],
    this.listStatus,
    this.decideStatus,
  });
  List<Map<String, dynamic>> pending;
  List<Map<String, dynamic>> history;
  int? listStatus;
  int? decideStatus;
  int listCalls = 0;

  Future<TestSession> session() => signedIn((req) async {
    if (req.url.path == '$_org/leaves/coff-requests' && req.method == 'GET') {
      listCalls++;
      if (listStatus != null) return _fail(listStatus!);
      final st = req.url.queryParameters['status'] ?? '';
      return ok(st == 'pending' ? pending : history);
    }
    if (req.url.path.endsWith('/decide')) {
      if (decideStatus != null) {
        return _fail(decideStatus!, 'Monthly C-Off cap reached (https://x.in)');
      }
      return ok({'id': 'x'});
    }
    return _fail(404, 'unexpected');
  }, empRole: 'manager');
}

void main() {
  group('CoffRepository', () {
    test('lists team requests with the exact query', () async {
      final srv = _Server(pending: [_row('a', 'Ann', 'pending')]);
      final s = await srv.session();
      final repo = CoffRepository(auth: s.auth);
      final p = await repo.teamRequests(history: false);
      await repo.teamRequests(history: true);
      expect(p.single['id'], 'a');
      expect(s.apiCalls[0].path, '$_org/leaves/coff-requests');
      expect(s.apiCalls[0].query, {'scope': 'team', 'status': 'pending'});
      expect(s.apiCalls[1].query, {
        'scope': 'team',
        'status': 'approved,rejected',
      });
    });

    test(
      'decide posts the decision; reject without a reason is refused',
      () async {
        final s = await _Server().session();
        final repo = CoffRepository(auth: s.auth);
        await repo.decide('a', approve: true);
        await repo.decide('b', approve: false, comments: ' no cover ');
        expect(s.apiCalls[0].path, '$_org/leaves/coff-requests/a/decide');
        expect(s.apiCalls[0].json, {'decision': 'approve'});
        expect(s.apiCalls[1].json, {
          'decision': 'reject',
          'comments': 'no cover',
        });
        await expectLater(
          repo.decide('c', approve: false, comments: '  '),
          throwsArgumentError,
        );
        expect(s.apiCalls.length, 2);
      },
    );
  });

  group('CoffApprovalsPanel', () {
    testWidgets('decidable rows first with buttons, others wait on the role', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        pending: [
          _row('w', 'Wes Waiting', 'pending', role: 'hr_manager'),
          _row('a', 'Ann Action', 'pending', canDecide: true),
        ],
        history: [_row('h', 'Hal History', 'approved')],
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);

      expect(find.text('Pending (2)'), findsOneWidget);
      expect(find.text('History (1)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Ann Action')).dy,
        lessThan(tester.getTopLeft(find.text('Wes Waiting')).dy),
      );
      expect(find.byKey(const ValueKey('approve-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('reject-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('approve-w')), findsNothing);
      expect(find.text('Waiting on HR manager'), findsOneWidget);
      expect(find.text('E-a · Ops'), findsOneWidget);
      expect(find.textContaining('Holiday (Gandhi Jayanti)'), findsWidgets);
      expect(find.text('8.50'), findsWidgets);
      expect(find.text('02 Oct 2026'), findsWidgets);
      expect(find.text('Covered the release a'), findsOneWidget);
      // no row-meta call
      expect(s.apiCalls.where((r) => r.path.endsWith('row-meta')), isEmpty);

      await tester.tap(find.text('History (1)'));
      await _settle(tester);
      expect(find.text('Hal History'), findsOneWidget);
      expect(find.text('Comments: Noted h'), findsOneWidget);
      expect(find.byKey(const ValueKey('approve-h')), findsNothing);
    });

    testWidgets('approve posts the decision and reloads', (tester) async {
      _tall(tester);
      final srv = _Server(
        pending: [_row('a', 'Ann', 'pending', canDecide: true)],
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);
      final before = srv.listCalls;
      await tester.tap(find.byKey(const ValueKey('approve-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-approve')));
      await _settle(tester);
      final post = s.apiCalls.singleWhere((r) => r.method == 'POST');
      expect(post.path, '$_org/leaves/coff-requests/a/decide');
      expect(post.json, {'decision': 'approve'});
      expect(srv.listCalls, greaterThan(before));
      expect(find.text('Request approved'), findsOneWidget);
    });

    testWidgets('reject needs a reason, then posts it', (tester) async {
      _tall(tester);
      final srv = _Server(
        pending: [_row('a', 'Ann', 'pending', canDecide: true)],
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('reject-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await tester.pumpAndSettle();
      expect(find.text('Please give a reason for rejecting.'), findsOneWidget);
      expect(s.apiCalls.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(find.byType(TextField), 'Not authorised');
      await tester.tap(find.byKey(const ValueKey('decision-reject')));
      await _settle(tester);
      final post = s.apiCalls.singleWhere((r) => r.method == 'POST');
      expect(post.json, {'decision': 'reject', 'comments': 'Not authorised'});
    });

    testWidgets('a 409 shows a safe message and the list reloads', (
      tester,
    ) async {
      _tall(tester);
      final srv = _Server(
        pending: [_row('a', 'Ann', 'pending', canDecide: true)],
        decideStatus: 409,
      );
      final s = await srv.session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);
      final before = srv.listCalls;
      await tester.tap(find.byKey(const ValueKey('approve-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decision-approve')));
      await _settle(tester);
      expect(find.textContaining('Monthly'), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
      expect(
        find.text(
          "This request couldn't be processed. Please refresh and try again.",
        ),
        findsOneWidget,
      );
      expect(srv.listCalls, greaterThan(before));
    });

    testWidgets('a 404 list (older server) shows the not-available message', (
      tester,
    ) async {
      _tall(tester);
      final s = await _Server(listStatus: 404).session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);
      expect(find.text(kCoffUnavailableMessage), findsOneWidget);
      expect(find.textContaining('unexpected'), findsNothing);
    });

    testWidgets('a failed list shows the generic message', (tester) async {
      _tall(tester);
      final s = await _Server(listStatus: 500).session();
      await tester.pumpWidget(
        _host(CoffApprovalsPanel(repository: CoffRepository(auth: s.auth))),
      );
      await _settle(tester);
      expect(
        find.text("Couldn't load requests. Please try again."),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
    });
  });
}
