// =============================================================================
// tax_deduction_screen.dart
// HR Footprints HRMS — Employee Tax Deduction (Flutter)
//
// Mirrors the web implementation in src/pages/TaxDeduction.tsx exactly:
//   * Identity resolution ......... rpc: resolve_my_employee_id()
//   * Gross (annual) salary ....... rpc: get_my_effective_annual_salary()
//   * Regime read ................. rpc: get_my_tax_regime(p_financial_year)
//   * Regime write ................ rpc: upsert_my_tax_regime(...)
//   * Declarations read ........... rpc: get_my_tax_declarations(p_financial_year)
//   * Declaration write ........... rpc: upsert_my_tax_declaration(...)
//   * Deduction catalogue ......... table: tax_deduction_types (is_active)
//   * Submission window ........... table: tax_submission_windows
//   * Org tax config (optional) ... table: income_tax_config
//   * Submit ...................... table: tax_declarations (status -> submitted)
//
// All writes go through SECURITY DEFINER RPCs to avoid the RLS statement
// timeouts (57014) that broke the previous version.
// =============================================================================

import 'dart:async';
import '../widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/drawer_route.dart';

final SupabaseClient _sb = Supabase.instance.client;

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

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
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
    appliesToRegime:
    ((m['applies_to_regime'] as List?) ?? const []).map((e) => '$e').toList(),
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
  }) =>
      TaxDeclaration(
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
  const TaxDeductionScreen({super.key});

  @override
  State<TaxDeductionScreen> createState() => _TaxDeductionScreenState();
}

