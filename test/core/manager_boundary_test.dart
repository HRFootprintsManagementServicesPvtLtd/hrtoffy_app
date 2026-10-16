import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/auth/auth_service.dart';
import 'package:hrms_app/core/manager_access.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/screens/login_screen.dart';
import 'package:hrms_app/screens/manager/manager_dashboard_screen.dart';
import 'package:hrms_app/screens/manager/manager_unavailable_screen.dart';
import 'package:hrms_app/screens/splash_screen.dart';
import 'package:hrms_app/widgets/app_drawer.dart';
import 'package:hrms_app/widgets/drawer_route.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _manager = AuthUser(id: 'u', email: 'm@x.com', organizationId: 'o', employeeId: 'e1', empRole: 'manager');

Future<void> _signIn(WidgetTester t) async {
  await t.enterText(find.widgetWithText(TextField, 'Email'), 'me@x.com');
  await t.enterText(find.widgetWithText(TextField, 'Password'), 'Secret123');
  await t.tap(find.text('Sign In'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('Cancel')); // location disclosure
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  tearDown(() => ManagerAccess.debugOverride(null));

  group('the app (AWS auth is the only mode)', () {
    test('every manager feature is migrated and available', () {
      expect(ManagerAccess.available, isTrue); // the manager home
      for (final f in ManagerFeature.values) {
        expect(ManagerAccess.isAvailable(f), isTrue, reason: '$f');
      }
    });

    test('a feature switched off never builds its screen (the boundary still works)', () {
      ManagerAccess.debugOverride(false);
      var built = 0;
      final w = managerScreenFor(ManagerFeature.expenses, () {
        built++;
        return const SizedBox();
      });
      expect(w, isA<ManagerUnavailableScreen>());
      expect(built, 0);
    });

    test('managerScreen builds the manager home', () {
      const marker = SizedBox(key: Key('real'));
      expect(managerScreen(() => marker), same(marker));
    });

    test('post-login / splash routing (awsHomeScreenFor) gives a manager the manager dashboard and everyone else the employee one', () {
      final w = awsHomeScreenFor(_manager);
      expect(w, isA<ManagerDashboardScreen>());
      expect((w as ManagerDashboardScreen).userEmail, 'm@x.com');
      expect(
        awsHomeScreenFor(const AuthUser(id: 'u', email: 'e@x.com', organizationId: 'o', employeeId: 'e2', empRole: 'employee')),
        isNot(isA<ManagerDashboardScreen>()),
      );
    });

    test('the role provider can become a manager and back', () {
      final p = RoleProvider();
      p.switchRole('manager');
      expect(p.activeRole, 'manager');
      p.switchRole('employee');
      expect(p.activeRole, 'employee');
    });

    testWidgets('a real AWS sign-in as a manager lands on the manager dashboard and only reads', (tester) async {
      final s = await signedIn((req) async => jsonResponse({'success': false}, 404), empRole: 'manager');
      await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: s.auth)));
      await _signIn(tester);
      expect(find.byType(ManagerDashboardScreen), findsOneWidget);
      expect(find.text(ManagerUnavailableScreen.message), findsNothing);
      expect(s.apiCalls.every((r) => r.method == 'GET'), isTrue);
    });

    testWidgets('the splash for a restored manager session shows the manager dashboard', (tester) async {
      final s = await signedIn((req) async => jsonResponse({'success': false}, 404), empRole: 'manager');
      await tester.pumpWidget(MaterialApp(home: GifSplashScreen(authService: s.auth)));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ManagerDashboardScreen), findsOneWidget);
    });

    testWidgets('the drawer "Switch to Manager" opens the manager dashboard', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final roles = RoleProvider();
      final key = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        ChangeNotifierProvider<RoleProvider>.value(
          value: roles,
          child: MaterialApp(
            home: Scaffold(
              key: key,
              body: const SizedBox(),
              endDrawer: AppDrawer(
                userEmail: 'm@x.com',
                userData: const {'id': 'e1', 'emp_role': 'manager'},
                fetchHrmsContext: () async => {},
                currentRoute: DrawerRoute.dashboard,
              ),
            ),
          ),
        ),
      );
      key.currentState!.openEndDrawer();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Switch to Manager'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Switch to Manager'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(roles.activeRole, 'manager');
      expect(find.byType(ManagerDashboardScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the drawer's logo timer
    });
  });

  group('every manager feature forced available (test-only override; never on in the app)', () {
    setUp(() => ManagerAccess.debugOverride(true));

    test('managerScreenFor builds any feature', () {
      const marker = SizedBox(key: Key('real'));
      for (final f in ManagerFeature.values) {
        expect(managerScreenFor(f, () => marker), same(marker));
      }
    });
  });

  test('every manager screen is built through managerScreen(...) (no bypass added later)', () {
    final screens = RegExp(
        r'\b(ManagerDashboardScreen|PendingApprovalsScreen|TeamAttendanceScreen|ManagerBenefitsScreen|ManagerLoansScreen|ManagerExpensesScreen|ManagerTravelScreen|ManagerEngageScreen|ManagerComplianceScreen)\(');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!screens.hasMatch(l)) continue;
        final isConstructorDeclaration = RegExp(r'^\s*const\s+\w+\(\{').hasMatch(l);
        // the call may be wrapped over a few lines by the formatter: look at this line and the two before it
        final window = lines.sublist(i < 2 ? 0 : i - 2, i + 1).join(' ');
        final guarded = window.contains('managerScreen(') || window.contains('managerScreenFor(');
        if (!isConstructorDeclaration && !guarded) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('main.dart does not print the employee update response or the FCM token', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src.contains('UPDATE RESPONSE'), isFalse);
    expect(src.contains('FCM Token'), isFalse);
    expect(RegExp(r'print\(\s*response\s*\)').hasMatch(src), isFalse);
  });

  test('main.dart logs no notification payload/data, title, token or exception text', () {
    final src = File('lib/main.dart').readAsStringSync();
    for (final banned in ['Payload =>', 'message.data}', 'notification?.title}', 'Foreground Message', 'print(e)', r'$e"', r"$e'"]) {
      expect(src.contains(banned), isFalse, reason: 'found $banned');
    }
    // every remaining print/debugPrint is a fixed message or a permission status: no interpolation of other values
    final interpolated = RegExp(r'(?<![A-Za-z])(?:debugP|p)rint\(\s*["\x27][^"\x27]*\$').allMatches(src).map((m) => m.group(0)!).toList();
    expect(interpolated, ['print(\'User granted permission: \$']);
  });
}
