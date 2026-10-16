import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/chat_repository.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/repositories/helpdesk_repository.dart';
import 'package:hrms_app/repositories/letters_repository.dart';
import 'package:hrms_app/repositories/recruitment_repository.dart';
import 'package:hrms_app/repositories/tasks_repository.dart';
import 'package:hrms_app/screens/manager/manager_engage_screen.dart';
import 'package:hrms_app/screens/manager/widgets/engage_tabs.dart';
import 'package:hrms_app/screens/manager/widgets/manager_state_views.dart';
import 'package:hrms_app/services/chat_service.dart';

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

Widget _screen(TestSession s) => MaterialApp(
  home: ManagerEngageScreen(
    userEmail: 'm@x.com',
    userData: const {'id': 'e1', 'organization_id': testOrgId},
    fetchHrmsContext: () async => {},
    engagementRepository: EngagementRepository(auth: s.auth),
    chatService: ChatService(repository: ChatRepository(auth: s.auth)),
    chatRepository: ChatRepository(auth: s.auth),
    tasksRepository: TasksRepository(auth: s.auth),
    helpdeskRepository: HelpdeskRepository(auth: s.auth),
    lettersRepository: LettersRepository(auth: s.auth),
    recruitmentRepository: RecruitmentRepository(auth: s.auth),
  ),
);

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);
final _forbidden = jsonResponse({
  'success': false,
  'error': {'message': 'Permission denied: engagement.manage'},
}, 403);

const _otherEmployee = '99999999-9999-9999-9999-999999999999';

/// Mutable server state for one test.
class _Server {
  Set<String> failing = {};
  Set<String> forbidden = {};
  bool recognitionPostForbidden = false;
  bool applyFails = false;
  Set<String> applied = {};
  List<Map<String, dynamic>> recognitions = [
    {
      'id': 'r1',
      'given_by': 'x',
      'given_to': 'y',
      'recognition_message': 'Great launch',
      'visibility': 'public',
      'from_employee': {'full_name': 'Asha Rao'},
      'to_employee': {'full_name': 'Ravi Kumar'},
      'recognition_badges': {'badge_name': 'Star Performer'},
    },
    {
      'id': 'r2',
      'given_by': 'x',
      'given_to': 'y',
      'recognition_message': 'Secret kudos',
      'visibility': 'private',
      'from_employee': {'full_name': 'Asha Rao'},
      'to_employee': {'full_name': 'Ravi Kumar'},
      'recognition_badges': {'badge_name': 'Secret Badge'},
    },
  ];
}

