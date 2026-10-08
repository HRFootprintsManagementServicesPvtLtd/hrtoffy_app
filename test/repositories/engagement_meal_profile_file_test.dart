import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/repositories/file_repository.dart';
import 'package:hrms_app/repositories/meal_repository.dart';
import 'package:hrms_app/repositories/profile_repository.dart';

import '../helpers/test_auth.dart';

void main() {
  group('EngagementRepository', () {
    test('announcements: {items} body, only live published ones', () async {
      final s = await signedIn((req) async => ok({
            'items': [
              {'id': 'a1', 'title': 'Live', 'is_active': true, 'status': 'published'},
              {'id': 'a2', 'title': 'Draft', 'is_active': true, 'status': 'draft'},
              {'id': 'a3', 'title': 'Off', 'is_active': false, 'status': 'published'},
              {'id': 'a4', 'title': 'Legacy row (no status)', 'is_active': true},
            ],
            'total': 4,
          }));
      final list = await EngagementRepository(auth: s.auth).announcements();
      expect(s.last.path, '/organizations/$testOrgId/engagement/announcements');
      expect(s.last.query['limit'], '200');
      expect(list.map((a) => a['id']), ['a1', 'a4']);
    });

    test('events: sorted soonest first, created_by preserved', () async {
      final s = await signedIn((req) async => ok({
            'items': [
              {'id': 'e2', 'event_date': '2026-11-20T00:00:00.000Z', 'created_by': testUserId},
              {'id': 'e1', 'event_date': '2026-10-05T00:00:00.000Z', 'created_by': 'other'},
            ],
          }));
      final list = await EngagementRepository(auth: s.auth).events();
      expect(list.map((e) => e['id']), ['e1', 'e2']);
      expect(list.last['created_by'], testUserId);
    });

    test('faqs: active only, grouped by category, newest first', () async {
      final s = await signedIn((req) async => ok([
            {'id': '1', 'category': 'Payroll', 'created_at': '2026-01-01T00:00:00Z', 'is_active': true},
            {'id': '2', 'category': 'HR', 'created_at': '2026-02-01T00:00:00Z', 'is_active': true},
            {'id': '3', 'category': 'HR', 'created_at': '2026-03-01T00:00:00Z', 'is_active': true},
            {'id': '4', 'category': 'HR', 'created_at': '2026-04-01T00:00:00Z', 'is_active': false},
          ]));
      final list = await EngagementRepository(auth: s.auth).faqs();
      expect(s.last.path, '/organizations/$testOrgId/faqs');
      expect(list.map((f) => f['id']), ['3', '2', '1']);
    });

    test('surveys: active list and completed ids', () async {
      final s = await signedIn((req) async {
        if (req.url.path.endsWith('/surveys/my-responses')) return ok([{'id': 'r1', 'survey_id': 's2', 'submitted_at': '2026-10-01T00:00:00Z'}]);
        return ok({'items': [{'id': 's1', 'title': 'A'}, {'id': 's2', 'title': 'B'}]});
      });
      final repo = EngagementRepository(auth: s.auth);
      expect((await repo.activeSurveys()).length, 2);
      expect(s.last.query['status'], 'active');
      expect(await repo.completedSurveyIds(), {'s2'});
      expect(s.last.path, '/organizations/$testOrgId/engagement/surveys/my-responses');
    });

    test('submitSurveyResponse posts answers when not yet answered', () async {
      final s = await signedIn((req) async {
        if (req.method == 'GET') return ok(null); // no earlier answer
        return ok({'id': 'r1'});
      });
      final answers = [{'question_id': 'q1', 'question_text': 'How?', 'answer': 'Fine'}];
      await EngagementRepository(auth: s.auth).submitSurveyResponse('s1', answers);
      expect(s.requests.map((r) => '${r.method} ${r.path}'), [
        'GET /organizations/$testOrgId/engagement/surveys/s1/my-response',
        'POST /organizations/$testOrgId/engagement/surveys/s1/respond',
      ]);
      expect(s.last.json, {'responses': answers});
    });

    test('submitSurveyResponse refuses a second submission with 409 (no overwrite)', () async {
      final s = await signedIn((req) async => ok({'id': 'earlier'}));
      await expectLater(
        EngagementRepository(auth: s.auth).submitSurveyResponse('s1', const []),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    });
  });

  group('MealRepository', () {
    Future<TestSession> meals({bool orgEnabled = true, bool? employeeEligible = true, bool configEnabled = true, List<Map<String, dynamic>> orders = const []}) {
      return signedIn((req) async {
        if (req.url.path.endsWith('/meals/eligibility/me')) {
          return ok({'eligible': orgEnabled, 'employeeEligible': employeeEligible, 'perMealAmount': 60, 'orderCutoffHours': 4, 'voucherMode': 'auto'});
        }
        if (req.url.path.endsWith('/meals/config')) {
          return ok({'is_enabled': configEnabled, 'per_meal_amount': '60.00', 'order_cutoff_hours': 4});
        }
        if (req.url.path.endsWith('/meals/orders') && req.method == 'GET') return ok(orders);
        if (req.url.path.endsWith('/meals/orders') && req.method == 'POST') return ok({'id': 'o1'}, 201);
        return jsonResponse({}, 404);
      });
    }

    test('shows the card with amount, cutoff and no order yet', () async {
      final s = await meals();
      final state = await MealRepository(auth: s.auth).today('2026-10-07');
      expect(state, isNotNull);
      expect(state!.amount, 60);
      expect(state.cutoffHours, 4);
      expect(state.order, isNull);
      final ordersCall = s.requests.firstWhere((r) => r.method == 'GET' && r.path.endsWith('/meals/orders'));
      expect(ordersCall.query, {'employeeId': testEmployeeId, 'orderDate': '2026-10-07'});
    });

    test('ignores cancelled orders and returns an active one', () async {
      final s = await meals(orders: [
        {'id': 'o0', 'status': 'cancelled'},
        {'id': 'o1', 'status': 'placed', 'voucher_code': 'ABC123'},
      ]);
      final state = await MealRepository(auth: s.auth).today('2026-10-07');
      expect(state!.order!['voucher_code'], 'ABC123');
    });

    test('hidden when the org, the employee switch or the config is off', () async {
      expect(await MealRepository(auth: (await meals(orgEnabled: false)).auth).today('d'), isNull);
      expect(await MealRepository(auth: (await meals(employeeEligible: false)).auth).today('d'), isNull);
      expect(await MealRepository(auth: (await meals(employeeEligible: null)).auth).today('d'), isNull);
      expect(await MealRepository(auth: (await meals(configEnabled: false)).auth).today('d'), isNull);
    });

    test('placeOrder posts the employee and date', () async {
      final s = await meals();
      expect(await MealRepository(auth: s.auth).placeOrder('2026-10-07'), isTrue);
      expect(s.last.json, {'employeeId': testEmployeeId, 'orderDate': '2026-10-07'});
    });

    test('a refused order (not eligible) surfaces as 403', () async {
      final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'You are not eligible for meal vouchers'}}, 403));
      await expectLater(MealRepository(auth: s.auth).placeOrder('d'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('not eligible'))));
    });
  });

  group('ProfileRepository', () {
    test('nominees: camelCase rows -> snake_case, newest first; update sends camelCase', () async {
      final s = await signedIn((req) async {
        if (req.method == 'PUT') return ok({'id': 'n1'});
        return ok([
          {'id': 'n1', 'nomineeName': 'Old', 'relationship': 'Spouse', 'sharePercent': 50, 'createdAt': '2026-01-01T00:00:00Z'},
          {'id': 'n2', 'nomineeName': 'New', 'relationship': 'Child', 'sharePercent': 50, 'createdAt': '2026-06-01T00:00:00Z'},
        ]);
      });
      final repo = ProfileRepository(auth: s.auth);
      final rows = await repo.nominees();
      expect(s.last.path, '/organizations/$testOrgId/employees/$testEmployeeId/nominees');
      expect(rows.map((r) => r['id']), ['n2', 'n1']);
      expect(rows.first['nominee_name'], 'New');
      expect(rows.first['share_percent'], 50);

      await repo.updateNominee('n1', name: 'Asha', relationship: 'Sister', sharePercent: 25);
      expect([s.last.method, s.last.path], ['PUT', '/organizations/$testOrgId/nominees/n1']);
      expect(s.last.json, {'nomineeName': 'Asha', 'relationship': 'Sister', 'sharePercent': 25});
    });

    test('documents: bare {items} body (no envelope), camelCase -> snake_case, newest first', () async {
      final s = await signedIn((req) async => jsonResponse({
            'items': [
              {'id': 'd1', 'documentName': 'CV.pdf', 'documentType': 'personal_upload', 'fileUrl': 'employee-documents/x', 'verificationStatus': 'pending', 'uploadedAt': '2026-01-01T00:00:00Z'},
              {'id': 'd2', 'documentName': 'ID.png', 'documentType': 'personal_upload', 'fileUrl': 'employee-documents/y', 'verificationStatus': 'verified', 'uploadedAt': '2026-05-01T00:00:00Z'},
            ],
          }));
      final docs = await ProfileRepository(auth: s.auth).documents();
      expect(docs.map((d) => d['id']), ['d2', 'd1']);
      expect(docs.first['document_name'], 'ID.png');
      expect(docs.first['file_url'], 'employee-documents/y');
      expect(docs.first['verification_status'], 'verified');
    });

    test('addDocument / deleteDocument', () async {
      final s = await signedIn((req) async => ok({'id': 'd9'}, 201));
      final repo = ProfileRepository(auth: s.auth);
      await repo.addDocument(name: 'CV.pdf', type: 'personal_upload', fileRef: 'employee-documents/o/e/cv.pdf', size: 123);
      expect(s.last.path, '/organizations/$testOrgId/employees/$testEmployeeId/documents');
      expect(s.last.json, {'documentType': 'personal_upload', 'documentName': 'CV.pdf', 'fileUrl': 'employee-documents/o/e/cv.pdf', 'fileSize': 123});
      await repo.deleteDocument('d9');
      expect([s.last.method, s.last.path], ['DELETE', '/organizations/$testOrgId/employees/$testEmployeeId/documents/d9']);
    });

    test('insurance policies are requested for the caller', () async {
      final s = await signedIn((req) async => ok([{'id': 'p1', 'insurance_type': 'health', 'policy_number': 'X1'}]));
      final rows = await ProfileRepository(auth: s.auth).insurancePolicies();
      expect(s.last.query, {'employeeId': testEmployeeId});
      expect(rows.single['policy_number'], 'X1');
    });
  });

  group('FileRepository', () {
    test('upload: multipart with bucket query, file part and content type', () async {
      final s = await signedIn((req) async => ok({'bucket': 'employee-documents', 'path': 'o/e/20261007-abc-cv.pdf', 'ref': 'employee-documents/o/e/20261007-abc-cv.pdf', 'url': null, 'size': 5}, 201));
      final up = await FileRepository(auth: s.auth).upload(bucket: 'employee-documents', bytes: utf8.encode('%PDF-'), fileName: 'cv.pdf');
      final r = s.last;
      expect([r.method, r.path], ['POST', '/organizations/$testOrgId/files']);
      expect(r.query, {'bucket': 'employee-documents'});
      expect(r.headers['content-type'], startsWith('multipart/form-data; boundary='));
      expect(r.headers['Authorization'], 'Bearer acc');
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"; filename="cv.pdf"'));
      expect(body, contains('content-type: application/pdf'));
      expect(body, contains('%PDF-'));
      expect(up.ref, 'employee-documents/o/e/20261007-abc-cv.pdf');
      expect(up.url, isNull);
    });

    test('upload on behalf of an employee / into a chat channel adds those params; avatars return a url', () async {
      final s = await signedIn((req) async => ok({'bucket': 'avatars', 'path': 'p', 'ref': 'avatars/p', 'url': 'https://api.hrtoffy.in/storage/v1/object/public/avatars/p', 'size': 3}, 201));
      final repo = FileRepository(auth: s.auth);
      final a = await repo.upload(bucket: 'avatars', bytes: [1, 2, 3], fileName: 'me.jpg', contentType: 'image/jpeg');
      expect(a.url, startsWith('https://api.hrtoffy.in/storage/v1/object/public/avatars/'));
      await repo.upload(bucket: 'claim-documents', bytes: [1], fileName: 'a.pdf', employeeId: 'emp-9');
      expect(s.last.query, {'bucket': 'claim-documents', 'employeeId': 'emp-9'});
      await repo.upload(bucket: 'chat-attachments', bytes: [1], fileName: 'a.png', channelId: 'ch-1');
      expect(s.last.query, {'bucket': 'chat-attachments', 'channelId': 'ch-1'});
    });

    test('upload retries once after a token refresh (multipart rebuilt)', () async {
      var posts = 0;
      final s = await signedIn((req) async {
        if (req.url.path == '/auth/refresh') return jsonResponse({'accessToken': 'acc2', 'refreshToken': 'ref2', 'expiresIn': 900});
        posts++;
        if (req.headers['Authorization'] != 'Bearer acc2') return jsonResponse({'success': false}, 401);
        return ok({'bucket': 'documents', 'path': 'p', 'ref': 'documents/p', 'url': null, 'size': 1}, 201);
      });
      final up = await FileRepository(auth: s.auth).upload(bucket: 'documents', bytes: [1], fileName: 'a.pdf');
      expect(up.ref, 'documents/p');
      expect(posts, 2);
    });

    test('url: asks the API to sign, returns the signed URL', () async {
      final s = await signedIn((req) async => ok({'url': 'https://signed/x?token=t', 'expiresAt': '2026-10-07T11:00:00Z', 'ref': 'claim-documents/a'}));
      final url = await FileRepository(auth: s.auth).url('claim-documents/a', expiresInSeconds: 600);
      expect(url, 'https://signed/x?token=t');
      expect(s.last.path, '/organizations/$testOrgId/files/url');
      expect(s.last.query, {'ref': 'claim-documents/a', 'expiresIn': '600'});
    });

    test('url: a legacy bare path carries a bucket hint; ordinary external links pass through untouched', () async {
      final s = await signedIn((req) async => ok({'url': 'https://signed/y'}));
      final repo = FileRepository(auth: s.auth);
      await repo.url('personal/uid/cv.pdf', bucketHint: 'employee-documents');
      expect(s.last.query, {'ref': 'personal/uid/cv.pdf', 'bucket': 'employee-documents'});
      s.requests.clear();
      expect(await repo.url('https://example.com/policy.pdf'), 'https://example.com/policy.pdf');
      expect(s.requests, isEmpty);
      // a legacy storage URL still goes through the API for a fresh signature
      await repo.url('https://abc.supabase.co/storage/v1/object/public/avatars/x.jpg');
      expect(s.requests.length, 1);
    });

    test('url: not found surfaces as an error', () async {
      final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'message': 'File not found'}}, 404));
      await expectLater(FileRepository(auth: s.auth).url('claim-documents/a'), throwsA(isA<ApiException>().having((e) => e.isNotFound, '404', true)));
    });

    test('delete sends the reference', () async {
      final s = await signedIn((req) async => ok(null));
      await FileRepository(auth: s.auth).delete('employee-documents/a/b', bucketHint: 'employee-documents');
      expect([s.last.method, s.last.path], ['DELETE', '/organizations/$testOrgId/files']);
      expect(s.last.query, {'ref': 'employee-documents/a/b', 'bucket': 'employee-documents'});
    });
  });
}
