import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'approval_errors.dart';
import 'base_repository.dart';

/// The signed-in employee's own loans, EMI schedule and loan limit, and the loan request.
///
/// Documents are not uploaded and no manager is chosen: the backend does not store either for a loan request.
///
/// Financial amounts can be missing, null or an encrypted-column placeholder of 0 on the server, so every
/// amount is parsed defensively here and the UI decides what a usable amount is (see [isUsableAmount]).
class LoansRepository extends BaseRepository {
  LoansRepository({super.auth});

  static const _loanNumbers = [
    'requested_amount',
    'approved_amount',
    'emi_amount',
    'total_interest',
    'total_repayment',
    'interest_rate',
  ];
  static const _emiNumbers = [
    'principal_amount',
    'interest_amount',
    'emi_amount',
    'outstanding_principal',
    'paid_amount',
  ];

  /// `GET /organizations/:orgId/loans?employeeId=<own>` - `data.items`, newest first.
  ///
  /// `employeeId` is always sent: managers, HR and finance would otherwise also receive their team's loans.
  /// Amounts become numbers (or null when missing or not numeric); `tenure_months` becomes an int.
  Future<List<Map<String, dynamic>>> loans() async {
    final data = await api.get(
      orgPath('/loans'),
      query: {'employeeId': employeeId},
    );
    final rows = asMapList(data).map((r) {
      final m = Map<String, dynamic>.from(snakeKeys(r) as Map);
      for (final k in _loanNumbers) {
        if (m.containsKey(k)) m[k] = asNum(m[k]);
      }
      if (m.containsKey('tenure_months'))
        m['tenure_months'] = asNum(m['tenure_months'])?.toInt();
      return m;
    }).toList();
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  /// `GET /organizations/:orgId/loans/emi-schedule?employeeId=<own>` - the instalments, by due date.
  /// Amounts become numbers (or null); `due_date` becomes `yyyy-MM-dd`.
  Future<List<Map<String, dynamic>>> emiSchedule() async {
    final data = await api.get(
      orgPath('/loans/emi-schedule'),
      query: {'employeeId': employeeId},
    );
    final rows = asMapList(data).map((r) {
      final m = Map<String, dynamic>.from(snakeKeys(r) as Map);
      for (final k in _emiNumbers) {
        if (m.containsKey(k)) m[k] = asNum(m[k]);
      }
      if (m['due_date'] != null) m['due_date'] = asDateOnly(m['due_date']);
      return m;
    }).toList();
    rows.sort(
      (a, b) => (asDate(a['due_date']) ?? DateTime(9999)).compareTo(
        asDate(b['due_date']) ?? DateTime(9999),
      ),
    );
    return rows;
  }

  /// `POST /organizations/:orgId/loans/request` -> the new loan's id (`data.loanId`, HTTP 201).
  ///
  /// Source contract (hrtoffy-backend-mobile-aws `src/modules/loans`): body `{employeeId, amount, reason, repaymentMonths?,
  /// loanCategory?, emiStartDate?}`. `employeeId` is always the signed-in user's own (from the session); the server accepts
  /// another employee only for HR/finance. `amount` must be a positive number and `reason` non-empty (both checked by the
  /// server); [repaymentMonths], when sent, is floored by the server and defaults to 12 when absent or not positive.
  /// `loanCategory` and `emiStartDate` are not sent (the server defaults the category to `salary_advance`).
  ///
  /// The server creates a `pending` request only. It does not store a manager or documents and does not enforce the
  /// grade's loan limit or any eligibility rule. Whether this route is deployed is not verified.
  Future<String> requestLoan({
    required double amount,
    required String reason,
    int? repaymentMonths,
    String? loanCategory,
  }) async {
    final data = await api.post(
      orgPath('/loans/request'),
      body: {
        'employeeId': employeeId,
        'amount': amount,
        'reason': reason.trim(),
        if (repaymentMonths != null) 'repaymentMonths': repaymentMonths,
        if (loanCategory != null && loanCategory.isNotEmpty)
          'loanCategory': loanCategory,
      },
    );
    final id = data is Map ? data['loanId']?.toString() : null;
    if (id == null || id.isEmpty) {
      throw const ApiException(
        502,
        'Unexpected response while submitting the loan request.',
        code: 'LOAN_BAD_RESPONSE',
      );
    }
    return id;
  }

  /// `GET /organizations/:orgId/grade-structures/limits/:gradeCode` -> the grade's `loanMaxAmount`,
  /// or null when there is no grade row, no limit, or the caller may not read it.
  Future<double?> loanMaxAmount(String gradeCode) async {
    final data = await api.get(
      orgPath('/grade-structures/limits/${Uri.encodeComponent(gradeCode)}'),
    );
    if (data is! Map) return null;
    return asNum(data['loanMaxAmount'])?.toDouble();
  }

  // ---------------------------------------------------------------- manager approvals

  /// Statuses a loan can still be decided in: the engine may leave a loan `manager_approved` after a manager's step
  /// (`loans.service.ts` `loadDecidableLoan` accepts `pending` and `manager_approved`).
  static const openStatuses = {'pending', 'manager_approved'};

  static bool isOpen(Map<String, dynamic> loan) =>
      openStatuses.contains((loan['status'] ?? '').toString().toLowerCase());

  /// `GET /organizations/:orgId/loans` (no `employeeId`) - the loans the server lets this manager see: their reporting
  /// tree plus their own (HR/finance: everyone). Newest first, every status (a `manager_approved` loan is not hidden).
  /// The caller's own loans are left out: nobody decides their own loan, and they are listed under My Loans.
  ///
  /// Each row is the usual normalized loan plus `employee`: `{full_name, employee_id, department}` from the server's
  /// employee relation (or an empty map). Amounts are numbers or null.
  Future<List<Map<String, dynamic>>> approvalLoans() async {
    final me = employeeId;
    final data = await api.get(orgPath('/loans'));
    final rows = asMapList(data)
        .map((r) {
          final m = Map<String, dynamic>.from(snakeKeys(r) as Map);
          for (final k in _loanNumbers) {
            if (m.containsKey(k)) m[k] = asNum(m[k]);
          }
          if (m.containsKey('tenure_months')) {
            m['tenure_months'] = asNum(m['tenure_months'])?.toInt();
          }
          Map? rel;
          for (final e in m.entries) {
            if (e.key.startsWith('employee_records') && e.value is Map) {
              rel = e.value as Map;
              break;
            }
          }
          m['employee'] = rel == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(rel);
          return m;
        })
        .where((m) => m['employee_id']?.toString() != me)
        .toList();
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  /// `POST /organizations/:orgId/loans/:loanId/approve` - NO body: the server approves at the requested amount
  /// (`loans.routes.ts` takes no body; `loans.service.ts` `approveLoan` passes the requested amount to the engine).
  Future<void> approveLoan(String loanId) async {
    await api.post(orgPath('/loans/${Uri.encodeComponent(loanId)}/approve'));
  }

  /// `POST /organizations/:orgId/loans/:loanId/reject` with `{reason}` when a reason was given (else `{}`).
  Future<void> rejectLoan(String loanId, {String? reason}) async {
    final r = reason?.trim() ?? '';
    await api.post(
      orgPath('/loans/${Uri.encodeComponent(loanId)}/reject'),
      body: {if (r.isNotEmpty) 'reason': r},
    );
  }

  /// Friendly text for a failed decision or approvals list.
  static String decisionErrorText(Object e) => approvalErrorText(
    e,
    fallback: "Couldn't complete this right now. Please try again.",
  );

  /// A loan or instalment amount worth showing: a real number above zero. A missing, non-numeric or
  /// zero amount may be an unreadable encrypted value on the server, so it is not shown as "₹0".
  static bool isUsableAmount(num? v) => v != null && v > 0;

  /// The statuses whose requested amount counts toward the loan limit.
  static const countedStatuses = {'active', 'approved', 'pending'};

  /// What the employee has taken or requested against the limit: the requested amounts of loans that are
  /// active, approved or pending. [incomplete] is true when a counted loan has no usable amount, so the
  /// total is a lower bound and must not be shown as exact.
  static ({double total, bool incomplete}) usedAgainstLimit(
    List<Map<String, dynamic>> loans,
  ) {
    var total = 0.0;
    var incomplete = false;
    for (final l in loans) {
      final status = (l['status'] ?? '').toString().toLowerCase();
      if (!countedStatuses.contains(status)) continue;
      final amount = asNum(l['requested_amount']);
      if (isUsableAmount(amount)) {
        total += amount!.toDouble();
      } else {
        incomplete = true;
      }
    }
    return (total: total, incomplete: incomplete);
  }
}
