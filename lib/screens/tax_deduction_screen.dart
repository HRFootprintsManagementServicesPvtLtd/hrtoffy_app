// =============================================================================
// tax_deduction_screen.dart
// HR Footprints HRMS — Employee Tax Deduction (Flutter)
//
// Reads and DRAFT saves go to the HR Toffy AWS API through TaxRepository:
//   * Employee ................... GET /employees/me
//   * Deduction catalogue ........ GET /payroll/tax-deduction-types
//   * Submission window .......... GET /payroll/tax-submission-window?financialYear=
//   * Org tax config ............. GET /payroll/income-tax-config?financialYear=
//   * Regime ..................... GET /payroll/me/tax-regime?financialYear=
//   * Declarations ............... GET /payroll/me/tax-declarations?financialYear=
//
// Writes: PUT /payroll/tax-regime-selections (regime) and PUT /payroll/tax-declarations (one declaration, saved
// as a draft). Submitting declarations for review is NOT available: the button only explains that.
// The server does not enforce the submission window or the deduction maximum (checked here only).
// =============================================================================

import '../widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api/api_client.dart';
import '../repositories/employee_repository.dart';
import '../repositories/tax_repository.dart';
import '../widgets/drawer_route.dart';

// ---------------------------------------------------------------------------
// Design tokens (Calm Professional)
// ---------------------------------------------------------------------------
class _T {
  static const primary = Color(0xFF1E90FF);
  static const heading = Color(0xFF222222);
  static const body = Color(0xFF444444);
  static const subtext = Color(0xFF888888);
  static const border = Color(0xFFE0E0E0);
  static const surface = Color(0xFFF9F9F9);
  static const success = Color(0xFF219653);
  static const warning = Color(0xFFF2994A);
  static const error = Color(0xFFEB5757);
  static const info = Color(0xFF2F80ED);

  static const pastelBlue = Color(0xFFD7E8FF);
  static const pastelAqua = Color(0xFFD4F3F7);
  static const pastelLavender = Color(0xFFEBDFF6);
  static const pastelPeach = Color(0xFFFFECE6);
  static const pastelMint = Color(0xFFDFF6E5);

