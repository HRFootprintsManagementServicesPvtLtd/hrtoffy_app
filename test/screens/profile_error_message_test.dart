import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/screens/my_profile_screen.dart';

void main() {
  const generic404 = "This isn't available right now. Please try again later or contact HR.";

  group('profileErrorMessage', () {
    test('a 404 is neutral and never shows the server text', () {
      expect(profileErrorMessage(const ApiException(404, 'Route PATCH:/organizations/x/employees/me not found')), generic404);
      expect(profileErrorMessage(const ApiException(404, 'Request failed (HTTP 404)')), generic404);
    });

    test('a call site where 404 means a missing document passes its own message', () {
      expect(profileErrorMessage(const ApiException(404, 'File not found'), notFound: kDocumentNotFoundMessage), kDocumentNotFoundMessage);
      expect(kDocumentNotFoundMessage, contains("couldn't be found"));
      expect(kDocumentNotFoundMessage, isNot(contains('try again later')), reason: 'retrying will not bring a missing document back');
    });

    test('notFound only replaces the 404 text; other statuses are unchanged', () {
      const doc = 'x';
      expect(profileErrorMessage(const ApiException(0, 'SocketException'), notFound: doc), contains('Network problem'));
      expect(profileErrorMessage(const ApiException(403, 'no'), notFound: doc), contains('permission'));
      expect(profileErrorMessage(const ApiException(401, 'no'), notFound: doc), contains('Session expired'));
      expect(profileErrorMessage(const ApiException(500, 'pg exploded'), notFound: doc), contains('busy'));
    });

    test('behavior that was already there is unchanged', () {
      expect(profileErrorMessage(const ApiException(0, 'x')), contains('Network problem'));
      expect(profileErrorMessage(const ApiException(403, 'x')), contains('permission'));
      expect(profileErrorMessage(const ApiException(401, 'x')), contains('Session expired'));
      expect(profileErrorMessage(const ApiException(500, 'boom')), contains('busy'));
      expect(profileErrorMessage(const ApiException(400, 'Phone number is invalid')), 'Phone number is invalid');
      expect(profileErrorMessage(TimeoutException('t')), contains('longer than usual'));
    });

    test('the 404 text is used for loads and uploads (the endpoint may be missing), without a retry-now promise', () {
      // call sites that pass no notFound: load, nominee update, avatar upload/remove, document upload
      expect(profileErrorMessage(const ApiException(404, 'x')), contains('contact HR'));
    });
  });

  group('profileSaveErrorMessage', () {
    test('a missing save route (404) says nothing was saved, not the generic "contact HR" text', () {
      final m = profileSaveErrorMessage(const ApiException(404, 'Route PATCH:/organizations/x/employees/me not found'));
      expect(m, contains('not saved'));
      expect(m, isNot(contains('Route PATCH')), reason: 'the raw server text is never shown');
      expect(m, isNot(generic404));
    });

    test('401, 403, network and server errors keep their friendly messages', () {
      expect(profileSaveErrorMessage(const ApiException(401, 'x')), contains('Session expired'));
      expect(profileSaveErrorMessage(const ApiException(403, 'x')), contains('permission'));
      expect(profileSaveErrorMessage(const ApiException(0, 'x')), contains('Network problem'));
      expect(profileSaveErrorMessage(const ApiException(500, 'pg exploded')), contains('busy'));
    });

    test('server validation errors (400/422) show the server\'s own reason', () {
      expect(profileSaveErrorMessage(const ApiException(400, 'dateOfBirth cannot be in the future')), 'dateOfBirth cannot be in the future');
      expect(profileSaveErrorMessage(const ApiException(422, 'Full name cannot be empty.')), 'Full name cannot be empty.');
    });
  });
}
