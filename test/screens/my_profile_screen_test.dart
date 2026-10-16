import 'dart:convert';

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

Map<String, dynamic> _me(String phone) => {
      'id': testEmployeeId,
      'organizationId': testOrgId,
      'fullName': 'Asha Rao',
      'employeeId': 'GC-001',
      'email': 'me@x.com',
      'phone': phone,
      'department': 'Finance',
      'designation': 'Analyst',
      'dateOfBirth': '1995-04-02',
      'dateOfJoining': '2023-06-01',
    };

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

class _Env {
  _Env(this.session, this.patches, this.gets);
  final TestSession session;
  final List<Map<String, dynamic>> patches;
  final List<String> gets;
}

Future<_Env> _env({int patchStatus = 200, String patchMessage = 'server text that must not be shown'}) async {
  final patches = <Map<String, dynamic>>[];
  final gets = <String>[];
  var phone = '9000000001';
  final s = await signedIn((req) async {
    final p = req.url.path;
    if (req.method == 'PATCH' && p == '$_org/employees/me') {
      patches.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
      if (patchStatus != 200) {
        return jsonResponse({
          'success': false,
          'error': {'message': patchMessage},
        }, patchStatus);
      }
      phone = (patches.last['phone'] ?? phone).toString();
      return ok(_me(phone));
    }
    if (req.method == 'GET') {
      gets.add(p);
      if (p == '$_org/employees/me') return ok(_me(phone));
      if (p == '$_org/payroll/me/sensitive-profile') return jsonResponse({'success': false}, 404);
      if (p == '$_org/employees/$testEmployeeId/nominees') return ok({'items': <dynamic>[]});
      if (p == '$_org/employees/$testEmployeeId/documents') return ok({'items': <dynamic>[]});
      if (p == '$_org/insurance/policies') return ok({'items': <dynamic>[]});
    }
    return jsonResponse({'success': false}, 404);
  });
  return _Env(s, patches, gets);
}

Widget _screen(_Env e) => ChangeNotifierProvider<RoleProvider>(
      create: (_) => RoleProvider(),
      child: MaterialApp(
        home: MyProfileScreen(
          email: 'me@x.com',
          userData: const {'id': testEmployeeId},
          fetchHrmsContext: () async => {},
          employeeRepository: EmployeeRepository(auth: e.session.auth),
          profileRepository: ProfileRepository(auth: e.session.auth),
          fileRepository: FileRepository(auth: e.session.auth),
        ),
      ),
    );

Finder get _phoneField => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Phone Number');

Future<void> _openBasicEditor(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_outlined).first);
  await tester.pumpAndSettle();
  expect(find.text('Edit Basic Information'), findsOneWidget);
}

