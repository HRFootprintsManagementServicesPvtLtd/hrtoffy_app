import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/expense_repository.dart';
import 'package:hrms_app/repositories/travel_repository.dart' show ReceiptFile;

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _cat(String id, String name, Object? limit) => {
  'id': id,
  'name': name,
  'monthly_limit': limit,
  'is_active': true,
};

Map<String, dynamic> _claim(
  String id, {
  String? categoryId,
  String created = '2026-10-01T10:00:00.000Z',
  Object? amount = '750.00',
}) => {
  'id': id,
  'claim_number': null,
  'title': 'Client lunch',
  'category_id': categoryId,
  'amount': amount,
  'status': 'pending',
  'expense_date': '2026-10-05T00:00:00.000Z',
  'created_at': created,
};

void main() {
  group('ExpenseRepository.categories', () {
    test(
      'GET /expenses/categories; monthly_limit strings become numbers',
      () async {
        final s = await signedIn(
          (req) async =>
              ok([_cat('c1', 'Travel', '5000.00'), _cat('c2', 'Food', null)]),
        );
        final list = await ExpenseRepository(auth: s.auth).categories();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/expenses/categories');
        expect(list.map((c) => c['name']), ['Travel', 'Food']);
        expect(list.first['monthly_limit'], 5000);
        expect(list.last['monthly_limit'], isNull);
      },
    );
  });

  group('ExpenseRepository.claims', () {
    test(
      'GET /expenses?employeeId=<own>; decimals become numbers; newest first',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _claim('old', created: '2026-09-01T00:00:00.000Z'),
            _claim('new'),
          ]),
        );
        final rows = await ExpenseRepository(auth: s.auth).claims();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/expenses');
        expect(s.last.query, {'employeeId': testEmployeeId});
        expect(rows.map((r) => r['id']), ['new', 'old']);
        expect(rows.first['amount'], 750);
        expect(rows.first['expense_date'], '2026-10-05');
        expect(
          rows.first['claim_number'],
          isNull,
        ); // left as the server returns it
      },
    );

    test(
      'category_id is mapped to category_name from the loaded categories',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _claim('a', categoryId: 'c1'),
            _claim('b', categoryId: 'unknown'),
            _claim('c'),
          ]),
        );
        final rows = await ExpenseRepository(auth: s.auth).claims(
          categories: [_cat('c1', 'Travel', 100), _cat('c2', 'Food', 0)],
        );
        expect(
          rows.firstWhere((r) => r['id'] == 'a')['category_name'],
          'Travel',
        );
        expect(
          rows.firstWhere((r) => r['id'] == 'b').containsKey('category_name'),
          isFalse,
        );
        expect(
          rows.firstWhere((r) => r['id'] == 'c').containsKey('category_name'),
          isFalse,
        );
      },
    );

    test('withCategoryNames does not change claims without a match', () {
      final out = ExpenseRepository.withCategoryNames([_claim('a')], const []);
      expect(out.single, _claim('a'));
    });

    test('empty list and API errors', () async {
      final s = await signedIn((req) async => ok([]));
      expect(await ExpenseRepository(auth: s.auth).claims(), isEmpty);
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'No'},
        }, 500),
      );
      await expectLater(
        ExpenseRepository(auth: f.auth).claims(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isServerError,
            'server error',
            true,
          ),
        ),
      );
    });
  });

  group('ExpenseRepository.createClaim', () {
    test(
      'POST /expenses with the lines in the same request and no other calls',
      () async {
        final s = await signedIn(
          (req) async =>
              ok({'id': 'e1', 'amount': '300.00', 'status': 'pending'}, 201),
        );
        final claim = await ExpenseRepository(auth: s.auth).createClaim(
          title: 'Client lunch',
          description: 'Q3 visit',
          categoryId: 'c1',
          lines: const [
            ExpenseLine(
              expenseDate: '2026-10-05',
              description: ' Lunch ',
              amount: 200,
            ),
            ExpenseLine(
              expenseDate: '2026-10-06',
              description: 'Cab',
              amount: 100.5,
            ),
          ],
        );
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/expenses');
        expect(s.last.json, {
          'employeeId': testEmployeeId,
          'title': 'Client lunch',
          'description': 'Q3 visit',
          'categoryId': 'c1',
          'items': [
            {
              'expense_date': '2026-10-05',
              'description': 'Lunch',
              'amount': 200.0,
              'receipt_url': null,
            },
            {
              'expense_date': '2026-10-06',
              'description': 'Cab',
              'amount': 100.5,
              'receipt_url': null,
            },
          ],
        });
        expect(claim['id'], 'e1');
        expect(claim['amount'], 300);
      },
    );

    test('empty lines are skipped; with none left nothing is sent', () async {
      final s = await signedIn((req) async => ok({'id': 'e1'}, 201));
      final repo = ExpenseRepository(auth: s.auth);
      await repo.createClaim(
        title: 't',
        lines: const [
          ExpenseLine(expenseDate: '2026-10-05', description: '', amount: 10),
          ExpenseLine(expenseDate: '2026-10-05', description: 'x', amount: 0),
          ExpenseLine(expenseDate: '2026-10-05', description: 'ok', amount: 5),
        ],
      );
      expect((s.last.json['items'] as List), hasLength(1));
      expect((s.last.json as Map).containsKey('categoryId'), isFalse);
      expect((s.last.json as Map).containsKey('description'), isFalse);

      final before = s.requests.length;
      await expectLater(
        repo.createClaim(
          title: 't',
          lines: const [
            ExpenseLine(expenseDate: '2026-10-05', description: '', amount: 0),
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(s.requests.length, before);
    });

    test(
      'receipts are uploaded to expense-receipts and the file reference goes into receipt_url',
      () async {
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/files') {
            return ok({
              'bucket': 'expense-receipts',
              'path': '$testEmployeeId/a.png',
              'ref': 'expense-receipts/$testEmployeeId/a.png',
              'url': null,
              'size': 3,
            }, 201);
          }
          return ok({'id': 'e1'}, 201);
        });
        await ExpenseRepository(auth: s.auth).createClaim(
          title: 't',
          lines: const [
            ExpenseLine(
              expenseDate: '2026-10-05',
              description: 'Taxi',
              amount: 50,
              receipt: ReceiptFile(
                bytes: [1, 2, 3],
                name: 'a.png',
                contentType: 'image/png',
              ),
            ),
            ExpenseLine(
              expenseDate: '2026-10-05',
              description: 'Tea',
              amount: 5,
            ),
          ],
        );
        final upload = s.apiCalls.first;
        expect(upload.path, '$_org/files');
        expect(upload.query['bucket'], 'expense-receipts');
        final items = s.last.json['items'] as List;
        expect(
          items[0]['receipt_url'],
          'expense-receipts/$testEmployeeId/a.png',
        );
        expect(items[1]['receipt_url'], isNull);
        expect(s.last.path, '$_org/expenses');
      },
    );

    test('a refused create surfaces as ApiException', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'Expense category not found'},
        }, 404),
      );
      await expectLater(
        ExpenseRepository(auth: s.auth).createClaim(
          title: 't',
          categoryId: 'x',
          lines: const [
            ExpenseLine(expenseDate: '2026-10-05', description: 'a', amount: 1),
          ],
        ),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'not found', true),
        ),
      );
    });
  });
}
