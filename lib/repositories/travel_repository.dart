import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'approval_errors.dart';
import 'base_repository.dart';
import 'employee_repository.dart';
import 'file_repository.dart';
import 'loans_repository.dart';

/// A receipt picked on the device, read into memory.
class ReceiptFile {
  const ReceiptFile({
    required this.bytes,
    required this.name,
    this.contentType,
  });

  final List<int> bytes;
  final String name;
  final String? contentType;
}

/// One line of a travel claim as entered on the form.
class TravelLine {
  const TravelLine({
    required this.expenseDate,
    required this.expenseType,
    required this.description,
    required this.amount,
    this.receipt,
  });

  /// `yyyy-MM-dd`
  final String expenseDate;
  final String expenseType;
  final String description;
  final double amount;
  final ReceiptFile? receipt;
}

/// The claim row was created but not every line could be saved.
///
/// The claim is left as it is (nothing is deleted automatically): it may exist without all its lines,
/// so the employee should check the list and contact HR.
class TravelClaimIncompleteException implements Exception {
  const TravelClaimIncompleteException({
    required this.claimId,
    required this.savedLines,
    required this.totalLines,
    this.cause,
  });

  final String claimId;
  final int savedLines;
  final int totalLines;
  final Object? cause;

  @override
  String toString() =>
      'TravelClaimIncompleteException(saved $savedLines of $totalLines)';
}

/// The signed-in employee's own travel claims.
class TravelRepository extends BaseRepository {
  TravelRepository({super.auth});

  static const receiptBucket = 'travel-receipts';

  late final FileRepository _files = FileRepository(auth: auth);

