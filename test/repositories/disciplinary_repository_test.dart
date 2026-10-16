import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/disciplinary_repository.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/disciplinary/cases';

void main() {
  test('cases reads the paged list with limit/page and no write', () async {
    final s = await signedIn((req) async {
      expect(req.url.path, _base);
      return ok({
        'items': [
          {
            'id': 'c1',
            'caseNumber': 'DC-1',
            'employee_id': 'e1',
            'status': 'issued',
          },
        ],
        'total': 1,
        'page': 1,
        'limit': 200,
      });
    });
    final rows = await DisciplinaryRepository(auth: s.auth).cases();
    expect(rows.single['case_number'], 'DC-1');
    expect(s.apiCalls.single.query['limit'], '200');
    expect(s.apiCalls.single.query['page'], '1');
    expect(s.apiCalls.single.query.containsKey('status'), isFalse);
    expect(s.apiCalls.every((r) => r.method == 'GET'), isTrue);
  });

  test('cases passes status and follows pages until total', () async {
    var calls = 0;
    final s = await signedIn((req) async {
      calls++;
      final n = req.url.queryParameters['page'] == '1' ? 200 : 5;
      return ok({
        'items': [
          for (var i = 0; i < n; i++) {'id': 'c$calls-$i'},
        ],
        'total': 205,
      });
    });
    final rows = await DisciplinaryRepository(
      auth: s.auth,
    ).cases(status: 'closed');
    expect(rows.length, 205);
    expect(calls, 2);
    expect(s.apiCalls.first.query['status'], 'closed');
  });

  test('tolerates a bare list and a missing body', () async {
    final s = await signedIn(
      (req) async => ok([
        {'id': 'c1'},
      ]),
    );
    expect((await DisciplinaryRepository(auth: s.auth).cases()).length, 1);
    final s2 = await signedIn((req) async => ok(null));
    expect(await DisciplinaryRepository(auth: s2.auth).cases(), isEmpty);
    expect(await DisciplinaryRepository(auth: s2.auth).caseById('x'), isEmpty);
  });

  test(
    'caseById, actions, responses and employeeNames use GET routes',
    () async {
      final s = await signedIn((req) async {
        switch (req.url.path) {
          case '$_base/c1':
            return ok({'id': 'c1', 'case_number': 'DC-1'});
          case '$_base/c1/actions':
            return ok([
              {'action_type': 'written_warning'},
            ]);
          case '$_base/c1/responses':
            return ok([
              {'response_text': 'sorry'},
            ]);
          case '/organizations/$testOrgId/employees/summaries':
            return ok([
              {'id': 'e1', 'fullName': 'Asha Rao'},
            ]);
        }
        return jsonResponse({'success': false}, 404);
      });
      final r = DisciplinaryRepository(auth: s.auth);
      expect((await r.caseById('c1'))['case_number'], 'DC-1');
      expect((await r.actions('c1')).single['action_type'], 'written_warning');
      expect((await r.responses('c1')).single['response_text'], 'sorry');
      expect(await r.employeeNames(), {'e1': 'Asha Rao'});
      expect(s.apiCalls.every((c) => c.method == 'GET'), isTrue);
    },
  );

  test('a 403 surfaces as a forbidden ApiException', () async {
    final s = await signedIn(
      (req) async => jsonResponse({'success': false, 'message': 'no'}, 403),
    );
    expect(
      DisciplinaryRepository(auth: s.auth).cases(),
      throwsA(
        isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
      ),
    );
  });
}
