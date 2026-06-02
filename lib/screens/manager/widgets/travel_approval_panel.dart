import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TravelApprovalPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const TravelApprovalPanel({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<TravelApprovalPanel> createState() => _TravelApprovalPanelState();
}

class _TravelApprovalPanelState extends State<TravelApprovalPanel> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool loading = true;
  List<dynamic> allPendingClaims = [];
  List<dynamic> actionableClaims = [];
  String? fetchError;
  Map<String, dynamic>? managerProfile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _initWorkflow();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initWorkflow() async {
    setState(() => loading = true);
    try {
      await _ensureManagerProfile();
      if (managerProfile != null) {
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

  Future<void> _fetchClaims() async {
    final orgId = managerProfile!['organization_id'];
    final myId = managerProfile!['id'];
    final role = (managerProfile!['emp_role'] ?? 'manager').toString().toLowerCase();
    final bool isHR = ['hr', 'hr_manager', 'hr_head', 'admin', 'super_admin'].contains(role);

    try {
      // STEP 2: Fetch all pending claims in org
      final res = await supabase
          .from('travel_claims')
          .select('*, employee:employee_id(full_name, employee_id, designation)')
          .eq('status', 'pending')
          .eq('organization_id', orgId)
          .order('created_at', ascending: false);

      final List<dynamic> claimsList = res as List<dynamic>;

      // For each claim, fetch expenses (Step 4)
      for (var claim in claimsList) {
        final expensesRes = await supabase
            .from('travel_expenses')
            .select()
            .eq('claim_id', claim['id'])
            .order('expense_date', ascending: true);
        claim['expenses'] = expensesRes;
      }

      // STEP 5: Filter for actionable
      // In a real scenario, this would check workflow_executions
      // For now, we simulate by checking if current manager is the designated approver
      List<dynamic> actionable = [];
      if (isHR) {
        actionable = claimsList;
      } else {
        actionable = claimsList.where((c) => c['manager_id'] == myId).toList();
      }

      if (mounted) {
        setState(() {
          allPendingClaims = claimsList;
          actionableClaims = actionable;
        });
      }
    } catch (e) {
      debugPrint("Fetch Travel Claims Error: $e");
      if (mounted) setState(() => fetchError = e.toString());
    }
  }

  Future<void> handleAction(dynamic claim, String action, String comments) async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      // Final status for mobile simplified flow
      final status = action == 'approve' ? 'approved' : 'rejected';
      
      await supabase.from('travel_claims').update({
        'status': status,
        'manager_comments': comments,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', claim['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Claim ${action == 'approve' ? 'Approved' : 'Rejected'}")),
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
        _buildTabs(),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (fetchError != null)
          Expanded(child: Center(child: Text("Error: $fetchError", style: const TextStyle(color: Colors.red))))
        else
          Expanded(child: _buildList()),
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
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(10)),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold),
        tabs: [
          const Tab(text: "Needs My Action"),
          Tab(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("All Pending"),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: Text("${allPendingClaims.length}", style: const TextStyle(fontSize: 10)),
              )
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildList() {
    final list = _tabController.index == 0 ? actionableClaims : allPendingClaims;
    
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            _tabController.index == 0 
              ? "No claims require your action at this time." 
              : "No pending travel claims found.",
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _TravelClaimCard(
        claim: list[index],
        isActionable: actionableClaims.any((c) => c['id'] == list[index]['id']),
        onReview: (action, comments) => handleAction(list[index], action, comments),
      ),
    );
  }
}

class _TravelClaimCard extends StatelessWidget {
  final dynamic claim;
  final bool isActionable;
  final Function(String, String) onReview;

  const _TravelClaimCard({required this.claim, required this.isActionable, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final emp = claim['employee'] ?? {};
    final expenses = (claim['expenses'] ?? []) as List<dynamic>;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(claim['claim_number'] ?? 'TCL-0000', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
                    _buildStatusBadge('PENDING'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(radius: 14, backgroundColor: Colors.blue.shade50, child: const Icon(Icons.person, size: 14, color: Colors.blue)),
                    const SizedBox(width: 8),
                    Text(emp['full_name'] ?? 'Unknown', style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(" • ${emp['designation'] ?? ''}", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoCell(Icons.location_on_outlined, "Destination", claim['trip_destination'] ?? '-'),
                    _infoCell(Icons.calendar_today_outlined, "Travel Dates", "${_formatDate(claim['trip_from_date'])} - ${_formatDate(claim['trip_to_date'])}"),
                    _infoCell(Icons.currency_rupee, "Total Amount", "₹${claim['total_amount']}"),
                  ],
                ),
                const SizedBox(height: 20),
                Text("Trip Purpose", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(claim['trip_purpose'] ?? '-', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black87)),
                
                if (expenses.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text("Expense Breakdown", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),
                  ...expenses.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(child: Text("${e['expense_type']} • ${_formatDate(e['expense_date'])}", style: GoogleFonts.montserrat(fontSize: 12))),
                        Text("₹${e['amount']}", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
          if (isActionable)
            InkWell(
              onTap: () => _showReviewDialog(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.assignment_turned_in_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text("Review Request", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
              child: Text("Not assigned to you at this workflow step", textAlign: TextAlign.center, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _infoCell(IconData icon, String label, String val) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 12, color: Colors.grey), const SizedBox(width: 4), Text(label, style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600))]),
          const SizedBox(height: 4),
          Text(val, style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('d MMM').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: GoogleFonts.montserrat(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  void _showReviewDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Review Travel Claim", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Claim: ${claim['claim_number']}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: controller, maxLines: 3, decoration: InputDecoration(hintText: "Enter your comments here...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ],
        ),
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () { Navigator.pop(ctx); onReview('reject', controller.text); }, 
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
                onPressed: () { Navigator.pop(ctx); onReview('approve', controller.text); }, 
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
          ]),
        ],
      ),
    );
  }
}
