import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/file_repository.dart';
import 'package:hrms_app/repositories/profile_repository.dart';
import 'package:hrms_app/screens/my_profile_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _me(Object? avatarUrl) => {
      'id': testEmployeeId,
      'organizationId': testOrgId,
      'fullName': 'Zara Khan',
      'employeeId': 'GC-009',
      'email': 'me@x.com',
      'phone': '9000000001',
      'avatarUrl': avatarUrl,
    };

Future<Widget> _screen(Object? avatarUrl) async {
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'GET') {
      if (p == '$_org/employees/me') return ok(_me(avatarUrl));
      if (p == '$_org/employees/$testEmployeeId/nominees') return ok({'items': <dynamic>[]});
      if (p == '$_org/employees/$testEmployeeId/documents') return ok({'items': <dynamic>[]});
      if (p == '$_org/insurance/policies') return ok({'items': <dynamic>[]});
    }
    return jsonResponse({'success': false}, 404);
  });
  return ChangeNotifierProvider<RoleProvider>(
    create: (_) => RoleProvider(),
    child: MaterialApp(
      home: MyProfileScreen(
        email: 'me@x.com',
        userData: const {'id': testEmployeeId},
        fetchHrmsContext: () async => {},
        employeeRepository: EmployeeRepository(auth: s.auth),
        profileRepository: ProfileRepository(auth: s.auth),
        fileRepository: FileRepository(auth: s.auth),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final removed in <Object?>['', '   ', null]) {
    testWidgets('a removed photo (${removed == null ? 'null' : "'$removed'"}) shows the first letter of the name, and tapping it does nothing', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await _screen(removed));
      await _settle(tester);

      expect(find.text('Z'), findsWidgets, reason: 'the initial of "Zara Khan" is drawn instead of an empty circle');
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
      expect(avatar.backgroundImage, isNull);

      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing, reason: 'no full-screen image page with a broken image is opened');
      expect(tester.takeException(), isNull);
    });
  }
}
