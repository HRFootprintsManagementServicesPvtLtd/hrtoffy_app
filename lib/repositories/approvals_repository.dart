import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Short, friendly text for a failed approval call. Never contains server text, urls, ids or exception text: the server's
/// own wording is only read to tell the engine's refusals apart (it answers 403 / 404 / 400 with the engine's message,
/// the engine's `code` is not part of the HTTP error), the user only ever sees the strings below.
String approvalsErrorText(
  Object e, {
  String fallback = "Couldn't complete this. Please try again.",
}) {
  if (e is ArgumentError) return 'Please add a reason before rejecting.';
  if (e is! ApiException) return fallback;
  if (e.isNetworkError) {
    return 'No connection. Please check your internet and try again.';
  }
  if (e.isUnauthorized) {
    return "Your session has expired. Please sign in again.";
  }
  final text = '${e.code ?? ''} ${e.message}'.toLowerCase();
  if (text.contains('self_approval') ||
      text.contains('own request') ||
      text.contains('your own') ||
      text.contains('yourself')) {
    return "You can't decide your own request.";
  }
  if (text.contains('override_reason')) {
    return 'A reason is needed to decide this request.';
  }
  if (text.contains('not_pending') ||
      text.contains('already') ||
      text.contains('not pending')) {
    return 'This request was already decided.';
  }
  if (text.contains('not_allowed')) {
    return "You can't decide this request. It is waiting for another approver.";
  }
  if (text.contains('amount_above_claim') || text.contains('bad_amount')) {
    return 'The approved amount is not valid for this request.';
  }
  if (e.isServerError) return fallback;
  if (e.isForbidden) return "You can't decide this request.";
  if (e.isNotFound) return 'This request is no longer available.';
  return "This request couldn't be processed. Please refresh and try again.";
}

/// True when [e] means the request in question is gone, already decided or not the caller's any more: the list is stale
/// and should be reloaded.
bool approvalIsStale(Object e) {
  if (e is! ApiException) return false;
  return e.isForbidden ||
      e.isNotFound ||
      e.statusCode == 400 ||
      e.statusCode == 409;
}

/// The engine's answer to "may the caller decide this request now?" (`approval_row_meta`).
class ApprovalMeta {
  const ApprovalMeta({
    required this.canApprove,
    this.executionFound = false,
    this.requiredRole,
    this.directMode = false,
    this.reason,
  });

  final bool canApprove;
  final bool executionFound;
  final String? requiredRole;
  final bool directMode;
  final String? reason;

  factory ApprovalMeta.fromMap(Map<String, dynamic> m) => ApprovalMeta(
    canApprove: m['can_approve'] == true,
    executionFound: m['execution_found'] == true,
    requiredRole: m['required_role']?.toString(),
    directMode: m['direct_mode'] == true,
    reason: m['reason']?.toString(),
  );
}

/// Canonical engine module name for a screen's wording (`travel` -> `travel_claims`).
String canonicalApprovalModule(String module) {
  switch (module.trim().toLowerCase()) {
    case 'leave':
    case 'leave_applications':
    case 'leave_requests':
      return 'leaves';
    case 'expense':
    case 'expense_claims':
      return 'expenses';
    case 'travel':
    case 'travel_claim':
      return 'travel_claims';
    case 'benefit':
    case 'benefit_claims':
      return 'benefits';
    case 'loan':
    case 'loans_advances':
      return 'loans';
    case 'ot':
    case 'overtime_records':
      return 'overtime';
    case 'regularization':
    case 'regularisation':
      return 'attendance_regularization';
    default:
      return module.trim().toLowerCase();
  }
}

/// Approvals through the HR Toffy API. The app never writes a status or an approver: every decision goes to a decision
/// route and the database approval engine decides who may decide (see docs/MOBILE_APPROVAL_CONTRACT.md in the backend).
class ApprovalsRepository extends BaseRepository {
  ApprovalsRepository({super.auth});

  static const _inboxPage = 100;
  static const _maxPages = 20;

  // ------------------------------------------------------------------ inbox

