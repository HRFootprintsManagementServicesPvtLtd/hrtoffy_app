import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in employee's tax declaration data: reads, plus saving the regime and declaration DRAFTS.
///
/// Submitting declarations for review is deliberately NOT part of this repository. The write routes are verified in
/// local backend source only; their deployment is not verified.
///
/// `ApiClient` unwraps the `{success, data}` envelope. Rows are handed to the UI as the snake_case maps it
/// read from the previous backend (`max_amount`, `declared_amount`, `regime_type`, ...), whatever case the backend
/// uses; decimals that arrive as strings (`"150000.00"`) become numbers. No field is invented: a missing
/// field stays absent / null.
class TaxRepository extends BaseRepository {
  TaxRepository({super.auth});

  /// `GET /organizations/:orgId/employees/me`
  Future<Map<String, dynamic>> employee() async {
    final data = await api.get(orgPath('/employees/me'));
    return _row(data) ?? <String, dynamic>{};
  }

  /// `GET /organizations/:orgId/payroll/tax-deduction-types`, active types only, ordered by `code`.
  Future<List<Map<String, dynamic>>> deductionTypes() async {
    final data = await api.get(orgPath('/payroll/tax-deduction-types'));
    final rows = asMapList(data)
        .map((r) => Map<String, dynamic>.from(snakeKeys(r) as Map))
        .where((r) => r['is_active'] != false)
        .map((r) => _numbers(r, const ['max_amount']))
        .toList();
    rows.sort((a, b) => '${a['code'] ?? ''}'.compareTo('${b['code'] ?? ''}'));
    return rows;
  }

  /// `GET /organizations/:orgId/payroll/tax-submission-window?financialYear=`; null when no window is set
  /// (no window means the declaration window is open).
  Future<Map<String, dynamic>?> submissionWindow(String financialYear) async {
    final data = await api.get(
      orgPath('/payroll/tax-submission-window'),
      query: {'financialYear': canonicalFinancialYear(financialYear)},
    );
    return _row(data);
  }

  /// `GET /organizations/:orgId/payroll/income-tax-config?financialYear=`; null when the organization has
  /// no configuration for that year (the UI then keeps its built-in defaults).
  Future<Map<String, dynamic>?> incomeTaxConfig(String financialYear) async {
    final data = await api.get(
      orgPath('/payroll/income-tax-config'),
      query: {'financialYear': canonicalFinancialYear(financialYear)},
    );
    final m = _row(data);
    if (m == null) return null;
    _numbers(m, const [
      'standard_deduction_old_regime',
      'standard_deduction_new_regime',
      'rebate_limit_old_regime',
      'rebate_limit_new_regime',
      'cess_rate',
    ]);
    for (final key in const ['old_regime_slabs', 'new_regime_slabs']) {
      final slabs = m[key];
      if (slabs is List) {
        m[key] = [
          for (final s in slabs)
            if (s is Map)
              _numbers(Map<String, dynamic>.from(snakeKeys(s) as Map), const [
                'min_income',
                'max_income',
                'rate',
              ]),
        ];
      }
    }
    return m;
  }

  /// `GET /organizations/:orgId/payroll/me/tax-regime?financialYear=` (the token identifies the employee);
  /// null when the employee has not chosen a regime for that year.
  Future<Map<String, dynamic>?> taxRegime(String financialYear) async {
    final data = await api.get(
      orgPath('/payroll/me/tax-regime'),
      query: {'financialYear': canonicalFinancialYear(financialYear)},
    );
    final m = _row(data);
    if (m == null) return null;
    return _numbers(m, const ['annual_tax_liability', 'monthly_tds']);
  }

  /// `GET /organizations/:orgId/payroll/me/tax-declarations?financialYear=` (the token identifies the employee).
  Future<List<Map<String, dynamic>>> taxDeclarations(
    String financialYear,
  ) async {
    final data = await api.get(
      orgPath('/payroll/me/tax-declarations'),
      query: {'financialYear': canonicalFinancialYear(financialYear)},
    );
    return asMapList(data)
        .map(
          (r) => _numbers(
            Map<String, dynamic>.from(snakeKeys(r) as Map),
            const ['declared_amount'],
          ),
        )
        .toList();
  }

