import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/core/auth/auth_service.dart';
import 'package:hrms_app/core/auth/token_store.dart';
import 'package:hrms_app/main.dart' show FirebaseNotificationService;
import 'package:hrms_app/screens/dashboard_screen.dart';
import 'package:hrms_app/screens/login_screen.dart';
import 'package:hrms_app/screens/manager/manager_dashboard_screen.dart';
import 'package:hrms_app/screens/splash_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_auth.dart';

Widget _marker(AuthUser u) =>
    Text('HOME ${u.empRole ?? 'none'} ${u.email} ${u.employeeId}');

Future<void> _signIn(WidgetTester t) async {
  await t.enterText(find.widgetWithText(TextField, 'Email'), 'me@x.com');
  await t.enterText(find.widgetWithText(TextField, 'Password'), 'Secret123');
  await t.tap(find.text('Sign In'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  // the location disclosure dialog; Cancel avoids the platform permission call
  expect(find.text('Location Permission Required'), findsOneWidget);
  await t.tap(find.text('Cancel'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  group('post-sign-in routing (awsHomeScreenFor)', () {
    test(
      'a manager gets the manager dashboard',
      () {
        const u = AuthUser(
          id: 'u',
          email: 'm@x.com',
          organizationId: 'o',
          employeeId: 'e1',
          empRole: 'manager',
        );
        expect(awsHomeScreenFor(u), isA<ManagerDashboardScreen>());
      },
    );

    test(
      'an employee goes to the employee dashboard with their employee id',
      () {
        const u = AuthUser(
          id: 'u',
          email: 'e@x.com',
          organizationId: 'o',
          employeeId: 'e2',
          empRole: 'employee',
        );
        final w = awsHomeScreenFor(u);
        expect(w, isA<DashboardScreen>());
        expect((w as DashboardScreen).email, 'e@x.com');
        expect(w.employeeId, 'e2');
      },
    );

    test(
      'HR and other roles use the employee dashboard, exactly as sign-in always did',
      () {
        const hr = AuthUser(
          id: 'u',
          email: 'h@x.com',
          organizationId: 'o',
          employeeId: 'e3',
          empRole: 'hr',
          isHrRole: true,
        );
        expect(awsHomeScreenFor(hr), isA<DashboardScreen>());
        const none = AuthUser(
          id: 'u',
          email: 'n@x.com',
          organizationId: 'o',
          employeeId: 'e4',
        );
        expect(awsHomeScreenFor(none), isA<DashboardScreen>());
      },
    );
  });

  group('AWS sign-in (LoginScreen)', () {
    testWidgets(
      'signs in through discover-tenants, login and resolve-user only, then opens the employee home',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LoginScreen(authService: s.auth, homeBuilder: _marker),
          ),
        );
        await _signIn(tester);

        expect(s.requests.map((r) => '${r.method} ${r.path}'), [
          'POST /auth/discover-tenants',
          'POST /auth/login',
          'GET /auth/resolve-user',
        ]);
        final login =
            s.requests.firstWhere((r) => r.path == '/auth/login').json as Map;
        expect(login['authMethod'], 'password');
        expect(login['email'], 'me@x.com');
        expect(
          find.text('HOME employee me@x.com $testEmployeeId'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a manager is routed by the role resolved from /auth/resolve-user',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
          empRole: 'manager',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LoginScreen(authService: s.auth, homeBuilder: _marker),
          ),
        );
        await _signIn(tester);
        expect(
          find.text('HOME manager me@x.com $testEmployeeId'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'wrong credentials show a message and stay on the login screen',
      (tester) async {
        final calls = <String>[];
        FlutterSecureStorage.setMockInitialValues({});
        final store = TokenStore();
        final api = ApiClient(
          tokenStore: store,
          httpClient: MockClient((req) async {
            calls.add(req.url.path);
            if (req.url.path == '/auth/discover-tenants') {
              return jsonResponse({
                'organizations': [
                  {'id': testOrgId, 'name': 'Goodclap'},
                ],
              });
            }
            return jsonResponse({
              'success': false,
              'error': {'message': 'bad'},
            }, 401);
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LoginScreen(
              authService: AuthService(api: api, tokenStore: store),
              homeBuilder: _marker,
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'me@x.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'wrong',
        );
        await tester.tap(find.text('Sign In'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Invalid credentials'), findsOneWidget);
        expect(find.textContaining('HOME'), findsNothing);
        expect(calls, ['/auth/discover-tenants', '/auth/login']);
      },
    );

    testWidgets(
      'phone-number login is not offered with AWS auth (it cannot create an AWS session)',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LoginScreen(authService: s.auth, homeBuilder: _marker),
          ),
        );
        expect(find.text('Login with Mobile Number'), findsNothing);
        expect(find.text('Mobile Number'), findsNothing);
        expect(find.text('Send OTP'), findsNothing);
        expect(find.text('Verify OTP'), findsNothing);
        // email/password sign-in and the reset link are still there
        expect(find.text('Sign In'), findsOneWidget);
        expect(find.text('Forgot Password?'), findsOneWidget);
      },
    );
  });

  group('startup: session restore and splash', () {
    test('restoreSession uses only the AWS API', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = TokenStore();
      await store.save(
        StoredSession(
          accessToken: 'acc',
          refreshToken: 'ref',
          userId: testUserId,
          email: 'me@x.com',
          organizationId: testOrgId,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      final paths = <String>[];
      final api = ApiClient(
        tokenStore: store,
        httpClient: MockClient((req) async {
          paths.add('${req.method} ${req.url.path}');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': testUserId,
                'email': 'me@x.com',
                'organizationId': testOrgId,
                'employeeId': testEmployeeId,
                'empRole': 'manager',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final auth = AuthService(api: api, tokenStore: store);
      expect(await auth.restoreSession(), isTrue);
      expect(paths, ['GET /auth/resolve-user']);
      expect(auth.currentUser?.isManager, isTrue);
    });

    testWidgets(
      'splash sends an employee with a session to the employee home',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: GifSplashScreen(authService: s.auth, homeBuilder: _marker),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text('HOME employee me@x.com $testEmployeeId'),
          findsOneWidget,
        );
        expect(
          s.requests,
          isEmpty,
        ); // the session was restored earlier; the splash makes no calls
      },
    );

    testWidgets(
      'splash sends a manager with a session to the manager home (same routing as sign-in)',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
          empRole: 'manager',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: GifSplashScreen(authService: s.auth, homeBuilder: _marker),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text('HOME manager me@x.com $testEmployeeId'),
          findsOneWidget,
        );
      },
    );

    testWidgets('splash without a session goes to the login screen', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = TokenStore();
      final auth = AuthService(
        api: ApiClient(
          tokenStore: store,
          httpClient: MockClient((_) async => http.Response('{}', 500)),
        ),
        tokenStore: store,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GifSplashScreen(authService: auth, homeBuilder: _marker),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.textContaining('HOME'), findsNothing);
    });
  });

  group('AWS-only startup (no Supabase SDK)', () {
    test(
      'main, login, splash, sign-out and the manager boundary contain no Supabase code or legacy flag',
      () {
        for (final path in [
          'lib/main.dart',
          'lib/screens/login_screen.dart',
          'lib/screens/splash_screen.dart',
          'lib/core/auth/sign_out.dart',
          'lib/core/manager_access.dart',
        ]) {
          final src = File(path).readAsStringSync();
          expect(
            src.toLowerCase().contains('supabase'),
            isFalse,
            reason: '$path mentions Supabase',
          );
          expect(src.contains('USE_AWS_AUTH'), isFalse, reason: '$path');
          expect(src.contains('useAwsAuth'), isFalse, reason: '$path');
          expect(src.contains('FeatureFlags'), isFalse, reason: '$path');
        }
        expect(File('lib/core/feature_flags.dart').existsSync(), isFalse);
      },
    );

    test(
      'startup still restores the AWS session and returns to login when it expires',
      () {
        final src = File('lib/main.dart').readAsStringSync();
        expect(src.contains('AuthService.instance.restoreSession()'), isTrue);
        expect(src.contains('onSessionExpired'), isTrue);
        expect(
          src.contains('FirebaseNotificationService.startForUser'),
          isTrue,
        );
      },
    );

    test(
      'an AWS session works with no Supabase anywhere (restoreSession path)',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
        );
        expect(s.auth.currentUser, isNotNull);
      },
    );
  });

  group('push token (FCM)', () {
    test(
      'the device token is never stored and no request is made (there is no AWS endpoint for it)',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({'success': false}, 404),
        );
        expect(
          await FirebaseNotificationService.persistToken('tok', 'me@x.com'),
          isFalse,
        );
        expect(s.requests, isEmpty);
      },
    );

    test(
      'starting push for a user never throws, even when Firebase is not available',
      () async {
        await FirebaseNotificationService.startForUser(
          'me@x.com',
        ); // no Firebase app in tests
      },
    );
  });
}