void main() {
  testWidgets('the profile loads from the API and shows the employee', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    expect(find.textContaining('Asha Rao'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a field and saving sends one PATCH with the change, then shows the new value, with no framework error', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);

    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, '9123456789');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(e.patches, hasLength(1));
    expect(e.patches.single['phone'], '9123456789');
    expect(e.patches.single.containsKey('email'), isFalse, reason: 'the sign-in email is never sent');
    expect(find.textContaining('Details updated'), findsOneWidget);
    expect(find.textContaining('9123456789'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the keyboard while a dialog is open does not reload the screen underneath or throw', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    final loadsBefore = e.gets.where((p) => p == '$_org/employees/me').length;

    await _openBasicEditor(tester);
    // the on-screen keyboard appears: MediaQuery.viewInsets changes
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.enterText(_phoneField, '9123456789');
    await tester.pump(const Duration(milliseconds: 300));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Basic Information'), findsOneWidget, reason: 'the dialog stays open');
    expect(
      e.gets.where((p) => p == '$_org/employees/me').length,
      loadsBefore,
      reason: 'a keyboard (layout) change is not a reason to reload the profile',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editors the website allows (basic, personal, emergency contact) open and close without a framework error', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.edit_outlined).at(i));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget, reason: 'editor $i opened');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'editor $i');
    }
    expect(e.patches, isEmpty);
  });

  testWidgets('work, bank and statutory (PAN, Aadhaar, UAN) details are read-only: managed by HR, with no editor', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    expect(find.text('Managed by HR'), findsNWidgets(3));
    // editable sections: basic, personal, emergency contact, nominees, documents
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(5));
    expect(find.text('Edit Bank Details'), findsNothing);
  });

  testWidgets('a phone number the website would refuse is not sent: the editor stays open with the reason', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, 'call me');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(e.patches, isEmpty);
    expect(find.textContaining('Enter a valid phone number'), findsOneWidget);
    expect(find.text('Edit Basic Information'), findsOneWidget, reason: 'the editor stays open so the input is not lost');

    // the website's pattern allows spaces, + - ( )
    await tester.enterText(_phoneField, '+91 (900) 123-4567');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(e.patches, hasLength(1));
    expect(e.patches.single.keys.toSet().difference(kEmployeeEditableProfileFields.map(_camel).toSet()), isEmpty,
        reason: 'only fields the website lets an employee edit are sent');
  });

  group('profileFieldError', () {
    final now = DateTime(2026, 10, 14);
    test('phone numbers follow the website pattern', () {
      expect(profileFieldError({'phone': '+91 98765-43210'}, now: now), isNull);
      expect(profileFieldError({'phone': '(040) 1234 567'}, now: now), isNull);
      expect(profileFieldError({'phone': ''}, now: now), isNull, reason: 'empty clears the field');
      expect(profileFieldError({'phone': '12345'}, now: now), isNotNull, reason: 'too short');
      expect(profileFieldError({'phone': '1' * 21}, now: now), isNotNull, reason: 'too long');
      expect(profileFieldError({'phone': 'abc1234567'}, now: now), isNotNull);
      expect(profileFieldError({'emergency_contact_number': 'x'}, now: now), isNotNull);
    });

    test('date of birth: valid, future and under 14', () {
      expect(profileFieldError({'date_of_birth': '1995-04-02'}, now: now), isNull);
      expect(profileFieldError({'date_of_birth': '2027-01-01'}, now: now), contains('future'));
      expect(profileFieldError({'date_of_birth': '2015-01-01'}, now: now), contains('14'));
      expect(profileFieldError({'date_of_birth': '2012-10-14'}, now: now), isNull, reason: 'exactly 14 today');
      expect(profileFieldError({'date_of_birth': 'garbage'}, now: now), isNotNull);
    });

    test('the editable field set is exactly the website\'s fifteen', () {
      expect(kEmployeeEditableProfileFields.length, 15);
      for (final hrOnly in ['bank_name', 'bank_account_no', 'bank_ifsc_code', 'pan_no', 'aadhaar_number', 'uan_no', 'department', 'designation', 'grade_code', 'employment_status', 'salary', 'email', 'emp_role']) {
        expect(kEmployeeEditableProfileFields.contains(hrOnly), isFalse, reason: hrOnly);
      }
    });
  });

  testWidgets('cancelling the editor sends nothing and throws nothing', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, '9123456789');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(e.patches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save the server refuses shows a friendly message, never the server text, and nothing crashes', (tester) async {
    _tall(tester);
    final e = await _env(patchStatus: 500);
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, '9123456789');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('server is busy'), findsOneWidget);
    expect(find.textContaining('server text'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after a save the profile is re-read from the server, and the new value is still there when the editor is reopened', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    final loadsBefore = e.gets.where((p) => p == '$_org/employees/me').length;

    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, '9123456789');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Basic Information'), findsNothing, reason: 'the editor closes once the server accepted the save');
    expect(e.gets.where((p) => p == '$_org/employees/me').length, loadsBefore + 1, reason: 'the profile is fetched again after the PATCH');
    expect(find.text('9123456789'), findsWidgets, reason: 'the card shows the server-returned value');

    // leave and reopen: the editor starts from the refreshed server value
    await _openBasicEditor(tester);
    final field = tester.widget<TextField>(_phoneField);
    expect(field.controller!.text, '9123456789');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('a save the server does not accept never looks like success', () {
    Future<void> saveRefused(WidgetTester tester, {required int status, String message = 'x', required Matcher shows}) async {
      _tall(tester);
      final e = await _env(patchStatus: status, patchMessage: message);
      await tester.pumpWidget(_screen(e));
      await _settle(tester);
      await _openBasicEditor(tester);
      await tester.enterText(_phoneField, '9123456789');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(e.patches, hasLength(1), reason: 'one attempt was made');
      expect(find.textContaining('Details updated'), findsNothing);
      expect(find.textContaining('Details saved'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Text && shows.matches(w.data ?? '', {})), findsOneWidget);
      expect(find.text('Edit Basic Information'), findsOneWidget, reason: 'the editor stays open so the input is not lost');
      expect(tester.widget<TextField>(_phoneField).controller!.text, '9123456789');
      expect(find.text('9000000001'), findsWidgets, reason: 'the profile still shows the stored value');
      expect(tester.takeException(), isNull);
    }

    testWidgets('404: the save route is missing on the server', (tester) async {
      await saveRefused(tester, status: 404, message: 'Route PATCH:/organizations/x/employees/me not found', shows: contains('not saved'));
    });

    testWidgets('400: the server\'s validation message is shown', (tester) async {
      await saveRefused(tester, status: 400, message: 'dateOfBirth must be a valid date', shows: equals('dateOfBirth must be a valid date'));
    });

    testWidgets('403: forbidden', (tester) async {
      await saveRefused(tester, status: 403, shows: contains("don't have permission"));
    });

    testWidgets('401: unauthorized', (tester) async {
      await saveRefused(tester, status: 401, shows: contains('Session expired'));
    });
  });

  testWidgets('the personal-information editor saves only whitelisted fields (no HR-managed key is ever sent)', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit Personal Information'), findsOneWidget);
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Current Address'), '12 Park Street');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(e.patches, hasLength(1));
    expect(e.patches.single['currentAddress'], '12 Park Street');
    expect(e.patches.single.keys.toSet().difference(kEmployeeEditableProfileFields.map(_camel).toSet()), isEmpty);
    for (final hr in ['bankName', 'bankAccountNo', 'bankIfscCode', 'panNo', 'aadhaarNumber', 'uanNo', 'department', 'designation', 'email']) {
      expect(e.patches.single.containsKey(hr), isFalse, reason: hr);
    }
  });

  testWidgets('the screen can be left while a save is still running without a framework error', (tester) async {
    _tall(tester);
    final e = await _env();
    await tester.pumpWidget(_screen(e));
    await _settle(tester);
    await _openBasicEditor(tester);
    await tester.enterText(_phoneField, '9123456789');
    await tester.tap(find.text('Save'));
    await tester.pump(); // request in flight
    await tester.pumpWidget(const MaterialApp(home: SizedBox())); // the screen is disposed
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

String _camel(String s) => s.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
