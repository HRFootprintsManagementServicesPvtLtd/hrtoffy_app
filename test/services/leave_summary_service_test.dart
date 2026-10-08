import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/leave_repository.dart';
import 'package:hrms_app/services/leave_summary_service.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/employees/$testEmployeeId';

Map<String, dynamic> _bal(String id, String name, Object allocated, num used, num remaining) => {
      'id': 'b-$id',
      'leave_type_id': id,
      'leave_type_name': name,
      'allocated_days': allocated,
      'used_days': used,
      'remaining_days': remaining,
      'year': 2026,
    };

void main() {
  test('totals, per-policy rows and the pending count come from the API (decimal strings accepted)', () async {
    final s = await signedIn((req) async {
      if (req.url.path == '$_base/leave-balances') {
        return ok([_bal('1', 'Casual Leave', '12.00', 2, 10), _bal('2', 'Sick Leave', 6, 1, 5)]);
      }
      if (req.url.path == '$_base/leaves') return ok({'items': [], 'total': 3, 'limit': 1, 'offset': 0});
      return jsonResponse({'success': false}, 404);
    });
    final svc = LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth));
    final out = await svc.fetch(year: 2026);
    expect(out.year, 2026);
    expect(out.totalAllocated, 18);
    expect(out.totalUsed, 3);
    expect(out.totalRemaining, 15);
    expect(out.pendingRequests, 3);
    expect(out.leavePolicyCount, 2);
    expect(out.policies.map((p) => p.name), ['Casual Leave', 'Sick Leave']);
    expect(out.policies.first.allocated, 12);
    // pending counts the three "awaiting a decision" statuses (decision: pending + manager_ + reviewer_approved)
    final pendingCall = s.apiCalls.firstWhere((r) => r.path == '$_base/leaves');
    expect(pendingCall.query['status'], 'pending,manager_approved,reviewer_approved');
  });

  test('duplicate policy names collapse to one entry, as before', () async {
    final s = await signedIn((req) async {
      if (req.url.path == '$_base/leave-balances') return ok([_bal('1', 'Casual', 5, 0, 5), _bal('2', 'Casual', 7, 1, 6)]);
      return ok({'items': [], 'total': 0, 'limit': 1, 'offset': 0});
    });
    final out = await LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth)).fetch();
    expect(out.leavePolicyCount, 1);
    expect(out.totalAllocated, 7);
  });

  test('no balance rows yet: falls back to the organisation policies (days_allowed)', () async {
    final s = await signedIn((req) async {
      if (req.url.path == '$_base/leave-balances') return ok([]);
      if (req.url.path == '$_base/leave-balance-summary') {
        return ok({
          'leaveApplications': [],
          'leavePolicies': [
            {'id': 'p1', 'name': 'Casual', 'days_allowed': 12},
            {'id': 'p2', 'name': 'Sick', 'days_allowed': 6},
          ],
          'year': 2026,
        });
      }
      return ok({'items': [], 'total': 0, 'limit': 1, 'offset': 0});
    });
    final out = await LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth)).fetch();
    expect(out.totalAllocated, 18);
    expect(out.totalUsed, 0);
    expect(out.totalRemaining, 18);
    expect(out.leavePolicyCount, 2);
  });

  test('a failing pending count does not blank the balances', () async {
    final s = await signedIn((req) async {
      if (req.url.path == '$_base/leave-balances') return ok([_bal('1', 'Casual', 12, 2, 10)]);
      return jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'nope'}}, 500);
    });
    final out = await LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth)).fetch();
    expect(out.totalRemaining, 10);
    expect(out.pendingRequests, 0);
  });

  test('a failing balances call is rethrown so the screens can show an error / retry', () async {
    final s = await signedIn((req) async => jsonResponse({'success': false, 'error': {'code': 'X', 'message': 'down'}}, 500));
    await expectLater(LeaveSummaryService.withRepository(LeaveRepository(auth: s.auth)).fetch(), throwsA(anything));
  });

  test('LeaveSummary.empty keeps its public shape', () {
    final e = LeaveSummary.empty(2026);
    expect(e.year, 2026);
    expect(e.totalAllocated + e.totalUsed + e.totalRemaining + e.pendingRequests + e.leavePolicyCount, 0);
    expect(e.policies, isEmpty);
    expect(LeaveSummary.empty().year, DateTime.now().year);
  });
}