  /// Pending workflow executions the caller may decide at their current step: `GET /organizations/:orgId/approvals`
  /// (manager step) and, for a caller who is not a plain manager, `GET /organizations/:orgId/reviewer-queue`
  /// (reviewer / HR steps), 100 per page. [module] narrows the answer to one module. Each execution keeps the
  /// server's fields (`id`, `module_name`, `record_id`, ...) and carries a `record` with the request's own fields plus
  /// `employee_full_name` and `employee_code`.
  Future<List<Map<String, dynamic>>> inbox({String? module}) async {
    final wanted = module == null ? null : canonicalApprovalModule(module);
    final lists = <List<Map<String, dynamic>>>[await _pages('/approvals')];
    if (user.empRole != 'manager') {
      try {
        lists.add(await _pages('/reviewer-queue'));
      } on ApiException {
        // the second queue is a bonus: the first answer is enough to show
      }
    }
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final list in lists) {
      for (final e in list) {
        final id = e['id']?.toString();
        if (id == null || !seen.add(id)) continue;
        if (wanted != null &&
            canonicalApprovalModule(e['module_name']?.toString() ?? '') !=
                wanted) {
          continue;
        }
        out.add(e);
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _pages(String suffix) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final data = await api.get(
        orgPath(suffix),
        query: {'limit': '$_inboxPage', 'offset': '${page * _inboxPage}'},
      );
      final map = data is Map ? data : const {};
      final items = asMapList(
        map['executions'] ?? data,
      ).map((m) => Map<String, dynamic>.from(snakeKeys(m) as Map)).toList();
      out.addAll(items);
      final total = asInt(map['total'], items.length);
      if (items.isEmpty || (page + 1) * _inboxPage >= total) break;
    }
    return out;
  }

  /// `POST /organizations/:orgId/approvals/:executionId/approve` with `{comments}`. The route reads its body, so an
  /// object is always sent. A `null` answer means the execution is not the caller's organization's: reported as not found.
  Future<void> approveInbox(String executionId, {String? comments}) async {
    final data = await api.post(
      orgPath('/approvals/$executionId/approve'),
      body: {if (_has(comments)) 'comments': comments!.trim()},
    );
    if (data == null) throw const ApiException(404, 'Not found');
  }

  /// `POST /organizations/:orgId/approvals/:executionId/reject` with `{reason}` (this route names it `reason`).
  Future<void> rejectInbox(String executionId, {required String reason}) async {
    _needReason(reason);
    final data = await api.post(
      orgPath('/approvals/$executionId/reject'),
      body: {'reason': reason.trim()},
    );
    if (data == null) throw const ApiException(404, 'Not found');
  }

  // --------------------------------------------------------- workflow routes

  /// `POST /organizations/:orgId/workflows/module/:module/:recordId/approve` with `{comments, decision?}`.
  /// [approvedAmount], when given, goes in `decision.approved_amount`.
  Future<void> approveWorkflow(
    String module,
    String recordId, {
    String? comments,
    num? approvedAmount,
  }) async {
    await api.post(
      orgPath(
        '/workflows/module/${canonicalApprovalModule(module)}/$recordId/approve',
      ),
      body: {
        if (_has(comments)) 'comments': comments!.trim(),
        if (approvedAmount != null)
          'decision': {'approved_amount': approvedAmount},
      },
    );
  }

  /// `POST /organizations/:orgId/workflows/module/:module/:recordId/reject` with `{comments}` (the reason).
  Future<void> rejectWorkflow(
    String module,
    String recordId, {
    required String comments,
  }) async {
    _needReason(comments);
    await api.post(
      orgPath(
        '/workflows/module/${canonicalApprovalModule(module)}/$recordId/reject',
      ),
      body: {'comments': comments.trim()},
    );
  }

  /// `POST /organizations/:orgId/workflows/module/:module/row-meta` with `{recordIds}`: whether the caller may decide each
  /// request (the same engine function the decision uses). The server answers camelCase; keys are matched either way.
  Future<Map<String, ApprovalMeta>> rowMeta(
    String module,
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return {};
    final out = <String, ApprovalMeta>{};
    for (var i = 0; i < recordIds.length; i += 500) {
      final chunk = recordIds.sublist(
        i,
        i + 500 > recordIds.length ? recordIds.length : i + 500,
      );
      final data = await api.post(
        orgPath(
          '/workflows/module/${canonicalApprovalModule(module)}/row-meta',
        ),
        body: {'recordIds': chunk},
      );
      if (data is! Map) continue;
      for (final e in data.entries) {
        if (e.value is! Map) continue;
        out[e.key.toString()] = ApprovalMeta.fromMap(
          Map<String, dynamic>.from(snakeKeys(e.value) as Map),
        );
      }
    }
    return out;
  }

