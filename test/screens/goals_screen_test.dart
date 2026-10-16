import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/goals_repository.dart';
import 'package:hrms_app/screens/goals_screen.dart';

import '../helpers/test_auth.dart';

Future<void> _settle(WidgetTester t) async {
  // the skeleton animates forever, so settle in bounded steps
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _screen(TestSession s) => MaterialApp(
  home: GoalsScreen(
    userEmail: 'me@x.com',
    userData: const {'id': testEmployeeId, 'organization_id': testOrgId},
    fetchHrmsContext: () async => {},
    repository: GoalsRepository(auth: s.auth),
  ),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 4200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Map<String, dynamic> _goal(
  String title,
  String created, {
  Object? achievement = 85,
  Map<String, dynamic> extra = const {},
}) => {
  'id': title,
  'title': title,
  'description': 'desc',
  'category': 'individual',
  'weightage': 25,
  'status': 'approved',
  'progress_percentage': 40,
  'achievement_status': achievement,
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
  testWidgets(
    'shows the active-cycle goals from GET /pms/goals, newest first, with masked ratings hidden',
    (tester) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => ok([
          _goal('Older goal', '2026-08-01T00:00:00.000Z'),
          _goal('Newer goal', '2026-10-01T00:00:00.000Z', achievement: 85.0),
        ]),
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      expect(s.apiCalls.single.path, '/pms/goals');
      expect(s.apiCalls.single.query, isEmpty);
      expect(find.text('Newer goal'), findsOneWidget);
      expect(find.text('Older goal'), findsOneWidget);
      // newest card is above the older one
      expect(
        tester.getTopLeft(find.text('Newer goal')).dy,
        lessThan(tester.getTopLeft(find.text('Older goal')).dy),
      );
      // numeric achievement renders without a trailing ".0"
      expect(find.text('85'), findsWidgets);
      expect(find.text('85.0'), findsNothing);
      expect(find.text('Q3'), findsWidgets);
      expect(find.text('25%'), findsWidgets);
      // hidden manager/reviewer/final ratings and remarks are simply not shown
      expect(find.text('Manager'), findsNothing);
      expect(find.text('Reviewer'), findsNothing);
      expect(find.text('Final'), findsNothing);
      expect(find.text('Manager Remarks'), findsNothing);
    },
  );

  testWidgets('ratings and remarks are shown when the server sends them', (
    tester,
  ) async {
    _tall(tester);
    final s = await signedIn(
      (req) async => ok([
        _goal(
          'Done goal',
          '2026-10-01T00:00:00.000Z',
          achievement: 72.5,
          extra: {
            'manager_rating': 4.5,
            'final_rating': 4,
            'manager_comments': 'Well done',
          },
        ),
      ]),
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
    expect(find.text('Manager Remarks'), findsOneWidget);
    expect(find.text('Well done'), findsOneWidget);
    expect(find.text('72.5'), findsWidgets);
    expect(find.text('Reviewer'), findsNothing);
  });

  testWidgets(
    'each goal card gets its own pastel colour, even when every goal has the same category',
    (tester) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => ok([
          _goal('Goal A', '2026-10-03T00:00:00.000Z'),
          _goal('Goal B', '2026-10-02T00:00:00.000Z'),
          _goal('Goal C', '2026-10-01T00:00:00.000Z'),
          _goal('Goal D', '2026-09-30T00:00:00.000Z'),
        ]),
      );
      await tester.pumpWidget(_screen(s));
      await _settle(tester);

      Color cardColor(String title) {
        final card = find
            .ancestor(
              of: find.text(title),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(20),
              ),
            )
            .first;
        return ((tester.widget<Container>(card)).decoration as BoxDecoration)
            .color!;
      }

      final colors = [
        for (final t in ['Goal A', 'Goal B', 'Goal C', 'Goal D']) cardColor(t),
      ];
      expect(
        colors.toSet().length,
        4,
        reason: 'neighbouring cards must differ',
      );
      for (var i = 1; i < colors.length; i++) {
        expect(colors[i], isNot(colors[i - 1]));
      }
    },
  );

  testWidgets('empty list shows the empty state', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async => ok([]));
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No goals found'), findsOneWidget);
  });

  testWidgets('an API error shows the empty state and no raw error text', (
    tester,
  ) async {
    _tall(tester);
    final s = await signedIn(
      (req) async => jsonResponse({
        'success': false,
        'error': {'message': 'pms db exploded'},
      }, 500),
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    expect(find.text('No goals found'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
  });
}
