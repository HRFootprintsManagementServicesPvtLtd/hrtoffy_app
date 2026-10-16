import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/chat_repository.dart';
import 'package:hrms_app/screens/chat_thread_screen.dart';
import 'package:hrms_app/screens/messages_screen.dart';
import 'package:hrms_app/services/chat_service.dart';
import 'package:hrms_app/widgets/chat_message_bubble.dart';
import 'package:hrms_app/widgets/create_channel_dialog.dart';
import 'package:hrms_app/widgets/new_chat_dialog.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _messages = '$_org/chat/channels/ch-1/messages';
const _poll = Duration(seconds: 2);

Map<String, dynamic> _msg(
  String id,
  String at,
  String content, {
  String sender = 'someone-else',
  List<Map<String, dynamic>> attachments = const [],
  String type = 'text',
}) => {
  'id': id,
  'channel_id': 'ch-1',
  'sender_user_id': sender,
  'content': content,
  'message_type': type,
  'is_deleted': false,
  'created_at': at,
  'attachments': attachments,
};

Future<void> _settle(WidgetTester t, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _thread(TestSession s) => MaterialApp(
  home: ChatThreadScreen(
    channelId: 'ch-1',
    title: 'Ravi Kumar',
    repository: ChatRepository(auth: s.auth),
    pollInterval: _poll,
  ),
);

int _messageGets(TestSession s) =>
    s.apiCalls.where((r) => r.method == 'GET' && r.path == _messages).length;

void main() {
  group('ChatThreadScreen', () {
    testWidgets(
      'shows the history from the AWS messages route, mine on the right',
      (tester) async {
        _tall(tester);
        final s = await signedIn(
          (req) async => ok({
            'messages': [
              _msg('m1', '2026-10-08T10:00:00.000Z', 'Hello there'),
              _msg(
                'm2',
                '2026-10-08T10:01:00.000Z',
                'Hi back',
                sender: testUserId,
              ),
            ],
            'members': [],
          }),
        );
        await tester.pumpWidget(_thread(s));
        await _settle(tester);

        expect(s.apiCalls.first.path, _messages);
        expect(find.text('Hello there'), findsOneWidget);
        expect(find.text('Hi back'), findsOneWidget);
        Alignment alignOf(String text) =>
            tester
                    .widget<Align>(
                      find
                          .ancestor(
                            of: find.text(text),
                            matching: find.byType(Align),
                          )
                          .first,
                    )
                    .alignment
                as Alignment;
        expect(alignOf('Hi back'), Alignment.centerRight);
        expect(alignOf('Hello there'), Alignment.centerLeft);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'polling picks up new messages without duplicating the existing ones',
      (tester) async {
        _tall(tester);
        var polls = 0;
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/chat/settings') return ok({});
          polls++; // counts the message fetches only: 1 = first load, 2 = first poll, 3 = second poll
          final base = [
            _msg('m1', '2026-10-08T10:00:00.000Z', 'first message'),
          ];
          final withNew = [
            ...base,
            _msg('m2', '2026-10-08T10:05:00.000Z', 'second message'),
          ];
          return ok({'messages': polls >= 3 ? withNew : base, 'members': []});
        });
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        expect(find.text('first message'), findsOneWidget);

        // identical polls: still exactly one of each, no extra rows
        await tester.pump(_poll);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('first message'), findsOneWidget);
        expect(find.text('second message'), findsNothing);

        // the new message arrives; the first is not repeated
        await tester.pump(_poll);
        await tester.pump(const Duration(milliseconds: 50));
        await _settle(tester);
        expect(find.text('second message'), findsOneWidget);
        expect(find.text('first message'), findsOneWidget);
        expect(find.byType(ChatMessageBubble), findsNWidgets(2));

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'one timer only: rebuilding the screen does not multiply the polling',
      (tester) async {
        _tall(tester);
        final s = await signedIn(
          (req) async => ok({
            'messages': [_msg('m1', '2026-10-08T10:00:00.000Z', 'hello')],
            'members': [],
          }),
        );
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        final before = _messageGets(s);

        // several rebuilds of the same screen (same widget tree)
        for (var i = 0; i < 5; i++) {
          await tester.pumpWidget(_thread(s));
        }
        await tester.pump(_poll);
        await tester.pump(_poll);
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          _messageGets(s) - before,
          2,
        ); // one request per interval, not five

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'polling stops when the screen is left (dispose cancels the timer)',
      (tester) async {
        _tall(tester);
        final s = await signedIn(
          (req) async => ok({
            'messages': [_msg('m1', '2026-10-08T10:00:00.000Z', 'hello')],
            'members': [],
          }),
        );
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        await tester.pump(_poll);
        await tester.pump(const Duration(milliseconds: 50));
        final whileOpen = _messageGets(s);
        expect(whileOpen, greaterThan(1));

        await tester.pumpWidget(const SizedBox()); // leave the thread
        await tester.pump(_poll * 5);
        expect(_messageGets(s), whileOpen);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets(
      'sending text posts {channelId, content, messageType} and refreshes the thread',
      (tester) async {
        _tall(tester);
        var sent = false;
        final s = await signedIn((req) async {
          if (req.method == 'POST' && req.url.path == '$_org/messages') {
            sent = true;
            return ok({'id': 'm2', 'content': 'on my way'}, 201);
          }
          if (req.url.path == '$_org/chat/settings') return ok({});
          return ok({
            'messages': [
              _msg('m1', '2026-10-08T10:00:00.000Z', 'where are you?'),
              if (sent)
                _msg(
                  'm2',
                  '2026-10-08T10:01:00.000Z',
                  'on my way',
                  sender: testUserId,
                ),
            ],
            'members': [],
          });
        });
        await tester.pumpWidget(_thread(s));
        await _settle(tester);

        await tester.enterText(find.byType(TextField), '  on my way ');
        await tester.tap(find.byIcon(Icons.send));
        await _settle(tester);

        final post = s.apiCalls.firstWhere((r) => r.method == 'POST');
        expect(post.path, '$_org/messages');
        expect(post.json, {
          'channelId': 'ch-1',
          'content': 'on my way',
          'messageType': 'text',
        });
        expect(find.text('on my way'), findsOneWidget); // in the list, once
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a failed send keeps the text and shows a safe message (no URL or raw error)',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.method == 'POST')
            return jsonResponse({
              'success': false,
              'error': {
                'message':
                    'db exploded at https://api.hrtoffy.in/organizations/x',
              },
            }, 500);
          if (req.url.path == '$_org/chat/settings') return ok({});
          return ok({'messages': [], 'members': []});
        });
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'important text');
        await tester.tap(find.byIcon(Icons.send));
        await _settle(tester);

        expect(
          find.text('Could not send the message. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'important text',
        );

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'the attach button respects the organization\'s file-sharing setting',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/chat/settings')
            return ok({'allow_file_sharing': false, 'max_file_size_mb': 10});
          return ok({'messages': [], 'members': []});
        });
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.attach_file));
        await tester.pump();
        expect(
          find.text('File sharing is turned off for your organization.'),
          findsOneWidget,
        );
        expect(s.apiCalls.where((r) => r.path == '$_org/files'), isEmpty);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a file message shows the attachment name and never the private reference',
      (tester) async {
        _tall(tester);
        const ref = 'chat-attachments/$testOrgId/ch-1/1-report.pdf';
        final s = await signedIn(
          (req) async => ok({
            'messages': [
              _msg(
                'm1',
                '2026-10-08T10:00:00.000Z',
                '📎 report.pdf',
                type: 'file',
                attachments: [
                  {
                    'file_name': 'report.pdf',
                    'file_url': ref,
                    'file_type': 'application/pdf',
                    'file_size': 10,
                  },
                ],
              ),
            ],
            'members': [],
          }),
        );
        await tester.pumpWidget(_thread(s));
        await _settle(tester);
        expect(find.text('report.pdf'), findsOneWidget);
        expect(find.textContaining('chat-attachments'), findsNothing);
        expect(find.text('📎 report.pdf'), findsNothing);
        // not asked for a link until it is opened
        expect(s.apiCalls.where((r) => r.path == '$_org/files/url'), isEmpty);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('ChatMessageBubble attachments', () {
    Widget bubble(Map<String, dynamic> m, AttachmentUrlResolver? r) =>
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(message: m, isMine: false, resolveUrl: r),
          ),
        );

    test('attachmentOf reads attachments[] and ignores plain messages', () {
      expect(
        ChatMessageBubble.attachmentOf({'content': 'hi', 'attachments': []}),
        isNull,
      );
      expect(ChatMessageBubble.attachmentOf({'content': 'hi'}), isNull);
      final a = ChatMessageBubble.attachmentOf({
        'content': '📎 x.png',
        'attachments': [
          {
            'file_name': 'x.png',
            'file_url': 'chat-attachments/o/c/x.png',
            'file_type': 'image/png',
          },
        ],
      })!;
      expect(a.name, 'x.png');
      expect(a.ref, 'chat-attachments/o/c/x.png');
      expect(a.type, 'image/png');
    });

    testWidgets(
      'an image attachment asks for its signed link once, even across rebuilds',
      (tester) async {
        var calls = 0;
        Future<String> resolver(String ref) async {
          calls++;
          return 'https://files.example/signed';
        }

        final m = _msg(
          'm1',
          '2026-10-08T10:00:00.000Z',
          '📎 x.png',
          type: 'file',
          attachments: [
            {
              'file_name': 'x.png',
              'file_url': 'chat-attachments/o/c/x.png',
              'file_type': 'image/png',
            },
          ],
        );
        await tester.pumpWidget(bubble(m, resolver));
        await tester.pump();
        await tester.pumpWidget(bubble(m, resolver));
        await tester.pump();
        await tester.pumpWidget(bubble(m, resolver));
        await tester.pump();
        expect(calls, 1);
        expect(find.textContaining('chat-attachments'), findsNothing);
      },
    );

    testWidgets('a text message shows its content', (tester) async {
      await tester.pumpWidget(
        bubble(_msg('m1', '2026-10-08T10:00:00.000Z', 'just text'), null),
      );
      expect(find.text('just text'), findsOneWidget);
    });
  });

  group('MessagesScreen', () {
    testWidgets('lists the conversations from GET /chat/channels', (
      tester,
    ) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => ok([
          {
            'id': 'd1',
            'channel_type': 'dm',
            'name': null,
            'other_member_name': 'Ravi Kumar',
            'last_message': 'See you',
            'last_message_at': '2026-10-08T12:00:00.000Z',
            'unread_count': 2,
            'created_at': '2026-10-01T09:00:00.000Z',
          },
          {
            'id': 'g1',
            'channel_type': 'group',
            'name': 'Project X',
            'other_member_name': null,
            'last_message': null,
            'last_message_at': null,
            'unread_count': 0,
            'created_at': '2026-10-02T09:00:00.000Z',
          },
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MessagesScreen(
            userEmail: 'me@x.com',
            userData: const {
              'id': testEmployeeId,
              'organization_id': testOrgId,
            },
            fetchHrmsContext: () async => {},
            chatService: ChatService(repository: ChatRepository(auth: s.auth)),
          ),
        ),
      );
      await _settle(tester);

      expect(s.apiCalls.single.path, '$_org/chat/channels');
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('See you'), findsOneWidget);
      expect(find.text('Project X'), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
    });
  });

  group('NewChatDialog', () {
    testWidgets(
      'lists the directory and opens a DM with {otherUserId, otherEmployeeId} (no search for existing DMs)',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/chat/employees') {
            return ok([
              {
                'id': 'e1',
                'full_name': 'Ravi Kumar',
                'department': 'Eng',
                'designation': 'Dev',
                'avatar_url': null,
                'user_id': 'u1',
              },
              {
                'id': 'e2',
                'full_name': 'Meera Iyer',
                'department': 'HR',
                'designation': 'Lead',
                'avatar_url': null,
                'user_id': 'u2',
              },
            ]);
          }
          if (req.url.path == '$_org/chat/channels/dm')
            return ok({'id': 'ch-9', 'existed': false});
          return jsonResponse({
            'success': false,
            'error': {'message': 'unexpected'},
          }, 404); // the thread opened afterwards
        });
        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NewChatDialog(
                onCreated: () => created++,
                repository: ChatRepository(auth: s.auth),
              ),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('Ravi Kumar'), findsOneWidget);
        expect(find.text('Meera Iyer'), findsOneWidget);

        await tester.tap(find.text('Ravi Kumar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final dm = s.apiCalls.firstWhere(
          (r) => r.path == '$_org/chat/channels/dm',
        );
        expect(dm.method, 'POST');
        expect(dm.json, {'otherUserId': 'u1', 'otherEmployeeId': 'e1'});
        expect(
          s.apiCalls.map((r) => r.path),
          isNot(contains('$_org/chat/channels/ch-9/members')),
        );
        expect(created, 1);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a failed directory load shows a safe message', (tester) async {
      _tall(tester);
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'pg exploded https://api.hrtoffy.in'},
        }, 500),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewChatDialog(
              onCreated: () {},
              repository: ChatRepository(auth: s.auth),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.text('Could not load employees. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('exploded'), findsNothing);
    });
  });

  group('CreateChannelDialog', () {
    testWidgets(
      'creates a group with {name, description, members: [{employeeId, userId}]}',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/chat/employees') {
            return ok([
              {
                'id': 'e1',
                'full_name': 'Ravi Kumar',
                'department': 'Eng',
                'designation': 'Dev',
                'avatar_url': null,
                'user_id': 'u1',
              },
              {
                'id': 'e2',
                'full_name': 'Meera Iyer',
                'department': 'HR',
                'designation': 'Lead',
                'avatar_url': null,
                'user_id': 'u2',
              },
            ]);
          }
          if (req.url.path == '$_org/chat/channels/group')
            return ok({'id': 'ch-10', 'name': 'Project X'});
          return jsonResponse({
            'success': false,
            'error': {'message': 'unexpected'},
          }, 404);
        });
        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CreateChannelDialog(
                onCreated: () => created++,
                repository: ChatRepository(auth: s.auth),
              ),
            ),
          ),
        );
        await _settle(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'Channel name (required)'),
          'Project X',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Description (optional)'),
          'Launch team',
        );
        await tester.tap(find.text('Ravi Kumar'));
        await tester.pump();
        await tester.tap(find.text('Meera Iyer'));
        await tester.pump();
        await tester.tap(find.text('Create Channel'));
        await _settle(tester);

        final post = s.apiCalls.firstWhere(
          (r) => r.path == '$_org/chat/channels/group',
        );
        expect(post.method, 'POST');
        expect(post.json, {
          'name': 'Project X',
          'description': 'Launch team',
          'members': [
            {'employeeId': 'e1', 'userId': 'u1'},
            {'employeeId': 'e2', 'userId': 'u2'},
          ],
        });
        expect(created, 1);
      },
    );

    testWidgets(
      'a refused group shows the server\'s refusal text but never a raw exception',
      (tester) async {
        _tall(tester);
        final s = await signedIn((req) async {
          if (req.url.path == '$_org/chat/employees') {
            return ok([
              {
                'id': 'e1',
                'full_name': 'Ravi Kumar',
                'department': 'Eng',
                'designation': 'Dev',
                'avatar_url': null,
                'user_id': 'u1',
              },
            ]);
          }
          return jsonResponse({
            'success': false,
            'error': {
              'message': 'Group channels are turned off for your organisation',
            },
          }, 403);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CreateChannelDialog(
                onCreated: () {},
                repository: ChatRepository(auth: s.auth),
              ),
            ),
          ),
        );
        await _settle(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Channel name (required)'),
          'G',
        );
        await tester.tap(find.text('Ravi Kumar'));
        await tester.pump();
        await tester.tap(find.text('Create Channel'));
        await _settle(tester);
        expect(
          find.text('Group channels are turned off for your organisation'),
          findsOneWidget,
        );
        expect(find.textContaining('ApiException'), findsNothing);
      },
    );
  });
}
