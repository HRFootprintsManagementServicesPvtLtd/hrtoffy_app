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

Future<Widget> _screen({required int docsStatus, List<Map<String, dynamic>> docs = const []}) async {
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'GET') {
      if (p == '$_org/employees/me') return ok({'id': testEmployeeId, 'organizationId': testOrgId, 'fullName': 'Zara Khan', 'email': 'me@x.com'});
      if (p == '$_org/employees/$testEmployeeId/nominees') return ok({'items': <dynamic>[]});
      if (p == '$_org/insurance/policies') return ok({'items': <dynamic>[]});
      if (p == '$_org/employees/$testEmployeeId/documents') {
        if (docsStatus != 200) return jsonResponse({'success': false, 'error': {'code': 'FORBIDDEN', 'message': 'DOCUMENTS_VIEW'}}, docsStatus);
        return jsonResponse({'items': docs});
      }
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

Future<void> _open(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(900, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the uploaded documents are listed (names and types), newest first', (tester) async {
    await _open(tester, await _screen(docsStatus: 200, docs: [
      {'id': 'd1', 'documentName': 'old.pdf', 'documentType': 'personal_upload', 'fileUrl': 'employee-documents/a', 'uploadedAt': '2026-10-01T00:00:00.000Z'},
      {'id': 'd2', 'documentName': 'new.pdf', 'documentType': 'personal_upload', 'fileUrl': 'employee-documents/b', 'uploadedAt': '2026-10-15T00:00:00.000Z'},
    ]));
    expect(find.text('new.pdf'), findsOneWidget);
    expect(find.text('old.pdf'), findsOneWidget);
    expect(find.text('No documents uploaded.'), findsNothing);
    expect(tester.getTopLeft(find.text('new.pdf')).dy, lessThan(tester.getTopLeft(find.text('old.pdf')).dy));
  });

  testWidgets('an empty list says "No documents uploaded."', (tester) async {
    await _open(tester, await _screen(docsStatus: 200));
    expect(find.text('No documents uploaded.'), findsOneWidget);
  });

  for (final status in [403, 500, 404]) {
    testWidgets('a failed list ($status) says it could not be loaded, never "No documents uploaded."', (tester) async {
      await _open(tester, await _screen(docsStatus: status));
      expect(find.text('No documents uploaded.'), findsNothing);
      expect(find.textContaining("Documents couldn't be loaded"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
