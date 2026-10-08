import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import '../core/auth/auth_service.dart';
import 'base_repository.dart';

/// Status values of a leave application and how the employee screens group them.
class LeaveStatus {
  LeaveStatus._();

  static const pending = 'pending';
  static const managerApproved = 'manager_approved';
  static const reviewerApproved = 'reviewer_approved';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const reviewerRejected = 'reviewer_rejected';
  static const cancelled = 'cancelled';

  /// Awaiting a final decision: counted as "pending" in the Summary and shown orange in the calendar.
  static const pendingLike = {pending, managerApproved, reviewerApproved};

  static String normalize(Object? s) => (s ?? '').toString().trim().toLowerCase();

  static bool isPendingLike(Object? s) => pendingLike.contains(normalize(s));
  static bool isApproved(Object? s) => normalize(s) == approved;
  static bool isRejected(Object? s) {
    final v = normalize(s);
    return v == rejected || v == reviewerRejected;
  }

  /// Inactive: a withdrawn request is not leave.
  static bool isCancelled(Object? s) => normalize(s) == cancelled;

  /// The API only lets the employee withdraw a request that is still `pending`.
  static bool canCancel(Object? s) => normalize(s) == pending;
}

/// One leave type's balance for a year.
class LeaveBalance {
  const LeaveBalance({
    required this.leaveTypeId,
    required this.name,
    required this.allocated,
    required this.used,
    required this.remaining,
    required this.year,
  });

  final String leaveTypeId;
  final String name;
  final num allocated;
  final num used;
  final num remaining;
  final int year;

  factory LeaveBalance.fromJson(Map<String, dynamic> row) => LeaveBalance(
        leaveTypeId: (row['leave_type_id'] ?? '').toString(),
        name: (row['leave_type_name'] ?? row['policy_name'] ?? '').toString(),
        allocated: asNum(row['allocated_days']) ?? 0,
        used: asNum(row['used_days']) ?? 0,
        remaining: asNum(row['remaining_days']) ?? 0,
        year: asInt(row['year'], DateTime.now().year),
      );
}

/// A message that is safe to show: never contains tokens or raw exception text.
String friendlyLeaveError(Object e) {
  if (e is ApiException) {
    if (e.isNetworkError) return 'Network problem. Check your connection and retry.';
    if (e.isForbidden) return "You don't have permission to do this.";
    if (e.isUnauthorized) return 'Session expired - please sign in again.';
    if (e.isServerError) return 'The server is busy right now. Please try again.';
    return e.message;
  }
  if (e is AuthFlowException) return e.message;
  return 'Something went wrong. Please try again.';
}

/// `7` for whole days, `7.5` otherwise.
String formatLeaveDays(num v) => v == v.truncate() ? v.truncate().toString() : v.toStringAsFixed(1);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The signed-in employee's own leave: balances, history, apply and cancel.
///
/// Everything goes through the HR Toffy API with the session's organization and employee; nothing is
/// looked up by email and no id is hardcoded.
class LeaveRepository extends BaseRepository {
  LeaveRepository({super.auth});

  /// `GET /organizations/:orgId/employees/:empId/leave-balances?year`
  Future<List<LeaveBalance>> balances({int? year}) async {
    final data = await api.get(orgPath('/employees/$employeeId/leave-balances'), query: {'year': year ?? DateTime.now().year});
    return asMapList(data).map(LeaveBalance.fromJson).toList();
  }

  /// `GET /organizations/:orgId/employees/:empId/leave-balance-summary?year` -> the organization's leave
  /// policies (`name`, `days_allowed`). Only used when the employee has no balance rows yet.
  Future<List<Map<String, dynamic>>> policies({int? year}) async {
    final data = await api.get(orgPath('/employees/$employeeId/leave-balance-summary'), query: {'year': year ?? DateTime.now().year});
    final list = data is Map ? data['leavePolicies'] : null;
    return asMapList(list);
  }

  /// How many of the caller's requests still await a final decision (pending, manager approved, reviewer approved):
  /// `GET /organizations/:orgId/employees/:empId/leaves?status=...&limit=1`, read from `total`.
  Future<int> pendingCount() async {
    final data = await api.get(orgPath('/employees/$employeeId/leaves'), query: {
      'status': LeaveStatus.pendingLike.join(','),
      'limit': 1,
    });
    return data is Map ? asInt(data['total']) : 0;
  }

  /// One page of `GET /organizations/:orgId/employees/:empId/leaves`.
  Future<({List<Map<String, dynamic>> items, int total})> historyPage({
    DateTime? from,
    DateTime? to,
    List<String>? statuses,
    int limit = 200,
    int offset = 0,
  }) async {
    final data = await api.get(orgPath('/employees/$employeeId/leaves'), query: {
      if (from != null) 'from': _ymd(from),
      if (to != null) 'to': _ymd(to),
      if (statuses != null && statuses.isNotEmpty) 'status': statuses.join(','),
      'limit': limit,
      'offset': offset,
    });
    final items = asMapList(data).map(_withManager).toList();
    final total = data is Map ? asInt(data['total'], items.length) : items.length;
    return (items: items, total: total);
  }

  /// Every application overlapping `[from, to]`, newest first, fetched page by page (the API caps a page at 200).
  Future<List<Map<String, dynamic>>> history({DateTime? from, DateTime? to, List<String>? statuses, int pageSize = 200}) async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    for (var page = 0; page < 25; page++) {
      final p = await historyPage(from: from, to: to, statuses: statuses, limit: pageSize, offset: offset);
      all.addAll(p.items);
      offset += p.items.length;
      if (p.items.isEmpty || offset >= p.total) break;
    }
    return all;
  }

  /// `POST /organizations/:orgId/leaves/record-application`. The employee comes from the session; the
  /// server counts the days (holidays, weekly offs, sandwich rule) and starts the approval workflow.
  Future<Map<String, dynamic>> apply({
    required String leaveTypeId,
    required DateTime from,
    required DateTime to,
    required String reason,
    String? attachmentUrl,
  }) async {
    final data = await api.post(orgPath('/leaves/record-application'), body: {
      'leaveTypeId': leaveTypeId,
      'fromDate': _ymd(from),
      'toDate': _ymd(to),
      'reason': reason,
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) 'attachmentUrl': attachmentUrl,
    });
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// `PUT /organizations/:orgId/leaves/applications/:id` with `{status: 'cancelled'}`. The API allows this
  /// for the owner while the request is still `pending`.
  Future<Map<String, dynamic>> cancel(String applicationId) async {
    final data = await api.put(orgPath('/leaves/applications/$applicationId'), body: {'status': LeaveStatus.cancelled});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// The flat `manager_name` / `manager_email` become the nested `manager` map the Calendar sheet reads;
  /// `status` is lower-cased and `total_days` is a number.
  static Map<String, dynamic> _withManager(Map<String, dynamic> row) {
    final name = row['manager_name'];
    final email = row['manager_email'];
    return {
      ...row,
      'status': LeaveStatus.normalize(row['status']),
      'total_days': asNum(row['total_days']) ?? row['total_days'],
      'manager': (name == null && email == null) ? null : {'full_name': name, 'email': email},
    };
  }
}
