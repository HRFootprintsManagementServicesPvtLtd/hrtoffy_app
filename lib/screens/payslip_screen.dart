import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:universal_html/html.dart' as html; // web fallback
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'dart:convert';


class PayslipScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const PayslipScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  final supabase = Supabase.instance.client;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 3; // Payslip tab index

  bool isLoading = true;
  bool isError = false;
  String? errorMsg;
  String? infoMsg;
  String? payrollCycleId;
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  Map<String, dynamic>? employee;
  Map<String, dynamic>? organization;
  Map<String, dynamic>? payslip; // stored or computed map for the selected period
  List<Map<String, dynamic>> salaryConfig = [];
  List<Map<String, dynamic>> professionalTaxSlabs = [];
  Map<String, dynamic>? eligibilityRow;
  Map<String, dynamic>? taxSelection;
  double monthlySalary = 0.0;
  bool isFuturePeriod = false;
  bool isAccessGranted = false;
  // PDF cache (fonts/logo)
  pw.Font? _pdfReg;
  pw.Font? _pdfBold;
  Uint8List? _cachedLogoBytes;
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  // -------------------------
  // Initialization
  // -------------------------
  Future<void> _initialize() async {
    setState(() {
      isLoading = true;
      isError = false;
      errorMsg = null;
      infoMsg = null;
    });

    try {
      await _loadEmployee();
      await _loadOrganization();
      await _fetchGlobals();
      await _fetchLatestReleasedPeriod();
      await _processPeriodChange(selectedMonth, selectedYear);

      // load default PDF fonts (built-in Helvetica). These always exist.
      final regularFontData =
      await rootBundle.load('fonts/Roboto-Regular.ttf');
      final boldFontData =
      await rootBundle.load('fonts/Roboto-Bold.ttf');

      _pdfReg = pw.Font.ttf(regularFontData);
      _pdfBold = pw.Font.ttf(boldFontData);


      // preload logo bytes
      final logoUrl = await _resolveLogoPublicUrl();
      _cachedLogoBytes = await _getLogoBytes(logoUrl);
    } catch (e, st) {
      debugPrint('init error: $e\n$st');
      setState(() {
        isError = true;
        errorMsg = e.toString();
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadEmployee() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    final userData = await supabase
        .from('employee_records')
        .select()
        .eq('user_id', user.id)   // ✅ CHANGE HERE
        .limit(1)
        .maybeSingle();

    if (userData == null) {
      throw Exception('Employee not found');
    }

    employee = Map<String, dynamic>.from(userData);

    /// decrypt employee sensitive fields
    final session = supabase.auth.currentSession;

    if (session == null || session.accessToken == null) {
      throw Exception("User not logged in. Please login again.");
    }

    final decrypted = await supabase.functions.invoke(
      'salary-encryption',
      body: {
        'action': 'decrypt',
        'table': 'employee_records',
        'record_id': employee!['id'],
      },
      headers: {
        'Authorization': 'Bearer ${session.accessToken}', // ✅ ADD THIS
      },
    );

    final body = decrypted.data is String
        ? jsonDecode(decrypted.data)
        : decrypted.data;

    final decryptedBody = Map<String, dynamic>.from(body ?? {});

    if (decryptedBody['success'] == true) {
      final decryptedData =
      Map<String, dynamic>.from(decryptedBody['data'] ?? {});
      employee = {...employee!, ...decryptedData};
    }


    final rawAnnual =
        (employee?['salary'] ?? employee?['annual_salary'])?.toString() ?? '0';

    monthlySalary = (double.tryParse(rawAnnual) ?? 0) / 12;
  }

  Future<void> _loadPayrollCycle(int month, int year) async {
    if (employee == null) return;

    final cycle = await supabase
        .from('payroll_cycles')
        .select('id,status')
        .eq('organization_id', employee!['organization_id'])
        .eq('month', month)
        .eq('year', year)
        .limit(1)
        .maybeSingle();

    payrollCycleId = cycle?['id'];
  }


  Future<void> _loadOrganization() async {
    if (employee == null) return;
    final orgData = await supabase
        .from('organizations')
        .select()
        .eq('id', employee!['organization_id'])
        .limit(1)
        .maybeSingle();
    if (orgData != null) {
      organization = Map<String, dynamic>.from(orgData as Map);
    }
  }
  Future<void> _fetchGlobals() async {
    if (organization == null) return;
    final cfg = await supabase
        .from('salary_configurations')
        .select()
        .eq('organization_id', organization!['id'])
        .eq('enabled', true);
    salaryConfig =
    cfg != null ? List<Map<String, dynamic>>.from(cfg as List) : [];

    final pTax = await supabase
        .from('professional_tax_slabs')
        .select()
        .eq('organization_id', organization!['id']);
    professionalTaxSlabs =
    pTax != null ? List<Map<String, dynamic>>.from(pTax as List) : [];
    professionalTaxSlabs.sort((a, b) =>
        ((a['min_amount'] ?? 0) as num).compareTo((b['min_amount'] ?? 0) as num));
  }
  Future<void> _fetchLatestReleasedPeriod() async {
    if (employee == null) return;

    final latest = await supabase
        .from('payroll_cycles')
        .select()
        .eq('organization_id', employee!['organization_id'])
        .eq('status', 'released')
        .order('year', ascending: false)
        .order('month', ascending: false)
        .limit(1)
        .maybeSingle();

    if (latest != null) {
      selectedMonth = latest['month'];
      selectedYear = latest['year'];
    }
  }

  Future<void> _loadTaxSelectionForFY(int month, int year) async {
    if (employee == null) return;
    final fy = _inferFinancialYear(year, month);
    final res = await supabase
        .from('tax_regime_selections')
        .select()
        .eq('employee_id', employee!['id'])
        .eq('financial_year', fy)
        .limit(1)
        .maybeSingle();
    if (res != null) taxSelection = Map<String, dynamic>.from(res as Map);
  }
  // -------------------------
  // Period change handling
  // -------------------------
  Future<void> _processPeriodChange(int month, int year) async {
    setState(() {
      isLoading = true;
      isError = false;
      errorMsg = null;
      infoMsg = null;
      payslip = null;
      isFuturePeriod = false;
      isAccessGranted = false;
    });
    final now = DateTime.now();
    final selectedDate = DateTime(year, month);
    final currentMonthDate = DateTime(now.year, now.month);
    if (selectedDate.isAfter(currentMonthDate)) {
      setState(() {
        isFuturePeriod = true;
        infoMsg = 'Payslip not processed for this month and year.';
        isLoading = false;
      });
      return;
    }
    final access = await _checkEmployeePayslipAccess(month, year);
    await _loadPayrollCycle(month, year);
    setState(() => isAccessGranted = access);
    if (!access) {
      setState(() {
        infoMsg = 'Payslip not released for this month and year.';
        isLoading = false;
      });
      return;
    }

    await _loadPayrollCycle(month, year);

    if (payrollCycleId == null) {
      setState(() {
        infoMsg = 'Payroll cycle not found for this period.';
        isLoading = false;
      });
      return;
    }

    final stored = await _fetchStoredPayslip(month, year);

    if (stored == null) {
      setState(() {
        infoMsg = 'Payslip not generated yet.';
        isLoading = false;
      });
      return;
    }

    /// decrypt payslip
    final session = supabase.auth.currentSession;



// ✅ ADD THESE TWO LINES HERE
    print("USER => ${supabase.auth.currentUser}");
    print("TOKEN => ${supabase.auth.currentSession?.accessToken}");

    if (session == null || session.accessToken == null) {
      throw Exception("User not logged in. Please login again.");
    }

    if (session == null || session.accessToken == null) {
      throw Exception("Session expired. Please login again.");
    }

    final decryptedRes = await supabase.functions.invoke(
      'salary-encryption',
      body: {
        'action': 'decrypt',
        'table': 'payslips',
        'record_id': stored['id'],
        'organization_id': employee!['organization_id'],
      },
      headers: {
        'Authorization': 'Bearer ${session!.accessToken}',
      },
    );

    final body = decryptedRes.data is String
        ? jsonDecode(decryptedRes.data)
        : decryptedRes.data;

    final decryptedBody = Map<String, dynamic>.from(body ?? {});

    if (decryptedBody['success'] != true) {
      throw Exception("Payslip decryption failed");
    }

    final payslipData =
    Map<String, dynamic>.from(decryptedBody['data'] ?? {});
    final attendance = await _computeAttendance(month, year);

    /// decrypt line items
    final lineItems = stored['payslip_line_items'] ?? [];

    if (lineItems.isNotEmpty) {

      final ids = lineItems.map((e) => e['id']).toList();

      final session = supabase.auth.currentSession;

      if (session == null || session.accessToken == null) {
        throw Exception("Session expired. Please login again.");
      }

      final batch = await supabase.functions.invoke(
        'salary-encryption',
        body: {
          'action': 'decrypt-batch',
          'table': 'payslip_line_items',
          'record_ids': ids,
          'organization_id': employee!['organization_id'],
        },
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      final batchBodyRaw = batch.data is String
          ? jsonDecode(batch.data)
          : batch.data;

      final batchBody = Map<String, dynamic>.from(batchBodyRaw ?? {});

      if (batchBody['success'] == true) {

        final body = batch.data is String
            ? jsonDecode(batch.data)
            : batch.data;

        final batchBody = Map<String, dynamic>.from(body ?? {});

        final decryptedItemsMap =
        Map<String, dynamic>.from(batchBody['data'] ?? {});

        final decryptedItems = ids
            .map((id) => decryptedItemsMap[id.toString()])
            .whereType<Map<String, dynamic>>()
            .toList();

        payslipData['payslip_line_items'] = decryptedItems;
        print("LINE ITEMS => ${payslipData['payslip_line_items']}"); // ✅ ADD HERE
      }
    }

    final enrichedPayslip = {
      ...payslipData,
      ...attendance,
    };


    setState(() {
      payslip = enrichedPayslip;
      isLoading = false;
    });


  }
  Future<bool> _checkEmployeePayslipAccess(int month, int year) async {
    if (employee == null) return false;

    // 1️⃣ Check payroll cycle status
    final cycle = await supabase
        .from('payroll_cycles')
        .select('status')
        .eq('organization_id', employee!['organization_id'])
        .eq('month', month)
        .eq('year', year)
        .limit(1)
        .maybeSingle();

    if (cycle != null &&
        (cycle['status'] == 'released' ||
            cycle['status'] == 'finalized')) {
      return true;
    }

    // 2️⃣ Check individual override access
    final override = await supabase
        .from('employee_payroll_access')
        .select('payslip_access_granted')
        .eq('employee_id', employee!['id'])
        .eq('month', month)
        .eq('year', year)
        .limit(1)
        .maybeSingle();

    return override?['payslip_access_granted'] == true;
  }

  Future<Map<String, dynamic>?> _fetchStoredPayslip(int month, int year) async {
    if (employee == null) return null;

    final res = await supabase
        .from('payslips')
        .select('*')
        .eq('employee_id', employee!['id'])
        .eq('month', month)
        .eq('year', year)
        .limit(1)
        .maybeSingle();

    if (res == null) return null;

    final lineItems = await supabase
        .from('payslip_line_items')
        .select()
        .eq('payslip_id', res['id']);

    res['payslip_line_items'] = lineItems;

    return Map<String, dynamic>.from(res);
  }


  // -------------------------
  // Robust upsert for payslips with RLS awareness
  // -------------------------
  Future<void> _savePayslipToDbRobust(Map<String, dynamic> computed) async {
    if (computed.isEmpty) return;
    var payload = Map<String, dynamic>.from(computed);
    // Remove nested objects and empty lists
    payload.removeWhere((k, v) => v is Map || (v is List && v.isEmpty));
    try {
      await supabase
          .from('payslips')
          .upsert([payload], onConflict: 'employee_id,organization_id,month,year');
      return;
    } catch (e) {
      final errStr = e.toString();
      debugPrint('Save payslip initial error: $errStr');
      // If blocked by RLS/permission, silently return (we still allow viewing & downloads)
      if (errStr.toLowerCase().contains('row-level security') ||
          errStr.contains('42501') ||
          errStr.toLowerCase().contains('forbidden')) {
        debugPrint('Upsert blocked by RLS or permission: $errStr');
        return;
      }
    }
    final unsupportedKeys = <String>{};
    for (int attempt = 0; attempt < 8; attempt++) {
      try {
        await supabase
            .from('payslips')
            .upsert([payload], onConflict: 'employee_id,organization_id,month,year');
        return;
      } catch (err) {
        final errStr = err.toString();
        debugPrint('Upsert retry error: $errStr');
        final m =
        RegExp(r"Could not find the '([^']+)' column").firstMatch(errStr);
        if (m != null) {
          final col = m.group(1);
          if (col != null && payload.containsKey(col)) {
            unsupportedKeys.add(col);
            payload.remove(col);
            debugPrint(
                'Removed unsupported payslip column: $col and retrying upsert');
            continue;
          }
        }
        final m2 =
        RegExp(r"the '([^']+)' column of 'payslips'").firstMatch(errStr);
        if (m2 != null) {
          final col = m2.group(1);
          if (col != null && payload.containsKey(col)) {
            unsupportedKeys.add(col);
            payload.remove(col);
            debugPrint(
                'Removed unsupported payslip column: $col and retrying upsert');
            continue;
          }
        }
        if (errStr.toLowerCase().contains('row-level security') ||
            errStr.contains('42501') ||
            errStr.toLowerCase().contains('forbidden')) {
          debugPrint('Upsert blocked by RLS or permission: $errStr');
          break;
        }
        debugPrint('Unrecoverable upsert error: $errStr');
        break;
      }
    }
    if (unsupportedKeys.isNotEmpty) {
      debugPrint('Final upsert attempted without keys: $unsupportedKeys');
    }
  }
  // -------------------------
  // Resolve logo URL and fetch bytes (cached)
  // -------------------------
  Future<String> _resolveLogoPublicUrl() async {
    final raw = organization?['logo_url']?.toString();
    if (raw == null || raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    try {
      final pub = supabase.storage.from('company-logos').getPublicUrl(raw);
      if (pub != null && pub.startsWith('http')) return pub;
    } catch (e) {
      debugPrint('getPublicUrl error: $e');
    }
    return raw;
  }
  Future<Uint8List?> _getLogoBytes(String? url) async {
    try {
      if (url == null || url.isEmpty) return null;
      if (!url.startsWith('http')) {
        url = await _resolveLogoPublicUrl();
      }
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (e) {
      debugPrint('logo fetch error: $e');
    }
    return null;
  }
  // -------------------------
  // Helpers
  // -------------------------
  String _inferFinancialYear(int year, int month) {
    if (month < 4) return '${year - 1}-$year';
    return '$year-${year + 1}';
  }
  double _computeProfessionalTax(double monthlySalary) {
    if (professionalTaxSlabs.isEmpty) return 0.0;
    for (final slab in professionalTaxSlabs) {
      final minA = ((slab['min_amount'] ?? 0) as num).toDouble();
      final maxA = (slab['max_amount'] == null)
          ? double.infinity
          : ((slab['max_amount'] ?? double.infinity) as num).toDouble();
      final amt = ((slab['amount'] ?? 0) as num).toDouble();
      if (monthlySalary >= minA && monthlySalary <= maxA) {
        return amt.roundToDouble();
      }
    }
    return 0.0;
  }
  String _formatCurrencyDouble(double v) {
    try {
      final nf = NumberFormat.currency(
        locale: 'en_IN',
        symbol: ' ',
        decimalDigits: 2,
      );
      return nf.format(v);
    } catch (_) {
      return v.toStringAsFixed(2);
    }
  }
  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }
  // -------------------------
  // Attendance calculation
  // -------------------------
  Future<Map<String, int>> _computeAttendance(
      int month,
      int year,
      ) async {
    if (employee == null) return {};

    /// 1️⃣ Total Monthly Days
    final int totalDays = DateUtils.getDaysInMonth(year, month);

    /// 2️⃣ Weekly Offs
    int weeklyOffs = 0;
    final workingDaysPerWeek =
        organization?['working_days_per_week'] ?? 5;

    final weeklyOffDays = workingDaysPerWeek == 6
        ? [DateTime.sunday]
        : [DateTime.saturday, DateTime.sunday];

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(year, month, day);
      if (weeklyOffDays.contains(date.weekday)) {
        weeklyOffs++;
      }
    }

    /// 3️⃣ Holidays
    final holidays = await supabase
        .from('holidays')
        .select('date')
        .eq('organization_id', employee!['organization_id'])
        .gte('date', '$year-${month.toString().padLeft(2, '0')}-01')
        .lte(
      'date',
      '$year-${month.toString().padLeft(2, '0')}-${totalDays.toString().padLeft(2, '0')}',
    );

    final int holidayCount = holidays?.length ?? 0;

    /// 4️⃣ Leaves (Paid vs LOP)
    double paidLeaveDays = 0;
    double lopDays = 0;

    final leaves = await supabase
        .from('leave_applications')
        .select(
      'from_date,to_date,leave_type,status,leave_duration_type,half_day_session',
    )
        .eq('employee_id', employee!['id'])
        .inFilter('status', ['approved', 'manager_approved']);

    for (final leave in leaves ?? []) {
      final leaveName =
      (leave['leave_type'] ?? '').toString().toLowerCase();

      final bool isLop = leaveName.contains('lop') ||
          leaveName.contains('loss of pay') ||
          leaveName.contains('unpaid');

      final from = DateTime.parse(leave['from_date']);
      final to = DateTime.parse(leave['to_date']);
      final durationType =
      (leave['leave_duration_type'] ?? 'full_day')
          .toString()
          .toLowerCase();

      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
        if (d.month == month && d.year == year) {
          final dayValue = durationType == 'half_day' ? 0.5 : 1.0;

          if (isLop) {
            lopDays += dayValue;
          } else {
            paidLeaveDays += dayValue;
          }
        }
      }
    }

    /// 5️⃣ Weekly Offs + Paid Leaves + Holidays
    final double weeklyOffsLeavesHolidays =
        weeklyOffs + paidLeaveDays + holidayCount;

    /// 6️⃣ Total Working Days
    final double totalWorkingDays =
        totalDays - weeklyOffsLeavesHolidays - lopDays;

    /// 7️⃣ Pay Days
    /// Pay Days = Calendar Days - LOP Days
    final double payDays = totalDays - lopDays;

    return {
      'total_monthly_days': totalDays,
      'effective_work_days': totalWorkingDays.round(),
      'weekly_offs_leaves_holidays': weeklyOffsLeavesHolidays.round(),
      'lop_absent': lopDays.round(),
      'pay_days': payDays.round(),
    };
  }



  // -------------------------
  // Compute single payslip
  // -------------------------

  static bool eligibility_row_bool(Map<String, dynamic>? row) {
    if (row == null) return false;
    return (row['is_pf_eligible'] == true ||
        row['is_pf_eligible']?.toString() == 'true');
  }
  static bool eligibility_row_bool_esi(Map<String, dynamic>? row) {
    if (row == null) return false;
    return (row['is_esi_eligible'] == true ||
        row['is_esi_eligible']?.toString() == 'true');
  }
  // PDF generation helpers (single MultiPage for bulk & single)
  pw.Widget _smallStatBoxPw(
      String title, String value, pw.Font f, pw.Font bf) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: f,
                fontSize: 8,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: bf,
                fontSize: 13,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  Future<Uint8List> _generateMultiPayslipPdfBytes(
      List<Map<String, dynamic>> pagesData,
      {Uint8List? logoBytes}) async {
    final doc = pw.Document();
    final nf =
    NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9', decimalDigits: 2);
    final pf = _pdfReg ?? pw.Font.helvetica();
    final pb = _pdfBold ?? pw.Font.helveticaBold();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin:
        const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        theme: pw.ThemeData(
          defaultTextStyle: pw.TextStyle(font: pf),
        ),
        build: (context) {
          final List<pw.Widget> widgets = <pw.Widget>[];
          for (final p in pagesData) {
            final Map<String, double> earnings = {};
            final Map<String, double> deductions = {};

            void addIfPresent(
                Map<String, double> target, String label, dynamic value) {
              final v = double.tryParse((value ?? '0').toString()) ?? 0.0;
              if (v != 0.0) target[label] = v;
            }
            addIfPresent(earnings, 'Basic Pay', p['basic_pay']);
            addIfPresent(earnings, 'HRA', p['hra']);
            addIfPresent(earnings, 'Special Allowance', p['special_allowance']);
            addIfPresent(
                earnings, 'Dearness Allowance', p['dearness_allowance']);
            addIfPresent(
                earnings, 'Conveyance Allowance', p['conveyance_allowance']);
            addIfPresent(
                earnings, 'Medical Allowance', p['medical_allowance']);
            addIfPresent(earnings, 'Other Allowances', p['other_allowances']);
            addIfPresent(earnings, 'Overtime Pay', p['overtime_pay']);
            addIfPresent(deductions, 'Employee PF', p['pf_employee']);
            addIfPresent(deductions, 'Employee ESI', p['employee_esi']);
            addIfPresent(deductions, 'Professional Tax', p['professional_tax']);
            addIfPresent(deductions, 'TDS/Income Tax', p['tds_income_tax']);
            addIfPresent(deductions, 'Health & Education Cess',
                p['health_education_cess']);
            addIfPresent(deductions, 'Excess Leave Deduction',
                p['excess_leave_deduction']);
            addIfPresent(deductions, 'Loan Deduction', p['loan_deduction']);
            addIfPresent(deductions, 'Other Deductions', p['other_deductions']);
            final gross = double.tryParse(
                (p['gross_salary'] ?? p['total_earnings'] ?? '0')
                    .toString()) ??
                0.0;
            final totalDeductions =
                double.tryParse((p['total_deductions'] ?? '0').toString()) ??
                    0.0;
            final net = double.tryParse(
                (p['net_pay'] ?? (gross - totalDeductions)).toString()) ??
                0.0;
            widgets.addAll([
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      if (logoBytes != null)
                        pw.Container(
                          width: 60,
                          height: 60,
                          child: pw.Image(
                            pw.MemoryImage(logoBytes),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      pw.SizedBox(width: 12),

                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            organization?['name'] ?? '',
                            style: pw.TextStyle(
                              font: pb,
                              fontSize: 16,
                            ),
                          ),

                          pw.SizedBox(height: 4),

                          pw.Text(
                            organization?['location'] ?? '',
                            style: pw.TextStyle(
                              font: pf,
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),

                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Payslip",
                        style: pw.TextStyle(
                          font: pb,
                          fontSize: 16,
                        ),
                      ),

                      pw.SizedBox(height: 4),

                      pw.Text(
                        DateFormat('MMMM yyyy').format(
                          DateTime(p['year'] ?? selectedYear, p['month'] ?? selectedMonth),
                        ),
                        style: pw.TextStyle(
                          font: pf,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'EMPLOYEE INFORMATION',
                                style:
                                pw.TextStyle(font: pb, fontSize: 10),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Text(
                                'Name: ${p['employee_name'] ?? ''}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                              pw.Text(
                                'Dept: ${p['department'] ?? ''}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                              pw.Text(
                                'PAN: ${p['pan_number'] ?? '--'}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Employee Code: ${p['employee_code'] ?? ''}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                              pw.Text(
                                'Designation: ${p['designation'] ?? ''}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                              pw.Text(
                                'UAN: ${p['pf_uan'] ?? '--'}',
                                style:
                                pw.TextStyle(font: pf, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Attendance Summary',
                      style: pw.TextStyle(font: pb, fontSize: 11),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      children: [
                        _smallStatBoxPw(
                            'TOTAL DAYS IN MONTH',
                            (p['total_monthly_days'] ?? '--')
                                .toString(),
                            pf,
                            pb),
                        pw.SizedBox(width: 8),
                        _smallStatBoxPw(
                            'TOTAL WORKING DAYS',
                            (p['effective_work_days'] ?? '--')
                                .toString(),
                            pf,
                            pb),
                        pw.SizedBox(width: 8),
                        _smallStatBoxPw(
                            'WEEKLY OFFS, LEAVES & HOLIDAYS',
                            (p['weekly_offs_leaves_holidays'] ?? '--')
                                .toString(),
                            pf,
                            pb),
                        pw.SizedBox(width: 8),
                        _smallStatBoxPw(
                          'LOP/ABSENT',
                          (p['lop_absent'] ?? '0').toString(),
                          pf,
                          pb,
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                  color: PdfColors.grey200),
                              borderRadius:
                              pw.BorderRadius.circular(6),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'PAY DAYS',
                                  style: pw.TextStyle(
                                    font: pf,
                                    fontSize: 10,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                  (p['pay_days'] ??
                                      p['total_monthly_days'] ??
                                      '--')
                                      .toString(),
                                  style: pw.TextStyle(
                                      font: pb, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey200),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(
                                  color: PdfColors.green,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: pw.Text(
                              'Earnings',
                              style: pw.TextStyle(
                                font: pb,
                                fontSize: 12,
                                color: PdfColors.green800,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Table(
                            columnWidths: {
                              0: pw.FlexColumnWidth(3),
                              1: pw.FlexColumnWidth(1),
                            },
                            children: [
                              for (final e in earnings.entries)
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets
                                          .symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: pw.Text(
                                        e.key,
                                        style: pw.TextStyle(
                                          font: pf,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets
                                          .symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: pw.Text(
                                        nf.format(e.value),
                                        style: pw.TextStyle(
                                          font: pf,
                                          fontSize: 10,
                                        ),
                                        textAlign:
                                        pw.TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets
                                        .symmetric(
                                        vertical: 6, horizontal: 4),
                                    child: pw.Text(
                                      'TOTAL EARNINGS',
                                      style: pw.TextStyle(
                                        font: pb,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets
                                        .symmetric(
                                        vertical: 6, horizontal: 4),
                                    child: pw.Text(
                                      nf.format(gross),
                                      style: pw.TextStyle(
                                        font: pb,
                                        fontSize: 10,
                                      ),
                                      textAlign:
                                      pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey200),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(
                                  color: PdfColors.red,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: pw.Text(
                              'Deductions',
                              style: pw.TextStyle(
                                font: pb,
                                fontSize: 12,
                                color: PdfColors.red800,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Table(
                            columnWidths: {
                              0: pw.FlexColumnWidth(3),
                              1: pw.FlexColumnWidth(1),
                            },
                            children: [
                              for (final d in deductions.entries)
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets
                                          .symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: pw.Text(
                                        d.key,
                                        style: pw.TextStyle(
                                          font: pf,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets
                                          .symmetric(
                                          vertical: 6, horizontal: 4),
                                      child: pw.Text(
                                        nf.format(d.value),
                                        style: pw.TextStyle(
                                          font: pf,
                                          fontSize: 10,
                                        ),
                                        textAlign:
                                        pw.TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets
                                        .symmetric(
                                        vertical: 6, horizontal: 4),
                                    child: pw.Text(
                                      'TOTAL DEDUCTIONS',
                                      style: pw.TextStyle(
                                        font: pb,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets
                                        .symmetric(
                                        vertical: 6, horizontal: 4),
                                    child: pw.Text(
                                      nf.format(totalDeductions),
                                      style: pw.TextStyle(
                                        font: pb,
                                        fontSize: 10,
                                      ),
                                      textAlign:
                                      pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue300),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: PdfColors.blue50,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [

                    pw.Text(
                      'GROSS SALARY',
                      style: pw.TextStyle(font: pf, fontSize: 10),
                    ),

                    pw.Text(
                      nf.format(gross),
                      style: pw.TextStyle(font: pb, fontSize: 11),
                    ),

                    pw.SizedBox(width: 20),

                    pw.Text(
                      'NET PAY',
                      style: pw.TextStyle(font: pb, fontSize: 12),
                    ),

                    pw.Text(
                      nf.format(net),
                      style: pw.TextStyle(
                        font: pb,
                        fontSize: 14,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'This is a system generated payslip and does not require a signature.',
                  style: pw.TextStyle(
                    font: pf,
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
              pw.NewPage(),
            ]);
          }
          return widgets;
        },
      ),
    );
    return doc.save();
  }
  Future<Uint8List> _generateSinglePayslipPdfBytes(Map<String, dynamic> p,
      {Uint8List? logoBytes}) async {
    return _generateMultiPayslipPdfBytes([p], logoBytes: logoBytes);
  }
  // -------------------------
  // Save PDF to Downloads (Option A)
  // -------------------------


  Future<void> _savePdfToDownloads(Uint8List bytes, String fileName) async {
    try {
      Directory? directory;

      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      await file.writeAsBytes(bytes);

      // 🔥 OPEN THE PDF AFTER SAVING
      await OpenFilex.open(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Payslip saved to Downloads"),
          ),
        );
      }
    } catch (e) {
      debugPrint("PDF SAVE ERROR: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save PDF"),
          ),
        );
      }
    }
  }
  // -------------------------
  // Download single payslip
  // -------------------------
  Future<void> _downloadSinglePayslipDirect(
      Map<String, dynamic> p) async {
    setState(() => isLoading = true);
    try {
      final logoBytes = _cachedLogoBytes ??
          await _getLogoBytes(await _resolveLogoPublicUrl());
      final bytes =
      await _generateSinglePayslipPdfBytes(p, logoBytes: logoBytes);
      final fileName =
          'Payslip_${employee?['employee_id'] ?? 'employee'}_${DateFormat('MMMM_yyyy').format(
        DateTime(p['year'] ?? selectedYear,
            p['month'] ?? selectedMonth),
      )}.pdf';
      await _savePdfToDownloads(bytes, fileName);
    } catch (e) {
      debugPrint('download single pdf error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }
  // -------------------------
  // Bulk export (reads stored payslips only)
  // -------------------------
  Future<void> _exportBulkRealPdf(int monthsCount) async {
    if (employee == null) return;
    setState(() => isLoading = true);
    try {
      final now = DateTime.now();
      final monthsNeeded = <Map<String, int>>[];
      for (int i = 0; i < monthsCount; i++) {
        final dt = DateTime(now.year, now.month - i);
        monthsNeeded.add({'month': dt.month, 'year': dt.year});
      }
      final monthsSet =
      monthsNeeded.map((m) => m['month']!).toSet().toList();
      final yearsSet =
      monthsNeeded.map((m) => m['year']!).toSet().toList();
      final res = await supabase
          .from('payslips')
          .select()
          .eq('employee_id', employee!['id'])
          .inFilter('month', monthsSet)
          .inFilter('year', yearsSet);
      final storedList = res != null
          ? List<Map<String, dynamic>>.from(res as List)
          : <Map<String, dynamic>>[];
      final Map<String, Map<String, dynamic>> storedMap = {};
      for (final s in storedList) {
        final key = '${s['month']}-${s['year']}';
        storedMap[key] = Map<String, dynamic>.from(s);
      }
      final pages = <Map<String, dynamic>>[];
      for (final my in monthsNeeded) {
        final key = '${my['month']}-${my['year']}';
        final p = storedMap[key];
        if (p == null) {
          debugPrint('Skipping missing stored payslip for $key');
          continue;
        }

        pages.add(p);
      }
      if (pages.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                Text('No payslips available for the selected months.')),
          );
        }
        return;
      }
      final logoBytes = _cachedLogoBytes ??
          await _getLogoBytes(await _resolveLogoPublicUrl());
      final bytes =
      await _generateMultiPayslipPdfBytes(pages, logoBytes: logoBytes);
      final fileName =
          'payslips-${employee?['employee_id']}-last$monthsCount.pdf';
      await _savePdfToDownloads(bytes, fileName);
    } catch (e) {
      debugPrint('Bulk export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk export failed: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }
  // -------------------------
  // UI helpers
  // -------------------------
  Widget _employeeCard() {
    if (employee == null) return const SizedBox();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person,
                color: Colors.blue[700], size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee?['full_name'] ?? '',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${employee?['employee_id'] ?? ''} · ${employee?['designation'] ?? ''} · ${employee?['department'] ?? ''}',
                  style: GoogleFonts.montserrat(
                    color: Colors.grey[700],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _periodSelectorCard() {
    final months = List.generate(12, (i) => i + 1);
    final years = List.generate(
        5, (i) => DateTime.now().year - 4 + i)
      ..sort((a, b) => b.compareTo(a));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_today,
                    color: Colors.blue[800], size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Select Period',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Choose the month and year to view your payslip',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  value: selectedMonth,
                  decoration: InputDecoration(
                    labelText: 'Month',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: months
                      .map(
                        (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        DateFormat.MMMM().format(
                          DateTime(2020, m),
                        ),
                        style: GoogleFonts.montserrat(),
                      ),
                    ),
                  )
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => selectedMonth = val);
                    await _processPeriodChange(
                        selectedMonth, selectedYear);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: selectedYear,
                  decoration: InputDecoration(
                    labelText: 'Year',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: years
                      .map(
                        (y) => DropdownMenuItem(
                      value: y,
                      child: Text(
                        y.toString(),
                        style: GoogleFonts.montserrat(),
                      ),
                    ),
                  )
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => selectedYear = val);
                    await _processPeriodChange(
                        selectedMonth, selectedYear);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _actionsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showBulkOptionsMenu,
            icon: const Icon(Icons.file_download_outlined,
                color: Colors.white),
            label: Text(
              'Bulk Download',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              if (payslip == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text('No payslip available to download')),
                  );
                }
                return;
              }

              await _downloadSinglePayslipDirect(payslip!);
            },
            icon: const Icon(Icons.download_outlined,
                color: Colors.white),
            label: Text(
              'Download PDF',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }
  void _showBulkOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Last 3 months (PDF)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportBulkRealPdf(3);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Last 6 months (PDF)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportBulkRealPdf(6);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Last 12 months (PDF)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportBulkRealPdf(12);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _infoChipAndBanner() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text(
              'Computed from Config',
              style: GoogleFonts.montserrat(fontSize: 13),
            ),
            backgroundColor: Colors.blue[50],
            avatar: const Icon(
              Icons.autorenew,
              size: 16,
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFFDF7F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange[100]!),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This payslip was computed using salary configuration.',
                  style: GoogleFonts.montserrat(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _payslipCardOrMessage() {
    if (isFuturePeriod || !isAccessGranted) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          infoMsg ?? 'Payslip not released for this month and year.',
          style: GoogleFonts.montserrat(
            color: Colors.orange[900],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (payslip == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No Payslip Found',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No payslips available for the selected period.',
              style: GoogleFonts.montserrat(color: Colors.grey[700]),
            ),
          ],
        ),
      );
    }
    final periodTitle =
        'Payslip - ${DateFormat.MMMM().format(DateTime(selectedYear, selectedMonth))} $selectedYear';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, color: Colors.blue[800]),
              const SizedBox(width: 8),
              Text(
                periodTitle,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            organization?['name'] ?? '-',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
          ),
          if ((organization?['location'] ?? '').toString().isNotEmpty)
            Text(
              organization?['location'] ?? '',
              style: GoogleFonts.montserrat(color: Colors.grey[700]),
            ),
          const SizedBox(height: 16),

          // Employee info
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                _infoPair('EMPLOYEE NAME', employee?['full_name'] ?? '--'),
                _infoPair('EMPLOYEE CODE', employee?['employee_id']?.toString() ?? '--'),
                _infoPair('DEPARTMENT', employee?['department']?.toString() ?? '--'),
                _infoPair('DESIGNATION', employee?['designation']?.toString() ?? '--'),
                _infoPair('PAN NUMBER', employee?['pan_no']?.toString() ?? '--'),
                _infoPair('UAN NUMBER', employee?['uan_no']?.toString() ?? '--'),
                _infoPair(
                  'DATE OF JOINING',
                  employee?['date_of_joining'] != null
                      ? _formatDate(employee!['date_of_joining'])
                      : '--',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Attendance
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _attItem(
                          'TOTAL DAYS IN MONTH',
                          (payslip?['total_monthly_days'] ?? '--')
                              .toString()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _attItem(
                          'TOTAL WORKING DAYS',
                          (payslip?['effective_work_days'] ?? '--')
                              .toString()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _attItem(
                          'WEEKLY OFFS, LEAVES & HOLIDAYS',
                          (payslip?['weekly_offs_leaves_holidays'] ?? '--')
                              .toString()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _attItem('LOP/ABSENT',
                          (payslip?['lop_absent'] ?? '0').toString()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _attItem(
                        'PAY DAYS',
                        (payslip?['pay_days'] ??
                            payslip?['total_monthly_days'] ??
                            '--')
                            .toString(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Earnings
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EARNINGS',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                ..._earningsRowsFromPayslip(payslip!)
                    .map(
                      (w) => Padding(
                    padding:
                    const EdgeInsets.symmetric(vertical: 4),
                    child: w,
                  ),
                ),
                const Divider(),
                _kvRow(
                  'TOTAL EARNINGS',
                  '₹ ${_formatCurrencyDouble(double.tryParse(
                      (payslip?['total_earnings'] ?? '0')
                          .toString()) ??
                      0)}',
                  isBold: true,
                  valueColor: Colors.green[700],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Deductions
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEDUCTIONS',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                ..._deductionRowsFromPayslip(payslip!)
                    .map(
                      (w) => Padding(
                    padding:
                    const EdgeInsets.symmetric(vertical: 4),
                    child: w,
                  ),
                ),
                const Divider(),
                _kvRow(
                  'TOTAL DEDUCTIONS',
                  '₹ ${_formatCurrencyDouble(double.tryParse(
                      (payslip?['total_deductions'] ?? '0')
                          .toString()) ??
                      0)}',
                  isBold: true,
                  valueColor: Colors.red[700],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Net pay
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 10),
                Text(
                  'NET PAY',
                  style: GoogleFonts.montserrat(
                    color: Colors.blue[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '₹ ${_formatCurrencyDouble(double.tryParse(
                      (payslip?['net_pay'] ?? '0').toString()) ??
                      0)}',
                  style: GoogleFonts.montserrat(
                    color: Colors.blue[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _infoPair(String title, String value) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
  Widget _attItem(String label, String value) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  Widget _kvRow(String left, String right,
      {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            right,
            style: GoogleFonts.montserrat(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }


  List<Widget> _earningsRowsFromPayslip(Map<String, dynamic> p) {
    if (p['payslip_line_items'] != null && p['payslip_line_items'].isNotEmpty) {
      final items = List<Map<String, dynamic>>.from(p['payslip_line_items']);
      return items
          .where((e) => e['component_type'] == 'earning')
          .map((e) => _kvRow(
        e['component_name'].toString().toUpperCase(),
        '₹ ${_formatCurrencyDouble(
          double.tryParse(e['component_amount'].toString()) ?? 0,
        )}',
      ))
          .toList();
    }

    final rows = <Widget>[];
    for (final cfg in salaryConfig) {
      final name = (cfg['component_name'] ?? cfg['name'] ?? '').toString();
      final type =
      (cfg['component_type'] ?? 'earning').toString().toLowerCase();
      if (type != 'earning') continue;
      final key = name.toLowerCase().replaceAll(' ', '_');
      final value = double.tryParse(p[key]?.toString() ?? '0') ?? 0.0;
      if (value == 0) continue;
      rows.add(
        _kvRow(
          name.toUpperCase(),
          '₹ ${_formatCurrencyDouble(value)}',
        ),
      );
    }
    if (salaryConfig.isEmpty) {
      void addIfPresent(String label, dynamic value) {
        final v = double.tryParse((value ?? '0').toString()) ?? 0.0;
        if (v == 0) return;
        rows.add(
          _kvRow(
            label,
            '₹ ${_formatCurrencyDouble(v)}',
          ),
        );
      }
      addIfPresent('BASIC PAY', p['basic_pay']);
      addIfPresent('HRA', p['hra']);
      addIfPresent('SPECIAL ALLOWANCE', p['special_allowance']);
      addIfPresent('DEARNESS ALLOWANCE', p['dearness_allowance']);
      addIfPresent('CONVEYANCE ALLOWANCE', p['conveyance_allowance']);
      addIfPresent('MEDICAL ALLOWANCE', p['medical_allowance']);
      addIfPresent('OTHER ALLOWANCE', p['other_allowance']);
      addIfPresent('OVERTIME PAY', p['overtime_pay']);
    }
    return rows;
  }
  List<Widget> _deductionRowsFromPayslip(Map<String, dynamic> p) {
    if (p['payslip_line_items'] != null && p['payslip_line_items'].isNotEmpty) {
      final items = List<Map<String, dynamic>>.from(p['payslip_line_items']);
      return items
          .where((e) => e['component_type'] == 'deduction')
          .map((e) => _kvRow(
        e['component_name'].toString().toUpperCase(),
        '₹ ${_formatCurrencyDouble(
          double.tryParse(e['component_amount'].toString()) ?? 0,
        )}',
      ))
          .toList();
    }

    final rows = <Widget>[];
    final deductionMap = {
      'pf_employee': 'EMPLOYEE PF',
      'esi_employee': 'EMPLOYEE ESI',
      'professional_tax': 'PROFESSIONAL TAX',
      'income_tax': 'INCOME TAX',
      'loan_deduction': 'LOAN DEDUCTION',
      'other_deductions': 'OTHER DEDUCTIONS',
    };

    deductionMap.forEach((key, label) {
      final value = double.tryParse(p[key]?.toString() ?? '0') ?? 0.0;
      if (value == 0) return;
      rows.add(
        _kvRow(
          label,
          '₹ ${_formatCurrencyDouble(value)}',
        ),
      );
    });
    if (rows.isEmpty && salaryConfig.isNotEmpty) {
      for (final cfg in salaryConfig) {
        final type =
        (cfg['component_type'] ?? 'earning').toString().toLowerCase();
        if (type != 'deduction') continue;
        final name =
        (cfg['component_name'] ?? cfg['name'] ?? '').toString();
        final key = name.toLowerCase().replaceAll(' ', '_');
        final value = double.tryParse(p[key]?.toString() ?? '0') ?? 0.0;
        if (value == 0) continue;
        rows.add(
          _kvRow(
            name.toUpperCase(),
            '₹ ${_formatCurrencyDouble(value)}',
          ),
        );
      }
    }
    if (rows.isEmpty) {
      void addIfPresent(String label, dynamic value) {
        final v = double.tryParse((value ?? '0').toString()) ?? 0.0;
        if (v == 0) return;
        rows.add(
          _kvRow(
            label,
            '₹ ${_formatCurrencyDouble(v)}',
          ),
        );
      }
      addIfPresent('EMPLOYEE PF', p['employee_pf']);
      addIfPresent('EMPLOYEE ESI', p['employee_esi']);
      addIfPresent('PROFESSIONAL TAX', p['professional_tax']);
      addIfPresent('TDS/INCOME TAX', p['tds_income_tax']);
      addIfPresent(
          'HEALTH EDUCATION CESS', p['health_education_cess']);
      addIfPresent(
          'EXCESS LEAVE DEDUCTION', p['excess_leave_deduction']);
      addIfPresent('LOAN DEDUCTION', p['loan_deduction']);
      addIfPresent('OTHER DEDUCTIONS', p['other_deductions']);
    }
    return rows;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F6FA),

      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: employee ?? {},
        companyLogoUrl: organization?['logo_url'],
        // ✅ FIX
        fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
        currentRoute: DrawerRoute.payroll,

      ),


      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'My Payslips',
          style: GoogleFonts.montserrat(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),

        // ✅ MENU ICON (THIS WAS THE REAL MISSING PIECE)
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),

      // 🔥 BODY + TOFFY OVERLAY
      body: Stack(
        children: [
          isLoading
              ? const SkeletonPayslipPage()
              : SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'My Payslips',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View and download your payslips',
                    style: GoogleFonts.montserrat(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _employeeCard(),
                  const SizedBox(height: 12),
                  _periodSelectorCard(),
                  const SizedBox(height: 12),
                  _actionsRow(),
                  const SizedBox(height: 12),
                  _infoChipAndBanner(),
                  const SizedBox(height: 12),
                  _payslipCardOrMessage(),
                ],
              ),
            ),
          ),

          // 🤖 TOFFY CHAT OVERLAY

        ],
      ),

      // 🔥 SVG BOTTOM NAVIGATION
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,

        onTap: (index) {
          setState(() => _bottomTabIndex = index);

          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    email: widget.userEmail,
                    employeeId: employee?['id'] ?? '',
                  ),
                ),
              );
              break;

            case 1:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeavesScreen(
                    email: widget.userEmail,
                    userData: widget.userData,
                    fetchHrmsContext: widget.fetchHrmsContext,
                  ),

                ),
              );
              break;

            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimeAttendanceScreen(
                    userEmail: widget.userEmail,
                    userData: widget.userData,                 // ✅ FIX
                    fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
                  ),
                ),
              );
              break;

            case 3:
            // ✅ CORRECT: already on Payslip → do nothing
              break;

            case 4:
              _scaffoldKey.currentState?.openEndDrawer();
              break;



          }
        },

        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/dashboard.svg",
              width: 22,
              color: _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/leaves.svg",
              width: 22,
              color: _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
            ),
            label: 'Leave',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/attendance.svg",
              width: 22,
              color: _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/payroll.svg",
              width: 22,
              color: _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
            ),
            label: 'Payslip',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
              color: Colors.grey,
            ),
            label: 'More',
          ),



        ],
      ),
    );
  }
}
