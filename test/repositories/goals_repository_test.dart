import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/goals_repository.dart';

import '../helpers/test_auth.dart';

Map<String, dynamic> _goal(
  String id, {
  String created = '2026-10-01T10:00:00.000Z',
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'emp_id': testEmployeeId,
  'cycle_id': 'cycle-1',
  'title': 'Goal $id',
  'description': 'Do the thing',
  'category': 'individual',
  'weightage': 25,
  'status': 'draft',
  'progress_percentage': 40,
  'achievement_status': 85,
  'framework_type': 'kra',
  'timeline': 'Q3',
  'target_date': '2026-12-31T00:00:00.000Z',
  'manager_rating': null,
  'reviewer_rating': null,
  'final_rating': null,
  'manager_comments': null,
  'reviewer_comments': null,
  'created_at': created,
  ...extra,
};

void main() {
  group('GoalsRepository.goals', () {
    test(
      'GET /pms/goals - not org-prefixed, no employeeId or cycleId, the token identifies the employee',
      () async {
        final s = await signedIn((req) async => ok([_goal('a')]));
        final rows = await GoalsRepository(auth: s.auth).goals();
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'GET');
        expect(s.last.path, '/pms/goals');
        expect(s.last.query, isEmpty);
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(rows, hasLength(1));
        expect(rows.single['title'], 'Goal a');
        expect(rows.single['framework_type'], 'kra');
        expect(rows.single['timeline'], 'Q3');
        expect(rows.single['status'], 'draft');
        expect(rows.single['target_date'], '2026-12-31T00:00:00.000Z');
      },
    );

    test(
      'rows are re-sorted newest created_at first (the API sends them oldest first)',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _goal('oldest', created: '2026-08-01T00:00:00.000Z'),
            _goal('middle', created: '2026-09-01T00:00:00.000Z'),
            _goal('newest', created: '2026-10-01T00:00:00.000Z'),
          ]),
        );
        final rows = await GoalsRepository(auth: s.auth).goals();
        expect(rows.map((r) => r['id']), ['newest', 'middle', 'oldest']);
      },
    );

    test('hidden ratings and comments stay null and nothing crashes', () async {
      final s = await signedIn((req) async => ok([_goal('a')]));
      final r = (await GoalsRepository(auth: s.auth).goals()).single;
      for (final k in [
        'manager_rating',
        'reviewer_rating',
        'final_rating',
        'manager_comments',
        'reviewer_comments',
      ]) {
        expect(r.containsKey(k), isTrue, reason: k);
        expect(r[k], isNull, reason: k);
      }
    });

    test('ratings that are present are numbers', () async {
      final s = await signedIn(
        (req) async => ok([
          _goal(
            'a',
            extra: {
              'manager_rating': 4.5,
              'reviewer_rating': '3.0',
              'final_rating': 4,
              'manager_comments': 'Good',
            },
          ),
        ]),
      );
      final r = (await GoalsRepository(auth: s.auth).goals()).single;
      expect(r['manager_rating'], 4.5);
      expect(r['reviewer_rating'], 3.0);
      expect(r['final_rating'], 4);
      expect(r['manager_comments'], 'Good');
    });

    test(
      'achievement_status is numeric (number stays a number, a numeric string becomes one, null stays null)',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _goal('n', extra: {'achievement_status': 85.5}),
            _goal('i', extra: {'achievement_status': 70}),
            _goal('s', extra: {'achievement_status': '60.00'}),
            _goal('z', extra: {'achievement_status': null}),
          ]),
        );
        final byId = {
          for (final r in await GoalsRepository(auth: s.auth).goals())
            r['id']: r,
        };
        expect(byId['n']!['achievement_status'], 85.5);
        expect(byId['i']!['achievement_status'], 70);
        expect(byId['s']!['achievement_status'], 60);
        expect(byId['s']!['achievement_status'], isA<num>());
        expect(byId['z']!['achievement_status'], isNull);
      },
    );

    test(
      'weightage and progress are numbers even when sent as strings',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _goal(
              'a',
              extra: {'weightage': '30.00', 'progress_percentage': '55'},
            ),
          ]),
        );
        final r = (await GoalsRepository(auth: s.auth).goals()).single;
        expect(r['weightage'], 30);
        expect(r['progress_percentage'], 55);
      },
    );

    test('empty list', () async {
      final s = await signedIn((req) async => ok([]));
      expect(await GoalsRepository(auth: s.auth).goals(), isEmpty);
    });

    test('API errors surface as ApiException', () async {
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'You cannot view this employee’s goals'},
        }, 403),
      );
      await expectLater(
        GoalsRepository(auth: f.auth).goals(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      final n = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'Not found'},
        }, 404),
      );
      await expectLater(
        GoalsRepository(auth: n.auth).goals(),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'not found', true),
        ),
      );
    });
  });
}
