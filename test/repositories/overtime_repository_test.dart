import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/overtime_repository.dart';

import '../helpers/test_auth.dart';

const _path =
    '/organizations/$testOrgId/employees/$testEmployeeId/overtime/records';

Map<String, dynamic> _row(
  String id,
  String otDate, {
  Object? amount = '1250.00',
  String status = 'approved',
}) => {
  'id': id,
  'employee_id': testEmployeeId,
  'organization_id': testOrgId,
  'ot_date': otDate,
  'total_hours': '2.50',
  'rate_multiplier': '1.50',
  'ot_amount': amount,
  'ot_type': 'weekday',
  'status': status,
};

void main() {
  group('OvertimeRepository.records', () {
    test(
      'GET /employees/:emp/overtime/records with the session org and employee, no email lookup',
      () async {
        final s = await signedIn(
          (req) async => ok([_row('o1', '2026-10-07T00:00:00.000Z')]),
        );
        final rows = await OvertimeRepository(auth: s.auth).records();
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'GET');
        expect(s.last.path, _path);
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(rows, hasLength(1));
        expect(rows.first['id'], 'o1');
        expect(rows.first['ot_type'], 'weekday');
        expect(rows.first['status'], 'approved');
      },
    );

    test('decimal columns stay strings, null amount stays null', () async {
      final s = await signedIn(
        (req) async =>
            ok([_row('o1', '2026-10-07', amount: null, status: 'pending')]),
      );
      final r = (await OvertimeRepository(auth: s.auth).records()).single;
      expect(r['total_hours'], '2.50');
      expect(r['rate_multiplier'], '1.50');
      expect(r['ot_amount'], isNull);
    });

    test('numeric values are passed through untouched', () async {
      final s = await signedIn(
        (req) async => ok([_row('o1', '2026-10-07', amount: 800)]),
      );
      expect(
        (await OvertimeRepository(auth: s.auth).records()).single['ot_amount'],
        800,
      );
    });

    test('empty list', () async {
      final s = await signedIn((req) async => ok([]));
      expect(await OvertimeRepository(auth: s.auth).records(), isEmpty);
    });

    test(
      'a {items: [...]} body is accepted and rows are sorted newest ot_date first',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _row('old', '2026-09-01'),
              _row('new', '2026-10-07T00:00:00.000Z'),
            ],
          }),
        );
        final rows = await OvertimeRepository(auth: s.auth).records();
        expect(rows.map((r) => r['id']), ['new', 'old']);
      },
    );

    test('camelCase keys are normalised to snake_case', () async {
      final s = await signedIn(
        (req) async => ok([
          {
            'id': 'o1',
            'otDate': '2026-10-07',
            'totalHours': '1.00',
            'otAmount': '10.00',
          },
        ]),
      );
      final r = (await OvertimeRepository(auth: s.auth).records()).single;
      expect(r['ot_date'], '2026-10-07');
      expect(r['total_hours'], '1.00');
      expect(r['ot_amount'], '10.00');
    });

    test('API error surfaces as ApiException', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'code': 'FORBIDDEN', 'message': 'Not allowed'},
        }, 403),
      );
      await expectLater(
        OvertimeRepository(auth: s.auth).records(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('server error is an ApiException 500', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'boom'},
        }, 500),
      );
      await expectLater(
        OvertimeRepository(auth: s.auth).records(),
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
}
