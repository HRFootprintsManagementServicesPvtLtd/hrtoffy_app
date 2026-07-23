import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class TaxDeductionScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const TaxDeductionScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<TaxDeductionScreen> createState() => _TaxDeductionScreenState();
}

class _TaxDeductionScreenState extends State<TaxDeductionScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  String? employeeId, organizationId, employeeName, employeeEmail, currentFY;
  double monthlySalary = 0.0;
  bool isLoading = true, canDeclare = true, canUploadProof = true;
  String selectedRegime = "new_regime";
  List<Map<String, dynamic>> deductionTypes = [];
  Map<String, dynamic> deductionDeclarations = {};
  Map<String, List<Map<String, dynamic>>> deductionProofs = {};
  Map<String, TextEditingController> amountControllers = {};
  Map<String, TextEditingController> notesControllers = {};
  double standardDeductionOld = 50000, standardDeductionNew = 75000, rebateLimitOld = 500000, rebateLimitNew = 700000;
  List<dynamic> oldRegimeSlabs = [{'minIncome': 0, 'maxIncome': 250000, 'rate': 0}, {'minIncome': 250000, 'maxIncome': 500000, 'rate': 5}, {'minIncome': 500000, 'maxIncome': 1000000, 'rate': 20}, {'minIncome': 1000000, 'maxIncome': null, 'rate': 30}];
  List<dynamic> newRegimeSlabs = [{'minIncome': 0, 'maxIncome': 400000, 'rate': 0}, {'minIncome': 400000, 'maxIncome': 800000, 'rate': 5}, {'minIncome': 800000, 'maxIncome': 1200000, 'rate': 10}, {'minIncome': 1200000, 'maxIncome': 1600000, 'rate': 15}, {'minIncome': 1600000, 'maxIncome': 2000000, 'rate': 20}, {'minIncome': 2000000, 'maxIncome': 2400000, 'rate': 25}, {'minIncome': 2400000, 'maxIncome': null, 'rate': 30}];
  DateTime? declarationStart, declarationEnd, proofStart, proofEnd;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    amountControllers.forEach((_, c) => c.dispose());
    notesControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() { isLoading = true; errorMsg = null; });
    try {
      currentFY = _getCurrentFY();
      final emp = await supabase.from('employee_records').select('id, organization_id, full_name, email').eq('email', widget.userEmail).maybeSingle();
      if (emp == null) { setState(() { errorMsg = "Employee record not found."; isLoading = false; }); return; }
      employeeId = emp['id'].toString();
      organizationId = emp['organization_id'].toString();
      employeeName = emp['full_name'].toString();
      employeeEmail = emp['email'].toString();

      final salaryRes = await supabase.rpc('get_employee_salary', params: {'p_employee_id': employeeId});
      monthlySalary = (salaryRes ?? 0).toDouble();

      var config = await supabase.from('income_tax_config').select().eq('organization_id', organizationId!).eq('financial_year', currentFY!).maybeSingle();
      if (config != null) {
        standardDeductionOld = (config['standard_deduction_old_regime'] ?? 50000).toDouble();
        standardDeductionNew = (config['standard_deduction_new_regime'] ?? 75000).toDouble();
        rebateLimitOld = (config['rebate_limit_old_regime'] ?? 500000).toDouble();
        rebateLimitNew = (config['rebate_limit_new_regime'] ?? 700000).toDouble();
        if (config['old_regime_slabs'] != null) oldRegimeSlabs = config['old_regime_slabs'];
        if (config['new_regime_ slabs'] != null) newRegimeSlabs = config['new_regime_slabs'];
      }

      var window = await supabase.from('tax_submission_windows').select().eq('organization_id', organizationId!).eq('financial_year', currentFY!).maybeSingle();
      if (window != null) {
        var now = DateTime.now();
        declarationStart = DateTime.tryParse(window['declaration_start_date'] ?? '');
        declarationEnd = DateTime.tryParse(window['declaration_end_date'] ?? '');
        proofStart = DateTime.tryParse(window['proof_submission_start_date'] ?? '');
        proofEnd = DateTime.tryParse(window['proof_submission_end_date'] ?? '');
        canDeclare = declarationStart != null && declarationEnd != null && now.isAfter(declarationStart!) && now.isBefore(declarationEnd!);
        canUploadProof = proofStart != null && proofEnd != null && now.isAfter(proofStart!) && now.isBefore(proofEnd!);
      }

      var regime = await supabase.from('tax_regime_selections').select('regime_type').eq('employee_id', employeeId!).eq('financial_year', currentFY!).maybeSingle();
      if (regime != null) selectedRegime = regime['regime_type'] ?? 'new_regime';

      await _fetchDeductionTypes();
      await _fetchDeclarations();
    } catch (e) { errorMsg = "$e"; }
    setState(() { isLoading = false; });
  }

  String _getCurrentFY() {
    var now = DateTime.now();
    int y = now.year;
    return now.month >= 4 ? "$y-${y + 1}" : "${y - 1}-$y";
  }

  Future<void> _fetchDeductionTypes() async {
    List<Map<String, dynamic>> types = [];
    if (selectedRegime == "old_regime") {
      final q = await supabase.from('tax_deduction_types').select().contains('applies_to_regime', ['old_regime']).eq('is_active', true).order('code');
      types = List<Map<String, dynamic>>.from(q);
    }
    setState(() {
      deductionTypes = types;
      for (final t in deductionTypes) {
        amountControllers.putIfAbsent(t['id'], () => TextEditingController());
        notesControllers.putIfAbsent(t['id'], () => TextEditingController());
      }
    });
  }

  Future<void> _fetchDeclarations() async {
    final res = await supabase.from('tax_declarations').select().eq('employee_id', employeeId!).eq('financial_year', currentFY!);
    deductionDeclarations.clear();
    for (final dec in res) {
      deductionDeclarations[dec['deduction_type_id']] = dec;
      if (amountControllers.containsKey(dec['deduction_type_id'])) amountControllers[dec['deduction_type_id']]!.text = (dec['declared_amount'] ?? '').toString();
      if (notesControllers.containsKey(dec['deduction_type_id'])) notesControllers[dec['deduction_type_id']]!.text = (dec['employee_notes'] ?? '').toString();
    }
    await _fetchAllProofs();
    setState(() {});
  }

  Future<void> _fetchAllProofs() async {
    deductionProofs.clear();
    for (final declaration in deductionDeclarations.values) {
      if (declaration['id'] == null) continue;
      final proofs = await supabase.from('tax_proofs').select().eq('declaration_id', declaration['id']).order('uploaded_at');
      deductionProofs[declaration['deduction_type_id']] = List<Map<String, dynamic>>.from(proofs);
    }
    setState(() {});
  }

  Future<void> _submitDeclarations() async {
    setState(() => isLoading = true);
    try {
      for (var type in deductionTypes) {
        final typeId = type['id'];
        final isClaimed = deductionDeclarations[typeId]?['is_claimed'] ?? false;
        final amount = double.tryParse(amountControllers[typeId]?.text ?? '0') ?? 0.0;
        final notes = notesControllers[typeId]?.text ?? '';

        if (deductionDeclarations.containsKey(typeId) && deductionDeclarations[typeId]['id'] != null) {
          await supabase.from('tax_declarations').update({
            'declared_amount': amount,
            'is_claimed': isClaimed,
            'employee_notes': notes,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', deductionDeclarations[typeId]['id']);
        } else {
          await supabase.from('tax_declarations').insert({
            'employee_id': employeeId,
            'organization_id': organizationId,
            'financial_year': currentFY,
            'deduction_type_id': typeId,
            'declared_amount': amount,
            'is_claimed': isClaimed,
            'employee_notes': notes,
            'status': 'pending',
          });
        }
      }

      final existingRegime = await supabase.from('tax_regime_selections').select().eq('employee_id', employeeId!).eq('financial_year', currentFY!).maybeSingle();
      if (existingRegime != null) {
        await supabase.from('tax_regime_selections').update({'regime_type': selectedRegime}).eq('id', existingRegime['id']);
      } else {
        await supabase.from('tax_regime_selections').insert({
          'employee_id': employeeId,
          'organization_id': organizationId,
          'financial_year': currentFY,
          'regime_type': selectedRegime,
        });
      }

      await _fetchDeclarations();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Declarations saved successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _uploadProof(String typeId) async {
    final declaration = deductionDeclarations[typeId];
    if (declaration == null || declaration['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please save declaration first")));
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    setState(() => isLoading = true);
    try {
      final file = result.files.first;
      final path = 'tax-proofs/$employeeId/${declaration['id']}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await supabase.storage.from('claim-documents').upload(path, File(file.path!));
      final fileUrl = supabase.storage.from('claim-documents').getPublicUrl(path);

      await supabase.from('tax_proofs').insert({
        'declaration_id': declaration['id'],
        'employee_id': employeeId,
        'organization_id': organizationId,
        'file_url': fileUrl,
        'file_name': file.name,
        'status': 'pending',
      });

      await _fetchAllProofs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload error: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Map<String, double> _calculateTaxSummary() {
    double gross = monthlySalary * 12;
    double stdDed = selectedRegime == 'new_regime' ? standardDeductionNew : standardDeductionOld;
    double deductions = 0.0;
    
    if (selectedRegime == 'old_regime') {
      deductionDeclarations.forEach((k, v) {
        if (v['is_claimed'] == true) {
          double declared = double.tryParse(amountControllers[k]?.text ?? '0') ?? 0;
          deductions += declared;
        }
      });
    }
    
    double taxable = (gross - stdDed - deductions).clamp(0.0, double.infinity);
    double tax = 0.0;
    List<dynamic> slabs = selectedRegime == 'new_regime' ? newRegimeSlabs : oldRegimeSlabs;
    double rebateLimit = selectedRegime == 'new_regime' ? rebateLimitNew : rebateLimitOld;

    if (taxable <= rebateLimit) {
      tax = 0.0;
    } else {
      for (var slab in slabs) {
        double min = (slab['minIncome'] ?? 0).toDouble();
        double? max = slab['maxIncome']?.toDouble();
        double rate = (slab['rate'] ?? 0).toDouble() / 100.0;

        if (taxable > min) {
          double taxableInSlab = (max == null || taxable < max) ? (taxable - min) : (max - min);
          tax += taxableInSlab * rate;
        }
      }
    }

    return {'taxableIncome': taxable, 'annualTaxLiability': tax, 'grossSalary': gross, 'totalDeductions': deductions + stdDed};
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.tax,
        companyLogoUrl: null,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 12),
                child: _circleIconBtn(
                  icon: "assets/icons/notification.svg",
                  onTap: () {
                    final empId = (widget.userData['id'] ?? widget.userData['employee_id'])?.toString() ?? '';
                    if (empId.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer()),
              ),
              const SizedBox(width: 1),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD7E8FF), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Tax Declarations", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Financial Year $currentFY", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: isLoading
                ? const SkeletonTaxDeclarationPage()
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildSectionCard(title: "Regime Selection", child: _buildRegimeUI()),
                        const SizedBox(height: 20),
                        _buildSectionCard(title: "Tax Summary", child: _buildSummaryUI()),
                        if (selectedRegime == "old_regime") ...[
                          const SizedBox(height: 24),
                          Text("Available Deductions", style: EmployeeUi.title(16)),
                          const SizedBox(height: 12),
                          ...deductionTypes.map((t) => _buildDeductionCard(t)),
                          const SizedBox(height: 20),
                          if (canDeclare) ElevatedButton(
                            onPressed: _submitDeclarations,
                            style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text("Save Declarations", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: employeeId ?? ''))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: EmployeeUi.title(16)), const SizedBox(height: 16), child]),
    );
  }

  Widget _buildRegimeUI() {
    return Column(
      children: [
        RadioListTile<String>(
          title: const Text('New Regime'),
          subtitle: const Text('Lower rates, fewer deductions'),
          value: 'new_regime',
          groupValue: selectedRegime,
          activeColor: EmployeeUi.primary,
          onChanged: (v) {
            setState(() => selectedRegime = v!);
            _fetchDeductionTypes();
          }
        ),
        RadioListTile<String>(
          title: const Text('Old Regime'),
          subtitle: const Text('Standard rates, multiple deductions'),
          value: 'old_regime',
          groupValue: selectedRegime,
          activeColor: EmployeeUi.primary,
          onChanged: (v) {
            setState(() => selectedRegime = v!);
            _fetchDeductionTypes();
          }
        ),
      ],
    );
  }

  Widget _buildSummaryUI() {
    final summary = _calculateTaxSummary();
    return Column(
      children: [
        _row("Gross Annual Salary", "₹${NumberFormat('#,##,###').format(summary['grossSalary'])}"),
        _row("Total Deductions", "₹${NumberFormat('#,##,###').format(summary['totalDeductions'])}"),
        _row("Taxable Income", "₹${NumberFormat('#,##,###').format(summary['taxableIncome'])}"),
        const Divider(height: 32),
        _row("Estimated Annual Tax", "₹${NumberFormat('#,##,###').format(summary['annualTaxLiability'])}", bold: true, color: EmployeeUi.primary),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)), Text(value, style: GoogleFonts.montserrat(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color))]));
  }

  Widget _buildDeductionCard(Map<String, dynamic> type) {
    final typeId = type['id'];
    final isClaimed = deductionDeclarations[typeId]?['is_claimed'] ?? false;
    final proofs = deductionProofs[typeId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Checkbox(
              value: isClaimed,
              activeColor: EmployeeUi.primary,
              onChanged: (v) {
                setState(() {
                  if (deductionDeclarations[typeId] == null) {
                    deductionDeclarations[typeId] = {'is_claimed': v, 'deduction_type_id': typeId};
                  } else {
                    deductionDeclarations[typeId]['is_claimed'] = v;
                  }
                });
              }
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(type['name'] ?? '', style: EmployeeUi.title(14)), Text(type['code'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey))]))
          ]),
          if (isClaimed) ...[
            const SizedBox(height: 12),
            TextField(
              controller: amountControllers[typeId],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount (₹)", border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesControllers[typeId],
              decoration: const InputDecoration(labelText: "Notes (Optional)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text("Proofs", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...proofs.map((p) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.file_present, size: 20),
              title: Text(p['file_name'] ?? 'Proof', style: const TextStyle(fontSize: 12)),
              subtitle: Text(p['status'] ?? 'pending', style: TextStyle(fontSize: 10, color: p['status'] == 'approved' ? Colors.green : Colors.orange)),
            )),
            if (canUploadProof) TextButton.icon(
              onPressed: () => _uploadProof(typeId),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text("Upload Proof"),
            ),
          ]
        ],
      ),
    );
  }
}
