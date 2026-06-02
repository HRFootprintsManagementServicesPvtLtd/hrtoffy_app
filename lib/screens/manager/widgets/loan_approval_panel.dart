import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class LoanApprovalPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const LoanApprovalPanel({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<LoanApprovalPanel> createState() => _LoanApprovalPanelState();
}

class _LoanApprovalPanelState extends State<LoanApprovalPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> loans = [];
  String? fetchError;
  Map<String, dynamic>? managerProfile;
  List<String> scopedEmployeeIds = [];

  @override
  void initState() {
    super.initState();
    _initWorkflow();
  }

  Future<void> _initWorkflow() async {
    setState(() => loading = true);
    try {
      await _ensureManagerProfile();
      if (managerProfile != null) {
        await _buildScope();
        await _fetchLoans();
      } else {
        setState(() => fetchError = "Could not identify manager profile.");
      }
    } catch (e) {
      setState(() => fetchError = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _ensureManagerProfile() async {
    if (widget.userData.containsKey('id') && widget.userData['id'] != null) {
      managerProfile = widget.userData;
      return;
    }
    final email = supabase.auth.currentUser?.email;
    if (email == null) return;
    final res = await supabase.from('employee_records').select().eq('email', email).maybeSingle();
    if (res != null) managerProfile = res;
  }

  Future<void> _buildScope() async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];
    final role = (managerProfile!['emp_role'] ?? 'manager').toString().toLowerCase();
    final orgId = managerProfile!['organization_id'];

    final hrRoles = ['hr', 'hr_manager', 'hr_head', 'admin', 'super_admin'];
    
    if (hrRoles.contains(role)) {
      // HR roles scope to org
      final res = await supabase.from('employee_records').select('id').eq('organization_id', orgId).eq('status', 'active');
      scopedEmployeeIds = (res as List).map((e) => e['id'].toString()).toList();
    } else if (role == 'reviewer') {
      // Reviewer logic: reviewer_id = myId -> get managers -> get their reports
      final managers = await supabase.from('employee_records').select('id').eq('reviewer_id', myId).eq('status', 'active');
      final managerIds = (managers as List).map((e) => e['id'].toString()).toList();
      if (managerIds.isNotEmpty) {
        final reports = await supabase.from('employee_records').select('id').inFilter('manager_id', managerIds).eq('status', 'active');
        scopedEmployeeIds = (reports as List).map((e) => e['id'].toString()).toList();
      }
    } else {
      // Basic manager: direct reports only as per workflow description
      final res = await supabase.from('employee_records').select('id').eq('manager_id', myId).eq('status', 'active');
      scopedEmployeeIds = (res as List).map((e) => e['id'].toString()).toList();
    }
  }

  Future<void> _fetchLoans() async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      // STEP 3: Fetch from loans_advances
      final query = supabase
          .from('loans_advances')
          .select('*, applicant:employee_id(full_name, employee_id, department, salary)')
          .or('manager_id.eq.$myId,employee_id.in.(${scopedEmployeeIds.join(',')})')
          .order('application_date', ascending: false);

      final res = await query;
      if (mounted) setState(() => loans = res);
    } catch (e) {
      debugPrint("Fetch Loans Error: $e");
      if (mounted) setState(() => fetchError = e.toString());
    }
  }

  Future<void> handleAction(dynamic loan, String action, String comments) async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      // Simplified workflow action for mobile
      // In web it calls processWorkflowAction which syncs to status
      final status = action == 'approve' ? 'approved' : 'rejected';
      
      await supabase.from('loans_advances').update({
        'status': status,
        'manager_comments': comments,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', loan['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Loan ${action == 'approve' ? 'Approved' : 'Rejected'}")),
        );
      }
      _fetchLoans();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (fetchError != null)
          Expanded(child: Center(child: Text("Error: $fetchError", style: const TextStyle(color: Colors.red))))
        else
          Expanded(child: _buildPanel()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: widget.onBack,
                child: const Icon(Icons.arrow_back, size: 20, color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Text("Back to inbox", style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text("Salary/amount information is restricted", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    if (loans.isEmpty) {
      return Center(child: Text("No loan requests found", style: GoogleFonts.montserrat(color: Colors.grey)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 40,
          dataRowMaxHeight: 60,
          horizontalMargin: 20,
          columnSpacing: 24,
          columns: [
            DataColumn(label: _headerText("Loan #")),
            DataColumn(label: _headerText("Employee")),
            DataColumn(label: _headerText("Category")),
            DataColumn(label: _headerText("Amount")),
            DataColumn(label: _headerText("Tenure")),
            DataColumn(label: _headerText("Status")),
            DataColumn(label: _headerText("Actions")),
          ],
          rows: loans.map((loan) {
            final emp = loan['applicant'] ?? {};
            return DataRow(cells: [
              DataCell(Text(loan['loan_number'] ?? '-', style: _cellStyle(isBold: true))),
              DataCell(Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp['full_name'] ?? 'Unknown', style: _cellStyle(isBold: true)),
                  Text(emp['employee_id'] ?? '', style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey)),
                ],
              )),
              DataCell(Text(loan['loan_category'] ?? '-', style: _cellStyle())),
              DataCell(Text("₹ ---", style: _cellStyle())), // Masked as per requirement
              DataCell(Text("${loan['tenure_months'] ?? '-'} months", style: _cellStyle())),
              DataCell(_buildStatusBadge(loan['status'])),
              DataCell(TextButton(
                onPressed: () => _showReviewDialog(loan),
                child: Text("Review", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _headerText(String label) {
    return Text(label, style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600));
  }

  TextStyle _cellStyle({bool isBold = false}) {
    return GoogleFonts.montserrat(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: Colors.black87);
  }

  Widget _buildStatusBadge(String? status) {
    final s = (status ?? 'pending').toLowerCase();
    Color color = Colors.orange;
    if (s == 'approved') color = Colors.green;
    if (s == 'rejected') color = Colors.red;

    return Text(
      s,
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: color,
        decoration: TextDecoration.underline,
      ),
    );
  }

  void _showReviewDialog(dynamic loan) {
    final controller = TextEditingController();
    final emp = loan['applicant'] ?? {};
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Review Loan Request", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Employee: ${emp['full_name']}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Category: ${loan['loan_category']}", style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Text("Reason: ${loan['reason'] ?? '-'}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Enter your comments here...",
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () { Navigator.pop(ctx); handleAction(loan, 'reject', controller.text); },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red, 
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); handleAction(loan, 'approve', controller.text); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, 
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
