import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/core/auth/password_reset_rules.dart';
import 'package:hrms_app/screens/forgot_password_dialog.dart';
import 'package:hrms_app/screens/otp_password_reset_dialog.dart';

import '../helpers/test_auth.dart';

const _request = '/auth/password-reset/request-otp';
const _verify = '/auth/password-reset/verify-otp';

/// Opens [dialog] from a button and records what it returns when it closes.
Widget _host(
  Widget Function() dialog,
  void Function(Object? result) onResult,
) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => onResult(
            await showDialog<Object?>(
              context: context,
              builder: (_) => dialog(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  group('PasswordResetRules', () {
    test('OTP must be exactly 6 digits', () {
      expect(PasswordResetRules.validateOtp('123456'), isNull);
      expect(PasswordResetRules.validateOtp(' 123456 '), isNull);
      for (final bad in [
        '',
        '12345',
        '1234567',
        '12345a',
        'abcdef',
        '12 456',
      ]) {
        expect(PasswordResetRules.validateOtp(bad), isNotNull, reason: bad);
      }
    });

    test('password: at least 8 characters', () {
      expect(
        PasswordResetRules.validateNewPassword('Abcde12'),
        'Password must be at least 8 characters',
      );
      expect(
        PasswordResetRules.validateNewPassword(''),
        'Password must be at least 8 characters',
      );
      expect(PasswordResetRules.validateNewPassword('Abcdef12'), isNull);
    });

    test('password: needs an uppercase letter', () {
      expect(
        PasswordResetRules.validateNewPassword('abcdefg1'),
        'Password must contain an uppercase letter',
      );
    });

    test('password: needs a digit', () {
      expect(
        PasswordResetRules.validateNewPassword('Abcdefgh'),
        'Password must contain a number',
      );
    });

    test('a valid password is accepted', () {
      expect(PasswordResetRules.validateNewPassword('NewPassword1'), isNull);
      expect(PasswordResetRules.validateNewPassword('Zz9!zzzz'), isNull);
    });

    test('email: empty and malformed are refused', () {
      expect(PasswordResetRules.validateEmail(''), isNotNull);
      expect(PasswordResetRules.validateEmail('not-an-email'), isNotNull);
      expect(PasswordResetRules.validateEmail('a@b'), isNotNull);
      expect(PasswordResetRules.validateEmail(' asha@x.com '), isNull);
    });
  });

  group('AuthService password-reset calls', () {
    test(
      'request OTP: POST /auth/password-reset/request-otp with {email}',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'message': 'If your email is registered, you will receive an OTP.',
          }),
        );
        await s.auth.requestPasswordResetOtp('  asha@x.com ');
        expect(s.last.method, 'POST');
        expect(s.last.path, _request);
        expect(s.last.json, {'email': 'asha@x.com'});
      },
    );

    test(
      'request OTP sends no bearer token, even when the user happens to be signed in',
      () async {
        final s = await signedIn(
          (req) async => jsonResponse({'message': 'ok'}),
        );
        expect(
          s.auth.api.runtimeType,
          ApiClient,
        ); // a session exists in this fixture
        await s.auth.requestPasswordResetOtp('asha@x.com');
        expect(s.last.headers.containsKey('Authorization'), isFalse);
      },
    );

    test(
      'verify OTP: POST /auth/password-reset/verify-otp with {email, otp, newPassword}, no bearer token',
      () async {
        final s = await signedIn(
          (req) async =>
              jsonResponse({'message': 'Password reset successfully'}),
        );
        await s.auth.confirmPasswordResetOtp(
          email: 'asha@x.com',
          otp: '123456',
          newPassword: 'NewPassword1',
        );
        expect(s.last.method, 'POST');
        expect(s.last.path, _verify);
        expect(s.last.json, {
          'email': 'asha@x.com',
          'otp': '123456',
          'newPassword': 'NewPassword1',
        });
        expect(s.last.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('a refused verification surfaces as ApiException 400', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'Invalid or expired OTP'},
        }, 400),
      );
      await expectLater(
        s.auth.confirmPasswordResetOtp(
          email: 'a@x.com',
          otp: '123456',
          newPassword: 'NewPassword1',
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });
  });

  group('ForgotPasswordDialog', () {
    testWidgets(
      'requests an OTP, shows a generic message and returns the email',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'message': 'If your email is registered, you will receive an OTP.',
          }),
        );
        Object? result = 'unset';
        await tester.pumpWidget(
          _host(
            () => ForgotPasswordDialog(authService: s.auth),
            (r) => result = r,
          ),
        );
        await _open(tester);

        await tester.enterText(find.byType(TextField), 'asha@x.com');
        await tester.tap(find.text('Send OTP'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // only the OTP request was made: no employee lookup, nothing else
        expect(s.requests, hasLength(1));
        expect(s.last.path, _request);
        expect(s.last.json, {'email': 'asha@x.com'});
        expect(result, 'asha@x.com');
        expect(
          find.text(
            'If this email is registered, an OTP has been sent. Please check your email.',
          ),
          findsOneWidget,
        );
        // it never says whether the address exists
        expect(find.textContaining('not registered'), findsNothing);
      },
    );

    testWidgets('an empty or malformed email is refused before any request', (
      tester,
    ) async {
      final s = await signedIn((req) async => jsonResponse({'message': 'ok'}));
      await tester.pumpWidget(
        _host(() => ForgotPasswordDialog(authService: s.auth), (_) {}),
      );
      await _open(tester);

      await tester.tap(find.text('Send OTP'));
      await tester.pump();
      expect(find.text('Please enter your email'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Send OTP'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);
      expect(s.requests, isEmpty);
    });

    testWidgets(
      'server and network failures show safe messages, never raw text',
      (tester) async {
        final s = await signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'db exploded at https://api.hrtoffy.in'},
          }, 500),
        );
        await tester.pumpWidget(
          _host(() => ForgotPasswordDialog(authService: s.auth), (_) {}),
        );
        await _open(tester);
        await tester.enterText(find.byType(TextField), 'asha@x.com');
        await tester.tap(find.text('Send OTP'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Could not request an OTP. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('exploded'), findsNothing);
        expect(find.textContaining('hrtoffy'), findsNothing);
      },
    );

    testWidgets('too many requests (429) shows a wait message', (tester) async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'rate'},
        }, 429),
      );
      await tester.pumpWidget(
        _host(() => ForgotPasswordDialog(authService: s.auth), (_) {}),
      );
      await _open(tester);
      await tester.enterText(find.byType(TextField), 'asha@x.com');
      await tester.tap(find.text('Send OTP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Too many attempts. Please wait a minute and try again.'),
        findsOneWidget,
      );
    });
  });

  group('OTPPasswordResetDialog', () {
    Future<TestSession> pumpDialog(
      WidgetTester tester,
      Future<TestSession> Function() session, {
      void Function(Object?)? onResult,
    }) async {
      final s = await session();
      await tester.pumpWidget(
        _host(
          () =>
              OTPPasswordResetDialog(email: 'asha@x.com', authService: s.auth),
          onResult ?? (_) {},
        ),
      );
      await _open(tester);
      return s;
    }

    Future<void> fill(
      WidgetTester t, {
      String otp = '123456',
      String password = 'NewPassword1',
      String? confirm,
    }) async {
      await t.enterText(find.widgetWithText(TextField, '6-digit OTP'), otp);
      await t.enterText(
        find.widgetWithText(TextField, 'New Password'),
        password,
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Confirm Password'),
        confirm ?? password,
      );
    }

    Future<void> submit(WidgetTester t) async {
      await t.ensureVisible(find.text('Reset Password'));
      await t.tap(find.text('Reset Password'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'a valid OTP and password call the verify route, close the dialog and ask to log in',
      (tester) async {
        Object? result = 'unset';
        final s = await pumpDialog(
          tester,
          () => signedIn(
            (req) async =>
                jsonResponse({'message': 'Password reset successfully'}),
          ),
          onResult: (r) => result = r,
        );
        await fill(tester);
        await submit(tester);

        expect(s.requests, hasLength(1));
        expect(s.last.path, _verify);
        expect(s.last.json, {
          'email': 'asha@x.com',
          'otp': '123456',
          'newPassword': 'NewPassword1',
        });
        expect(
          find.text('Password reset successful. Please login.'),
          findsOneWidget,
        );
        expect(
          find.text('Enter OTP & New Password'),
          findsNothing,
        ); // dialog closed
        expect(result, isNull);
      },
    );

    for (final c
        in <
          ({
            String name,
            String otp,
            String password,
            String? confirm,
            String error,
          })
        >[
          (
            name: 'an OTP that is not 6 digits',
            otp: '12345',
            password: 'NewPassword1',
            confirm: null,
            error: 'Enter valid 6-digit OTP',
          ),
          (
            name: 'an OTP with letters',
            otp: '12345a',
            password: 'NewPassword1',
            confirm: null,
            error: 'Enter valid 6-digit OTP',
          ),
          (
            name: 'a password under 8 characters',
            otp: '123456',
            password: 'Abcde12',
            confirm: null,
            error: 'Password must be at least 8 characters',
          ),
          (
            name: 'a password without an uppercase letter',
            otp: '123456',
            password: 'abcdefg1',
            confirm: null,
            error: 'Password must contain an uppercase letter',
          ),
          (
            name: 'a password without a digit',
            otp: '123456',
            password: 'Abcdefgh',
            confirm: null,
            error: 'Password must contain a number',
          ),
          (
            name: 'mismatching confirmation',
            otp: '123456',
            password: 'NewPassword1',
            confirm: 'NewPassword2',
            error: 'Passwords do not match',
          ),
        ]) {
      testWidgets('rejects ${c.name} without calling the server', (
        tester,
      ) async {
        final s = await pumpDialog(
          tester,
          () => signedIn((req) async => jsonResponse({'message': 'ok'})),
        );
        await fill(
          tester,
          otp: c.otp,
          password: c.password,
          confirm: c.confirm,
        );
        await submit(tester);
        expect(find.text(c.error), findsOneWidget);
        expect(s.requests, isEmpty);
      });
    }

    testWidgets(
      'a wrong or expired OTP (400) shows a safe message and keeps the dialog open',
      (tester) async {
        final s = await pumpDialog(
          tester,
          () => signedIn(
            (req) async => jsonResponse({
              'success': false,
              'error': {
                'message': 'Invalid OTP hash mismatch in auth_mfa_challenges',
              },
            }, 400),
          ),
        );
        await fill(tester);
        await submit(tester);
        expect(s.requests, hasLength(1));
        expect(
          find.text(
            'The OTP is invalid or has expired. Please check it or request a new one.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('auth_mfa'), findsNothing);
        expect(find.text('Enter OTP & New Password'), findsOneWidget);
      },
    );

    testWidgets('server errors show a generic message', (tester) async {
      await pumpDialog(
        tester,
        () => signedIn(
          (req) async => jsonResponse({
            'success': false,
            'error': {'message': 'stack trace at /srv/app.js:12'},
          }, 500),
        ),
      );
      await fill(tester);
      await submit(tester);
      expect(
        find.text('Could not reset the password. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('stack trace'), findsNothing);
    });
  });

  group('no Supabase in the reset flow', () {
    for (final path in [
      'lib/screens/forgot_password_dialog.dart',
      'lib/screens/otp_password_reset_dialog.dart',
      'lib/core/auth/password_reset_rules.dart',
    ]) {
      test('$path does not reference Supabase', () {
        final source = File(path).readAsStringSync().toLowerCase();
        expect(source.contains('supabase'), isFalse);
        expect(source.contains('functions.invoke'), isFalse);
        expect(source.contains('employee_records'), isFalse);
      });
    }
  });
}
