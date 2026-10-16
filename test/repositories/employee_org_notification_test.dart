import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/notification_repository.dart';
import 'package:hrms_app/repositories/organization_repository.dart';

import '../helpers/test_auth.dart';

void main() {
  group('EmployeeRepository', () {
    test('getMe: GET /employees/me, camelCase DTO -> the snake_case row the UI reads', () async {
      final s = await signedIn((req) async => ok({
            'id': testEmployeeId,
            'organizationId': testOrgId,
            'employeeId': 'EMP-001',
            'fullName': 'Asha Rao',
            'managerName': 'Ravi',
            'managerEmail': 'ravi@x.com',
            'reviewerName': 'Rita',
            'dateOfBirth': '1990-05-17',
            'bankIfscCode': 'HDFC0001',
            'gradeCode': 'G3',
            'avatarUrl': null,
            'emergencyContactName': 'Sam',
          }));
      final emp = await EmployeeRepository(auth: s.auth).getMe();
      expect(s.last.method, 'GET');
      expect(s.last.path, '/organizations/$testOrgId/employees/me');
      expect(s.last.headers['Authorization'], 'Bearer acc');
      expect(emp, {
        'id': testEmployeeId,
        'organization_id': testOrgId,
        'employee_id': 'EMP-001',
        'full_name': 'Asha Rao',
        'manager_name': 'Ravi',
        'manager_email': 'ravi@x.com',
        'reviewer_name': 'Rita',
        'date_of_birth': '1990-05-17',
        'bank_ifsc_code': 'HDFC0001',
        'grade_code': 'G3',
        'avatar_url': null,
        'emergency_contact_name': 'Sam',
      });
    });

    test('getByEmail encodes the address', () async {
      final s = await signedIn((req) async => ok({'id': 'm1', 'fullName': 'Ravi', 'email': 'ravi+x@x.com'}));
      final m = await EmployeeRepository(auth: s.auth).getByEmail('ravi+x@x.com');
      expect(s.last.path, '/organizations/$testOrgId/employees/by-email/ravi%2Bx%40x.com');
      expect(m['full_name'], 'Ravi');
    });

    test('updateMe: snake_case UI fields -> camelCase body, returns the saved record', () async {
      final s = await signedIn((req) async => ok({'id': testEmployeeId, 'phone': '99', 'bloodGroup': 'O+'}));
      final saved = await EmployeeRepository(auth: s.auth).updateMe({
        'phone': '99',
        'date_of_birth': '1990-05-17',
        'blood_group': 'O+',
        'emergency_contact_relationship': 'Sister',
      });
      expect(s.last.method, 'PATCH');
      expect(s.last.path, '/organizations/$testOrgId/employees/me');
      expect(s.last.json, {
        'phone': '99',
        'dateOfBirth': '1990-05-17',
        'bloodGroup': 'O+',
        'emergencyContactRelationship': 'Sister',
      });
      expect(saved['blood_group'], 'O+');
    });

    test('updateMe refuses HR-managed fields and the sign-in email before any request is made', () async {
      final s = await signedIn((req) async => ok({'id': testEmployeeId}));
      final repo = EmployeeRepository(auth: s.auth);
      final before = s.requests.length;
      for (final field in ['bank_name', 'bank_account_no', 'bank_ifsc_code', 'pan_no', 'aadhaar_number', 'uan_no', 'department', 'designation', 'grade_code', 'employment_status', 'salary', 'email']) {
        await expectLater(repo.updateMe({'phone': '9123456789', field: 'x'}), throwsArgumentError, reason: field);
      }
      expect(s.requests.length, before, reason: 'nothing is sent when a restricted field is present');
    });

    test('setAvatarUrl sends the url, or null to remove the photo', () async {
      final s = await signedIn((req) async => ok({'id': testEmployeeId, 'avatarUrl': null}));
      final repo = EmployeeRepository(auth: s.auth);
      await repo.setAvatarUrl('https://api.hrtoffy.in/storage/v1/object/public/avatars/a.jpg');
      expect(s.last.path, '/organizations/$testOrgId/employees/me/avatar');
      expect(s.last.json, {'avatarUrl': 'https://api.hrtoffy.in/storage/v1/object/public/avatars/a.jpg'});
      await repo.setAvatarUrl(null);
      expect(s.last.json, {'avatarUrl': null});
    });

    test('getSensitiveProfile reads the caller\'s own decrypted values', () async {
      final s = await signedIn((req) async => ok({'salary': 1200000.5, 'pan_no': 'ABCDE1234F', 'uan_no': null, 'bank_account_no': '000123'}));
      final p = await EmployeeRepository(auth: s.auth).getSensitiveProfile();
      expect(s.last.path, '/organizations/$testOrgId/payroll/me/sensitive-profile');
      expect(p['pan_no'], 'ABCDE1234F');
      expect(p['uan_no'], isNull);
    });

    test('a 403 surfaces as a typed ApiException', () async {
      final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'code': 'FORBIDDEN', 'message': 'nope'}}, 403));
      await expectLater(EmployeeRepository(auth: s.auth).getMe(), throwsA(isA<ApiException>().having((e) => e.isForbidden, '403', true)));
    });

    test('needs a signed-in employee', () async {
      final s = await signedIn((req) async => ok({}));
      await s.auth.logout();
      await expectLater(EmployeeRepository(auth: s.auth).getMe(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    });
  });

  group('OrganizationRepository', () {
    test('combines /info (name) and /branding (logo)', () async {
      final s = await signedIn((req) async {
        if (req.url.path.endsWith('/info')) return ok({'organization_id': testOrgId, 'organization_name': 'Goodclap Initiatives'});
        return ok({'logoUrl': 'https://cdn/x.png', 'primaryBrandColor': '#fff'});
      });
      final org = await OrganizationRepository(auth: s.auth).getOrganization();
      expect(org, {'id': testOrgId, 'name': 'Goodclap Initiatives', 'logo_url': 'https://cdn/x.png'});
    });

    test('a branding failure only drops the logo', () async {
      final s = await signedIn((req) async {
        if (req.url.path.endsWith('/info')) return ok({'organization_id': testOrgId, 'organization_name': 'Goodclap'});
        return jsonResponse({'success': false, 'error': {'message': 'forbidden'}}, 403);
      });
      final org = await OrganizationRepository(auth: s.auth).getOrganization();
      expect(org['name'], 'Goodclap');
      expect(org['logo_url'], isNull);
    });
  });

  group('NotificationRepository', () {
    test('list: paging params, server unread count, rows untouched', () async {
      final s = await signedIn((req) async => ok({
            'items': [
              {'id': 'n1', 'title': 'Leave approved', 'body': 'b', 'read': false, 'created_at': '2026-10-07T10:00:00Z'},
              {'id': 'n2', 'title': 'Welcome', 'body': 'b', 'read': true, 'created_at': '2026-10-01T10:00:00Z'},
            ],
            'total': 57,
            'unread': 9,
          }));
      final page = await NotificationRepository(auth: s.auth).list(limit: 50, offset: 10);
      expect(s.last.path, '/organizations/$testOrgId/notifications');
      expect(s.last.query, {'limit': '50', 'offset': '10'});
      expect(page.items.length, 2);
      expect(page.items.first['title'], 'Leave approved');
      expect(page.total, 57);
      expect(page.unread, 9);
    });

    test('unread falls back to counting the page when the server omits it', () async {
      final s = await signedIn((req) async => ok({'items': [{'id': 'n1', 'read': false}, {'id': 'n2', 'read': true}]}));
      expect((await NotificationRepository(auth: s.auth).list()).unread, 1);
    });

    test('markRead / markAllRead hit the right endpoints', () async {
      final s = await signedIn((req) async => ok({'message': 'ok'}));
      final repo = NotificationRepository(auth: s.auth);
      await repo.markRead('n1');
      expect([s.last.method, s.last.path], ['POST', '/organizations/$testOrgId/notifications/n1/read']);
      await repo.markAllRead();
      expect(s.last.path, '/organizations/$testOrgId/notifications/mark-all-read');
    });
  });
}
