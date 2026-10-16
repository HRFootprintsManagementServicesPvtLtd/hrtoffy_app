import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/screens/surveys_screen.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _surveysModule = '$_org/surveys';
const _engagementList = '$_org/engagement/surveys';
String _myResponse(String id) => '$_org/engagement/surveys/$id/my-response';

Map<String, dynamic> _survey(String id, String title) => {
      'id': id,
      'title': title,
      'description': 'About $title',
      'survey_type': 'survey',
      'status': 'active',
      'questions': [
        {'id': 'q1', 'text': 'How?', 'type': 'text'},
      ],
    };

final _two = [_survey('s1', 'Pulse Survey'), _survey('s2', 'Culture Poll')];

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

Future<void> _open(WidgetTester tester, TestSession s) async {
  _tall(tester);
  await tester.pumpWidget(MaterialApp(
    home: SurveysScreen(
      userEmail: 'me@x.com',
      userData: const {'id': testEmployeeId},
      fetchHrmsContext: () async => <String, dynamic>{},
      repository: EngagementRepository(auth: s.auth),
      auth: s.auth,
    ),
  ));
  await _settle(tester);
}

/// A server whose surveys module lists [surveys] and answers `my-response` from [answered] (survey id -> submitted_at);
/// ids in [failing] answer 404 for the lookup.
Future<TestSession> _session({
  List<Map<String, dynamic>>? surveys,
  Map<String, String> answered = const {},
  Set<String> failing = const {},
}) {
  final list = surveys ?? _two;
  return signedIn((req) async {
    final p = req.url.path;
    if (p == _surveysModule) return ok(list);
    for (final s in list) {
      final id = s['id'].toString();
      if (p == _myResponse(id)) {
        if (failing.contains(id)) {
          return jsonResponse({'success': false, 'error': {'message': 'Route not found'}}, 404);
        }
        if (answered.containsKey(id)) {
          return ok({'id': 'r-$id', 'survey_id': id, 'submitted_at': answered[id]});
        }
        return ok(null);
      }
    }
    return jsonResponse({'success': false}, 404);
  });
}