  /// `PUT /organizations/:orgId/payroll/tax-regime-selections` (payroll-tax.routes.ts) with
  /// `{employeeId, financialYear, regime_type}`. `employeeId` is always the signed-in user's own (from the session); the
  /// server refuses another employee's id unless the caller holds the tax-config permission, and for the employee's own
  /// row it keeps only `regime_type` and `selected_at` (computed fields are dropped). The server does NOT validate
  /// `regime_type` or `financialYear`, so the app sends only `new_regime` / `old_regime` and the same year string it
  /// reads with. The `/payroll/me/tax-regime` PUT is deliberately not used: its source upserts on a Prisma key
  /// (`employee_id_organization_id_financial_year`) that the schema does not define.
  Future<void> saveTaxRegime({
    required String financialYear,
    required String regimeType,
  }) async {
    if (regimeType != 'new_regime' && regimeType != 'old_regime') {
      throw ArgumentError.value(regimeType, 'regimeType');
    }
    final data = await api.put(
      orgPath('/payroll/tax-regime-selections'),
      body: {
        'employeeId': employeeId,
        'financialYear': canonicalFinancialYear(financialYear),
        'regime_type': regimeType,
        // The employee's own row may update `selected_at` (REGIME_SELECTION_EMPLOYEE_FIELDS); the route passes it unchanged to
        // Prisma's DateTime column on create and update. Payroll orders an employee's elections by `selected_at` (latest wins),
        // and an update that omits it keeps the old value. This does not fix ordering against rows stored under another
        // financial-year spelling by other clients.
        'selected_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (data is! Map)
      throw const ApiException(
        502,
        'Unexpected response while saving the tax regime.',
        code: 'TAX_BAD_RESPONSE',
      );
  }

  /// `PUT /organizations/:orgId/payroll/tax-declarations` (payroll-tax.routes.ts) with
  /// `{employeeId, financialYear, deductionTypeId, declared_amount, is_claimed, employee_notes}`; saves ONE declaration
  /// as the employee's own. Partial updates are supported (only the keys sent change). `status` is never sent: the server
  /// creates a new row as `draft`, leaves a draft/submitted row as it is, and sends an approved or rejected row back to
  /// `submitted` when the employee edits it (so the app does not edit those). This is a draft save, not a submission.
  /// The server does NOT enforce the submission window or the deduction type's maximum, and does not validate the amount.
  Future<void> saveTaxDeclarationDraft({
    required String financialYear,
    required String deductionTypeId,
    required bool isClaimed,
    double? declaredAmount,
    String? notes,
  }) async {
    if (declaredAmount != null &&
        (!declaredAmount.isFinite || declaredAmount < 0)) {
      throw ArgumentError.value(declaredAmount, 'declaredAmount');
    }
    final data = await api.put(
      orgPath('/payroll/tax-declarations'),
      body: {
        'employeeId': employeeId,
        'financialYear': canonicalFinancialYear(financialYear),
        'deductionTypeId': deductionTypeId,
        'is_claimed': isClaimed,
        if (declaredAmount != null) 'declared_amount': declaredAmount,
        if (notes != null) 'employee_notes': notes,
      },
    );
    if (data is! Map)
      throw const ApiException(
        502,
        'Unexpected response while saving the declaration.',
        code: 'TAX_BAD_RESPONSE',
      );
  }

  /// The financial year in the CANONICAL `YYYY-YY` form ("2026-27"), which is what the website stores and queries by at
  /// every tax boundary and what the projection route requires. The tax routes match the string EXACTLY (the backend
  /// does no normalization), so the legacy `YYYY-YYYY` spelling ("2026-2027") finds nothing that the website saved
  /// (regime, declarations, organization config, submission window) and would save rows under a different key.
  /// Anything that is not a `YYYY-YYYY` pair is returned unchanged.
  static String canonicalFinancialYear(String financialYear) {
    final m = RegExp(r'^\s*(\d{4})-(\d{4})\s*$').firstMatch(financialYear);
    if (m == null) return financialYear.trim();
    return '${m.group(1)}-${m.group(2)!.substring(2)}';
  }

  /// `GET /organizations/:orgId/payroll/calc/tds/projection?employeeId=&financialYear=`: the payroll server's own
  /// estimate for the signed-in employee, the one the website shows (paid months + projection of the rest of the year,
  /// both regimes, declarations as they count). The server allows an employee to read only their own. Nothing is
  /// computed here; null when the route answers with something that is not a projection.
  Future<TdsProjection?> projection(String financialYear) async {
    final data = await api.get(
      orgPath('/payroll/calc/tds/projection'),
      query: {
        'employeeId': employeeId,
        'financialYear': canonicalFinancialYear(financialYear),
      },
    );
    return data is Map ? TdsProjection.fromJson(Map<String, dynamic>.from(data)) : null;
  }

  /// A salary figure usable for tax, or null. Null, zero, negative, non-numeric and non-finite values are all
  /// "unavailable": a zero may be an unreadable encrypted column rather than a real salary, so it must never
  /// feed a tax calculation.
  static double? usableSalary(dynamic raw) {
    final n = asNum(raw);
    if (n == null) return null;
    final d = n.toDouble();
    return d.isFinite && d > 0 ? d : null;
  }

  /// One object from a bare object, a one-element list, or `{items|data: [...]}`; null when empty/absent.
  static Map<String, dynamic>? _row(dynamic data) {
    dynamic d = data;
    if (d is Map && (d['items'] is List || d['data'] is List))
      d = d['items'] ?? d['data'];
    if (d is List) d = d.isEmpty ? null : d.first;
    if (d is! Map || d.isEmpty) return null;
    return Map<String, dynamic>.from(snakeKeys(d) as Map);
  }

  static Map<String, dynamic> _numbers(
    Map<String, dynamic> m,
    List<String> keys,
  ) {
    for (final k in keys) {
      if (m.containsKey(k)) m[k] = asNum(m[k]);
    }
    return m;
  }
}

double? _dec(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final d = double.tryParse(v.toString());
  return d != null && d.isFinite ? d : null;
}

/// One regime's figures from the payroll server's projection. Amounts arrive as decimal strings; a missing figure
/// stays null (never 0).
class TdsRegimeProjection {
  const TdsRegimeProjection({
    required this.projectedAnnualIncome,
    required this.annualTax,
    required this.taxableIncome,
    required this.monthlyTds,
    required this.standardDeduction,
    required this.allowedDeductions,
  });

  final double? projectedAnnualIncome;
  final double? annualTax;
  final double? taxableIncome;
  final double? monthlyTds;
  final double? standardDeduction;

  /// The declared deductions that count under this regime (sum of `allowed`), null when the server sent none.
  final double? allowedDeductions;

  /// The projection carries the figures that the summary shows.
  bool get isUsable => taxableIncome != null && annualTax != null && monthlyTds != null;

  factory TdsRegimeProjection.fromJson(Map<String, dynamic> j) {
    double? allowed;
    final ds = j['deductions'];
    if (ds is List) {
      for (final d in ds) {
        if (d is Map) allowed = (allowed ?? 0) + (_dec(d['allowed']) ?? 0);
      }
    }
    return TdsRegimeProjection(
      projectedAnnualIncome: _dec(j['projectedAnnualIncome']),
      annualTax: _dec(j['annualTax']),
      taxableIncome: _dec(j['taxableIncome']),
      monthlyTds: _dec(j['monthlyTds']),
      standardDeduction: _dec(j['standardDeduction']),
      allowedDeductions: allowed,
    );
  }
}

/// The payroll server's tax projection for the financial year (`payroll/calc/tds/projection`).
class TdsProjection {
  const TdsProjection({
    required this.applicable,
    required this.reason,
    required this.selectedRegime,
    required this.oldRegime,
    required this.newRegime,
    required this.recommendedRegime,
    required this.annualSaving,
    required this.earnedToDate,
    required this.tdsDeductedToDate,
    required this.warnings,
    required this.usedUnverifiedRule,
  });

  /// False when the server does not compute TDS for this employee (exempt, switched off, no rule): [reason] says why.
  final bool applicable;
  final String? reason;

  /// 'old' | 'new' | null
  final String? selectedRegime;
  final TdsRegimeProjection? oldRegime;
  final TdsRegimeProjection? newRegime;

  /// 'old' | 'new' | 'equal' | null
  final String? recommendedRegime;
  final double? annualSaving;

  /// Gross paid per month so far in the year, as the server counted it.
  final List<({String month, double? gross})> earnedToDate;
  final double? tdsDeductedToDate;
  final List<String> warnings;

  /// The TDS rule behind the figures is a draft nobody has verified yet: the figures are an estimate.
  final bool usedUnverifiedRule;

  TdsRegimeProjection? forRegime(String regimeType) =>
      regimeType == 'old_regime' ? oldRegime : newRegime;

  factory TdsProjection.fromJson(Map<String, dynamic> j) {
    final regimes = j['regimes'] is Map ? Map<String, dynamic>.from(j['regimes'] as Map) : const <String, dynamic>{};
    TdsRegimeProjection? regime(String k) =>
        regimes[k] is Map ? TdsRegimeProjection.fromJson(Map<String, dynamic>.from(regimes[k] as Map)) : null;
    final earned = <({String month, double? gross})>[];
    final e = j['earnedToDate'];
    if (e is List) {
      for (final r in e) {
        if (r is Map) earned.add((month: (r['month'] ?? '').toString(), gross: _dec(r['gross'])));
      }
    }
    final w = j['warnings'];
    return TdsProjection(
      applicable: j['applicable'] == true,
      reason: j['reason']?.toString(),
      selectedRegime: j['selectedRegime']?.toString(),
      oldRegime: regime('old'),
      newRegime: regime('new'),
      recommendedRegime: j['recommendedRegime']?.toString(),
      annualSaving: _dec(j['annualSaving']),
      earnedToDate: earned,
      tdsDeductedToDate: _dec(j['tdsDeductedToDate']),
      warnings: w is List ? w.map((x) => x.toString()).toList() : const [],
      usedUnverifiedRule: j['usedUnverifiedRule'] == true,
    );
  }
}