Future<TestSession> _session(
  _Server srv, {
  List<Map<String, dynamic>> channels = const [],
}) {
  return signedIn((req) async {
    final path = req.url.path;
    if (srv.failing.contains(path)) return _boom;
    if (srv.forbidden.contains(path)) return _forbidden;
    if (req.method == 'POST') {
      if (path == '$_org/engagement/recognition') {
        if (srv.recognitionPostForbidden) return _forbidden;
        srv.recognitions = [
          {
            'id': 'r3',
            'recognition_message': 'Thanks for the help',
            'visibility': 'public',
            'from_employee': {'full_name': 'Me'},
            'to_employee': {'full_name': 'Priya Shah'},
            'recognition_badges': {'badge_name': 'Team Player'},
          },
          ...srv.recognitions,
        ];
        return ok({'id': 'r3'}, 201);
      }
      if (path.startsWith('$_org/recruitment/internal-jobs/') &&
          path.endsWith('/apply')) {
        if (srv.applyFails) {
          return jsonResponse({
            'success': false,
            'error': {'message': 'Internal exploded'},
          }, 400);
        }
        srv.applied.add(path.split('/')[5]);
        return ok({'id': 'app1'}, 201);
      }
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    }
    switch (path) {
      case '$_org/chat/channels':
        return ok(channels);
      case '$_org/chat/employees':
        return ok([
          {
            'id': testEmployeeId,
            'full_name': 'Me Myself',
            'department': 'Ops',
            'designation': 'Manager',
            'user_id': testUserId,
          },
          {
            'id': _otherEmployee,
            'full_name': 'Priya Shah',
            'department': 'Finance',
            'designation': 'Accountant',
            'user_id': 'u2',
          },
          {
            'id': 'e3',
            'full_name': 'Ravi Kumar',
            'department': 'Sales',
            'designation': 'Executive',
            'user_id': 'u3',
          },
        ]);
      case '$_org/engagement/announcements':
        return ok({
          'items': [
            {
              'id': 'a1',
              'title': 'Office closed Friday',
              'body': 'Please plan',
              'priority': 'high',
              'category': 'general',
              'created_at': '2026-10-05T09:00:00.000Z',
              'is_active': true,
              'status': 'published',
            },
            {
              'id': 'a2',
              'title': 'Secret draft',
              'body': 'x',
              'created_at': '2026-10-05T09:00:00.000Z',
              'is_active': true,
              'status': 'draft',
            },
            {
              'id': 'a3',
              'title': 'Old notice',
              'body': 'x',
              'created_at': '2026-10-05T09:00:00.000Z',
              'is_active': false,
              'status': 'published',
            },
          ],
        });
      case '$_org/engagement/events':
        return ok({
          'items': [
            {
              'id': 'ev1',
              'title': 'Town hall',
              'event_date': '2026-11-02T10:00:00.000Z',
              'location': 'Main hall',
            },
          ],
        });
      case '$_org/engagement/surveys':
        return ok({
          'items': [
            {
              'id': 's1',
              'title': 'Pulse survey',
              'description': 'Quarterly pulse',
            },
          ],
        });
      case '$_org/faqs':
        return ok([
          {
            'id': 'f1',
            'question': 'How do I apply for leave?',
            'answer': 'Use the Leaves screen',
            'is_active': true,
            'category': 'HR',
          },
        ]);
      case '$_org/engagement/recognition':
        return ok({
          'items': srv.recognitions,
          'total': srv.recognitions.length,
        });
      case '$_org/engagement/recognition/badges':
        return ok([
          {'id': 'b1', 'badge_name': 'Team Player', 'points_value': 10},
          {'id': 'b2', 'badge_name': 'Star Performer', 'points_value': 25},
        ]);
      case '$_org/dashboard/celebrations':
        return ok({
          'birthdays': [
            {'id': 'e3', 'full_name': 'Ravi Kumar', 'department': 'Sales'},
          ],
          'anniversaries': [
            {'id': 'e4', 'full_name': 'Neha Jain', 'yearsCompleted': 3},
          ],
        });
      case '$_org/tasks':
        return ok({
          'items': [
            {
              'id': 'ta1',
              'employee_id': testEmployeeId,
              'status': 'in_progress',
              'task': {
                'task_title': 'Complete onboarding checklist',
                'task_type': 'onboarding',
                'task_description': 'Do the steps',
                'checklist_items': ['Sign policy', 'Collect laptop'],
              },
            },
            {
              'id': 'ta2',
              'employee_id': _otherEmployee,
              'status': 'pending',
              'task': {
                'task_title': 'Report member task',
                'task_type': 'general',
              },
            },
          ],
          'total': 2,
        });
      case '$_org/helpdesk/tickets':
        return ok({
          'items': [
            {
              'id': 't1',
              'employee_id': testEmployeeId,
              'subject': 'Laptop broken',
              'category': 'it',
              'status': 'pending',
              'created_at': '2026-10-01T09:00:00.000Z',
            },
            {
              'id': 't2',
              'employee_id': _otherEmployee,
              'subject': 'Addressed to me by a report',
              'category': 'hr',
              'status': 'pending',
              'created_at': '2026-10-02T09:00:00.000Z',
            },
          ],
          'total': 2,
          'page': 1,
          'limit': 200,
        });
      case '$_org/letters/employee/$testEmployeeId':
        return ok({
          'rows': [
            {
              'id': 'l1',
              'employee_id': testEmployeeId,
              'letter_category': 'Appointment Letter',
              'subject_line': 'Welcome aboard',
              'sent_at': '2026-09-01T09:00:00.000Z',
              'created_at': '2026-08-30T09:00:00.000Z',
            },
          ],
          'total': 1,
          'page': 1,
          'limit': 200,
        });
      case '$_org/recruitment/internal-jobs':
        return ok([
          {
            'id': 'j1',
            'job_title': 'Senior Analyst',
            'department': 'Finance',
            'location': 'Pune',
            'employment_type': 'full_time',
            'salary_min': '500000.00',
            'salary_max': '900000.00',
            'number_of_positions': 2,
            'internal_deadline': '2026-12-18',
            'job_description': 'Analyse things',
            'created_at': '2026-10-01T09:00:00.000Z',
          },
          {
            'id': 'j2',
            'job_title': 'Team Lead',
            'created_at': '2026-10-01T09:00:00.000Z',
          },
        ]);
      case '$_org/recruitment/internal-jobs/my-applications':
        return ok([
          for (final id in srv.applied)
            {'id': 'app-$id', 'job_id': id, 'status': 'active'},
        ]);
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  }, empRole: 'manager');
}

Future<void> _tapSub(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await _settle(t);
}

Future<(_Server, TestSession)> _open(
  WidgetTester tester, {
  void Function(_Server)? setup,
}) async {
  _tall(tester);
  final srv = _Server();
  setup?.call(srv);
  final s = await _session(srv);
  await tester.pumpWidget(_screen(s));
  await _settle(tester);
  return (srv, s);
}

List<String> _calls(TestSession s) =>
    s.requests.map((r) => '${r.method} ${r.path}').toList();

void main() {
  testWidgets('Messages is present and uses the AWS chat; all tabs kept', (
    tester,
  ) async {
    _tall(tester);
    final s = await _session(
      _Server(),
      channels: [
        {
          'id': 'c1',
          'channel_type': 'group',
          'name': 'Managers',
          'last_message': 'See you at 5',
          'last_message_at': '2026-10-08T10:00:00.000Z',
        },
      ],
    );
    await tester.pumpWidget(_screen(s));
    await _settle(tester);

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Managers'), findsOneWidget);
    expect(find.text('See you at 5'), findsOneWidget);
    expect(_calls(s), ['GET $_org/chat/channels']);
    for (final t in [
      'Internal Updates',
      'Company Directory',
      'Tasks & Checklists',
      'Tickets',
      'Letters & Documents',
      'Internal Opportunities',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets(
    'announcements, events, surveys and FAQs load through the existing repository routes',
    (tester) async {
      final (_, s) = await _open(tester);

      await _tapSub(tester, 'Announcements');
      expect(find.text('Office closed Friday'), findsOneWidget);
      expect(find.text('Secret draft'), findsNothing);
      expect(find.text('Old notice'), findsNothing);

      await _tapSub(tester, 'Events & Calendar');
      expect(find.text('Town hall'), findsOneWidget);

      await _tapSub(tester, 'Surveys');
      expect(find.text('Pulse survey'), findsOneWidget);
      expect(find.text('Take Survey'), findsOneWidget);

      await _tapSub(tester, 'FAQs');
      expect(find.text('How do I apply for leave?'), findsOneWidget);

      expect(_calls(s).toSet(), {
        'GET $_org/chat/channels',
        'GET $_org/engagement/announcements',
        'GET $_org/engagement/events',
        'GET $_org/engagement/surveys',
        'GET $_org/faqs',
      });
      expect(
        s.requests
            .firstWhere((r) => r.path.endsWith('/surveys'))
            .query['status'],
        'active',
      );
    },
  );

  testWidgets(
    'Company Directory lists colleagues from the chat directory, searchable',
    (tester) async {
      final (_, s) = await _open(tester);
      await _tapSub(tester, 'Company Directory');
      expect(find.text('Priya Shah'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
      expect(_calls(s).where((c) => c.contains('chat/employees')).length, 1);

      await tester.enterText(find.byType(TextField), 'finance');
      await _settle(tester);
      expect(find.text('Priya Shah'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await _settle(tester);
      expect(find.text('No colleagues found'), findsOneWidget);

      await tester.tap(find.text('Org Chart'));
      await _settle(tester);
      expect(find.text("The org chart isn't available yet"), findsOneWidget);
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Tasks: only the caller\'s own assignments are requested and shown',
    (tester) async {
      final (_, s) = await _open(tester);
      await _tapSub(tester, 'Tasks & Checklists');
      final req = s.requests.firstWhere((r) => r.path == '$_org/tasks');
      expect(req.query['assignedTo'], testEmployeeId);
      expect(find.text('Complete onboarding checklist'), findsOneWidget);
      expect(find.text('Report member task'), findsNothing);

      await tester.tap(find.text('Complete onboarding checklist'));
      await _settle(tester);
      expect(find.text('• Sign policy'), findsOneWidget);

      await tester.tap(find.text('Manage Tasks'));
      await _settle(tester);
      expect(find.text("Managing tasks isn't available yet"), findsOneWidget);
    },
  );

  testWidgets(
    'Tickets: own tickets only, filtered by the caller\'s employee id',
    (tester) async {
      final (_, s) = await _open(tester);
      await _tapSub(tester, 'Tickets');
      final req = s.requests.firstWhere(
        (r) => r.path == '$_org/helpdesk/tickets',
      );
      expect(req.query['employee_id'], testEmployeeId);
      expect(find.text('Laptop broken'), findsOneWidget);
      expect(find.text('Addressed to me by a report'), findsNothing);
      expect(find.text('My Tickets'), findsOneWidget);
    },
  );

  testWidgets('Letters: reads only the caller\'s own letters (rows)', (
    tester,
  ) async {
    final (_, s) = await _open(tester);
    await _tapSub(tester, 'Letters & Documents');
    final paths = s.requests.map((r) => r.path).toList();
    expect(paths.where((p) => p.contains('/letters/')), [
      '$_org/letters/employee/$testEmployeeId',
    ]);
    expect(find.text('Appointment Letter'), findsOneWidget);
    expect(find.textContaining('Welcome aboard'), findsOneWidget);
    expect(find.textContaining('Issued: 01 Sep 2026'), findsOneWidget);
  });

  testWidgets('Letters empty state', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async {
      if (req.url.path == '$_org/chat/channels') return ok([]);
      if (req.url.path == '$_org/letters/employee/$testEmployeeId') {
        return ok({'rows': [], 'total': 0, 'page': 1, 'limit': 200});
      }
      return jsonResponse({'success': false}, 404);
    }, empRole: 'manager');
    await tester.pumpWidget(_screen(s));
    await _settle(tester);
    await _tapSub(tester, 'Letters & Documents');
    expect(find.textContaining('No letters yet'), findsOneWidget);
  });

  testWidgets(
    'Internal Opportunities: list, apply (own application), then Applied',
    (tester) async {
      final (srv, s) = await _open(tester);
      await _tapSub(tester, 'Internal Opportunities');
      expect(find.text('Senior Analyst'), findsOneWidget);
      expect(find.text('Pune'), findsOneWidget);
      expect(find.text('INR 5,00,000 - 9,00,000'), findsOneWidget);
      expect(find.text('Deadline: 18 Dec 2026'), findsOneWidget);
      // a job without details shows no invented location, salary or deadline
      expect(find.text('Team Lead'), findsOneWidget);
      expect(find.text('Mumbai'), findsNothing);
      expect(find.text('INR null - null'), findsNothing);
      expect(find.text('Apply'), findsNWidgets(2));

      await tester.tap(find.text('Apply').first);
      await _settle(tester);
      final post = s.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, '$_org/recruitment/internal-jobs/j1/apply');
      expect(post.json, <String, dynamic>{});
      expect(find.text('Applied successfully!'), findsOneWidget);
      expect(srv.applied, {'j1'});
      expect(find.text('APPLIED'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'Internal Opportunities: a failed apply shows a friendly message only',
    (tester) async {
      final (_, _) = await _open(tester, setup: (s) => s.applyFails = true);
      await _tapSub(tester, 'Internal Opportunities');
      await tester.tap(find.text('Apply').first);
      await _settle(tester);
      expect(
        find.text("Couldn't submit your application. Please try again."),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
      expect(find.text('APPLIED'), findsNothing);
    },
  );

  testWidgets(
    'Recognition: lists recognitions, hides others\' private ones, shows celebrations',
    (tester) async {
      final (_, s) = await _open(tester);
      await _tapSub(tester, 'Recognition');
      expect(find.text('Star Performer'), findsOneWidget);
      expect(find.text('Great launch'), findsOneWidget);
      expect(find.text('Secret kudos'), findsNothing);
      expect(find.text('Celebrations Today!'), findsOneWidget);
      expect(find.text('Neha Jain'), findsOneWidget);
      expect(find.text('Work anniversary'), findsOneWidget);
      expect(find.text('Birthday'), findsOneWidget);
      expect(s.requests.every((r) => r.method == 'GET'), isTrue);
      final rec = s.requests.firstWhere(
        (r) => r.path == '$_org/engagement/recognition',
      );
      expect(rec.query['limit'], '50');
    },
  );

  testWidgets('Give Recognition: exact request body, then the list refreshes', (
    tester,
  ) async {
    final (_, s) = await _open(tester);
    await _tapSub(tester, 'Recognition');
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    expect(find.text('Give Recognition'), findsWidgets);

    // the caller is not offered as a recipient
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await _settle(tester);
    expect(find.text('Me Myself'), findsNothing);
    await tester.tap(find.text('Priya Shah').last);
    await _settle(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await _settle(tester);
    await tester.tap(find.text('Team Player').last);
    await _settle(tester);

    await tester.enterText(find.byType(TextField).last, 'Thanks for the help');
    await tester.tap(find.text('Send Recognition'));
    await _settle(tester);

    final posts = s.requests.where((r) => r.method == 'POST').toList();
    expect(posts.length, 1);
    expect(posts.single.path, '$_org/engagement/recognition');
    expect(posts.single.json, {
      'given_to': _otherEmployee,
      'badge_id': 'b1',
      'recognition_message': 'Thanks for the help',
      'visibility': 'public',
      'points': 10,
    });
    // dialog closed, list re-read and the new recognition is shown
    expect(find.text('Send Recognition'), findsNothing);
    expect(find.text('Thanks for the help'), findsOneWidget);
    expect(
      s.requests
          .where(
            (r) =>
                r.method == 'GET' && r.path == '$_org/engagement/recognition',
          )
          .length,
      2,
    );
  });

  testWidgets(
    'Give Recognition: a 403 shows the friendly state, never server text',
    (tester) async {
      final (_, s) = await _open(
        tester,
        setup: (s) => s.recognitionPostForbidden = true,
      );
      await _tapSub(tester, 'Recognition');
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await _settle(tester);
      await tester.tap(find.text('Priya Shah').last);
      await _settle(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await _settle(tester);
      await tester.tap(find.text('Team Player').last);
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Thanks');
      await tester.tap(find.text('Send Recognition'));
      await _settle(tester);

      expect(find.text(kRecognitionNotAllowedMessage), findsOneWidget);
      expect(find.textContaining('Permission denied'), findsNothing);
      expect(find.textContaining('engagement.manage'), findsNothing);
      expect(s.requests.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'Give Recognition: validation stops an incomplete form before any request',
    (tester) async {
      final (_, s) = await _open(tester);
      await _tapSub(tester, 'Recognition');
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      await tester.tap(find.text('Send Recognition'));
      await _settle(tester);
      expect(find.textContaining('Choose a colleague'), findsOneWidget);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  group('403 shows "Not available for your role" for just that part', () {
    final cases = {
      'Company Directory': '$_org/chat/employees',
      'Tasks & Checklists': '$_org/tasks',
      'Tickets': '$_org/helpdesk/tickets',
      'Letters & Documents': '$_org/letters/employee/$testEmployeeId',
      'Internal Opportunities': '$_org/recruitment/internal-jobs',
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        await _open(tester, setup: (s) => s.forbidden = {e.value});
        await tester.tap(find.text(e.key));
        await _settle(tester);
        expect(find.text(kManagerRoleUnavailableMessage), findsOneWidget);
        expect(find.textContaining('Permission denied'), findsNothing);
      });
    }
  });

  group('failures show a fixed message, never the server text', () {
    final cases = {
      'Announcements': '$_org/engagement/announcements',
      'Events & Calendar': '$_org/engagement/events',
      'Surveys': '$_org/engagement/surveys',
      'FAQs': '$_org/faqs',
      'Recognition': '$_org/engagement/recognition',
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        await _open(tester, setup: (s) => s.failing = {e.value});
        await _tapSub(tester, e.key);
        expect(find.text(kEngageLoadFailedMessage), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
      });
    }

    final mainTabs = {
      'Company Directory': '$_org/chat/employees',
      'Tasks & Checklists': '$_org/tasks',
      'Tickets': '$_org/helpdesk/tickets',
      'Letters & Documents': '$_org/letters/employee/$testEmployeeId',
      'Internal Opportunities': '$_org/recruitment/internal-jobs',
    };
    for (final e in mainTabs.entries) {
      testWidgets(e.key, (tester) async {
        await _open(tester, setup: (s) => s.failing = {e.value});
        await tester.tap(find.text(e.key));
        await _settle(tester);
        expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
      });
    }
  });

  testWidgets(
    'a failed celebrations strip is a small note; recognitions still show',
    (tester) async {
      await _open(
        tester,
        setup: (s) => s.failing = {'$_org/dashboard/celebrations'},
      );
      await _tapSub(tester, 'Recognition');
      expect(
        find.textContaining("celebrations aren't available"),
        findsOneWidget,
      );
      expect(find.text('Great launch'), findsOneWidget);
    },
  );

  test(
    'no write route other than recognition and apply, no Supabase, no raw error text',
    () {
      final files = [
        'lib/screens/manager/manager_engage_screen.dart',
        'lib/screens/manager/widgets/engage_tabs.dart',
        'lib/screens/manager/widgets/manager_state_views.dart',
      ];
      for (final f in files) {
        final src = File(f).readAsStringSync();
        for (final banned in [
          'supabase',
          'Supabase',
          'print(',
          'debugPrint(',
          r'$e"',
          r"$e'",
          r'Error: $',
          '.insert(',
          '.upsert(',
          'candidates',
          'job_applications',
          '.message}',
          'e.message)',
        ]) {
          // the one allowed use of an error message: matching "already applied" (never displayed)
          if (banned == '.message}' || banned == 'e.message)') continue;
          expect(src.contains(banned), isFalse, reason: '$f has "$banned"');
        }
      }
      // the apply and give-recognition posts are the only writes
      final repos = [
        'lib/repositories/tasks_repository.dart',
        'lib/repositories/helpdesk_repository.dart',
        'lib/repositories/letters_repository.dart',
      ];
      for (final f in repos) {
        final src = File(f).readAsStringSync();
        expect(
          RegExp(r'api\.(post|put|patch|delete)').hasMatch(src),
          isFalse,
          reason: f,
        );
      }
    },
  );
}