void main() {
  group('SurveysScreen', () {
    testWidgets('active surveys render with no warning when every lookup works', (tester) async {
      final s = await _session();
      await _open(tester, s);

      expect(find.text('Pulse Survey'), findsOneWidget);
      expect(find.text('Culture Poll'), findsOneWidget);
      expect(find.text('Participate Now'), findsNWidgets(2));
      expect(find.textContaining("couldn't confirm"), findsNothing);
      expect(find.text('1 questions'), findsNWidgets(2));
      expect(s.requests.where((r) => r.path == _surveysModule).single.query['status'], 'active');
    });

    testWidgets('an answered survey is Completed with the date the server reported, and is not offered again', (tester) async {
      final s = await _session(answered: {'s2': '2026-04-27T10:00:00.000Z'});
      await _open(tester, s);

      expect(find.text('Pulse Survey'), findsOneWidget);
      expect(find.text('Culture Poll'), findsNothing);
      expect(find.text('Participate Now'), findsOneWidget);

      await tester.tap(find.text('Completed'));
      await _settle(tester);
      expect(find.text('Culture Poll'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.textContaining('Submitted 27/4/2026'), findsOneWidget);
      expect(find.text('1 questions'), findsOneWidget);
    });

    testWidgets('when every surveys is answered the Active tab is empty and Completed lists them all (the website case: Active 0, Completed N)', (tester) async {
      final s = await _session(answered: {'s1': '2026-03-02T08:00:00Z', 's2': '2026-04-23T08:00:00Z'});
      await _open(tester, s);

      expect(find.text('No active surveys'), findsOneWidget);
      expect(find.textContaining("couldn't confirm"), findsNothing);
      await tester.tap(find.text('Completed'));
      await _settle(tester);
      expect(find.text('COMPLETED'), findsNWidgets(2));
    });

    testWidgets('a failed lookup never marks that survey completed: it stays in Active and the screen says completion is unconfirmed', (tester) async {
      final s = await _session(failing: {'s1'}, answered: {'s2': '2026-04-27T10:00:00Z'});
      await _open(tester, s);

      expect(find.text('Pulse Survey'), findsOneWidget);
      expect(find.text('Participate Now'), findsOneWidget);
      expect(find.textContaining("couldn't confirm"), findsOneWidget);
      expect(find.textContaining('Route not found'), findsNothing);
      expect(find.textContaining('ApiException'), findsNothing);

      await tester.tap(find.text('Completed'));
      await _settle(tester);
      expect(find.text('Culture Poll'), findsOneWidget, reason: 'the survey whose lookup worked is still shown as completed');
      expect(find.text('Pulse Survey'), findsNothing);
    });

    testWidgets('every lookup failing: surveys stay Active, none is Completed, and Completed does not claim to be empty', (tester) async {
      final s = await _session(failing: {'s1', 's2'});
      await _open(tester, s);

      expect(find.text('Participate Now'), findsNWidgets(2));
      expect(find.textContaining("couldn't confirm"), findsOneWidget);
      await tester.tap(find.text('Completed'));
      await _settle(tester);
      expect(find.text('COMPLETED'), findsNothing);
      expect(find.text("Completed surveys can't be shown right now."), findsOneWidget);
      expect(find.text('No completed surveys'), findsNothing, reason: 'unknown is not the same as none');
    });

    testWidgets('no surveys at all is simply "No active surveys": no warning and no per-survey requests', (tester) async {
      final s = await _session(surveys: const []);
      await _open(tester, s);

      expect(find.text('No active surveys'), findsOneWidget);
      expect(find.textContaining("couldn't confirm"), findsNothing);
      expect(s.requests.where((r) => r.path.contains('my-response')), isEmpty);
    });

    testWidgets('when the surveys module cannot answer, the engagement list is used instead', (tester) async {
      final s = await signedIn((req) async {
        final p = req.url.path;
        if (p == _surveysModule) return jsonResponse({'success': false}, 404);
        if (p == _engagementList) return ok({'items': [_survey('s9', 'Fallback Survey')]});
        if (p == _myResponse('s9')) return ok(null);
        return jsonResponse({'success': false}, 404);
      });
      await _open(tester, s);
      expect(find.text('Fallback Survey'), findsOneWidget);
    });

    testWidgets('a failure to load the surveys shows a friendly message and Retry, never the raw error', (tester) async {
      var calls = 0;
      final s = await signedIn((req) async {
        final p = req.url.path;
        if (p == _surveysModule || p == _engagementList) {
          calls++;
          if (calls <= 2) return jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'boom'}}, 500);
          return ok(_two);
        }
        if (p.endsWith('/my-response')) return ok(null);
        return jsonResponse({'success': false}, 404);
      });
      await _open(tester, s);

      expect(find.textContaining('server is busy'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.text('No active surveys'), findsNothing, reason: 'a failure is not an empty list');

      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Pulse Survey'), findsOneWidget);
    });
  });

  group('EngagementRepository.surveyCompletion', () {
    test('reports answered, open and unknown surveys separately and runs the lookups a few at a time', () async {
      var running = 0;
      var peak = 0;
      final s = await signedIn((req) async {
        final id = req.url.pathSegments[req.url.pathSegments.length - 2];
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        if (id == 'bad') return jsonResponse({'success': false}, 500);
        if (id == 'done') return ok({'id': 'r', 'submitted_at': '2026-01-05T00:00:00Z'});
        return ok(null);
      });
      final ids = ['done', 'open', 'bad', for (var i = 0; i < 8; i++) 'o$i'];
      final c = await EngagementRepository(auth: s.auth).surveyCompletion(ids, concurrency: 3);
      expect(c.isCompleted('done'), isTrue);
      expect(c.submittedAt['done'], '2026-01-05T00:00:00Z');
      expect(c.isCompleted('open'), isFalse);
      expect(c.unknown, {'bad'});
      expect(peak, lessThanOrEqualTo(3));
      expect(s.requests.length, ids.length);
    });

    test('surveys beyond the cap are unknown, not completed and not open', () async {
      final s = await signedIn((req) async => ok(null));
      final c = await EngagementRepository(auth: s.auth).surveyCompletion(['a', 'b', 'c'], maxSurveys: 2);
      expect(c.unknown, {'c'});
      expect(s.requests.length, 2);
    });
  });
}
