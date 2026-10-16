import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/screens/survey_response_screen.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/engagement/surveys/s1';
const _myResponse = '$_base/my-response';
const _respond = '$_base/respond';

const _survey = {
  'id': 's1',
  'title': 'Pulse Survey',
  'questions': [
    {'id': 'q1', 'text': 'Happy?', 'type': 'yes-no', 'required': true},
  ],
};

/// Opens the survey from a parent screen, so a successful submit (the screen pops) is observable.
Future<void> _open(WidgetTester tester, TestSession s) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(children: [
          ElevatedButton(
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => SurveyResponseScreen(
                    survey: _survey,
                    employeeId: testEmployeeId,
                    organizationId: testOrgId,
                    userEmail: 'me@x.com',
                    repository: EngagementRepository(auth: s.auth),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ]),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Yes'));
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Submit Survey'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('SurveyResponseScreen submit errors', () {
    testWidgets('404 from the my-response pre-check: friendly message, nothing is posted, screen stays open', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return jsonResponse({'success': false, 'error': {'message': 'Route GET:/x not found'}}, 404);
        return ok({'id': 'r1'});
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.textContaining("isn't available right now"), findsOneWidget);
      expect(find.textContaining('Your answers were not submitted'), findsOneWidget);
      expect(find.textContaining('Route GET'), findsNothing);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty, reason: '404 does not mean "not yet answered"');
      expect(find.text('Submit Survey'), findsOneWidget, reason: 'the screen stays open so the answers are not lost');
    });

    testWidgets('a 5xx on the pre-check shows a friendly message and posts nothing', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return jsonResponse({'success': false, 'error': {'message': 'pg exploded'}}, 500);
        return ok({'id': 'r1'});
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.textContaining('server is busy'), findsOneWidget);
      expect(find.textContaining('pg exploded'), findsNothing);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a refusal when posting (closed survey, 400) shows a friendly message, not the server text', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok(null);
        return jsonResponse({'success': false, 'error': {'message': 'This survey is closed (internal)'}}, 400);
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.textContaining('may be closed'), findsOneWidget);
      expect(find.textContaining('(internal)'), findsNothing);
    });

    testWidgets('a 403 when posting shows a permission message', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok(null);
        return jsonResponse({'success': false, 'error': {'message': 'Missing permission engagement.view'}}, 403);
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.textContaining('engagement.view'), findsNothing);
    });

    testWidgets('a 404 when posting (survey gone) shows the same friendly not-available message', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok(null);
        return jsonResponse({'success': false, 'error': {'message': 'Survey not found'}}, 404);
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.textContaining("isn't available right now"), findsOneWidget);
      expect(find.text('Survey not found'), findsNothing);
    });

    testWidgets('a non-API failure (for example a malformed response) is also friendly, not an unhandled exception', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok(null);
        return jsonResponse({'success': true, 'data': {'id': 'r1'}}, 200);
      });
      // Force a non-ApiException by making the repository throw after a successful pre-check.
      final repo = _ThrowingRepository(s);
      await tester.pumpWidget(MaterialApp(
        home: SurveyResponseScreen(
          survey: _survey,
          employeeId: testEmployeeId,
          organizationId: testOrgId,
          userEmail: 'me@x.com',
          repository: repo,
        ),
      ));
      await tester.tap(find.text('Yes'));
      await tester.pump();
      await _submit(tester);

      expect(find.textContaining("couldn't submit your survey"), findsOneWidget);
      expect(find.textContaining('FormatException'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the existing 409 duplicate guard still wins: its own message, and nothing is posted', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok({'id': 'earlier'});
        return ok({'id': 'r1'});
      });
      await _open(tester, s);
      await _submit(tester);

      expect(find.text('You have already submitted this survey.'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('success is unchanged: pre-check says unanswered, answers are posted, screen closes with true', (tester) async {
      final s = await signedIn((req) async {
        if (req.url.path == _myResponse) return ok(null);
        if (req.url.path == _respond) return ok({'id': 'r1'});
        return jsonResponse({'success': false}, 404);
      });
      await _open(tester, s);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(s.requests.map((r) => '${r.method} ${r.path}'), ['GET $_myResponse', 'POST $_respond']);
      expect(s.last.json['responses'], [
        {'question_id': 'q1', 'question_text': 'Happy?', 'answer': 'yes'},
      ]);
      expect(find.text('Submit Survey'), findsNothing, reason: 'the screen closed');
    });
  });

  group('surveySubmitErrorMessage', () {
    test('never contains raw exception or server text', () {
      for (final e in <Object>[
        const ApiException(404, 'Route GET:/a/b not found'),
        const ApiException(500, 'db exploded at https://api.hrtoffy.in'),
        const ApiException(0, 'Network error: SocketException'),
        const ApiException(401, 'jwt expired'),
        const ApiException(400, 'This survey is closed'),
        Exception('stack trace here'),
      ]) {
        final m = surveySubmitErrorMessage(e);
        expect(m, contains('Your answers were not submitted'));
        expect(m, isNot(contains('Route GET')));
        expect(m, isNot(contains('exploded')));
        expect(m, isNot(contains('Exception')));
        expect(m, isNot(contains('jwt')));
        expect(m, isNot(contains('api.hrtoffy.in')));
      }
    });
  });
}

/// A repository whose submit fails with a non-API error, to cover the generic fallback.
class _ThrowingRepository extends EngagementRepository {
  _ThrowingRepository(TestSession s) : super(auth: s.auth);

  @override
  Future<void> submitSurveyResponse(String surveyId, List<Map<String, dynamic>> responses) async {
    throw const FormatException('bad json from server');
  }
}
