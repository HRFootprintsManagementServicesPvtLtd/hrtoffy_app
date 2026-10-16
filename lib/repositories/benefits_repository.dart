import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'approval_errors.dart';
import 'base_repository.dart';

/// The signed-in employee's benefit claims, the benefit catalog and claim submission.
///
/// [submitClaim] exists, but the screen keeps it switched off (`kBenefitClaimSubmissionEnabled`) until the backend fix
/// that stores a claim's payroll fields (payment mode, month, year, manager) is confirmed deployed: without it an
/// approved claim is never picked up by payroll.
class BenefitsRepository extends BaseRepository {
  BenefitsRepository({super.auth});

  /// `GET /organizations/:orgId/benefits/claims?employeeId=<own>` - newest claim first.
  ///
  /// `employeeId` is always sent: users who can view compensation would otherwise receive the whole
  /// organization's claims. Each claim carries `benefits_catalog: {benefit_name, benefit_type, description}`.
  /// Decimal columns arrive as strings (`"1250.00"`) and dates as timestamps; the UI gets numbers (whole
  /// amounts without a trailing `.0`) and `yyyy-MM-dd`.
  Future<List<Map<String, dynamic>>> claims() async {
    final data = await api.get(
      orgPath('/benefits/claims'),
      query: {'employeeId': employeeId},
    );
    final rows = asMapList(data).map(_normalizeClaim).toList();
    rows.sort((a, b) {
      final byDate = (asDate(b['claim_date']) ?? DateTime(0)).compareTo(
        asDate(a['claim_date']) ?? DateTime(0),
      );
      if (byDate != 0) return byDate;
      return (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      );
    });
    return rows;
  }

  /// `GET /organizations/:orgId/benefits/claims/:claimId` - one claim with the full catalog entry. The server answers
  /// "not found" for a claim that is not the caller's own (unless the caller may view compensation).
  Future<Map<String, dynamic>> claim(String claimId) async {
    final data = await api.get(
      orgPath('/benefits/claims/${Uri.encodeComponent(claimId)}'),
    );
    if (data is! Map)
      throw const ApiException(
        502,
        'Unexpected response while loading the claim.',
        code: 'BENEFIT_BAD_RESPONSE',
      );
    return _normalizeClaim(Map<String, dynamic>.from(data));
  }

  /// `POST /organizations/:orgId/benefits/claims` with `{employeeId, benefitId, claimedAmount, description}` -> `{claimId}`.
  ///
  /// `employeeId` is the signed-in user's own (from the session); the server accepts someone else's only for
  /// HR/finance. The status, claim date, payment mode, month/year, manager and submitter are set by the server and are
  /// never sent. The server checks only that the amount is positive and the benefit belongs to the organization: it does
  /// NOT enforce the yearly or grade limit, so those checks in the app are advisory. No attachment is sent
  /// (`supportingDocuments` is left out): the app does not upload claim documents yet.
  Future<String> submitClaim({
    required String benefitId,
    required double amount,
    required String description,
  }) async {
    final data = await api.post(
      orgPath('/benefits/claims'),
      body: {
        'employeeId': employeeId,
        'benefitId': benefitId,
        'claimedAmount': amount,
        'description': description,
      },
    );
    final id = data is Map ? data['claimId']?.toString() : null;
    if (id == null || id.isEmpty)
      throw const ApiException(
        502,
        'Unexpected response while submitting the claim.',
        code: 'BENEFIT_BAD_RESPONSE',
      );
    return id;
  }

  /// `GET /organizations/:orgId/benefits/catalog` - the organization's active benefits (`id`, `benefit_name`, ...).
  Future<List<Map<String, dynamic>>> catalog() async {
    final data = await api.get(orgPath('/benefits/catalog'));
    return asMapList(
      data,
    ).map((c) => Map<String, dynamic>.from(snakeKeys(c) as Map)).toList();
  }

  /// `GET /organizations/:orgId/grade-structures/limits/:gradeCode` - the grade's limits as
  /// `{grade_code, grade_name, benefit_annual_limit, loan_max_amount, travel_per_trip_limit}`, or null
  /// when the grade has no row (or the caller may not read it). Amounts are numbers.
  Future<Map<String, dynamic>?> gradeLimit(String gradeCode) async {
    final data = await api.get(
      orgPath('/grade-structures/limits/${Uri.encodeComponent(gradeCode)}'),
    );
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(snakeKeys(data) as Map);
    for (final k in const [
      'benefit_annual_limit',
      'loan_max_amount',
      'travel_per_trip_limit',
    ]) {
      if (m.containsKey(k)) m[k] = asNum(m[k]);
    }
    return m;
  }

  /// What this calendar [year] has used of the annual benefit limit: the approved amount (else the claimed
  /// amount) of every claim of that `claim_year` that is not rejected. A claim without a `claim_year` is not counted.
  static double claimedTotalForYear(
    List<Map<String, dynamic>> claims,
    int year,
  ) {
    var total = 0.0;
    for (final c in claims) {
      if (asInt(c['claim_year']) == year && c['status'] != 'rejected') {
        total += asDouble(c['approved_amount'] ?? c['claimed_amount']);
      }
    }
    return total;
  }

  // ---------------------------------------------------------------- manager ESI approvals