  static const r = 14.0;
}

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
String _inr(num v) => _money.format(v.round());

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class TaxDeductionType {
  final String id;
  final String code;
  final String name;
  final String description;
  final double maxAmount;
  final String sectionReference;
  final List<String> appliesToRegime;
  final bool requiresProof;

  TaxDeductionType({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.maxAmount,
    required this.sectionReference,
    required this.appliesToRegime,
    required this.requiresProof,
  });

  factory TaxDeductionType.fromMap(Map<String, dynamic> m) => TaxDeductionType(
    id: m['id'] as String,
    code: (m['code'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    description: (m['description'] ?? '') as String,
    maxAmount: _d(m['max_amount']),
    sectionReference: (m['section_reference'] ?? '') as String,
    appliesToRegime: ((m['applies_to_regime'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(),
    requiresProof: (m['requires_proof'] ?? false) as bool,
  );
}

class TaxDeclaration {
  final String? id;
  final String deductionTypeId;
  final double declaredAmount;
  final bool isClaimed;
  final String? employeeNotes;
  final String status;

  TaxDeclaration({
    required this.id,
    required this.deductionTypeId,
    required this.declaredAmount,
    required this.isClaimed,
    required this.employeeNotes,
    required this.status,
  });

  factory TaxDeclaration.fromMap(Map<String, dynamic> m) => TaxDeclaration(
    id: m['id'] as String?,
    deductionTypeId: m['deduction_type_id'] as String,
    declaredAmount: _d(m['declared_amount']),
    isClaimed: (m['is_claimed'] ?? false) as bool,
    employeeNotes: m['employee_notes'] as String?,
    status: (m['status'] ?? 'draft') as String,
  );

  TaxDeclaration copyWith({
    double? declaredAmount,
    bool? isClaimed,
    String? employeeNotes,
    String? status,
  }) => TaxDeclaration(
    id: id,
    deductionTypeId: deductionTypeId,
    declaredAmount: declaredAmount ?? this.declaredAmount,
    isClaimed: isClaimed ?? this.isClaimed,
    employeeNotes: employeeNotes ?? this.employeeNotes,
    status: status ?? this.status,
  );
}

class SubmissionWindow {
  final DateTime? declarationStart;
  final DateTime? declarationEnd;
  final DateTime? proofStart;
  final DateTime? proofEnd;

  SubmissionWindow({
    this.declarationStart,
    this.declarationEnd,
    this.proofStart,
    this.proofEnd,
  });

  factory SubmissionWindow.fromMap(Map<String, dynamic> m) => SubmissionWindow(
    declarationStart: _date(m['declaration_start_date']),
    declarationEnd: _date(m['declaration_end_date']),
    proofStart: _date(m['proof_submission_start_date']),
    proofEnd: _date(m['proof_submission_end_date']),
  );
}

class TaxSlab {
  final double minIncome;
  final double? maxIncome;
  final double rate;
  const TaxSlab(this.minIncome, this.maxIncome, this.rate);

  factory TaxSlab.fromMap(Map<String, dynamic> m) => TaxSlab(
    _d(m['minIncome'] ?? m['min_income']),
    (m['maxIncome'] ?? m['max_income']) == null
        ? null
        : _d(m['maxIncome'] ?? m['max_income']),
    _d(m['rate']),
  );
}

class IncomeTaxConfig {
  double stdDeductionOld;
  double stdDeductionNew;
  List<TaxSlab> oldSlabs;
  List<TaxSlab> newSlabs;
  double rebateLimitOld;
  double rebateLimitNew;
  double cessRate;

  IncomeTaxConfig({
    required this.stdDeductionOld,
    required this.stdDeductionNew,
    required this.oldSlabs,
    required this.newSlabs,
    required this.rebateLimitOld,
    required this.rebateLimitNew,
    required this.cessRate,
  });

  /// Same defaults the web page ships with.
  factory IncomeTaxConfig.defaults() => IncomeTaxConfig(
    stdDeductionOld: 50000,
    stdDeductionNew: 75000,
    oldSlabs: const [
      TaxSlab(0, 250000, 0),
      TaxSlab(250001, 500000, 5),
      TaxSlab(500001, 1000000, 20),
      TaxSlab(1000001, null, 30),
    ],
    newSlabs: const [
      TaxSlab(0, 400000, 0),
      TaxSlab(400001, 800000, 5),
      TaxSlab(800001, 1200000, 10),
      TaxSlab(1200001, 1600000, 15),
      TaxSlab(1600001, 2000000, 20),
      TaxSlab(2000001, 2400000, 25),
      TaxSlab(2400001, null, 30),
    ],
    rebateLimitOld: 500000,
    rebateLimitNew: 700000,
    cessRate: 4,
  );
}

class TaxComputation {
  final double grossSalary;
  final double standardDeduction;
  final double oldRegimeDeductions;
  final double totalDeductions;
  final double taxableIncome;
  final double annualTaxLiability;
  final double monthlyTDS;

  const TaxComputation({
    required this.grossSalary,
    required this.standardDeduction,
    required this.oldRegimeDeductions,
    required this.totalDeductions,
    required this.taxableIncome,
    required this.annualTaxLiability,
    required this.monthlyTDS,
  });
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v');
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class TaxDeductionScreen extends StatefulWidget {
  const TaxDeductionScreen({
    super.key,
    this.taxRepository,
    this.employeeRepository,
  });

  final TaxRepository? taxRepository;
  final EmployeeRepository? employeeRepository;

  @override
  State<TaxDeductionScreen> createState() => _TaxDeductionScreenState();
}

class _TaxDeductionScreenState extends State<TaxDeductionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TaxRepository _tax = widget.taxRepository ?? TaxRepository();
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();

  bool _loading = true;
  String? _fatalError;

  String _fy = '';
  Map<String, dynamic>? _employee;

  /// The employee's annual salary, or null when it is missing, zero or otherwise unusable (it may be an
  /// unreadable encrypted value). Tax figures are NOT shown while it is null.
  double? _annualSalary;

  /// The payroll server's own projection for this financial year (the figures the website shows), or null when the
  /// route could not be read. When it is usable the summary shows ITS numbers; nothing is computed on the device.
  TdsProjection? _projection;

  /// The server's figures for the regime currently selected, when the projection applies and carries them.
  TdsRegimeProjection? get _server {
    final p = _projection;
    if (p == null || !p.applicable) return null;
    final r = p.forRegime(_regime);
    return (r != null && r.isUsable) ? r : null;
  }

  /// When the server says TDS is not computed for this employee (exempt, switched off, no rule), no tax figure is shown at
  /// all: a salary read from another source must not produce a computed tax that contradicts the server.
  bool get _salaryAvailable =>
      _projection?.applicable == false ? false : (_annualSalary != null || _server != null);

  static const _notAvailable = 'Not available';

  /// A tax figure derived from salary: "Not available" rather than a misleading ₹0 when salary is unknown.
  String _taxFigure(double v) => _salaryAvailable ? _inr(v) : _notAvailable;

  String _regime = 'new_regime'; // 'new_regime' | 'old_regime'
  bool _regimeConfirmed = false;

  /// The regime as the server has it (null when none saved); [_regime] may differ until "Confirm" succeeds.
  String? _savedRegime;
  bool _savingRegime = false;
  bool _savingDrafts = false;

  /// Deduction types edited on this screen and not saved yet.
  final Set<String> _dirty = {};

  List<TaxDeductionType> _types = [];
  final Map<String, TaxDeclaration> _declarations = {};
  SubmissionWindow? _window;
  IncomeTaxConfig _config = IncomeTaxConfig.defaults();

  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};

  @override
  void initState() {
    super.initState();
    _fy = _currentFinancialYear();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in _amountCtrls.values) {
      c.dispose();
    }
    for (final c in _notesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // India FY: 1 Apr – 31 Mar (same helper as web)
  // Canonical `YYYY-YY` ("2026-27"): the form the website stores under and every tax route matches exactly.
  String _currentFinancialYear() {
    final now = DateTime.now();
    final start = now.month >= 4 ? now.year : now.year - 1;
    return TaxRepository.canonicalFinancialYear('$start-${start + 1}');
  }

  // -------------------------------------------------------------------------
  // Bootstrap (reads only)
  // -------------------------------------------------------------------------
  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _fatalError = null;
    });

    try {
      final results = await Future.wait<Object?>([
        _tax.employee(),
        _tax.deductionTypes(),
        _tax.submissionWindow(_fy),
        _tax.incomeTaxConfig(_fy),
        _tax.taxRegime(_fy),
        _tax.taxDeclarations(_fy),
      ]);
      final emp = results[0] as Map<String, dynamic>;
      if (emp.isEmpty) {
        throw const ApiException(
          404,
          'No employee record',
          code: 'NO_EMPLOYEE',
        );
      }
      _employee = emp;
      _annualSalary = await _resolveAnnualSalary(emp);
      _projection = await _loadProjection();

      _types = (results[1] as List<Map<String, dynamic>>)
          .map(_typeOrNull)
          .whereType<TaxDeductionType>()
          .toList();
      final w = results[2] as Map<String, dynamic>?;
      _window = w == null ? null : SubmissionWindow.fromMap(w);
      _config = _configFrom(results[3] as Map<String, dynamic>?);
      _applyRegime(results[4] as Map<String, dynamic>?);
      _applyDeclarations(results[5] as List<Map<String, dynamic>>);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fatalError = _loadError(e);
      });
    }
  }

  /// The server's projection (`payroll/calc/tds/projection`), best effort: any failure (route not on this server,
  /// not allowed, server error) leaves it null and the screen falls back to what it had, never to invented figures.
  Future<TdsProjection?> _loadProjection() async {
    try {
      return await _tax.projection(_fy);
    } catch (_) {
      return null;
    }
  }

  /// Salary sources, in order: the caller's own decrypted `sensitive-profile` (best effort: it may not
  /// exist on every environment, so a failure is not an error), then the `salary` on the employee record.
  /// Anything missing, zero or unparseable is null, never 0.
  Future<double?> _resolveAnnualSalary(Map<String, dynamic> emp) async {
    try {
      final sensitive = await _employees.getSensitiveProfile();
      final v = TaxRepository.usableSalary(sensitive['salary']);
      if (v != null) return v;
    } catch (_) {}
    return TaxRepository.usableSalary(emp['salary']);
  }

  TaxDeductionType? _typeOrNull(Map<String, dynamic> m) {
    try {
      return TaxDeductionType.fromMap(m);
    } catch (_) {
      return null; // a malformed row must not break the screen
    }
  }

  IncomeTaxConfig _configFrom(Map<String, dynamic>? m) {
    final cfg = IncomeTaxConfig.defaults();
    if (m == null) return cfg;
    cfg.stdDeductionOld = _d(m['standard_deduction_old_regime']) > 0
        ? _d(m['standard_deduction_old_regime'])
        : cfg.stdDeductionOld;
    cfg.stdDeductionNew = _d(m['standard_deduction_new_regime']) > 0
        ? _d(m['standard_deduction_new_regime'])
        : cfg.stdDeductionNew;
    cfg.rebateLimitOld = _d(m['rebate_limit_old_regime']) > 0
        ? _d(m['rebate_limit_old_regime'])
        : cfg.rebateLimitOld;
    cfg.rebateLimitNew = _d(m['rebate_limit_new_regime']) > 0
        ? _d(m['rebate_limit_new_regime'])
        : cfg.rebateLimitNew;
    cfg.cessRate = _d(m['cess_rate']) > 0 ? _d(m['cess_rate']) : cfg.cessRate;

    final oldS = m['old_regime_slabs'];
    if (oldS is List && oldS.isNotEmpty) {
      cfg.oldSlabs = oldS
          .map((e) => TaxSlab.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final newS = m['new_regime_slabs'];
    if (newS is List && newS.isNotEmpty) {
      cfg.newSlabs = newS
          .map((e) => TaxSlab.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return cfg;
  }

  void _applyRegime(Map<String, dynamic>? row) {
    final r = row?['regime_type'];
    if (r is String && r.isNotEmpty) {
      _regime = r;
      _regimeConfirmed = true;
      _savedRegime = r;
    } else {
      _regime = 'new_regime';
      _regimeConfirmed = false;
      _savedRegime = null;
    }
  }

  void _applyDeclarations(List<Map<String, dynamic>> rows) {
    _declarations.clear();
    for (final m in rows) {
      final TaxDeclaration d;
      try {
        d = TaxDeclaration.fromMap(m);
      } catch (_) {
        continue; // a malformed row must not break the screen
      }
      _declarations[d.deductionTypeId] = d;
      final amount = d.declaredAmount > 0
          ? d.declaredAmount.toStringAsFixed(0)
          : '';
      _amountCtrls
              .putIfAbsent(d.deductionTypeId, () => TextEditingController())
              .text =
          amount;
      _notesCtrls
              .putIfAbsent(d.deductionTypeId, () => TextEditingController())
              .text =
          d.employeeNotes ?? '';
    }
  }

  /// Never shows the server's own message (it can carry internal details).
  String _loadError(Object e) {
    if (e is ApiException && (e.code == 'NO_EMPLOYEE' || e.isNotFound)) {
      return 'We could not find your tax information. Please contact HR.';
    }
    if (e is ApiException && e.isForbidden) {
      return 'You do not have permission to view this information.';
    }
    return "Couldn't load your tax information. Pull down to try again.";
  }

  // -------------------------------------------------------------------------
  // Writes: the regime and declaration DRAFTS only. Submitting for review stays unavailable.
  // The server does not enforce the submission window or the deduction maximum; the checks below are the app's own.
  // -------------------------------------------------------------------------
  void _submitUnavailable() => _toast(
    "Submitting declarations for review isn't available yet. Your saved declarations are drafts. Please contact HR.",
    _T.warning,
  );

  static const _saveFailed = "Couldn't save. Please try again.";

  static final _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  /// A declaration can be edited in the app while it is new, a draft or already submitted: the server sends an
  /// approved or rejected one back for review when it is edited, so those stay read-only here.
  bool _editable(TaxDeclaration? d) =>
      d == null || d.status == 'draft' || d.status == 'submitted';

  void _selectRegime(String regime) {
    if (_savingRegime) return;
    if (!_declarationOpen) {
      _toast(
        'The declaration window is closed. Please contact HR.',
        _T.warning,
      );
      return;
    }
    setState(() => _regime = regime);
  }

  Future<void> _saveRegime() async {
    if (_savingRegime) return;
    if (!_declarationOpen) {
      _toast(
        'The declaration window is closed. Please contact HR.',
        _T.warning,
      );
      return;
    }
    if (_savedRegime == _regime) {
      _toast('This regime is already saved.', _T.info);
      return;
    }
    setState(() => _savingRegime = true);
    try {
      await _tax.saveTaxRegime(financialYear: _fy, regimeType: _regime);
    } catch (_) {
      if (mounted) {
        setState(() => _savingRegime = false);
        _toast(_saveFailed, _T.error);
      }
      return;
    }
    // Show what the server now holds, not what was typed.
    try {
      _applyRegime(await _tax.taxRegime(_fy));
    } catch (_) {
      _savedRegime = _regime;
      _regimeConfirmed = true;
    }
    _projection = await _loadProjection();
    if (!mounted) return;
    setState(() => _savingRegime = false);
    _toast('Tax regime saved.', _T.success);
  }

  void _toggleClaimed(TaxDeductionType t, bool value) {
    final d = _declarations[t.id];
    if (!_editable(d) || !_declarationOpen || _savingDrafts) return;
    setState(() {
      _declarations[t.id] =
          (d ??
                  TaxDeclaration(
                    id: null,
                    deductionTypeId: t.id,
                    declaredAmount: 0,
                    isClaimed: value,
                    employeeNotes: null,
                    status: 'draft',
                  ))
              .copyWith(isClaimed: value);
      _dirty.add(t.id);
    });
  }

  void _onAmountEdited(TaxDeductionType t, String text) {
    final d = _declarations[t.id];
    if (d == null || !_editable(d)) return;
    final n = _amountPattern.hasMatch(text.trim())
        ? double.tryParse(text.trim())
        : null;
    setState(() {
      if (n != null) _declarations[t.id] = d.copyWith(declaredAmount: n);
      _dirty.add(t.id);
    });
  }

  /// Why this deduction's current input cannot be saved, or null.
  String? _draftProblem(TaxDeductionType t) {
    final d = _declarations[t.id];
    if (d == null || !d.isClaimed) return null;
    final text = (_amountCtrls[t.id]?.text ?? '').trim();
    if (!_amountPattern.hasMatch(text))
      return 'Enter an amount (up to 2 decimals)';
    final n = double.parse(text);
    if (t.maxAmount > 0 && n > t.maxAmount)
      return 'Exceeds the ${_inr(t.maxAmount)} statutory limit';
    return null;
  }

  Future<void> _saveDrafts() async {
    if (_savingDrafts) return;
    if (!_declarationOpen) {
      _toast(
        'The declaration window is closed. Please contact HR.',
        _T.warning,
      );
      return;
    }
    final pending = [
      for (final t in _types)
        if (_dirty.contains(t.id)) t,
    ];
    if (pending.isEmpty) {
      _toast('There are no changes to save.', _T.info);
      return;
    }
    if (pending.any((t) => _draftProblem(t) != null)) {
      setState(() {});
      _toast('Fix the highlighted amounts first.', _T.warning);
      return;
    }
    // Before anything is sent: payroll counts saved declarations in TDS even when they have not been submitted for review.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save declarations?'),
        content: const Text(
          'Saving these declarations may change the TDS deducted from your salary, even though they have not been '
          'submitted for review. They are saved as drafts only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _savingDrafts) return;
    setState(() => _savingDrafts = true);
    var failed = 0;
    for (final t in pending) {
      final d = _declarations[t.id]!;
      try {
        await _tax.saveTaxDeclarationDraft(
          financialYear: _fy,
          deductionTypeId: t.id,
          isClaimed: d.isClaimed,
          declaredAmount: d.isClaimed
              ? double.parse(_amountCtrls[t.id]!.text.trim())
              : null,
          notes: (_notesCtrls[t.id]?.text ?? '').trim(),
        );
        _dirty.remove(t.id);
      } catch (_) {
        failed++;
      }
    }
    // Show what the server now holds, but only when everything saved: after a failure the typed input is kept.
    if (failed == 0) {
      try {
        _applyDeclarations(await _tax.taxDeclarations(_fy));
      } catch (_) {}
    }
    if (failed == 0) _projection = await _loadProjection();
    if (!mounted) return;
    setState(() => _savingDrafts = false);
    _toast(
      failed == 0
          ? 'Draft saved. It has not been submitted for review.'
          : "Couldn't save $failed of ${pending.length} declarations. Please try again.",
      failed == 0 ? _T.success : _T.error,
    );
  }

  // -------------------------------------------------------------------------
  // Windows (no window == open, same as web)
  // -------------------------------------------------------------------------
  bool get _declarationOpen {
    final w = _window;
    if (w == null || w.declarationStart == null || w.declarationEnd == null) {
      return true;
    }
    final now = DateTime.now();
    return !now.isBefore(w.declarationStart!) &&
        !now.isAfter(w.declarationEnd!.add(const Duration(days: 1)));
  }

  bool get _proofOpen {
    final w = _window;
    if (w == null || w.proofStart == null || w.proofEnd == null) return true;
    final now = DateTime.now();
    return !now.isBefore(w.proofStart!) &&
        !now.isAfter(w.proofEnd!.add(const Duration(days: 1)));
  }

  // -------------------------------------------------------------------------
  // Tax engine — 1:1 port of calculateTDS() in TaxDeduction.tsx
  // -------------------------------------------------------------------------
  List<TaxDeductionType> get _applicableDeductions =>
      _types.where((t) => t.appliesToRegime.contains(_regime)).toList();

  TaxComputation _calculateTDS() {
    final s = _server;
    if (s != null) {
      final deductions = _regime == 'old_regime' ? (s.allowedDeductions ?? 0) : 0.0;
      return TaxComputation(
        grossSalary: s.projectedAnnualIncome ?? 0,
        standardDeduction: s.standardDeduction ?? 0,
        oldRegimeDeductions: deductions,
        totalDeductions: (s.standardDeduction ?? 0) + deductions,
        taxableIncome: s.taxableIncome ?? 0,
        annualTaxLiability: s.annualTax ?? 0,
        monthlyTDS: s.monthlyTds ?? 0,
      );
    }
    // Unavailable salary is 0 only inside this struct; the UI checks _salaryAvailable and never shows
    // the resulting figures as a real tax result.
    final annualSalary = _annualSalary ?? 0;

    final standardDeduction = _regime == 'new_regime'
        ? _config.stdDeductionNew
        : _config.stdDeductionOld;

    double oldRegimeDeductions = 0;
    if (_regime == 'old_regime') {
      for (final d in _declarations.values) {
        if (d.isClaimed && d.declaredAmount > 0) {
          oldRegimeDeductions += d.declaredAmount;
        }
      }
    }

    final totalDeductions = _regime == 'new_regime'
        ? standardDeduction
        : standardDeduction + oldRegimeDeductions;

    final taxableIncome = (annualSalary - totalDeductions) > 0
        ? annualSalary - totalDeductions
        : 0.0;

    double annualTax = 0;

    if (_regime == 'new_regime') {
      double cumulative = 0;
      for (final slab in _config.newSlabs) {
        final slabMin = slab.minIncome;
        final slabMax = slab.maxIncome ?? double.infinity;
        if (taxableIncome > slabMin) {
          final band = slabMax - slabMin + 1;
          final applicable = (taxableIncome - slabMin) < band
              ? (taxableIncome - slabMin)
              : band;
          if (applicable > 0) cumulative += applicable * (slab.rate / 100);
        }
      }
      annualTax = cumulative;
      if (taxableIncome <= _config.rebateLimitNew)
        annualTax = 0; // 87A full rebate
    } else {
      double cumulative = 0;
      for (final slab in _config.oldSlabs) {
        final slabMin = slab.minIncome;
        final slabMax = slab.maxIncome ?? double.infinity;
        if (taxableIncome > slabMin) {
          final band = slabMax - slabMin;
          final applicable = (taxableIncome - slabMin) < band
              ? (taxableIncome - slabMin)
              : band;
          if (applicable > 0) cumulative += applicable * (slab.rate / 100);
        }
      }
      annualTax = cumulative;
      if (taxableIncome <= _config.rebateLimitOld) {
        annualTax = annualTax < 12500 ? annualTax : 12500; // 87A capped
      }
    }

    final withCess = annualTax * (1 + _config.cessRate / 100);

    return TaxComputation(
      grossSalary: annualSalary,
      standardDeduction: standardDeduction,
      oldRegimeDeductions: oldRegimeDeductions,
      totalDeductions: totalDeductions,
      taxableIncome: taxableIncome.toDouble(),
      annualTaxLiability: withCess,
      monthlyTDS: withCess / 12,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      endDrawer: AppDrawer(
        userEmail: _tax.auth.currentUser?.email ?? '',
        userData: _employee ?? {},
        fetchHrmsContext: () async => _employee ?? {},
        currentRoute: DrawerRoute.tax,
        companyLogoUrl: null,
      ),
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Tax Deduction',
          style: TextStyle(
            color: _T.heading,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: _T.heading),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _T.border),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _bootstrap,
          ),

          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      body: _loading
          ? const _LoadingSkeleton()
          : _fatalError != null
          ? _ErrorState(message: _fatalError!, onRetry: _bootstrap)
          : RefreshIndicator(
              color: _T.primary,
              onRefresh: _bootstrap,
              child: _content(),
            ),
    );
  }

  Widget _content() {
    final calc = _calculateTDS();
    final deductions = _applicableDeductions;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _headerCard(calc),
        const SizedBox(height: 16),
        _regimeCard(),
        const SizedBox(height: 16),
        _summaryCard(calc),
        const SizedBox(height: 16),
        if (_projection != null && _projection!.applicable) ...[
          _incomeCountedCard(),
          const SizedBox(height: 16),
          _comparisonCard(),
          const SizedBox(height: 16),
        ],
        if (_regime == 'old_regime') ...[
          _deductionsCard(deductions),
          const SizedBox(height: 16),
        ] else
          _newRegimeNotice(),
        _actionsRow(),
      ],
    );
  }

  Widget _headerCard(TaxComputation calc) {
    final name = (_employee?['full_name'] ?? '') as String;
    final code = (_employee?['employee_id'] ?? '') as String;

    return _Card(
      background: _T.pastelBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'My Tax Declaration' : name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _T.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      code.isEmpty ? 'FY $_fy' : '$code  •  FY $_fy',
                      style: const TextStyle(fontSize: 12, color: _T.subtext),
                    ),
                  ],
                ),
              ),
              _Chip(
                label: _regime == 'new_regime' ? 'New Regime' : 'Old Regime',
                color: _T.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  label: _server != null ? 'Projected Annual Income' : 'Gross Salary (Annual)',
                  value: _salaryAvailable
                      ? _inr(calc.grossSalary)
                      : _notAvailable,
                  hint: !_salaryAvailable ? 'Contact HR' : null,
                ),
              ),
              Container(width: 1, height: 44, color: Colors.white70),
              Expanded(
                child: _Kpi(
                  label: 'Monthly TDS',
                  value: _taxFigure(calc.monthlyTDS),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _regimeCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Select Tax Regime'),
          const SizedBox(height: 4),
          const Text(
            'You can switch regimes any time during the declaration window.',
            style: TextStyle(fontSize: 12, color: _T.subtext),
          ),
          const SizedBox(height: 12),
          _RegimeTile(
            title: 'New Regime',
            subtitle:
                'Lower slab rates • Standard deduction ${_inr(_config.stdDeductionNew)} • No Chapter VI-A deductions',
            selected: _regime == 'new_regime',
            enabled: true,
            onTap: () => _selectRegime('new_regime'),
          ),
          const SizedBox(height: 10),
          _RegimeTile(
            title: 'Old Regime',
            subtitle:
                'Standard deduction ${_inr(_config.stdDeductionOld)} • Claim 80C, 80D, HRA and more',
            selected: _regime == 'old_regime',
            enabled: true,
            onTap: () => _selectRegime('old_regime'),
          ),
          if (!_declarationOpen) ...[
            const SizedBox(height: 12),
            const _Notice(
              icon: Icons.lock_clock_rounded,
              color: _T.warning,
              text: 'The declaration window is closed. Please contact HR.',
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _T.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _savingRegime ? null : _saveRegime,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                _savingRegime
                    ? 'Saving...'
                    : (_regimeConfirmed
                          ? 'Update Confirmed Regime'
                          : 'Confirm Regime'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(TaxComputation c) {
    return _Card(
      background: _T.pastelAqua,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Tax Summary'),
          const SizedBox(height: 12),
          _row(
            _server != null ? 'Projected Annual Income' : 'Gross Salary (Annual)',
            _salaryAvailable ? _inr(c.grossSalary) : _notAvailable,
          ),
          _row('Standard Deduction', '− ${_inr(c.standardDeduction)}'),
          if (_regime == 'old_regime')
            _row('Chapter VI-A Deductions', '− ${_inr(c.oldRegimeDeductions)}'),
          const Divider(height: 20, color: Colors.white),
          _row('Taxable Income', _taxFigure(c.taxableIncome), bold: true),
          _row(
            'Annual Tax (incl. ${_config.cessRate.toStringAsFixed(0)}% cess)',
            _taxFigure(c.annualTaxLiability),
          ),
          const Divider(height: 20, color: Colors.white),
          _row(
            'Monthly TDS',
            _taxFigure(c.monthlyTDS),
            bold: true,
            highlight: true,
          ),
          if (_server != null) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.info_outline_rounded,
              color: _T.info,
              text: _projection!.usedUnverifiedRule
                  ? 'Calculated by the payroll server. The tax rule it used has not been verified yet, so treat these as an estimate.'
                  : 'Calculated by the payroll server from your paid months and the projection for the rest of the year.',
            ),
          ] else if (_projection != null && !_projection!.applicable) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.info_outline_rounded,
              color: _T.info,
              text:
                  'Tax is not calculated for you${(_projection!.reason ?? '').isEmpty ? '' : ': ${_projection!.reason}'}.',
            ),
          ] else if (!_salaryAvailable) ...[
            const SizedBox(height: 10),
            const _Notice(
              icon: Icons.info_outline_rounded,
              color: _T.info,
              text:
                  'Your annual salary is not available right now, so your tax cannot be calculated. Please contact HR.',
            ),
          ],
        ],
      ),
    );
  }

  /// Paid months counted so far and the TDS already deducted, as the server reports them.
  Widget _incomeCountedCard() {
    final p = _projection!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Income counted for FY $_fy'),
          const SizedBox(height: 4),
          const Text(
            'Paid payroll months, plus the projection for the rest of the year in the summary above.',
            style: TextStyle(fontSize: 12, color: _T.subtext),
          ),
          const SizedBox(height: 10),
          if (p.earnedToDate.isEmpty)
            const Text(
              'No paid payroll months yet this year.',
              style: TextStyle(fontSize: 13, color: _T.body),
            )
          else
            for (final m in p.earnedToDate)
              _row('Paid ${m.month}', m.gross == null ? _notAvailable : _inr(m.gross!)),
          if (p.tdsDeductedToDate != null) ...[
            const Divider(height: 20, color: Colors.white),
            _row('TDS already deducted this year', _inr(p.tdsDeductedToDate!)),
          ],
        ],
      ),
    );
  }

  /// Both regimes side by side, as the server computed them, with its recommendation.
  Widget _comparisonCard() {
    final p = _projection!;
    final o = p.oldRegime;
    final n = p.newRegime;
    String fig(double? v) => v == null ? _notAvailable : _inr(v);
    String recommendation() {
      switch (p.recommendedRegime) {
        case 'new':
          return 'Lower estimated tax: New Regime${p.annualSaving == null ? '' : ' (saves ${_inr(p.annualSaving!)} a year)'}';
        case 'old':
          return 'Lower estimated tax: Old Regime${p.annualSaving == null ? '' : ' (saves ${_inr(p.annualSaving!)} a year)'}';
        case 'equal':
          return 'Both regimes give the same estimated tax';
        default:
          return '';
      }
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Compare both regimes'),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: SizedBox()),
              SizedBox(width: 90, child: Text('Old', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
              SizedBox(width: 90, child: Text('New', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            ],
          ),
          for (final r in [
            ('Taxable income', o?.taxableIncome, n?.taxableIncome),
            ('Estimated annual tax', o?.annualTax, n?.annualTax),
            ('Monthly TDS', o?.monthlyTds, n?.monthlyTds),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 12, color: _T.body))),
                  SizedBox(width: 90, child: Text(fig(r.$2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _T.heading))),
                  SizedBox(width: 90, child: Text(fig(r.$3), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _T.heading))),
                ],
              ),
            ),
          if (recommendation().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(recommendation(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _T.primary)),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: bold ? _T.heading : _T.body,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 18 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: highlight ? _T.primary : _T.heading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _newRegimeNotice() {
    return _Card(
      background: _T.pastelLavender,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, color: _T.info, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Under the New Regime, Chapter VI-A deductions (80C, 80D, HRA, etc.) '
              'are not applicable. Switch to the Old Regime to declare deductions.',
              style: TextStyle(fontSize: 13, color: _T.body, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deductionsCard(List<TaxDeductionType> deductions) {
    if (deductions.isEmpty) {
      return _Card(
        child: Column(
          children: const [
            Icon(Icons.receipt_long_outlined, size: 40, color: _T.subtext),
            SizedBox(height: 10),
            Text(
              'No deduction types have been configured by your organisation yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _T.subtext),
            ),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Available Deductions'),
          const SizedBox(height: 4),
          const Text(
            'Tick a deduction and enter the amount you intend to invest/claim this year.',
            style: TextStyle(fontSize: 12, color: _T.subtext),
          ),
          const SizedBox(height: 12),
          ...deductions.map(_deductionTile),
        ],
      ),
    );
  }

  Widget _deductionTile(TaxDeductionType t) {
    final decl = _declarations[t.id];
    final claimed = decl?.isClaimed ?? false;

    final amountCtrl = _amountCtrls.putIfAbsent(
      t.id,
      () => TextEditingController(
        text: (decl != null && decl.declaredAmount > 0)
            ? decl.declaredAmount.toStringAsFixed(0)
            : '',
      ),
    );
    final notesCtrl = _notesCtrls.putIfAbsent(
      t.id,
      () => TextEditingController(text: decl?.employeeNotes ?? ''),
    );

    final overLimit =
        t.maxAmount > 0 && (decl?.declaredAmount ?? 0) > t.maxAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: claimed ? _T.pastelMint.withOpacity(0.55) : _T.surface,
        border: Border.all(
          color: claimed ? _T.success.withOpacity(0.35) : _T.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: claimed,
                activeColor: _T.primary,
                onChanged: _editable(decl) && !_savingDrafts
                    ? (v) => _toggleClaimed(t, v ?? false)
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _T.heading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (t.sectionReference.isNotEmpty)
                            _Chip(label: t.sectionReference, color: _T.info),
                          if (t.maxAmount > 0)
                            Text(
                              'Max ${_inr(t.maxAmount)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _T.subtext,
                              ),
                            ),
                          if (t.requiresProof)
                            const Text(
                              'Proof required',
                              style: TextStyle(fontSize: 11, color: _T.warning),
                            ),
                        ],
                      ),
                      if (t.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          t.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _T.subtext,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (claimed) ...[
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              readOnly: !_editable(decl) || _savingDrafts,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) => _onAmountEdited(t, v),
              decoration: InputDecoration(
                labelText: 'Declared amount',
                prefixText: '₹ ',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                errorText: _dirty.contains(t.id)
                    ? _draftProblem(t)
                    : (overLimit
                          ? 'Exceeds the ${_inr(t.maxAmount)} statutory limit'
                          : null),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.primary, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              readOnly: !_editable(decl) || _savingDrafts,
              onChanged: (_) => _dirty.add(t.id),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _T.primary, width: 1.4),
                ),
              ),
            ),
            if ((decl?.status ?? 'draft') != 'draft') ...[
              const SizedBox(height: 8),
              _Chip(
                label: 'Status: ${decl!.status}',
                color: decl.status == 'approved'
                    ? _T.success
                    : decl.status == 'rejected'
                    ? _T.error
                    : _T.info,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionsRow() {
    if (_regime != 'old_regime') return const SizedBox.shrink();

    return Column(
      children: [
        if (!_proofOpen)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: _Notice(
              icon: Icons.info_outline_rounded,
              color: _T.warning,
              text:
                  'The proof submission window is closed. Declarations can still be reviewed by HR.',
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _T.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _savingDrafts ? null : _saveDrafts,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(
              _savingDrafts ? 'Saving...' : 'Save Draft',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.primary,
              side: const BorderSide(color: _T.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _submitUnavailable,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              'Submit Declarations for Review',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small presentational widgets
// ---------------------------------------------------------------------------
class _Card extends StatelessWidget {
  final Widget child;
  final Color? background;
  const _Card({required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(_T.r),
        border: Border.all(color: _T.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: _T.heading,
    ),
  );
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  const _Kpi({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _T.body)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _T.heading,
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: const TextStyle(fontSize: 10, color: _T.warning),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: _T.body, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _RegimeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _RegimeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _T.pastelBlue.withOpacity(0.6) : _T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _T.primary : _T.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _T.primary : _T.subtext,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _T.heading,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _T.subtext,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(_T.r),
        border: Border.all(color: _T.border),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [block(130), block(220), block(210), block(260)],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _T.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _T.body, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _T.primary),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
