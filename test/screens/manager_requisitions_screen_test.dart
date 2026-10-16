import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/requisitions_repository.dart';
import 'package:hrms_app/screens/manager/manager_requisitions_screen.dart';
import 'package:hrms_app/screens/manager/widgets/manager_state_views.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/recruitment/requisitions';

Widget _screen(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: ManagerRequisitionsScreen(
      userEmail: 'm@x.com',
      userData: const {
        'id': testEmployeeId,
        'organization_id': testOrgId,
        'emp_role': 'manager',
      },
      fetchHrmsContext: () async => {},
      requisitionsRepository: RequisitionsRepository(auth: s.auth),
    ),
  ),
);

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

Map<String, dynamic> _req(
  String id,
  String status, {
  String by = testEmployeeId,
  String? reason,
}) => {
  'id': id,
  'requisition_number': 'REQ-2026-000$id',
  'position_title': 'Engineer $id',
  'department': 'Tech',
  'number_of_positions': 2,
  'priority': 'high',
  'status': status,
  'requested_by': by,
  'requester_name': 'Asha Rao',
  'expected_joining_date': '2026-12-01',
  'rejection_reason': reason,
  'key_skills': ['Dart', 'SQL'],
};

/// A fake server: a mutable list, handles list/get/post/patch/submit/cancel.
class _Server {
  _Server(this.rows);
  List<Map<String, dynamic>> rows;
  int? statusForAll;

  Future<TestSession> session() => signedIn((req) async {
    if (statusForAll != null) {
      return jsonResponse({
        'success': false,
        'message': 'secret',
      }, statusForAll!);
    }
    final p = req.url.path;
    if (p == '/organizations/$testOrgId/employees/summaries') {
      return ok([
        {'id': 'e9', 'fullName': 'Boss One'},
      ]);
    }
    if (p == _base && req.method == 'GET') {
      final st = req.url.queryParameters['status'];
      final shown = rows.where((r) => st == null || r['status'] == st).toList();
      return ok({
        'items': shown,
        'total': shown.length,
        'page': 1,
        'limit': 20,
      });
    }
    if (p == _base && req.method == 'POST') {
      return ok({'id': '9', 'status': 'draft'}, 201);
    }
    final m = RegExp('^$_base/(\\w+)(/\\w+)?\$').firstMatch(p);
    if (m != null) {
      final r = rows.firstWhere((x) => x['id'] == m.group(1));
      if (m.group(2) == '/submit') r['status'] = 'pending_approval';
      if (m.group(2) == '/cancel') r['status'] = 'cancelled';
      return ok(r);
    }
    return jsonResponse({'success': false}, 404);
  });
}

