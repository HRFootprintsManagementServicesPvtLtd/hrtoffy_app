import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/compliance_repository.dart';
import 'package:hrms_app/repositories/engagement_repository.dart';
import 'package:hrms_app/repositories/helpdesk_repository.dart';
import 'package:hrms_app/repositories/letters_repository.dart';
import 'package:hrms_app/repositories/recruitment_repository.dart';
import 'package:hrms_app/repositories/tasks_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _other = '99999999-9999-9999-9999-999999999999';

void main() {
  test(
    'TasksRepository requests and returns only the own assignments',
    () async {
      final s = await signedIn(
        (req) async => ok({
          'items': [
            {'id': 'a', 'employee_id': testEmployeeId},
            {'id': 'b', 'employee_id': _other},
          ],
        }),
      );
      final rows = await TasksRepository(auth: s.auth).myTasks();
      expect(rows.map((r) => r['id']), ['a']);
      expect(s.last.method, 'GET');
      expect(s.last.path, '$_org/tasks');
      expect(s.last.query, {'assignedTo': testEmployeeId});
    },
  );

  test(
    'HelpdeskRepository requests own tickets and drops tickets addressed to the caller',
    () async {
      final s = await signedIn(
        (req) async => ok({
          'items': [
            {'id': 'a', 'employee_id': testEmployeeId},
            {'id': 'b', 'employee_id': _other},
            {'id': 'c', 'employee_id': null},
          ],
        }),
      );
      final rows = await HelpdeskRepository(auth: s.auth).myTickets();
      expect(rows.map((r) => r['id']), ['a']);
      expect(s.last.path, '$_org/helpdesk/tickets');
      expect(s.last.query, {'employee_id': testEmployeeId, 'limit': '200'});
    },
  );

  test('LettersRepository reads only the own id and the rows key', () async {
    final s = await signedIn(
      (req) async => ok({
        'rows': [
          {'id': 'l1', 'employee_id': testEmployeeId},
          {'id': 'l2', 'employee_id': _other},
        ],
        'total': 2,
      }),
    );
    final rows = await LettersRepository(auth: s.auth).myLetters();
    expect(rows.map((r) => r['id']), ['l1']);
    expect(s.last.path, '$_org/letters/employee/$testEmployeeId');
  });

  test('RecruitmentRepository routes and apply body', () async {
    final s = await signedIn((req) async {
      if (req.url.path.endsWith('/my-applications')) {
        return ok([
          {'job_id': 'j1'},
          {'job_id': 'j2'},
        ]);
      }
      if (req.method == 'POST') return ok({'id': 'x'}, 201);
      return ok([
        {'id': 'j1'},
      ]);
    });
    final repo = RecruitmentRepository(auth: s.auth);
    expect((await repo.internalJobs()).length, 1);
    expect(s.last.path, '$_org/recruitment/internal-jobs');
    expect(await repo.appliedJobIds(), {'j1', 'j2'});
    expect(s.last.path, '$_org/recruitment/internal-jobs/my-applications');
    await repo.applyInternal('j1');
    expect(s.last.method, 'POST');
    expect(s.last.path, '$_org/recruitment/internal-jobs/j1/apply');
    expect(s.last.json, <String, dynamic>{});
  });

  test(
    'EngagementRepository recognition read, badges, give body, celebrations',
    () async {
      final s = await signedIn((req) async {
        switch (req.url.path) {
          case '$_org/engagement/recognition':
            if (req.method == 'POST') return ok({'id': 'r'}, 201);
            return ok({
              'items': [
                {'id': '1', 'visibility': 'public'},
                {
                  'id': '2',
                  'visibility': 'private',
                  'given_by': _other,
                  'given_to': 'z',
                },
                {
                  'id': '3',
                  'visibility': 'private',
                  'given_by': 'z',
                  'given_to': testEmployeeId,
                },
                {'id': '4'},
              ],
            });
          case '$_org/engagement/recognition/badges':
            return ok([
              {'id': 'b1', 'badge_name': 'Star'},
            ]);
          case '$_org/dashboard/celebrations':
            return ok({
              'birthdays': [
                {'full_name': 'A'},
              ],
              'anniversaries': [
                {'full_name': 'B', 'yearsCompleted': 2},
                {'full_name': ''},
              ],
            });
        }
        return jsonResponse({'success': false}, 404);
      });
      final repo = EngagementRepository(auth: s.auth);
      expect((await repo.recognitions()).map((r) => r['id']), ['1', '3', '4']);
      expect(s.last.query, {'limit': '50'});
      expect((await repo.badges()).single['badge_name'], 'Star');
      final cel = await repo.celebrations();
      expect(cel.map((c) => '${c['kind']}:${c['full_name']}'), [
        'birthday:A',
        'anniversary:B',
      ]);
      expect(cel.last['years'], 2);

      await repo.giveRecognition(
        givenTo: _other,
        badgeId: 'b1',
        message: 'hi',
        points: 5,
      );
      expect(s.last.method, 'POST');
      expect(s.last.json, {
        'given_to': _other,
        'badge_id': 'b1',
        'recognition_message': 'hi',
        'visibility': 'public',
        'points': 5,
      });
      await repo.giveRecognition(
        givenTo: _other,
        badgeId: 'b1',
        message: 'hi',
        visibility: 'private',
      );
      expect(s.last.json, {
        'given_to': _other,
        'badge_id': 'b1',
        'recognition_message': 'hi',
        'visibility': 'private',
      });
    },
  );

  test('a 403 on giving recognition surfaces as ApiException(403)', () async {
    final s = await signedIn(
      (req) async => jsonResponse({
        'success': false,
        'error': {'message': 'no'},
      }, 403),
    );
    expect(
      EngagementRepository(
        auth: s.auth,
      ).giveRecognition(givenTo: 'a', badgeId: 'b', message: 'm'),
      throwsA(
        isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
      ),
    );
  });

  test('ComplianceRepository routes, null score and name lookup', () async {
    final s = await signedIn((req) async {
      final p = req.url.path;
      if (p == '$_org/compliance/health') return ok({'overall_score': null});
      if (p == '$_org/employees/summaries') {
        return ok([
          {'id': 'e1', 'fullName': 'Asha', 'employeeId': 'E1'},
        ]);
      }
      if (p == '$_org/compliance/returns' ||
          p == '$_org/posh/complaints' ||
          p == '$_org/locum/contractors') {
        return ok({
          'items': [
            {'id': 'x'},
          ],
          'total': 1,
        });
      }
      return ok([
        {'id': 'x'},
      ]);
    });
    final repo = ComplianceRepository(auth: s.auth);
    expect(await repo.healthScore(), isNull);
    expect(await repo.employeeNames(), {'e1': 'Asha'});
    final expected = <String, Future<List<Map<String, dynamic>>> Function()>{
      '$_org/compliance/wage-register/fines': () => repo.wageRegister('fines'),
      '$_org/compliance/wage-register/deductions': () =>
          repo.wageRegister('deductions'),
      '$_org/compliance/wage-register/advances': () =>
          repo.wageRegister('advances'),
      '$_org/compliance/returns': repo.returns,
      '$_org/compliance/factory-accidents': repo.factoryAccidents,
      '$_org/compliance/shops-certs': repo.shopsCerts,
      '$_org/bonus-runs': repo.bonusRuns,
      '$_org/gratuity/provisions': repo.gratuityProvisions,
      '$_org/posh/complaints': repo.poshComplaints,
      '$_org/maternity/cases': repo.maternityCases,
      '$_org/locum/contractors': repo.contractors,
      '$_org/compliance/apprentices': repo.apprentices,
    };
    for (final e in expected.entries) {
      expect((await e.value()).length, 1, reason: e.key);
      expect(s.last.method, 'GET');
      expect(s.last.path, e.key);
    }
  });
}
