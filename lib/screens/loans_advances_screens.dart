import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class LoansAdvancesScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const LoansAdvancesScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<LoansAdvancesScreen> createState() => _LoansAdvancesScreenState();
}

class _LoansAdvancesScreenState extends State<LoansAdvancesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  final supabase = Supabase.instance.client;

  double? maxEligibleAmount;
  double utilizationPercent = 0.0;
  double totalOutstanding = 0.0;
  bool loadingEligibility = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _fetchEligibility();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEligibility() async {
    try {
      if (!mounted) return;
      setState(() => loadingEligibility = true);
      final empId = widget.userData['id'] ?? widget.userData['employee_id'];
      final grade = widget.userData['grade_code'] ?? widget.userData['grade_name'];

      if (grade != null) {
        final gradeRes = await supabase.from('grade_levels').select('loan_max_amount').eq('grade_name', grade).maybeSingle();
        if (gradeRes != null) {
          maxEligibleAmount = (gradeRes['loan_max_amount'] ?? 0).toDouble();
        }
      }

      final activeLoans = await supabase.from('loans_advances').select('requested_amount, status').eq('employee_id', empId).inFilter('status', ['active', 'approved', 'pending']);
      
      double used = 0;
      if (activeLoans is List && activeLoans.isNotEmpty) {
        for (var l in activeLoans) {
          used += (double.tryParse(l['requested_amount']?.toString() ?? '0') ?? 0);
        }
      }

      totalOutstanding = used;
      if (maxEligibleAmount != null && maxEligibleAmount! > 0) {
        utilizationPercent = (used / maxEligibleAmount!).clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint("Eligibility error: $e");
    } finally {
      if (mounted) setState(() => loadingEligibility = false);
    }
  }

  Widget _buildEligibilityCard() {
    if (loadingEligibility) return const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator());
    if (maxEligibleAmount == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(color: EmployeeUi.blueBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Loan Eligibility", style: EmployeeUi.title(16)),
              Text("₹${NumberFormat('#,##,###').format(maxEligibleAmount)} limit", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: utilizationPercent,
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(utilizationPercent > 0.8 ? Colors.red : EmployeeUi.primary),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Utilization: ${(utilizationPercent * 100).toStringAsFixed(0)}%", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
              Text("Outstanding: ₹${NumberFormat('#,##,###').format(totalOutstanding)}", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
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
        currentRoute: DrawerRoute.loans,
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
                    colors: [Color(0xFFEBDFF6), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Loans & Advances", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Manage your financial requests", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildEligibilityCard(),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmployeeUi.border)),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                    unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'My Loans'), Tab(text: 'EMI Schedule')],
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                MyLoansTab(userEmail: widget.userEmail),
                EMIScheduleTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0 ? FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ApplyLoanPage(userData: widget.userData)));
          if (result == true) {
            _fetchEligibility();
            setState(() {});
          }
        },
        backgroundColor: EmployeeUi.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) async {
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id'].toString()))); return; }
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
}

class MyLoansTab extends StatelessWidget {
  final String userEmail;
  final SupabaseClient supabase = Supabase.instance.client;
  MyLoansTab({Key? key, required this.userEmail}) : super(key: key);

  Future<List<Map<String, dynamic>>> fetchLoans() async {
    final email = userEmail;
    final emp = await supabase.from('employee_records').select('id').eq('email', email).maybeSingle();
    if (emp == null) return [];
    final res = await supabase.from('loans_advances').select().eq('employee_id', emp['id']).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  String formatCurrency(dynamic value) {
    if (value == null) return '₹0';
    return '₹${NumberFormat('#,##,###').format(double.tryParse(value.toString()) ?? 0)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchLoans(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SkeletonLoansMyLoans();
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [SvgPicture.asset("assets/icons/loans.svg", height: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)), const SizedBox(height: 20), Text("No loans found", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54))]));
        }
        final loans = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: loans.length,
          itemBuilder: (context, i) {
            final loan = loans[i];
            final status = (loan['status'] ?? "").toString().toLowerCase();
            Color statusColor = Colors.grey;
            if (status == 'approved' || status == 'active') statusColor = Colors.green;
            else if (status == 'pending') statusColor = Colors.orange;
            else if (status == 'rejected') statusColor = Colors.red;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: EmployeeUi.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(loan['loan_number'] ?? "LOAN-ID", style: EmployeeUi.title(15)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
                  ]),
                  const SizedBox(height: 12),
                  _rowInfo("Category", loan['loan_category']),
                  _rowInfo("Amount", formatCurrency(loan['requested_amount'])),
                  _rowInfo("Tenure", "${loan['tenure_months']} months"),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _rowInfo(String label, dynamic value) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [Text("$label: ", style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)), Text(value?.toString() ?? '-', style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w600))]));
  }
}

