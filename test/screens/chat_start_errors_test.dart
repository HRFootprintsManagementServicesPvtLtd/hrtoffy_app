import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/chat_repository.dart';
import 'package:hrms_app/widgets/create_channel_dialog.dart';
import 'package:hrms_app/widgets/new_chat_dialog.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _directory = [
  {'id': 'e1', 'full_name': 'Ravi Kumar', 'department': 'Eng', 'designation': 'Dev', 'avatar_url': null, 'user_id': 'u1'},
  {'id': 'e2', 'full_name': 'Meera Iyer', 'department': 'HR', 'designation': 'Lead', 'avatar_url': null, 'user_id': 'u2'},
];

/// The directory loads fine (it is read with elevated rights on the server) but creating the chat answers 404
/// "Employee not found" (the lookup of the colleague runs under row-level security).
Future<TestSession> _session({String createPath = '', int status = 404}) => signedIn((req) async {
      if (req.url.path == '$_org/chat/employees') return ok(_directory);
      if (req.url.path == createPath) {
        return jsonResponse({'success': false, 'error': {'message': 'Employee not found'}}, status);
      }
      return jsonResponse({'success': false}, 404);
    });

void main() {
  testWidgets('starting a direct message that the server answers with 404 says the chat could not be started, not "Employee not found"', (tester) async {
    _tall(tester);
    final s = await _session(createPath: '$_org/chat/channels/dm');
    var created = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NewChatDialog(onCreated: () => created++, repository: ChatRepository(auth: s.auth))),
    ));
    await _settle(tester);

    await tester.tap(find.text('Ravi Kumar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final dm = s.apiCalls.firstWhere((r) => r.path == '$_org/chat/channels/dm');
    expect(dm.json, {'otherUserId': 'u1', 'otherEmployeeId': 'e1'}, reason: 'the request itself is what the server expects');
    expect(find.text(kChatStartNotFoundMessage), findsOneWidget);
    expect(find.text('Employee not found'), findsNothing);
    expect(created, 0);
  });

  testWidgets('creating a group that the server answers with 404 shows the same clear message', (tester) async {
    _tall(tester);
    final s = await _session(createPath: '$_org/chat/channels/group');
    var created = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CreateChannelDialog(onCreated: () => created++, repository: ChatRepository(auth: s.auth))),
    ));
    await _settle(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Channel name (required)'), 'Project X');
    await tester.tap(find.text('Ravi Kumar'));
    await tester.pump();
    await tester.tap(find.text('Create Channel'));
    await _settle(tester);

    expect(find.text(kChatStartNotFoundMessage), findsOneWidget);
    expect(find.text('Employee not found'), findsNothing);
    expect(created, 0);
  });

  testWidgets('a 404 while LOADING the directory has its own message, never the server text and not the start-chat message', (tester) async {
    _tall(tester);
    final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'Route not found'}}, 404));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NewChatDialog(onCreated: () {}, repository: ChatRepository(auth: s.auth))),
    ));
    await _settle(tester);
    expect(find.text(kChatDirectoryNotFoundMessage), findsOneWidget);
    expect(find.textContaining('Route not found'), findsNothing);
    expect(find.text(kChatStartNotFoundMessage), findsNothing);
  });

  test('chatErrorText only replaces a 404 when a replacement is given; other statuses are unchanged', () {
    const nf = ApiException(404, 'Employee not found');
    expect(chatErrorText(nf, 'x'), 'Employee not found');
    expect(chatErrorText(nf, 'x', notFound: 'custom'), 'custom');
    expect(chatErrorText(const ApiException(403, 'Group channels are turned off'), 'x', notFound: 'custom'), 'Group channels are turned off');
    expect(chatErrorText(const ApiException(500, 'boom'), 'fallback', notFound: 'custom'), 'fallback');
    expect(chatErrorText(const ApiException(0, 'net'), 'fallback', notFound: 'custom'), contains('No connection'));
  });
}