  /// `GET /organizations/:orgId/benefits/esi/claims` - ESI claims waiting for this caller (`benefits.routes.ts`,
  /// `benefits.service.ts` `listEsiClaimsForApproval`): a manager gets their reporting tree's `pending` ESI claims, HR gets
  /// `pending` and `manager_approved` ones. Decided claims are not part of this list, so there is no history.
  ///
  /// Rows are the server's ESI claim plus `employee_name`, `employee_code`, `department`. `claimed_amount` is not an amount
  /// the employee entered for ESI claims (the server stores 0), so the UI never shows it. The caller's own claims are left out.
  Future<List<Map<String, dynamic>>> esiApprovalClaims() async {
    final me = employeeId;
    final data = await api.get(orgPath('/benefits/esi/claims'));
    final rows = asMapList(data).map(_normalizeClaim).toList();
    for (final m in rows) {
      for (final k in const ['esi_start_date', 'esi_end_date']) {
        if (m[k] != null) m[k] = asDateOnly(m[k]);
      }
      if (m['esi_days_claimed'] != null) {
        m['esi_days_claimed'] = asInt(m['esi_days_claimed']);
      }
    }
    rows.removeWhere((m) => m['employee_id']?.toString() == me);
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  /// `POST /organizations/:orgId/benefits/esi/claims/:claimId/approve`. The route destructures `request.body`, so a JSON body
  /// is ALWAYS sent: `{}` or `{comments}`.
  Future<void> approveEsiClaim(String claimId, {String? comments}) =>
      _decideEsi(claimId, 'approve', comments);

  /// `POST /organizations/:orgId/benefits/esi/claims/:claimId/reject` - always a JSON body: `{}` or `{comments}`.
  Future<void> rejectEsiClaim(String claimId, {String? comments}) =>
      _decideEsi(claimId, 'reject', comments);

  Future<void> _decideEsi(String claimId, String verb, String? comments) async {
    final c = comments?.trim() ?? '';
    await api.post(
      orgPath('/benefits/esi/claims/${Uri.encodeComponent(claimId)}/$verb'),
      body: {if (c.isNotEmpty) 'comments': c},
    );
  }

  // ---------------------------------------------------------------- manager general (non-ESI) approvals

  /// `GET /organizations/:orgId/benefits/claims` (NO `employeeId`; `benefits.service.ts` `listBenefitClaims`): a manager gets
  /// their own claims plus their reporting tree's, every status, as `{items, total}`. ESI claims (`is_esi_claim == true`) and
  /// the caller's own claims are left out. Each row is the normalized claim plus `employee`
  /// (`{full_name, email, employee_id, department}` from the server's employee relation, or an empty map) and
  /// `benefit_name` (from `benefits_catalog`). Newest first.
  Future<List<Map<String, dynamic>>> generalApprovalClaims() async {
    final me = employeeId;
    final data = await api.get(orgPath('/benefits/claims'));
    final rows = <Map<String, dynamic>>[];
    for (final raw in asMapList(data)) {
      final m = _normalizeClaim(raw);
      if (m['is_esi_claim'] == true) continue;
      if (m['employee_id']?.toString() == me) continue;
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
      final cat = m['benefits_catalog'];
      if (cat is Map && cat['benefit_name'] != null) {
        m['benefit_name'] = cat['benefit_name'].toString();
      }
      rows.add(m);
    }
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? asDate(b['claim_date']) ?? DateTime(0))
          .compareTo(
            asDate(a['created_at']) ?? asDate(a['claim_date']) ?? DateTime(0),
          ),
    );
    return rows;
  }

  /// `POST /organizations/:orgId/benefits/claims/:claimId/approve` with `{approvedAmount}` (required by the service, which
  /// passes it to the approval engine as `approved_amount`; the caller defaults it to the claimed amount).
  Future<void> approveClaim(String claimId, {required num approvedAmount}) async {
    await api.post(
      orgPath('/benefits/claims/${Uri.encodeComponent(claimId)}/approve'),
      body: {'approvedAmount': approvedAmount},
    );
  }

  /// `POST /organizations/:orgId/benefits/claims/:claimId/reject` with `{comments}` (the route reads `comments`; a JSON
  /// object is always sent because the handler destructures the body).
  Future<void> rejectClaim(String claimId, {String? comments}) async {
    final c = comments?.trim() ?? '';
    await api.post(
      orgPath('/benefits/claims/${Uri.encodeComponent(claimId)}/reject'),
      body: {if (c.isNotEmpty) 'comments': c},
    );
  }

  /// Friendly text for a failed decision or approvals list.
  static String decisionErrorText(Object e) => approvalErrorText(
    e,
    fallback: "Couldn't complete this right now. Please try again.",
  );

  static Map<String, dynamic> _normalizeClaim(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(snakeKeys(raw) as Map);
    for (final k in const [
      'claimed_amount',
      'approved_amount',
      'taxable_amount',
      'exempt_amount',
    ]) {
      if (m.containsKey(k)) m[k] = _plain(asNum(m[k]));
    }
    for (final k in const ['claim_month', 'claim_year']) {
      if (m[k] != null) m[k] = asInt(m[k]);
    }
    if (m['claim_date'] != null) m['claim_date'] = asDateOnly(m['claim_date']);
    return m;
  }

  /// 1250.0 -> 1250 (shown as "1250", as the numeric column used to arrive); 1250.5 stays.
  static num? _plain(num? v) =>
      (v != null && v == v.truncate()) ? v.truncate() : v;
}