class EMIScheduleTab extends StatelessWidget {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchEMI() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final res = await supabase.from('loan_emi_schedule').select('*, loans_advances(loan_number)').eq('employee_id', user.id).order('due_date', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchEMI(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SkeletonLoansEMISchedule();
        final emis = snapshot.data!;
        if (emis.isEmpty) return const Center(child: Text("No EMI schedules found."));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: emis.length,
          itemBuilder: (context, i) {
            final emi = emis[i];
            final status = (emi['status'] ?? 'pending').toString().toLowerCase();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: EmployeeUi.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Loan: ${emi['loans_advances']?['loan_number'] ?? '-'}", style: EmployeeUi.title(14)),
                      Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: status == 'paid' ? Colors.green : Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("Due Date: ${emi['due_date'].toString().substring(0, 10)}", style: GoogleFonts.montserrat(fontSize: 13)),
                  Text("Outstanding: ₹${NumberFormat('#,##,###').format(emi['outstanding_principal'] ?? 0)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text("EMI Amount: ₹${NumberFormat('#,##,###').format(emi['emi_amount'] ?? 0)}", style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class ApplyLoanPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const ApplyLoanPage({Key? key, required this.userData}) : super(key: key);

  @override
  State<ApplyLoanPage> createState() => _ApplyLoanPageState();
}

class _ApplyLoanPageState extends State<ApplyLoanPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  final supabase = Supabase.instance.client;
  String? _loanCategory = 'personal_loan';
  int tenure = 12;
  DateTime? emiStartDate;
  PlatformFile? attachment;
  bool submitting = false;

  final List<String> categories = ["salary_advance", "personal_loan", "emergency_loan", "education_loan", "vehicle_loan", "travel_advance"];
  final List<int> tenureOptions = [3, 6, 12, 18, 24, 36];

  String prettify(String text) => text.split('_').map((e) => e[0].toUpperCase() + e.substring(1).toLowerCase()).join(' ');

  Future<void> submitLoan() async {
    if (!_formKey.currentState!.validate()) return;
    if (emiStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select EMI start date")));
      return;
    }
    
    setState(() => submitting = true);
    try {
      final empId = widget.userData['id'] ?? widget.userData['employee_id'];
      final orgId = widget.userData['organization_id'];
      final managerId = widget.userData['manager_id'];

      String? fileUrl;
      if (attachment != null) {
        final path = 'loans/$empId/${DateTime.now().millisecondsSinceEpoch}_${attachment!.name}';
        await supabase.storage.from('claim-documents').upload(path, File(attachment!.path!));
        fileUrl = supabase.storage.from('claim-documents').getPublicUrl(path);
      }

      final res = await supabase.from('loans_advances').insert({
        "loan_number": "LOAN-${DateTime.now().millisecondsSinceEpoch}",
        "employee_id": empId,
        "organization_id": orgId,
        "manager_id": managerId,
        "loan_category": _loanCategory,
        "requested_amount": double.parse(_amountController.text),
        "tenure_months": tenure,
        "emi_start_date": emiStartDate!.toIso8601String(),
        "purpose": _purposeController.text,
        "supporting_documents": fileUrl != null ? [{'name': attachment!.name, 'url': fileUrl}] : [],
        "status": "pending",
        "application_date": DateTime.now().toIso8601String(),
      }).select().single();

      await supabase.rpc('initialize_workflow', params: {
        'p_module': 'loans',
        'p_target_id': res['id'],
        'p_org_id': orgId,
      });

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Application failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmployeeUi.pageBg,
      appBar: EmployeeUi.appBar(title: "Apply for Loan"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: EmployeeUi.cardDecoration(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Request Loan", style: EmployeeUi.title(18)),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: "Loan Category", border: OutlineInputBorder()),
                  value: _loanCategory,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(prettify(c)))).toList(),
                  onChanged: (v) => setState(() => _loanCategory = v),
                  validator: (v) => v == null ? "Select category" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _amountController, decoration: const InputDecoration(labelText: "Requested Amount (₹)", border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? "") ?? 0) <= 0 ? "Enter valid amount" : null),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: "Tenure (Months)", border: OutlineInputBorder()),
                  value: tenure,
                  items: tenureOptions.map((t) => DropdownMenuItem(value: t, child: Text("$t Months"))).toList(),
                  onChanged: (v) => setState(() => tenure = v!),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() => emiStartDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                    child: Row(children: [Text(emiStartDate == null ? "Select EMI Start Date" : "EMI Starts: ${DateFormat('yyyy-MM-dd').format(emiStartDate!)}"), const Spacer(), const Icon(Icons.calendar_today, size: 18)]),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _purposeController, decoration: const InputDecoration(labelText: "Purpose", border: OutlineInputBorder()), minLines: 2, maxLines: 4, validator: (v) => (v == null || v.isEmpty) ? "Purpose required" : null),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles();
                    if (result != null) setState(() => attachment = result.files.first);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50),
                    child: Row(children: [Icon(Icons.attach_file, color: EmployeeUi.primary), const SizedBox(width: 12), Expanded(child: Text(attachment == null ? "Attach Supporting Document" : attachment!.name, style: GoogleFonts.montserrat(fontSize: 13))), if (attachment != null) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => attachment = null))]),
                  ),
                ),
                const SizedBox(height: 24),
                submitting ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: submitLoan, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Submit Loan Request", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
