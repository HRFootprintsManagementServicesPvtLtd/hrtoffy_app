import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/chat_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _channel(
  String id,
  String type, {
  String? name,
  String? other,
  String? last,
  String? lastAt,
  int unread = 0,
  String created = '2026-10-01T09:00:00.000Z',
}) => {
  'id': id,
  'organization_id': testOrgId,
  'channel_type': type,
  'name': name,
  'other_member_name': other,
  'last_message': last,
  'last_message_at': lastAt,
  'unread_count': unread,
  'created_at': created,
};

Map<String, dynamic> _msg(
  String id,
  String at, {
  String content = 'hi',
  String type = 'text',
  String sender = 'someone',
  bool deleted = false,
  List<Map<String, dynamic>>? attachments,
}) => {
  'id': id,
  'channel_id': 'ch-1',
  'sender_user_id': sender,
  'sender_name': 'Asha Rao',
  'content': deleted ? null : content,
  'message_type': type,
  'is_deleted': deleted,
  'created_at': at,
  'attachments': attachments ?? [],
};

void main() {
  group('channels()', () {
    test(
      'GET /chat/channels - one call; DM titled by the other person, groups by name; fields mapped; newest first',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _channel(
              'g1',
              'group',
              name: 'Project X',
              last: 'Ship it',
              lastAt: '2026-10-08T10:00:00.000Z',
              unread: 3,
            ),
            _channel(
              'd1',
              'dm',
              other: 'Ravi Kumar',
              last: 'See you',
              lastAt: '2026-10-08T12:00:00.000Z',
            ),
            _channel('d2', 'dm', created: '2026-09-01T09:00:00.000Z'),
          ]),
        );
        final list = await ChatRepository(auth: s.auth).channels();
        expect(s.apiCalls, hasLength(1));
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/chat/channels');
        expect(s.last.headers['Authorization'], 'Bearer acc');

        expect(list.map((c) => c.id), ['d1', 'g1', 'd2']);
        final dm = list[0];
        expect(dm.title, 'Ravi Kumar');
        expect(dm.type, 'dm');
        expect(dm.latestMessage, 'See you');
        expect(dm.latestTime, DateTime.parse('2026-10-08T12:00:00.000Z'));
        expect(dm.unreadCount, 0);
        final group = list[1];
        expect(group.title, 'Project X');
        expect(group.type, 'group');
        expect(group.unreadCount, 3);
        // no messages yet: placeholder text and the channel's creation time
        expect(list[2].latestMessage, 'No messages yet');
        expect(list[2].latestTime, DateTime.parse('2026-09-01T09:00:00.000Z'));
        expect(list[2].title, 'Direct Message');
      },
    );

    test('a group without a name still gets a title; empty list', () async {
      final s = await signedIn((req) async => ok([_channel('g', 'group')]));
      expect(
        (await ChatRepository(auth: s.auth).channels()).single.title,
        'Group Chat',
      );
      final e = await signedIn((req) async => ok([]));
      expect(await ChatRepository(auth: e.auth).channels(), isEmpty);
    });
  });

  group('messages()', () {
    test(
      'GET /chat/channels/:id/messages - data.messages, oldest first, deleted ones dropped',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'messages': [
              _msg('m2', '2026-10-08T10:05:00.000Z', content: 'second'),
              _msg(
                'm1',
                '2026-10-08T10:00:00.000Z',
                content: 'first',
                sender: testUserId,
              ),
              _msg('m3', '2026-10-08T10:06:00.000Z', deleted: true),
            ],
            'members': [
              {'user_id': testUserId, 'role': 'owner'},
            ],
          }),
        );
        final rows = await ChatRepository(auth: s.auth).messages('ch-1');
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/chat/channels/ch-1/messages');
        expect(rows.map((m) => m['id']), ['m1', 'm2']);
        expect(rows.first['content'], 'first');
        expect(rows.first['sender_user_id'], testUserId);
        expect(rows.first['sender_name'], 'Asha Rao');
      },
    );

    test(
      'attachments[] are mapped (file messages), other messages get an empty list',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'messages': [
              _msg('m1', '2026-10-08T10:00:00.000Z', content: 'plain'),
              _msg(
                'm2',
                '2026-10-08T10:01:00.000Z',
                content: '📎 report.pdf',
                type: 'file',
                attachments: [
                  {
                    'id': 'a1',
                    'message_id': 'm2',
                    'file_name': 'report.pdf',
                    'file_url': 'chat-attachments/$testOrgId/ch-1/1-report.pdf',
                    'file_size': 2048,
                    'file_type': 'application/pdf',
                  },
                ],
              ),
            ],
            'members': [],
          }),
        );
        final rows = await ChatRepository(auth: s.auth).messages('ch-1');
        expect(rows[0]['attachments'], isEmpty);
        final a =
            (rows[1]['attachments'] as List).single as Map<String, dynamic>;
        expect(a['file_name'], 'report.pdf');
        expect(a['file_url'], 'chat-attachments/$testOrgId/ch-1/1-report.pdf');
        expect(a['file_type'], 'application/pdf');
        expect(a['file_size'], 2048);
      },
    );

    test('empty channel and errors', () async {
      final s = await signedIn(
        (req) async => ok({'messages': [], 'members': []}),
      );
      expect(await ChatRepository(auth: s.auth).messages('ch-1'), isEmpty);
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'You are not a member of this channel'},
        }, 403),
      );
      await expectLater(
        ChatRepository(auth: f.auth).messages('ch-1'),
        throwsA(
          isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
        ),
      );
    });
  });

  group('sending', () {
    test(
      'sendText: POST /messages with {channelId, content, messageType: text} and no sender id',
      () async {
        final s = await signedIn(
          (req) async => ok({'id': 'm9', 'content': 'hello'}),
        );
        final m = await ChatRepository(auth: s.auth).sendText('ch-1', 'hello');
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/messages');
        expect(s.last.json, {
          'channelId': 'ch-1',
          'content': 'hello',
          'messageType': 'text',
        });
        expect((s.last.json as Map).containsKey('sender_user_id'), isFalse);
        expect(m['id'], 'm9');
      },
    );

    test(
      'sendFile: upload (chat-attachments + channelId) -> file message -> attachment record with the file reference',
      () async {
        const ref = 'chat-attachments/$testOrgId/ch-1/1-report.pdf';
        final s = await signedIn((req) async {
          switch (req.url.path) {
            case '$_org/files':
              return ok({
                'bucket': 'chat-attachments',
                'path': '$testOrgId/ch-1/1-report.pdf',
                'ref': ref,
                'url': null,
                'size': 4,
              }, 201);
            case '$_org/messages':
              return ok({'id': 'm7'}, 201);
            case '$_org/message-attachments':
              return ok({'id': 'a1'}, 201);
          }
          return jsonResponse({
            'success': false,
            'error': {'message': 'unexpected ${req.url.path}'},
          }, 404);
        });
        final m = await ChatRepository(auth: s.auth).sendFile(
          'ch-1',
          bytes: [1, 2, 3, 4],
          fileName: 'report.pdf',
          contentType: 'application/pdf',
        );
        expect(m['id'], 'm7');

        expect(s.apiCalls.map((r) => '${r.method} ${r.path}'), [
          'POST $_org/files',
          'POST $_org/messages',
          'POST $_org/message-attachments',
        ]);
        expect(s.apiCalls[0].query['bucket'], 'chat-attachments');
        expect(s.apiCalls[0].query['channelId'], 'ch-1');
        expect(s.apiCalls[1].json, {
          'channelId': 'ch-1',
          'content': '📎 report.pdf',
          'messageType': 'file',
        });
        expect(s.apiCalls[2].json, {
          'messageId': 'm7',
          'fileName': 'report.pdf',
          'fileUrl': ref,
          'fileSize': 4,
          'fileType': 'application/pdf',
        });
      },
    );

    test(
      'a failed upload creates no message; a failed attachment record is reported',
      () async {
        final up = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'You are not a member of this channel'},
          }, 403),
        );
        await expectLater(
          ChatRepository(
            auth: up.auth,
          ).sendFile('ch-1', bytes: [1], fileName: 'a.pdf'),
          throwsA(isA<ApiException>()),
        );
        expect(up.apiCalls.where((r) => r.path == '$_org/messages'), isEmpty);

        final att = await signedIn((req) async {
          if (req.url.path == '$_org/files')
            return ok({
              'bucket': 'chat-attachments',
              'path': 'p',
              'ref': 'chat-attachments/p',
              'url': null,
              'size': 1,
            }, 201);
          if (req.url.path == '$_org/messages') return ok({'id': 'm1'}, 201);
          return jsonResponse({
            'success': false,
            'error': {'message': 'boom'},
          }, 500);
        });
        await expectLater(
          ChatRepository(
            auth: att.auth,
          ).sendFile('ch-1', bytes: [1], fileName: 'a.pdf'),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'attachmentUrl: a signed link from the Files API for the private reference',
      () async {
        final s = await signedIn(
          (req) async => ok({'url': 'https://files.example/signed?x=1'}),
        );
        final url = await ChatRepository(
          auth: s.auth,
        ).attachmentUrl('chat-attachments/org/ch/1-a.pdf');
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/files/url');
        expect(s.last.query['ref'], 'chat-attachments/org/ch/1-a.pdf');
        expect(url, 'https://files.example/signed?x=1');
      },
    );
  });

  group('new chats', () {
    test('directory: GET /chat/employees mapping', () async {
      final s = await signedIn(
        (req) async => ok([
          {
            'id': 'e1',
            'full_name': 'Ravi Kumar',
            'department': 'Eng',
            'designation': 'Dev',
            'avatar_url': null,
            'user_id': 'u1',
          },
        ]),
      );
      final list = await ChatRepository(auth: s.auth).directory();
      expect(s.last.method, 'GET');
      expect(s.last.path, '$_org/chat/employees');
      expect(list.single['full_name'], 'Ravi Kumar');
      expect(list.single['user_id'], 'u1');
      expect(list.single['id'], 'e1');
    });

    test(
      'openDirectMessage: POST /chat/channels/dm with {otherUserId, otherEmployeeId}; returns the channel id (existing or new)',
      () async {
        final s = await signedIn(
          (req) async => ok({'id': 'ch-5', 'existed': true}),
        );
        final id = await ChatRepository(
          auth: s.auth,
        ).openDirectMessage(otherUserId: 'u1', otherEmployeeId: 'e1');
        expect(
          s.apiCalls,
          hasLength(1),
        ); // no "find the existing DM" calls from the app
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/chat/channels/dm');
        expect(s.last.json, {'otherUserId': 'u1', 'otherEmployeeId': 'e1'});
        expect(id, 'ch-5');
      },
    );

    test(
      'createGroup: POST /chat/channels/group with {name, description, members: [{employeeId, userId}]}',
      () async {
        final s = await signedIn(
          (req) async => ok({'id': 'ch-6', 'name': 'Project X'}),
        );
        final id = await ChatRepository(auth: s.auth).createGroup(
          name: 'Project X',
          description: 'Launch team',
          members: [
            (employeeId: 'e1', userId: 'u1'),
            (employeeId: 'e2', userId: 'u2'),
          ],
        );
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/chat/channels/group');
        expect(s.last.json, {
          'name': 'Project X',
          'description': 'Launch team',
          'members': [
            {'employeeId': 'e1', 'userId': 'u1'},
            {'employeeId': 'e2', 'userId': 'u2'},
          ],
        });
        expect(id, 'ch-6');
      },
    );

    test(
      'createGroup without a description leaves it out; a response without an id is an error',
      () async {
        final s = await signedIn((req) async => ok({'id': 'ch-6'}));
        await ChatRepository(auth: s.auth).createGroup(
          name: 'G',
          description: '',
          members: [(employeeId: 'e1', userId: 'u1')],
        );
        expect((s.last.json as Map).containsKey('description'), isFalse);
        final bad = await signedIn((req) async => ok({'nope': true}));
        await expectLater(
          ChatRepository(
            auth: bad.auth,
          ).openDirectMessage(otherUserId: 'u', otherEmployeeId: 'e'),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('settings, read state', () {
    test(
      'settings: GET /chat/settings with defaults for missing values',
      () async {
        final s = await signedIn(
          (req) async =>
              ok({'allow_file_sharing': false, 'max_file_size_mb': '5.00'}),
        );
        final st = await ChatRepository(auth: s.auth).settings();
        expect(s.last.path, '$_org/chat/settings');
        expect(st.allowFileSharing, isFalse);
        expect(st.maxFileSizeMb, 5);
        expect(st.allowGroupChannels, isTrue);
        final d = await signedIn((req) async => ok({}));
        final def = await ChatRepository(auth: d.auth).settings();
        expect(def.allowFileSharing, isTrue);
        expect(def.maxFileSizeMb, 10);
      },
    );

    test('markRead and unreadCount use the verified routes', () async {
      final s = await signedIn(
        (req) async => req.method == 'PUT'
            ? jsonResponse({'success': true})
            : ok({'total': 4}),
      );
      final repo = ChatRepository(auth: s.auth);
      await repo.markRead('ch-1');
      expect(s.last.method, 'PUT');
      expect(s.last.path, '$_org/chat/channels/ch-1/read');
      expect(await repo.unreadCount(), 4);
      expect(s.last.path, '$_org/chat/unread-count');
    });

    test('currentUserId is the signed-in user id', () async {
      final s = await signedIn((req) async => ok([]));
      expect(ChatRepository(auth: s.auth).currentUserId, testUserId);
    });
  });

  group('chatErrorText', () {
    test('never exposes raw URLs, tokens or server internals', () {
      expect(
        chatErrorText(
          const ApiException(500, 'db exploded at https://api.hrtoffy.in/x'),
          'Could not send.',
        ),
        'Could not send.',
      );
      expect(
        chatErrorText(
          const ApiException(401, 'bad token abc'),
          'Could not send.',
        ),
        'Could not send.',
      );
      expect(
        chatErrorText(
          Exception('SocketException: https://api.hrtoffy.in/organizations/x'),
          'Could not send.',
        ),
        'Could not send.',
      );
      expect(
        chatErrorText(
          const ApiException(0, 'Failed host lookup api.hrtoffy.in'),
          'x',
        ),
        isNot(contains('hrtoffy')),
      );
    });

    test('passes on the server\'s refusals worded for the user', () {
      expect(
        chatErrorText(
          const ApiException(
            403,
            'Group channels are turned off for your organisation',
          ),
          'x',
        ),
        'Group channels are turned off for your organisation',
      );
      expect(
        chatErrorText(const ApiException(404, 'Employee not found'), 'x'),
        'Employee not found',
      );
    });
  });
}
