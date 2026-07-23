import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

class ManagerLoansScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerLoansScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerLoansScreen> createState() => _ManagerLoansScreenState();
}

class _ManagerLoansScreenState extends State<ManagerLoansScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String activeAction = 'none'; // none, my_loans, apply, emi_schedule, approvals, all_loans, hr_submit
  bool loading = true;
  
  int pendingCount = 0;
  String? employeeId, organizationId, grade, empRole;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => loading = true);
    try {
      employeeId = widget.userData['id']?.toString();
      organizationId = widget.userData['organization_id']?.toString();
      grade = widget.userData['grade_code']?.toString();
      empRole = widget.userData['emp_role']?.toString();

      await _fetchApprovalCount();
    } catch (e) {
      debugPrint("Error initializing manager loans: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchApprovalCount() async {
    try {
      final myId = employeeId;
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
      List<String> teamIds = [];
      if (hierarchy is List) {
        teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      }

      var query = supabase.from('loans_advances').select('id').eq('status', 'pending');
      if (teamIds.isNotEmpty) {
        query = query.or('manager_id.eq.$myId,employee_id.in.(${teamIds.join(",")})');
      } else {
        query = query.eq('manager_id', myId!);
      }
      
      final res = await query;
      if (mounted) setState(() => pendingCount = (res as List).length);
    } catch (e) {
      debugPrint("Error fetching loan approval counts: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.loans,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Image.asset("assets/HR TOFFY.png", height: 35),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu, color: Colors.black),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (activeAction != 'none') return _buildDetailView();

    return RefreshIndicator(
      onRefresh: _initData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroBanner(),
            const SizedBox(height: 32),
            _buildGrid(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFD7E8FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Rewards that feel personal",
            style: GoogleFonts.playfairDisplay(color: const Color(0xFF444444), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Manage your loans, apply for advances, and track EMI schedules easily.",
            style: GoogleFonts.montserrat(color: const Color(0xFF666666), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final bool isManager = ['manager', 'reviewer', 'hr', 'hr_manager', 'hr_head', 'admin'].contains(empRole?.toLowerCase());
    final bool isAdmin = ['admin', 'hr_head'].contains(empRole?.toLowerCase());
    final bool isHR = ['hr', 'hr_manager', 'hr_head', 'admin'].contains(empRole?.toLowerCase());

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.9,
      children: [
        _actionCard("My Loans", "Track your active loans.", Icons.credit_card, const Color(0xFFD4F3F7), 'my_loans'),
        _actionCard("Apply for Loan", "Request a new advance.", Icons.add_circle_outline, const Color(0xFFDFF6E5), 'apply'),
        _actionCard("EMI Schedule", "View upcoming deductions.", Icons.calendar_today, const Color(0xFFEBDFF6), 'emi_schedule'),
        if (isManager) _actionCard("Approvals", "Review team loan requests.", Icons.check_box_outlined, const Color(0xFFFFECE6), 'approvals', badge: pendingCount),
        if (isAdmin) _actionCard("All Loans", "View organization-wide loans.", Icons.list_alt_rounded, const Color(0xFFF5F5F5), 'all_loans'),
        if (isHR) _actionCard("HR Submit", "Apply on behalf of employee.", Icons.add_to_photos_outlined, const Color(0xFFDFF6E5), 'hr_submit'),
      ],
    );
  }

  Widget _actionCard(String label, String desc, IconData icon, Color color, String action, {int? badge}) {
    return InkWell(
      onTap: () => setState(() => activeAction = action),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.black87, size: 24),
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Color(0xFFEB5757), shape: BoxShape.circle),
                      child: Text(badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(label, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Expanded(
              child: Text(desc, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black54, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    Widget child;
    String title;

    switch (activeAction) {
      case 'approvals':
        title = "Loan Approvals";
        child = LoanApprovalPanel(userData: widget.userData, onBack: () => setState(() => activeAction = 'none'));
        break;
      case 'my_loans':
        title = "My Loans";
        child = MyLoansPanel(employeeId: employeeId!, organizationId: organizationId!);
        break;
      case 'apply':
        title = "Apply for Loan";
        child = LoanApplicationPanel(
          employeeId: employeeId!,
          organizationId: organizationId!,
          grade: grade,
          managerId: widget.userData['manager_id']?.toString(),
          onSuccess: () {
            setState(() => activeAction = 'none');
            _initData();
          },
        );
        break;
      case 'emi_schedule':
        title = "EMI Schedule";
        child = EMISchedulePanel(employeeId: employeeId!);
        break;
      case 'all_loans':
        title = "All Loans";
        child = AllLoansPanel(organizationId: organizationId!);
        break;
      case 'hr_submit':
        title = "HR Loan Submission";
        child = HRLoanSubmissionPanel(organizationId: organizationId!, onSuccess: () {
          setState(() => activeAction = 'none');
          _initData();
        });
        break;
      default:
        title = activeAction.replaceAll('_', ' ').toUpperCase();
        child = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text("$title View Coming Soon", style: GoogleFonts.montserrat(color: Colors.grey)),
            ],
          ),
        );
    }

    return Column(
      children: [
        if (activeAction != 'approvals') _buildDetailHeader(title),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildDetailHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white),
      child: InkWell(
        onTap: () => setState(() => activeAction = 'none'),
        child: Row(
          children: [
            const Icon(Icons.arrow_back, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Text("Back to overview", style: GoogleFonts.montserrat(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(title, style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// 🔵 My Loans Panel
class MyLoansPanel extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  const MyLoansPanel({super.key, required this.employeeId, required this.organizationId});

  @override
  State<MyLoansPanel> createState() => _MyLoansPanelState();
}

class _MyLoansPanelState extends State<MyLoansPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> loans = [];

  @override
  void initState() {
    super.initState();
    _fetchLoans();
  }

  Future<void> _fetchLoans() async {
    setState(() => loading = true);
    try {
      final res = await supabase
          .from('loans_advances')
          .select('*, loan_types(loan_type_name)')
          .eq('employee_id', widget.employeeId)
          .order('application_date', ascending: false);
      
      var data = List<Map<String, dynamic>>.from(res);
      if (data.isNotEmpty) {
        try {
          final ids = data.map((l) => l['id']).toList();
          final decryptRes = await supabase.functions.invoke('salary-encryption', body: {
            'action': 'decrypt-batch',
            'table': 'loans_advances',
            'ids': ids,
          });
          
          if (decryptRes.data != null && decryptRes.data is List) {
            final decryptedMap = {for (var item in decryptRes.data) item['id']: item};
            for (var loan in data) {
              if (decryptedMap.containsKey(loan['id'])) {
                final d = decryptedMap[loan['id']];
                loan['requested_amount'] = d['requested_amount'];
                loan['approved_amount'] = d['approved_amount'];
                loan['outstanding_principal'] = d['outstanding_principal'];
                loan['emi_amount'] = d['emi_amount'];
              }
            }
          }
        } catch (de) {
          debugPrint("Decryption error: $de");
        }
      }
      if (mounted) setState(() => loans = data);
    } catch (e) {
      debugPrint("Error fetching my loans: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (loans.isEmpty) return Center(child: Text("No loans found", style: GoogleFonts.montserrat(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: loans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final loan = loans[index];
        final status = (loan['status'] ?? 'pending').toString().toLowerCase();
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loan['loan_number'] ?? 'LN-NEW', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade700)),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              Text(loan['loan_category']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'LOAN', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(loan['purpose'] ?? '-', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat("Requested", "₹${NumberFormat('#,##,###').format(double.tryParse(loan['requested_amount']?.toString() ?? '0') ?? 0)}"),
                  _stat("Tenure", "${loan['tenure_months']} Months"),
                  _stat("EMI", "₹${NumberFormat('#,##,###').format(double.tryParse(loan['emi_amount']?.toString() ?? '0') ?? 0)}"),
                ],
              ),
              if (loan['is_hr_submission'] == true) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text("HR SUBMITTED", style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'pending': color = const Color(0xFFF2994A); break;
      case 'approved': color = const Color(0xFF219653); break;
      case 'rejected': color = const Color(0xFFEB5757); break;
      case 'active': case 'disbursed': color = const Color(0xFF2F80ED); break;
      case 'closed': color = const Color(0xFF888888); break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _stat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey)),
        Text(val, style: GoogleFonts.playfairDisplay(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// 🟢 Loan Application Panel
class LoanApplicationPanel extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  final String? grade;
  final String? managerId;
  final VoidCallback onSuccess;

  const LoanApplicationPanel({
    super.key,
    required this.employeeId,
    required this.organizationId,
    this.grade,
    this.managerId,
    required this.onSuccess,
  });

  @override
  State<LoanApplicationPanel> createState() => _LoanApplicationPanelState();
}

class _LoanApplicationPanelState extends State<LoanApplicationPanel> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  String? category = 'personal_loan';
  double? amount;
  int tenure = 12;
  String? purpose;
  DateTime? emiStartDate;
  PlatformFile? attachment;
  
  bool submitting = false;
  double? maxEligibleAmount;
  double utilizationPercent = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchEligibility();
  }

  Future<void> _fetchEligibility() async {
    try {
      // Fetch grade limits
      if (widget.grade != null) {
        final gradeRes = await supabase.from('grade_levels').select('loan_max_amount').eq('grade_name', widget.grade!).maybeSingle();
        if (gradeRes != null) {
          maxEligibleAmount = (gradeRes['loan_max_amount'] ?? 0).toDouble();
        }
      }

      // Fetch current utilization (RPC or sum)
      final activeLoans = await supabase.from('loans_advances').select('requested_amount').eq('employee_id', widget.employeeId).inFilter('status', ['active', 'approved', 'pending']);
      
      double used = 0;
      if (activeLoans is List && activeLoans.isNotEmpty) {
        try {
          final ids = activeLoans.map((l) => l['id']).toList();
          final decryptRes = await supabase.functions.invoke('salary-encryption', body: {
            'action': 'decrypt-batch',
            'table': 'loans_advances',
            'ids': ids
          });
          if (decryptRes.data != null) {
            for (var item in decryptRes.data) {
              used += (double.tryParse(item['requested_amount']?.toString() ?? '0') ?? 0);
            }
          }
        } catch (_) {}
      }

      if (maxEligibleAmount != null && maxEligibleAmount! > 0) {
        utilizationPercent = (used / maxEligibleAmount!).clamp(0.0, 1.0);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Eligibility fetch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (maxEligibleAmount != null) _buildUtilizationCard(),
            const SizedBox(height: 24),
            _fieldTitle("Loan Category"),
            DropdownButtonFormField<String>(
              value: category,
              items: ['personal_loan', 'salary_advance', 'emergency_loan', 'education_loan', 'vehicle_loan', 'travel_advance']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.replaceAll('_', ' ').toUpperCase()))).toList(),
              onChanged: (v) => setState(() => category = v),
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 16),
            _fieldTitle("Requested Amount (₹)"),
            TextFormField(
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(hint: "Enter amount"),
              onChanged: (v) => amount = double.tryParse(v),
              validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? "Invalid amount" : null,
            ),
            const SizedBox(height: 16),
            _fieldTitle("Tenure (Months)"),
            DropdownButtonFormField<int>(
              value: tenure,
              items: [3, 6, 12, 24].map((e) => DropdownMenuItem(value: e, child: Text("$e Months"))).toList(),
              onChanged: (v) => setState(() => tenure = v!),
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 16),
            _fieldTitle("EMI Start Date"),
            TextFormField(
              readOnly: true,
              decoration: _inputDecoration(hint: emiStartDate == null ? "Select date" : DateFormat('dd MMM yyyy').format(emiStartDate!)),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                if (d != null) setState(() => emiStartDate = d);
              },
            ),
            const SizedBox(height: 16),
            _fieldTitle("Purpose"),
            TextFormField(
              maxLines: 3,
              decoration: _inputDecoration(hint: "Reason for loan..."),
              onChanged: (v) => purpose = v,
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
            const SizedBox(height: 20),
            _fieldTitle("Supporting Documents"),
            _buildFilePicker(),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF219653),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit Application", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilizationCard() {
    Color color = Colors.green;
    if (utilizationPercent > 0.7) color = Colors.orange;
    if (utilizationPercent > 0.9) color = Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Loan Utilization", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("${(utilizationPercent * 100).toStringAsFixed(0)}%", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: utilizationPercent, backgroundColor: Colors.white, valueColor: AlwaysStoppedAnimation(color), minHeight: 8),
          ),
          const SizedBox(height: 8),
          Text("Max Limit: ₹${NumberFormat('#,##,###').format(maxEligibleAmount)}", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildFilePicker() {
    return InkWell(
      onTap: () async {
        final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
        if (res != null) setState(() => attachment = res.files.first);
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload_outlined, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Text(attachment?.name ?? "Upload Document (PDF/JPG)", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (emiStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select EMI start date")));
      return;
    }
    setState(() => submitting = true);
    try {
      String? fileUrl;
      if (attachment != null) {
        final path = 'loans/${widget.employeeId}/${DateTime.now().millisecondsSinceEpoch}_${attachment!.name}';
        await supabase.storage.from('claim-documents').upload(path, File(attachment!.path!));
        fileUrl = supabase.storage.from('claim-documents').getPublicUrl(path);
      }

      final res = await supabase.from('loans_advances').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'manager_id': widget.managerId,
        'loan_category': category,
        'requested_amount': amount,
        'tenure_months': tenure,
        'emi_start_date': emiStartDate!.toIso8601String(),
        'purpose': purpose,
        'supporting_documents': fileUrl != null ? [{'name': attachment!.name, 'url': fileUrl}] : [],
        'status': 'pending',
        'application_date': DateTime.now().toIso8601String(),
      }).select().single();

      // Initialize Workflow
      await supabase.rpc('initialize_workflow', params: {
        'p_module': 'loans',
        'p_target_id': res['id'],
        'p_org_id': widget.organizationId,
      });

      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  Widget _fieldTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)));
}

// 🟣 EMI Schedule Panel
class EMISchedulePanel extends StatefulWidget {
  final String employeeId;
  const EMISchedulePanel({super.key, required this.employeeId});

  @override
  State<EMISchedulePanel> createState() => _EMISchedulePanelState();
}

class _EMISchedulePanelState extends State<EMISchedulePanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  Map<String, List<dynamic>> schedule = {};

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    setState(() => loading = true);
    try {
      final res = await supabase
          .from('loan_emi_schedule')
          .select('*, loans_advances(loan_number, loan_category)')
          .eq('employee_id', widget.employeeId)
          .order('due_date', ascending: true);
      
      final data = List<Map<String, dynamic>>.from(res);
      
      // Decrypt if needed (though schedule amounts might not be encrypted in user prompt instructions for simple display, but prompt says all amounts)
      // For now grouping by loan
      Map<String, List<dynamic>> grouped = {};
      for (var row in data) {
        final ln = row['loans_advances']?['loan_number'] ?? 'Unknown';
        if (!grouped.containsKey(ln)) grouped[ln] = [];
        grouped[ln]!.add(row);
      }
      
      if (mounted) setState(() => schedule = grouped);
    } catch (e) {
      debugPrint("Error fetching EMI schedule: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (schedule.isEmpty) return Center(child: Text("No EMI schedules found", style: GoogleFonts.montserrat(color: Colors.grey)));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: schedule.entries.map((entry) {
        return ExpansionTile(
          title: Text(entry.key, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(entry.value.first['loans_advances']?['loan_category']?.toString().toUpperCase() ?? '', style: const TextStyle(fontSize: 10)),
          children: entry.value.map((emi) {
            final status = (emi['status'] ?? 'pending').toString().toLowerCase();
            return ListTile(
              dense: true,
              title: Text("EMI #${emi['emi_number']} - ${DateFormat('MMM yyyy').format(DateTime.parse(emi['due_date']))}"),
              subtitle: Text("Outstanding: ₹${NumberFormat('#,##,###').format(emi['outstanding_principal'] ?? 0)}", style: const TextStyle(fontSize: 11)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("₹${NumberFormat('#,##,###').format(emi['emi_amount'] ?? 0)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
                  _statusChip(status),
                ],
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _statusChip(String status) {
    Color color = Colors.orange;
    if (status == 'paid') color = Colors.green;
    return Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold));
  }
}

// 🟠 Loan Approval Panel
class LoanApprovalPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  const LoanApprovalPanel({super.key, required this.userData, required this.onBack});

  @override
  State<LoanApprovalPanel> createState() => _LoanApprovalPanelState();
}

class _LoanApprovalPanelState extends State<LoanApprovalPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> claims = [];

  @override
  void initState() {
    super.initState();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    setState(() => loading = true);
    try {
      final myId = widget.userData['id'];
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
      List<String> teamIds = [];
      if (hierarchy is List) {
        teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      }

      var query = supabase
          .from('loans_advances')
          .select('*, employee_records!loans_advances_employee_id_fkey(full_name, employee_id)')
          .eq('status', 'pending');
      
      if (teamIds.isNotEmpty) {
        query = query.or('manager_id.eq.$myId,employee_id.in.(${teamIds.join(",")})');
      } else {
        query = query.eq('manager_id', myId);
      }

      final res = await query.order('application_date', ascending: false);
      
      var data = List<Map<String, dynamic>>.from(res);
      if (data.isNotEmpty) {
        try {
          final ids = data.map((l) => l['id']).toList();
          final decryptRes = await supabase.functions.invoke('salary-encryption', body: {'action': 'decrypt-batch', 'table': 'loans_advances', 'ids': ids});
          if (decryptRes.data != null) {
            final decryptedMap = {for (var item in decryptRes.data) item['id']: item};
            for (var loan in data) {
              if (decryptedMap.containsKey(loan['id'])) {
                final d = decryptedMap[loan['id']];
                loan['requested_amount'] = d['requested_amount'];
              }
            }
          }
        } catch (de) {
          debugPrint("Decryption error: $de");
        }
      }
      if (mounted) setState(() => claims = data);
    } catch (e) {
      debugPrint("Error fetching loan approvals: $e");
      if (mounted) setState(() => claims = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _processAction(dynamic loan, String action, String comments) async {
    try {
      await supabase.rpc('process_workflow_step', params: {
        'p_module': 'loans',
        'p_target_id': loan['id'],
        'p_action': action,
        'p_actor_id': widget.userData['id'],
        'p_actor_email': widget.userData['email'],
        'p_comments': comments,
      });
      _fetchApprovals();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Action error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: loading 
            ? const Center(child: CircularProgressIndicator())
            : claims.isEmpty 
              ? const Center(child: Text("No pending loan requests"))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: claims.length,
                  itemBuilder: (context, index) {
                    final loan = claims[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(loan['employee_records']?['full_name'] ?? 'Employee', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${loan['loan_category']} • ${loan['tenure_months']} Months"),
                            const SizedBox(height: 4),
                            Text("₹${NumberFormat('#,##,###').format(double.tryParse(loan['requested_amount']?.toString() ?? '0') ?? 0)}", style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.rate_review_outlined, color: Colors.blue),
                          onPressed: () => _showReviewDialog(loan),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showReviewDialog(dynamic loan) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Review Loan Request"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Employee: ${loan['employee_records']?['full_name'] ?? 'Unknown'}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: "Comments...")),
          ],
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _processAction(loan, 'reject', controller.text); }, child: const Text("Reject", style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _processAction(loan, 'approve', controller.text); }, child: const Text("Approve")),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: InkWell(
        onTap: widget.onBack,
        child: Row(children: [const Icon(Icons.arrow_back, size: 18), const SizedBox(width: 8), Text("Back", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold))]),
      ),
    );
  }
}

// ⚪ All Loans Panel (Admin)
class AllLoansPanel extends StatefulWidget {
  final String organizationId;
  const AllLoansPanel({super.key, required this.organizationId});

  @override
  State<AllLoansPanel> createState() => _AllLoansPanelState();
}

class _AllLoansPanelState extends State<AllLoansPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> loans = [];

  @override
  void initState() {
    super.initState();
    _fetchAllLoans();
  }

  Future<void> _fetchAllLoans() async {
    setState(() => loading = true);
    try {
      final res = await supabase
          .from('loans_advances')
          .select('*, employee_records!loans_advances_employee_id_fkey(full_name, employee_id)')
          .eq('organization_id', widget.organizationId)
          .order('application_date', ascending: false);
      
      var data = List<Map<String, dynamic>>.from(res);
      if (data.isNotEmpty) {
        final ids = data.map((l) => l['id']).toList();
        final decryptRes = await supabase.functions.invoke('salary-encryption', body: {'action': 'decrypt-batch', 'table': 'loans_advances', 'ids': ids});
        if (decryptRes.data != null) {
          final decryptedMap = {for (var item in decryptRes.data) item['id']: item};
          for (var loan in data) {
            if (decryptedMap.containsKey(loan['id'])) {
              final d = decryptedMap[loan['id']];
              loan['requested_amount'] = d['requested_amount'];
            }
          }
        }
      }
      if (mounted) setState(() => loans = data);
    } catch (e) {
      debugPrint("Error fetching all loans: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: loans.length,
      itemBuilder: (context, index) {
        final loan = loans[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(loan['employee_records']?['full_name'] ?? 'Unknown', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
            subtitle: Text("${loan['loan_number']} • ${loan['status']?.toUpperCase()}"),
            trailing: Text("₹${NumberFormat('#,##,###').format(double.tryParse(loan['requested_amount']?.toString() ?? '0') ?? 0)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}

// 🟢 HR Loan Submission Panel
class HRLoanSubmissionPanel extends StatefulWidget {
  final String organizationId;
  final VoidCallback onSuccess;
  const HRLoanSubmissionPanel({super.key, required this.organizationId, required this.onSuccess});

  @override
  State<HRLoanSubmissionPanel> createState() => _HRLoanSubmissionPanelState();
}

class _HRLoanSubmissionPanelState extends State<HRLoanSubmissionPanel> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  List<dynamic> employees = [];
  String? selectedEmployeeId;
  String? category = 'personal_loan';
  double? amount;
  int tenure = 12;
  String? purpose;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final res = await supabase.from('employee_records').select('id, full_name, employee_id').eq('organization_id', widget.organizationId).order('full_name');
      if (mounted) setState(() => employees = res);
    } catch (e) {
      debugPrint("Error fetching employees: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Submit a loan request on behalf of an employee.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            _fieldTitle("Select Employee"),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: selectedEmployeeId,
              items: employees.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text("${e['full_name']} (${e['employee_id']})"))).toList(),
              onChanged: (v) => setState(() => selectedEmployeeId = v),
              decoration: _inputDecoration(),
              validator: (v) => v == null ? "Required" : null,
            ),
            const SizedBox(height: 16),
            _fieldTitle("Loan Category"),
            DropdownButtonFormField<String>(
              value: category,
              items: ['personal_loan', 'salary_advance', 'emergency_loan', 'education_loan', 'vehicle_loan', 'travel_advance']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.replaceAll('_', ' ').toUpperCase()))).toList(),
              onChanged: (v) => setState(() => category = v),
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 16),
            _fieldTitle("Requested Amount (₹)"),
            TextFormField(
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(hint: "Enter amount"),
              onChanged: (v) => amount = double.tryParse(v),
              validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? "Invalid amount" : null,
            ),
            const SizedBox(height: 16),
            _fieldTitle("Tenure (Months)"),
            DropdownButtonFormField<int>(
              value: tenure,
              items: [3, 6, 12, 24].map((e) => DropdownMenuItem(value: e, child: Text("$e Months"))).toList(),
              onChanged: (v) => setState(() => tenure = v!),
              decoration: _inputDecoration(),
            ),
            const SizedBox(height: 16),
            _fieldTitle("Purpose"),
            TextFormField(
              maxLines: 3,
              decoration: _inputDecoration(hint: "Reason for loan..."),
              onChanged: (v) => purpose = v,
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF219653),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit HR Application", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final res = await supabase.from('loans_advances').insert({
        'employee_id': selectedEmployeeId,
        'organization_id': widget.organizationId,
        'loan_category': category,
        'requested_amount': amount,
        'tenure_months': tenure,
        'purpose': purpose,
        'status': 'pending',
        'is_hr_submission': true,
        'submitted_by': supabase.auth.currentUser!.id,
        'application_date': DateTime.now().toIso8601String(),
      }).select().single();

      await supabase.rpc('initialize_workflow', params: {
        'p_module': 'loans',
        'p_target_id': res['id'],
        'p_org_id': widget.organizationId,
      });

      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  Widget _fieldTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)));
}