void main() {
  testWidgets('lists cards with the key fields and filters by status', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([_req('1', 'draft'), _req('2', 'approved')]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text('REQ-2026-0001'), findsOneWidget);
    expect(find.text('Engineer 1'), findsOneWidget);
    expect(find.text('Draft'), findsNWidgets(2)); // chip + badge
    expect(find.text('High'), findsNWidgets(2));
    expect(find.textContaining('Requested by Asha Rao'), findsNWidgets(2));
    expect(find.textContaining('1 Dec 2026'), findsNWidgets(2));
    expect(find.textContaining('2 position(s)'), findsNWidgets(2));

    await t.tap(find.widgetWithText(ChoiceChip, 'Approved'));
    await _settle(t);
    expect(find.text('Engineer 1'), findsNothing);
    expect(find.text('Engineer 2'), findsOneWidget);
    expect(
      s.apiCalls.any((r) => r.path == _base && r.query['status'] == 'approved'),
      isTrue,
    );
    expect(s.apiCalls.any((r) => r.path.contains('decide')), isFalse);
  });

  testWidgets('Load more appears when total exceeds items', (t) async {
    _tall(t);
    final s = await signedIn((req) async {
      if (req.url.path != _base) return ok([]);
      final page = req.url.queryParameters['page'];
      return ok({
        'items': [page == '1' ? _req('1', 'draft') : _req('2', 'draft')],
        'total': 2,
        'page': int.parse(page!),
        'limit': 20,
      });
    });
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text('Engineer 2'), findsNothing);
    await t.tap(find.text('Load more'));
    await _settle(t);
    expect(find.text('Engineer 2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(s.apiCalls.last.query['page'], '2');
  });

  testWidgets('empty list says so', (t) async {
    final s = await signedIn(
      (req) async => ok({'items': [], 'total': 0, 'page': 1, 'limit': 20}),
    );
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text('No requisitions'), findsOneWidget);
  });

  testWidgets('404 says not available yet with Retry; 403 the role message', (
    t,
  ) async {
    final srv = _Server([])..statusForAll = 404;
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text(kRequisitionsNotAvailableYetMessage), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);

    final srv2 = _Server([])..statusForAll = 403;
    final s2 = await srv2.session();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_screen(s2));
    await _settle(t);
    expect(find.text(kRequisitionsUnavailableMessage), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('a server error shows a fixed message and Retry reloads', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([_req('1', 'draft')])..statusForAll = 500;
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
    srv.statusForAll = null;
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.text('Engineer 1'), findsOneWidget);
  });

  testWidgets('detail of my draft: Edit, Submit (confirmed) reloads', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([_req('1', 'draft')]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('Engineer 1'));
    await _settle(t);
    expect(find.text('Dart, SQL'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await t.tap(find.text('Submit'));
    await _settle(t);
    // dialog: refuse first
    await t.tap(find.text('Not now'));
    await _settle(t);
    expect(s.apiCalls.any((r) => r.path.endsWith('/submit')), isFalse);

    await t.tap(find.text('Submit'));
    await _settle(t);
    await t.tap(find.widgetWithText(TextButton, 'Submit'));
    await _settle(t);
    final submits = s.apiCalls.where((r) => r.path == '$_base/1/submit');
    expect(submits.length, 1);
    expect(submits.single.method, 'POST');
    expect(find.text('Pending Approval'), findsWidgets);
    expect(find.text('Edit'), findsNothing); // reloaded: no longer editable
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('cancel asks for confirmation then posts cancel', (t) async {
    _tall(t);
    final srv = _Server([_req('1', 'pending_approval')]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('Engineer 1'));
    await _settle(t);
    expect(find.text('Edit'), findsNothing); // pending: not editable
    expect(find.text('Submit'), findsNothing);
    await t.tap(find.text('Cancel'));
    await _settle(t);
    expect(s.apiCalls.any((r) => r.path.endsWith('/cancel')), isFalse);
    await t.tap(find.text('Cancel requisition'));
    await _settle(t);
    expect(s.apiCalls.where((r) => r.path == '$_base/1/cancel').length, 1);
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets(
    'rejected shows the reason and allows edit; not mine hides actions',
    (t) async {
      _tall(t);
      final srv = _Server([
        _req('1', 'rejected', reason: 'Budget frozen'),
        _req('2', 'draft', by: 'someone-else'),
      ]);
      final s = await srv.session();
      await t.pumpWidget(_screen(s));
      await _settle(t);
      await t.tap(find.text('Engineer 1'));
      await _settle(t);
      expect(find.text('Budget frozen'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await t.pageBack();
      await _settle(t);
      await t.tap(find.text('Engineer 2'));
      await _settle(t);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Submit'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    },
  );

  testWidgets('409 on submit shows a fixed message, never server text', (
    t,
  ) async {
    _tall(t);
    final s = await signedIn((req) async {
      final p = req.url.path;
      if (p == '$_base/1/submit') {
        return jsonResponse({'success': false, 'message': 'db secret'}, 409);
      }
      if (p == '$_base/1') return ok(_req('1', 'draft'));
      if (p == _base) {
        return ok({
          'items': [_req('1', 'draft')],
          'total': 1,
          'page': 1,
          'limit': 20,
        });
      }
      return ok([]);
    });
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('Engineer 1'));
    await _settle(t);
    await t.tap(find.text('Submit'));
    await _settle(t);
    await t.tap(find.widgetWithText(TextButton, 'Submit'));
    await _settle(t);
    expect(find.textContaining("can't be changed"), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('form validates, then Save draft posts without submit', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('New'));
    await _settle(t);

    await t.tap(find.text('Save draft'));
    await _settle(t);
    expect(find.text('Position title is required'), findsOneWidget);
    expect(s.apiCalls.any((r) => r.method == 'POST'), isFalse);

    await t.enterText(find.byKey(const Key('f_title')), 'QA Lead');
    await t.enterText(find.byKey(const Key('f_exp_min')), '5');
    await t.enterText(find.byKey(const Key('f_exp_max')), '2');
    await t.enterText(find.byKey(const Key('f_sal_min')), '-1');
    await t.enterText(find.byKey(const Key('f_currency')), 'RUPEE');
    await t.enterText(find.byKey(const Key('f_positions')), '501');
    await t.tap(find.text('Save draft'));
    await _settle(t);
    expect(find.text('Max must be at least min'), findsOneWidget);
    expect(find.text('Enter 0 or more'), findsOneWidget);
    expect(find.text('Use a 3-letter code'), findsOneWidget);
    expect(find.text('Enter a number from 1 to 500'), findsOneWidget);
    expect(s.apiCalls.any((r) => r.method == 'POST'), isFalse);

    await t.enterText(find.byKey(const Key('f_exp_max')), '8');
    await t.enterText(find.byKey(const Key('f_sal_min')), '100');
    await t.enterText(find.byKey(const Key('f_currency')), 'usd');
    await t.enterText(find.byKey(const Key('f_positions')), '3');
    await t.tap(find.text('Save draft'));
    await _settle(t);
    final post = s.apiCalls.firstWhere((r) => r.method == 'POST');
    expect(post.path, _base);
    expect(post.json['submit'], false);
    expect(post.json['position_title'], 'QA Lead');
    expect(post.json['number_of_positions'], 3);
    expect(post.json['currency'], 'USD');
    expect(post.json['experience_max'], 8);
    for (final k in ['requested_by', 'status', 'organization_id']) {
      expect((post.json as Map).containsKey(k), isFalse);
    }
  });

  testWidgets('Submit for approval on a new requisition sends submit true', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('New'));
    await _settle(t);
    await t.enterText(find.byKey(const Key('f_title')), 'Designer');
    await t.tap(find.text('Submit for approval'));
    await _settle(t);
    final post = s.apiCalls.firstWhere((r) => r.method == 'POST');
    expect(post.json['submit'], true);
    expect(find.text('New requisition'), findsNothing); // closed, list reloaded
  });

  testWidgets('editing a draft PATCHes then submit also POSTs submit', (
    t,
  ) async {
    _tall(t);
    final srv = _Server([_req('1', 'draft')]);
    final s = await srv.session();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('Engineer 1'));
    await _settle(t);
    await t.tap(find.text('Edit'));
    await _settle(t);
    expect(find.text('Edit requisition'), findsOneWidget);
    await t.enterText(find.byKey(const Key('f_title')), 'Senior Engineer');
    await t.tap(find.text('Submit for approval'));
    await _settle(t);
    final patch = s.apiCalls.firstWhere((r) => r.method == 'PATCH');
    expect(patch.path, '$_base/1');
    expect(patch.json['position_title'], 'Senior Engineer');
    expect((patch.json as Map).containsKey('submit'), isFalse);
    expect(
      s.apiCalls.any((r) => r.method == 'POST' && r.path == '$_base/1/submit'),
      isTrue,
    );
    expect(s.apiCalls.any((r) => r.path.contains('decide')), isFalse);
  });

  testWidgets('a 400 on save shows a fixed validation message', (t) async {
    _tall(t);
    final s = await signedIn((req) async {
      if (req.method == 'POST') {
        return jsonResponse({'success': false, 'message': 'raw zod'}, 400);
      }
      if (req.url.path == _base) {
        return ok({'items': [], 'total': 0, 'page': 1, 'limit': 20});
      }
      return ok([]);
    });
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('New'));
    await _settle(t);
    await t.enterText(find.byKey(const Key('f_title')), 'X');
    await t.tap(find.text('Save draft'));
    await _settle(t);
    expect(
      find.text('Please check the details and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw zod'), findsNothing);
  });
}
