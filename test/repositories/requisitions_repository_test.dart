import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/requisitions_repository.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/recruitment/requisitions';
const _forbidden = [
  'requested_by',
  'status',
  'organization_id',
  'id',
  'requisition_number',
];

void main() {
  test('list reads page/limit/status and maps the page', () async {
    final s = await signedIn((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, _base);
      return ok({
        'items': [
          {'id': 'r1', 'requisitionNumber': 'REQ-2026-0001', 'status': 'draft'},
        ],
        'page': 2,
        'limit': 20,
        'total': 41,
      });
    });
    final repo = RequisitionsRepository(auth: s.auth);
    final p = await repo.list(status: 'draft', page: 2);
    expect(p.items.single['requisition_number'], 'REQ-2026-0001');
    expect(p.total, 41);
    expect(p.page, 2);
    final q = s.apiCalls.single.query;
    expect(q['status'], 'draft');
    expect(q['page'], '2');
    expect(q['limit'], '20');
    await repo.list(limit: 500);
    expect(s.apiCalls.last.query['limit'], '100');
    expect(s.apiCalls.last.query.containsKey('status'), isFalse);
  });

  test('byId, submit and cancel use the exact paths with no body', () async {
    final s = await signedIn((req) async => ok({'id': 'r1', 'status': 'x'}));
    final repo = RequisitionsRepository(auth: s.auth);
    await repo.byId('r1');
    await repo.submit('r1');
    await repo.cancel('r1');
    expect(s.apiCalls.map((c) => '${c.method} ${c.path}').toList(), [
      'GET $_base/r1',
      'POST $_base/r1/submit',
      'POST $_base/r1/cancel',
    ]);
    expect(s.apiCalls[1].body, isEmpty);
    expect(s.apiCalls[2].body, isEmpty);
  });

  test('create sends submit flag and never a forbidden key', () async {
    final s = await signedIn((req) async => ok({'id': 'r1'}, 201));
    final repo = RequisitionsRepository(auth: s.auth);
    final fields = {
      'position_title': 'Engineer',
      'number_of_positions': 2,
      'requested_by': 'me',
      'status': 'approved',
      'organization_id': 'o',
    };
    await repo.create(fields);
    await repo.create(fields, submit: true);
    final a = s.apiCalls[0];
    final b = s.apiCalls[1];
    expect(a.method, 'POST');
    expect(a.path, _base);
    expect(a.json, {
      'position_title': 'Engineer',
      'number_of_positions': 2,
      'submit': false,
    });
    expect(b.json['submit'], true);
    for (final c in s.apiCalls) {
      for (final k in _forbidden) {
        expect((c.json as Map).containsKey(k), isFalse, reason: k);
      }
    }
  });

  test('update patches only allowed keys and never submit', () async {
    final s = await signedIn((req) async => ok({'id': 'r1'}));
    await RequisitionsRepository(
      auth: s.auth,
    ).update('r1', {'position_title': 'New', 'submit': true, 'status': 'x'});
    final c = s.apiCalls.single;
    expect(c.method, 'PATCH');
    expect(c.path, '$_base/r1');
    expect(jsonDecode(c.body), {'position_title': 'New'});
  });

  test('never calls decide; there is no decide method', () async {
    final s = await signedIn((req) async => ok({'id': 'r1'}));
    final repo = RequisitionsRepository(auth: s.auth);
    await repo.list();
    await repo.byId('r1');
    await repo.create({'position_title': 'a'});
    await repo.update('r1', {'position_title': 'b'});
    await repo.submit('r1');
    await repo.cancel('r1');
    expect(s.apiCalls.any((c) => c.path.contains('decide')), isFalse);
  });

  test('isMine matches the employee id or user id', () async {
    final s = await signedIn((req) async => ok(null));
    final repo = RequisitionsRepository(auth: s.auth);
    expect(repo.isMine(testEmployeeId), isTrue);
    expect(repo.isMine(testUserId), isTrue);
    expect(repo.isMine('someone-else'), isFalse);
    expect(repo.isMine(null), isFalse);
  });

  test('errors surface as ApiException with their status', () async {
    for (final code in [403, 404, 409, 400]) {
      final s = await signedIn(
        (req) async => jsonResponse({'success': false, 'message': 'x'}, code),
      );
      expect(
        RequisitionsRepository(auth: s.auth).submit('r1'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', code)),
      );
    }
  });
}