  /// `GET /organizations/:orgId/workflows/module/:module/:recordId/can-approve`.
  Future<ApprovalMeta> canApprove(String module, String recordId) async {
    final data = await api.get(
      orgPath(
        '/workflows/module/${canonicalApprovalModule(module)}/$recordId/can-approve',
      ),
    );
    final map = data is Map
        ? Map<String, dynamic>.from(snakeKeys(data) as Map)
        : <String, dynamic>{};
    return ApprovalMeta.fromMap(map);
  }

  // --------------------------------------------------------- regularization

  /// `GET /organizations/:orgId/attendance/regularization-requests?status=&limit=`. Pending: `status=pending`
  /// (up to 100); history: `status=approved,rejected` (50, newest decision first). The server shows a manager only their
  /// reporting tree. Rows carry `employee_records {full_name, employee_id, department}`.
  Future<List<Map<String, dynamic>>> regularizations({
    required bool history,
  }) async {
    final data = await api.get(
      orgPath('/attendance/regularization-requests'),
      query: {
        'status': history ? 'approved,rejected' : 'pending',
        'limit': history ? '50' : '100',
      },
    );
    return _rows(data is Map ? data['requests'] : data);
  }

  /// `POST /organizations/:orgId/attendance/regularization-requests/:id/approve` with `{comments}`. The server applies the
  /// attendance correction; the app writes nothing else.
  Future<void> approveRegularization(String id, {String? comments}) async {
    await api.post(
      orgPath('/attendance/regularization-requests/$id/approve'),
      body: {if (_has(comments)) 'comments': comments!.trim()},
    );
  }

  /// `POST /organizations/:orgId/attendance/regularization-requests/:id/reject` with `{comments}`.
  Future<void> rejectRegularization(
    String id, {
    required String comments,
  }) async {
    _needReason(comments);
    await api.post(
      orgPath('/attendance/regularization-requests/$id/reject'),
      body: {'comments': comments.trim()},
    );
  }

  // --------------------------------------------------------------- overtime

  /// `GET /organizations/:orgId/attendance/overtime/approvable?status=`: pending (`pending` and `manager_approved`)
  /// or, for history, everything of the caller's scope that is no longer pending (approved / rejected), newest first,
  /// at most 50 (the route has no rejected-only filter). Rows carry `employee_records {id, full_name, employee_id, department}`.
  Future<List<Map<String, dynamic>>> overtime({required bool history}) async {
    final data = await api.get(
      orgPath('/attendance/overtime/approvable'),
      query: {'status': history ? 'all' : 'pending'},
    );
    final rows = _rows(data);
    if (!history) return rows;
    return rows
        .where((r) {
          final s = r['status']?.toString();
          return s == 'approved' || s == 'rejected';
        })
        .take(50)
        .toList();
  }

  /// `POST /organizations/:orgId/attendance/overtime/records/:id/approve` (the route reads no body; `{}` is sent).
  Future<void> approveOvertime(String id) async {
    await api.post(
      orgPath('/attendance/overtime/records/$id/approve'),
      body: {},
    );
  }

  /// `POST /organizations/:orgId/attendance/overtime/records/:id/reject` with `{comments}`.
  Future<void> rejectOvertime(String id, {required String comments}) async {
    _needReason(comments);
    await api.post(
      orgPath('/attendance/overtime/records/$id/reject'),
      body: {'comments': comments.trim()},
    );
  }

  // ----------------------------------------------------------------- counts

  /// `GET /organizations/:orgId/dashboard/approval-counts`: only queues with a count above zero are in the answer. For a
  /// manager the server computes `approvals-requests-leaves` and `approvals-regularization` only.
  Future<Map<String, int>> counts() async {
    final data = await api.get(orgPath('/dashboard/approval-counts'));
    final map = data is Map ? data : const {};
    return {for (final e in map.entries) e.key.toString(): asInt(e.value)};
  }

  // ---------------------------------------------------------------- helpers

  List<Map<String, dynamic>> _rows(dynamic data) => asMapList(
    data,
  ).map((m) => Map<String, dynamic>.from(snakeKeys(m) as Map)).toList();

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  static void _needReason(String reason) {
    if (!_has(reason)) throw ArgumentError('A reason is required');
  }
}