  /// `GET /organizations/:orgId/travel/claims?employeeId=<own>`, newest first.
  ///
  /// `employeeId` is always sent: managers and HR would otherwise also receive their team's claims.
  /// Decimal columns arrive as strings and dates as ISO timestamps; the UI gets numbers and `yyyy-MM-dd`.
  Future<List<Map<String, dynamic>>> claims() async {
    final data = await api.get(
      orgPath('/travel/claims'),
      query: {'employeeId': employeeId},
    );
    final rows = asMapList(data).map(_normalizeClaim).toList();
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  /// The caller's reporting manager (`employee_records.manager_id`), or null.
  Future<String?> managerId() async {
    final me = await EmployeeRepository(auth: auth).getMe();
    final id = me['manager_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Uploads a receipt to the private `travel-receipts` bucket and returns its `bucket/path` reference.
  Future<String> uploadReceipt(ReceiptFile file) async {
    final up = await _files.upload(
      bucket: receiptBucket,
      bytes: file.bytes,
      fileName: file.name,
      contentType: file.contentType,
    );
    return up.ref;
  }

  /// `POST /organizations/:orgId/travel/claims`. `claim_number` is never sent (the server assigns it).
  /// Returns the created claim row (with its `id`).
  Future<Map<String, dynamic>> createClaim({
    required String tripPurpose,
    required String tripDestination,
    required String fromLocation,
    required DateTime tripFromDate,
    required DateTime tripToDate,
    required String travelType,
    required double totalAmount,
    String? managerId,
  }) async {
    final days =
        DateTime(tripToDate.year, tripToDate.month, tripToDate.day)
            .difference(
              DateTime(tripFromDate.year, tripFromDate.month, tripFromDate.day),
            )
            .inDays +
        1;
    final data = await api.post(
      orgPath('/travel/claims'),
      body: {
        'employee_id': employeeId,
        'trip_purpose': tripPurpose,
        'trip_destination': tripDestination,
        'from_location': fromLocation,
        'trip_from_date': _ymd(tripFromDate),
        'trip_to_date': _ymd(tripToDate),
        'total_days': days,
        'travel_type': travelType,
        'total_amount': totalAmount,
        'status': 'pending',
        if (managerId != null && managerId.isNotEmpty) 'manager_id': managerId,
      },
    );
    if (data is! Map || data['id'] == null) {
      throw const ApiException(500, 'Unexpected response from the server');
    }
    return _normalizeClaim(Map<String, dynamic>.from(data));
  }

  /// `POST /organizations/:orgId/travel-expenses` - one call per line (the API has no bulk form).
  Future<void> addLine(
    String claimId,
    TravelLine line, {
    String? receiptRef,
  }) async {
    await api.post(
      orgPath('/travel-expenses'),
      body: {
        'claimId': claimId,
        'amount': line.amount,
        'expenseType': line.expenseType,
        'description': line.description,
        'expenseDate': line.expenseDate,
        if (receiptRef != null) 'receiptUrl': receiptRef,
      },
    );
  }

  /// Uploads the receipts, creates the claim, then saves every line.
  ///
  /// * A failed receipt upload happens before anything is created, so the original error is thrown.
  /// * If a line fails after the claim exists, a [TravelClaimIncompleteException] is thrown and the claim is
  ///   left untouched (no automatic delete). It is never reported as submitted.
  Future<String> submitClaim({
    required String tripPurpose,
    required String tripDestination,
    required String fromLocation,
    required DateTime tripFromDate,
    required DateTime tripToDate,
    required String travelType,
    required List<TravelLine> lines,
  }) async {
    if (lines.isEmpty) throw StateError('Add at least one expense line');

    final refs = <String?>[];
    for (final line in lines) {
      refs.add(
        line.receipt == null ? null : await uploadReceipt(line.receipt!),
      );
    }

    final total = lines.fold<double>(0, (sum, l) => sum + l.amount);
    final claim = await createClaim(
      tripPurpose: tripPurpose,
      tripDestination: tripDestination,
      fromLocation: fromLocation,
      tripFromDate: tripFromDate,
      tripToDate: tripToDate,
      travelType: travelType,
      totalAmount: total,
      managerId: await _managerIdOrNull(),
    );
    final claimId = claim['id'].toString();

    var saved = 0;
    try {
      for (var i = 0; i < lines.length; i++) {
        await addLine(claimId, lines[i], receiptRef: refs[i]);
        saved++;
      }
    } catch (e) {
      // The claim exists but is missing lines. It is deliberately not deleted: the caller reports it as incomplete.
      throw TravelClaimIncompleteException(
        claimId: claimId,
        savedLines: saved,
        totalLines: lines.length,
        cause: e,
      );
    }
    return claimId;
  }

  /// The manager lookup must never block a submission.
  Future<String?> _managerIdOrNull() async {
    try {
      return await managerId();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- manager approvals

  /// Statuses a claim can still be decided in (the engine's open statuses for `travel_claims`).
  static const openStatuses = {'pending', 'manager_approved'};

  static bool isOpen(Map<String, dynamic> claim) =>
      openStatuses.contains((claim['status'] ?? '').toString().toLowerCase());

  /// `GET /organizations/:orgId/travel/claims` (no `employeeId`) - the claims the server lets this manager see: their
  /// reporting tree plus their own (`travel-access.ts` `visibleEmployeeIds`; HR sees all). Newest first, every status.
  /// The caller's own claims are left out (nobody decides their own claim; they are in the hub's own list).
  ///
  /// Each row is the normalized claim plus `employee` (`{full_name, employee_id, department, designation}` from the list's
  /// employee relation, or an empty map) and `expenses` (the claim's `travel_expenses` lines, amounts as numbers).
  Future<List<Map<String, dynamic>>> approvalClaims() async {
    final me = employeeId;
    final data = await api.get(orgPath('/travel/claims'));
    final rows = asMapList(data)
        .map((r) {
          final m = _normalizeClaim(r);
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
          final lines = m['travel_expenses'];
          final expenses = <Map<String, dynamic>>[];
          if (lines is List) {
            for (final l in lines) {
              if (l is! Map) continue;
              final e = Map<String, dynamic>.from(snakeKeys(l) as Map);
              if (e.containsKey('amount')) e['amount'] = asNum(e['amount']);
              if (e['expense_date'] != null) {
                e['expense_date'] = asDateOnly(e['expense_date']);
              }
              expenses.add(e);
            }
          }
          m['expenses'] = expenses;
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

  /// `POST /organizations/:orgId/travel/claims/:claimId/approve` with `{}` or `{approvedAmount}` (`travel-claims.routes.ts`).
  /// The server's answer is the claim without the employee relation, so callers reload the list instead of using it.
  Future<void> approveClaim(String claimId, {double? approvedAmount}) async {
    await api.post(
      orgPath('/travel/claims/${Uri.encodeComponent(claimId)}/approve'),
      body: {if (approvedAmount != null) 'approvedAmount': approvedAmount},
    );
  }

  /// `POST /organizations/:orgId/travel/claims/:claimId/reject` with `{reason}` when given (else `{}`).
  Future<void> rejectClaim(String claimId, {String? reason}) async {
    final r = reason?.trim() ?? '';
    await api.post(
      orgPath('/travel/claims/${Uri.encodeComponent(claimId)}/reject'),
      body: {if (r.isNotEmpty) 'reason': r},
    );
  }

  static const travelAdvanceCategory = 'travel_advance';

  /// Travel advances are loans with `loan_category = travel_advance`: `POST /loans/request` with that category.
  Future<String> requestAdvance({
    required double amount,
    required String reason,
    int? repaymentMonths,
  }) => LoansRepository(auth: auth).requestLoan(
    amount: amount,
    reason: reason,
    repaymentMonths: repaymentMonths,
    loanCategory: travelAdvanceCategory,
  );

  /// The caller's own travel advances: their own loans (`GET /loans?employeeId=<own>`) in the `travel_advance` category.
  Future<List<Map<String, dynamic>>> advances() async {
    final all = await LoansRepository(auth: auth).loans();
    return all
        .where(
          (l) =>
              (l['loan_category'] ?? '').toString().toLowerCase() ==
              travelAdvanceCategory,
        )
        .toList();
  }

  /// Friendly text for a failed decision or approvals list.
  static String decisionErrorText(Object e) => approvalErrorText(
    e,
    fallback: "Couldn't complete this right now. Please try again.",
  );

  static Map<String, dynamic> _normalizeClaim(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(snakeKeys(raw) as Map);
    for (final k in const ['total_amount', 'approved_amount']) {
      if (m.containsKey(k)) m[k] = asNum(m[k]);
    }
    for (final k in const ['trip_from_date', 'trip_to_date']) {
      if (m[k] != null) m[k] = asDateOnly(m[k]);
    }
    return m;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