class _TaxDeductionScreenState extends State<TaxDeductionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();
  bool _loading = true;
  bool _saving = false;
  String? _fatalError;

  String _fy = '';
  String? _employeeId;
  Map<String, dynamic>? _employee;
  double _effectiveAnnualSalary = 0;

  String _regime = 'new_regime'; // 'new_regime' | 'old_regime'
  bool _regimeConfirmed = false;

  List<TaxDeductionType> _types = [];
  final Map<String, TaxDeclaration> _declarations = {};
  SubmissionWindow? _window;
  IncomeTaxConfig _config = IncomeTaxConfig.defaults();

  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};
  final Map<String, Timer> _debouncers = {};

  @override
  void initState() {
    super.initState();
    _fy = _currentFinancialYear();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final t in _debouncers.values) {
      t.cancel();
    }
    for (final c in _amountCtrls.values) {
      c.dispose();
    }
    for (final c in _notesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // India FY: 1 Apr – 31 Mar (same helper as web)
  String _currentFinancialYear() {
    final now = DateTime.now();
    return now.month >= 4
        ? '${now.year}-${now.year + 1}'
        : '${now.year - 1}-${now.year}';
  }

  // -------------------------------------------------------------------------
  // Bootstrap
  // -------------------------------------------------------------------------
  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _fatalError = null;
    });

    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _fatalError = 'You are signed out. Please sign in again.';
        });
        return;
      }

      // 1) Resolve own employee record (user_id / email / phone)
      String? empId;
      try {
        final resolved = await _sb.rpc('resolve_my_employee_id');
        if (resolved is String && resolved.isNotEmpty) empId = resolved;
      } catch (_) {
        empId = null;
      }

      // 2) Load the employee row
      Map<String, dynamic>? emp;
      try {
        final q = _sb.from('employee_records').select();
        final rows = empId != null
            ? await q.eq('id', empId).limit(1)
            : await q.eq('email', user.email ?? '').limit(1);
        if ((rows as List).isNotEmpty) {
          emp = Map<String, dynamic>.from(rows.first as Map);
        }
      } catch (_) {
        emp = null;
      }

      if (emp == null) {
        setState(() {
          _loading = false;
          _fatalError = 'We could not find your employee record. Please contact HR.';
        });
        return;
      }

      _employee = emp;
      _employeeId = emp['id'] as String?;

      // 3) Effective annual salary (handles encrypted/zeroed column)
      double annual = 0;
      try {
        final v = await _sb.rpc('get_my_effective_annual_salary');
        annual = _d(v);
      } catch (_) {
        annual = 0;
      }
      if (annual <= 0) annual = _d(emp['salary']);
      _effectiveAnnualSalary = annual;

      // 4) Parallel loads
      await Future.wait([
        _fetchDeductionTypes(),
        _fetchSubmissionWindow(emp['organization_id'] as String?),
        _fetchIncomeTaxConfig(emp['organization_id'] as String?),
      ]);

      // 5) Regime + declarations
      await Future.wait([_fetchRegime(), _fetchDeclarations()]);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fatalError = 'Failed to load tax information. Pull to retry.';
      });
    }
  }

  Future<void> _fetchDeductionTypes() async {
    try {
      final rows = await _sb
          .from('tax_deduction_types')
          .select()
          .eq('is_active', true)
          .order('code');
      _types = (rows as List)
          .map((e) => TaxDeductionType.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      _types = [];
    }
  }

  Future<void> _fetchSubmissionWindow(String? orgId) async {
    if (orgId == null) return;
    try {
      final row = await _sb
          .from('tax_submission_windows')
          .select()
          .eq('organization_id', orgId)
          .eq('financial_year', _fy)
          .maybeSingle();
      if (row != null) {
        _window = SubmissionWindow.fromMap(Map<String, dynamic>.from(row));
      }
    } catch (_) {
      _window = null; // no window == open (same as web)
    }
  }

  Future<void> _fetchIncomeTaxConfig(String? orgId) async {
    if (orgId == null) return;
    try {
      final row = await _sb
          .from('income_tax_config')
          .select()
          .eq('organization_id', orgId)
          .eq('financial_year', _fy)
          .maybeSingle();
      if (row == null) return;

      final m = Map<String, dynamic>.from(row);
      final cfg = IncomeTaxConfig.defaults();
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
      _config = cfg;
    } catch (_) {
      _config = IncomeTaxConfig.defaults();
    }
  }

  Future<void> _fetchRegime() async {
    try {
      final data = await _sb.rpc('get_my_tax_regime', params: {'p_financial_year': _fy});
      final row = data is List ? (data.isNotEmpty ? data.first : null) : data;
      if (row is Map) {
        final r = row['regime_type'];
        if (r is String && r.isNotEmpty) {
          _regime = r;
          _regimeConfirmed = true;
        }
      }
    } catch (_) {
      // keep default new_regime
    }
  }

  Future<void> _fetchDeclarations() async {
    try {
      final data =
      await _sb.rpc('get_my_tax_declarations', params: {'p_financial_year': _fy});
      _declarations.clear();
      if (data is List) {
        for (final e in data) {
          final m = Map<String, dynamic>.from(e as Map);
          final d = TaxDeclaration.fromMap(m);
          _declarations[d.deductionTypeId] = d;
          _amountCtrls
              .putIfAbsent(
              d.deductionTypeId,
                  () => TextEditingController(
                  text: d.declaredAmount > 0
                      ? d.declaredAmount.toStringAsFixed(0)
                      : ''))
              .text = d.declaredAmount > 0 ? d.declaredAmount.toStringAsFixed(0) : '';
          _notesCtrls
              .putIfAbsent(d.deductionTypeId,
                  () => TextEditingController(text: d.employeeNotes ?? ''))
              .text = d.employeeNotes ?? '';
        }
      }
    } catch (_) {
      // leave map as-is
    }
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------
  Future<void> _changeRegime(String next) async {
    if (next == _regime) return;
    final previous = _regime;

    setState(() => _regime = next); // optimistic

    try {
      await _sb.rpc('upsert_my_tax_regime', params: {
        'p_financial_year': _fy,
        'p_regime_type': next,
        'p_annual_tax_liability': null,
        'p_monthly_tds': null,
      });

      _toast(
        'Tax regime set to ${next == 'new_regime' ? 'New Regime' : 'Old Regime'}',
        _T.success,
      );

      if (next == 'new_regime' && _declarations.isNotEmpty) {
        _toast('Switching to New Regime excludes Old Regime deductions from TDS.',
            _T.warning);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _regime = previous);
      _toast(_friendly(e, 'Failed to update tax regime'), _T.error);
    }
  }

  /// Single write path for checkbox / amount / notes — mirrors web
  /// handleDeductionChange(). Nulls mean "leave unchanged".
  Future<void> _changeDeduction(
      String deductionTypeId, {
        bool? isClaimed,
        double? declaredAmount,
        String? notes,
      }) async {
    final previous = _declarations[deductionTypeId];

    final optimistic = (previous ??
        TaxDeclaration(
          id: null,
          deductionTypeId: deductionTypeId,
          declaredAmount: 0,
          isClaimed: false,
          employeeNotes: null,
          status: 'draft',
        ))
        .copyWith(
      isClaimed: isClaimed,
      declaredAmount: declaredAmount,
      employeeNotes: notes,
    );

    setState(() => _declarations[deductionTypeId] = optimistic);

    try {
      final data = await _sb.rpc('upsert_my_tax_declaration', params: {
        'p_financial_year': _fy,
        'p_deduction_type_id': deductionTypeId,
        'p_is_claimed': isClaimed,
        'p_declared_amount': declaredAmount,
        'p_employee_notes': notes,
      });

      final row = data is List ? (data.isNotEmpty ? data.first : null) : data;
      if (row is Map && mounted) {
        setState(() {
          _declarations[deductionTypeId] =
              TaxDeclaration.fromMap(Map<String, dynamic>.from(row));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous != null) {
          _declarations[deductionTypeId] = previous;
        } else {
          _declarations.remove(deductionTypeId);
        }
      });
      _toast(_friendly(e, 'Failed to update deduction'), _T.error);
    }
  }

  Future<void> _confirmRegime() async {
    setState(() => _saving = true);
    try {
      final calc = _calculateTDS();
      await _sb.rpc('upsert_my_tax_regime', params: {
        'p_financial_year': _fy,
        'p_regime_type': _regime,
        'p_annual_tax_liability': calc.annualTaxLiability.round(),
        'p_monthly_tds': calc.monthlyTDS.round(),
      });
      await _fetchRegime();
      if (!mounted) return;
      setState(() => _regimeConfirmed = true);
      _toast('${_regime == 'new_regime' ? 'New' : 'Old'} Regime confirmed for FY $_fy',
          _T.success);
    } catch (e) {
      _toast(_friendly(e, 'Failed to confirm regime'), _T.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitDeclarations() async {
    setState(() => _saving = true);
    try {
      final claimed =
      _declarations.values.where((d) => d.isClaimed && d.id != null).toList();
      for (final d in claimed) {
        await _sb
            .from('tax_declarations')
            .update({'status': 'submitted'}).eq('id', d.id as String);
      }
      await _fetchDeclarations();
      if (!mounted) return;
      setState(() {});
      _toast('Declarations submitted for HR review.', _T.success);
    } catch (e) {
      _toast(_friendly(e, 'Failed to submit declarations'), _T.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final annualSalary =
    _effectiveAnnualSalary > 0 ? _effectiveAnnualSalary : _d(_employee?['salary']);

    final standardDeduction =
    _regime == 'new_regime' ? _config.stdDeductionNew : _config.stdDeductionOld;

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

    final taxableIncome =
    (annualSalary - totalDeductions) > 0 ? annualSalary - totalDeductions : 0.0;

    double annualTax = 0;

    if (_regime == 'new_regime') {
      double cumulative = 0;
      for (final slab in _config.newSlabs) {
        final slabMin = slab.minIncome;
        final slabMax = slab.maxIncome ?? double.infinity;
        if (taxableIncome > slabMin) {
          final band = slabMax - slabMin + 1;
          final applicable =
          (taxableIncome - slabMin) < band ? (taxableIncome - slabMin) : band;
          if (applicable > 0) cumulative += applicable * (slab.rate / 100);
        }
      }
      annualTax = cumulative;
      if (taxableIncome <= _config.rebateLimitNew) annualTax = 0; // 87A full rebate
    } else {
      double cumulative = 0;
      for (final slab in _config.oldSlabs) {
        final slabMin = slab.minIncome;
        final slabMax = slab.maxIncome ?? double.infinity;
        if (taxableIncome > slabMin) {
          final band = slabMax - slabMin;
          final applicable =
          (taxableIncome - slabMin) < band ? (taxableIncome - slabMin) : band;
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
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  String _friendly(Object e, String fallback) {
    if (e is PostgrestException) {
      if (e.code == '57014') {
        return 'The server took too long to respond. Please try again.';
      }
      if (e.code == '42501' || (e.message).toLowerCase().contains('row-level')) {
        return 'You do not have permission to perform this action.';
      }
      return e.message.isNotEmpty ? e.message : fallback;
    }
    return fallback;
  }

  void _debounce(String key, VoidCallback fn) {
    _debouncers[key]?.cancel();
    _debouncers[key] = Timer(const Duration(milliseconds: 600), fn);
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      endDrawer: AppDrawer(
        userEmail: _sb.auth.currentUser?.email ?? '',
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
              color: _T.heading, fontWeight: FontWeight.w700, fontSize: 20),
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
                          color: _T.heading),
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
                  label: 'Gross Salary (Annual)',
                  value: _inr(calc.grossSalary),
                  hint: calc.grossSalary <= 0 ? 'Not configured — contact HR' : null,
                ),
              ),
              Container(width: 1, height: 44, color: Colors.white70),
              Expanded(
                child: _Kpi(label: 'Monthly TDS', value: _inr(calc.monthlyTDS)),
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
            enabled: _declarationOpen,
            onTap: () => _changeRegime('new_regime'),
          ),
          const SizedBox(height: 10),
          _RegimeTile(
            title: 'Old Regime',
            subtitle:
            'Standard deduction ${_inr(_config.stdDeductionOld)} • Claim 80C, 80D, HRA and more',
            selected: _regime == 'old_regime',
            enabled: _declarationOpen,
            onTap: () => _changeRegime('old_regime'),
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
                shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: (_saving || !_declarationOpen) ? null : _confirmRegime,
              icon: _saving
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                _regimeConfirmed ? 'Update Confirmed Regime' : 'Confirm Regime',
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
          _row('Gross Salary (Annual)', _inr(c.grossSalary)),
          _row('Standard Deduction', '− ${_inr(c.standardDeduction)}'),
          if (_regime == 'old_regime')
            _row('Chapter VI-A Deductions', '− ${_inr(c.oldRegimeDeductions)}'),
          const Divider(height: 20, color: Colors.white),
          _row('Taxable Income', _inr(c.taxableIncome), bold: true),
          _row('Annual Tax (incl. ${_config.cessRate.toStringAsFixed(0)}% cess)',
              _inr(c.annualTaxLiability)),
          const Divider(height: 20, color: Colors.white),
          _row('Monthly TDS', _inr(c.monthlyTDS), bold: true, highlight: true),
          if (c.grossSalary <= 0) ...[
            const SizedBox(height: 10),
            const _Notice(
              icon: Icons.info_outline_rounded,
              color: _T.info,
              text:
              'Your annual salary is not available yet. Tax figures will populate once HR configures your salary structure.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, bool highlight = false}) {
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
    final locked = !_declarationOpen;

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

    final overLimit = t.maxAmount > 0 && (decl?.declaredAmount ?? 0) > t.maxAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: claimed ? _T.pastelMint.withOpacity(0.55) : _T.surface,
        border:
        Border.all(color: claimed ? _T.success.withOpacity(0.35) : _T.border),
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
                onChanged: locked
                    ? null
                    : (v) => _changeDeduction(t.id, isClaimed: v ?? false),
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
                            color: _T.heading),
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
                            Text('Max ${_inr(t.maxAmount)}',
                                style: const TextStyle(
                                    fontSize: 11, color: _T.subtext)),
                          if (t.requiresProof)
                            const Text('Proof required',
                                style:
                                TextStyle(fontSize: 11, color: _T.warning)),
                        ],
                      ),
                      if (t.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          t.description,
                          style: const TextStyle(
                              fontSize: 12, color: _T.subtext, height: 1.35),
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
              enabled: !locked,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Declared amount',
                prefixText: '₹ ',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                errorText: overLimit
                    ? 'Exceeds the ${_inr(t.maxAmount)} statutory limit'
                    : null,
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
              onChanged: (v) {
                final amt = double.tryParse(v) ?? 0;
                setState(() {
                  final cur = _declarations[t.id];
                  if (cur != null) {
                    _declarations[t.id] = cur.copyWith(declaredAmount: amt);
                  }
                });
                _debounce('amt_${t.id}',
                        () => _changeDeduction(t.id, declaredAmount: amt));
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              enabled: !locked,
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
              onChanged: (v) =>
                  _debounce('note_${t.id}', () => _changeDeduction(t.id, notes: v)),
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
    final hasClaims = _declarations.values.any((d) => d.isClaimed);
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
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.primary,
              side: const BorderSide(color: _T.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: (_saving || !hasClaims || !_declarationOpen)
                ? null
                : _submitDeclarations,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Submit Declarations for Review',
                style: TextStyle(fontWeight: FontWeight.w600)),
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
        fontSize: 16, fontWeight: FontWeight.w700, color: _T.heading),
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
              fontSize: 22, fontWeight: FontWeight.w700, color: _T.heading),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!,
                style: const TextStyle(fontSize: 10, color: _T.warning)),
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
      style:
      TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
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
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, color: _T.body, height: 1.35)),
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
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _T.heading)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: _T.subtext, height: 1.35)),
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
