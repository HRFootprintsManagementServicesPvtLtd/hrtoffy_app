import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class BenefitApprovalPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const BenefitApprovalPanel({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<BenefitApprovalPanel> createState() => _BenefitApprovalPanelState();
}

class _BenefitApprovalPanelState extends State<BenefitApprovalPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> claims = [];
  String? fetchError;
  Map<String, dynamic>? managerProfile;
  List<String> teamMemberIds = [];

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
        await _fetchTeamScope();
        await _fetchClaims();
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

  Future<void> _fetchTeamScope() async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      // STEP 2: Use full hierarchy RPC
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
      if (hierarchy is List) {
        teamMemberIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      } else {
        teamMemberIds = [myId.toString()];
      }
    } catch (e) {
      debugPrint("Hierarchy RPC Error: $e");
      teamMemberIds = [myId.toString()];
    }
  }

  Future<void> _fetchClaims() async {
    if (teamMemberIds.isEmpty) return;

    try {
      // STEP 3: Fetch benefit_claims with joins
      final res = await supabase
          .from('benefit_claims')
          .select('''
            *,
            employee:employee_id (full_name, employee_id),
            catalog:benefit_id (benefit_name)
          ''')
          .inFilter('employee_id', teamMemberIds)
          .inFilter('status', ['pending', 'approved', 'rejected'])
          .order('created_at', ascending: false);

      if (mounted) setState(() => claims = res);
    } catch (e) {
      debugPrint("Fetch Benefit Claims Error: $e");
      if (mounted) setState(() => fetchError = "Data fetch failed: $e");
    }
  }

  Future<void> handleAction(dynamic claim, String action, String comments) async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      final status = action == 'approve' ? 'approved' : 'rejected';
      
      await supabase.from('benefit_claims').update({
        'status': status,
        'manager_comments': comments,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', claim['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Benefit Claim ${action == 'approve' ? 'Approved' : 'Rejected'}")),
        );
      }
      _fetchClaims();
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
          InkWell(
            onTap: widget.onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Text("Back to inbox", style: GoogleFonts.montserrat(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Benefit Claims — Reimbursement claims under benefit policies.",
            style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    if (claims.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text("No benefit claims found", style: GoogleFonts.montserrat(color: Colors.grey.shade400, fontSize: 13))));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 50,
          dataRowMaxHeight: 70,
          horizontalMargin: 20,
          columnSpacing: 24,
          columns: [
            DataColumn(label: _headerText("Employee")),
            DataColumn(label: _headerText("Benefit")),
            DataColumn(label: _headerText("Amount")),
            DataColumn(label: _headerText("Status")),
            DataColumn(label: _headerText("Actions")),
          ],
          rows: claims.map((claim) {
            final emp = claim['employee'] ?? {};
            final catalog = claim['catalog'] ?? {};
            final status = (claim['status'] ?? 'pending').toString().toLowerCase();

            return DataRow(cells: [
              DataCell(Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp['full_name'] ?? 'Unknown', style: _cellStyle(isBold: true)),
                  Text(emp['employee_id'] ?? '', style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                ],
              )),
              DataCell(Text(catalog['benefit_name'] ?? '-', style: _cellStyle())),
              DataCell(Text("₹${NumberFormat('#,##,###').format(claim['claimed_amount'] ?? 0)}", style: _cellStyle(isBold: true))),
              DataCell(_buildStatusBadge(status)),
              DataCell(
                IconButton(
                  icon: Icon(
                    status == 'pending' ? Icons.rate_review_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: Colors.blue.shade700,
                  ),
                  onPressed: () => status == 'pending' ? _showReviewDialog(claim) : _showViewDialog(claim),
                ),
              ),
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

  Widget _buildStatusBadge(String status) {
    Color color = Colors.orange;
    if (status == 'approved') color = Colors.green;
    if (status == 'rejected') color = Colors.red;

    return Text(
      status.toUpperCase(),
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: color,
        decoration: TextDecoration.underline,
      ),
    );
  }

  void _showReviewDialog(dynamic claim) {
    final controller = TextEditingController();
    final emp = claim['employee'] ?? {};
    final catalog = claim['catalog'] ?? {};
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Review Benefit Claim", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Employee: ${emp['full_name']}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text("Benefit: ${catalog['benefit_name']}", style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Text("Claim Date: ${DateFormat('dd MMM yyyy').format(DateTime.parse(claim['claim_date']))}", style: const TextStyle(fontSize: 12)),
            Text("Amount: ₹${claim['claimed_amount']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("Description: ${claim['description'] ?? '-'}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Decision comments...",
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
                  onPressed: () { Navigator.pop(ctx); handleAction(claim, 'reject', controller.text); },
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
                  onPressed: () { Navigator.pop(ctx); handleAction(claim, 'approve', controller.text); },
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

  void _showViewDialog(dynamic claim) {
    final emp = claim['employee'] ?? {};
    final catalog = claim['catalog'] ?? {};
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Claim Details", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row("Employee", emp['full_name']),
            _row("Benefit", catalog['benefit_name']),
            _row("Amount", "₹${claim['claimed_amount']}"),
            _row("Status", claim['status']?.toUpperCase() ?? '-'),
            if (claim['manager_comments'] != null) _row("Manager Comments", claim['manager_comments']),
            if (claim['description'] != null) _row("Employee Notes", claim['description']),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  Widget _row(String label, String? val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
          Text(val ?? '-', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }
}
