import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ReviewerLeavesView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const ReviewerLeavesView({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<ReviewerLeavesView> createState() => _ReviewerLeavesViewState();
}

class _ReviewerLeavesViewState extends State<ReviewerLeavesView> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool loading = true;
  String searchQuery = "";
  List<String> allTeamMemberIds = [];
  List<dynamic> allRequests = [];
  String? fetchError;
  Map<String, dynamic>? managerProfile;
  
  int pendingCount = 0;
  int approvedCount = 0;
  int rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    if (!mounted) return;
    setState(() {
      loading = true;
      fetchError = null;
    });
    
    try {
      await _ensureManagerProfile();
      if (managerProfile != null) {
        await _fetchTeamScope();
        if (allTeamMemberIds.isNotEmpty) {
          await _fetchCounts();
          await _fetchRequests();
        } else {
          if (mounted) {
            setState(() {
              pendingCount = 0;
              approvedCount = 0;
              rejectedCount = 0;
              allRequests = [];
            });
          }
        }
      } else {
        if (mounted) setState(() => fetchError = "Could not identify manager profile.");
      }
    } catch (e) {
      debugPrint("Workflow Init Error: $e");
      if (mounted) setState(() => fetchError = e.toString());
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

    try {
      final res = await supabase.from('employee_records').select().eq('email', email).maybeSingle();
      if (res != null) {
        managerProfile = res;
      }
    } catch (e) {
      debugPrint("Error fetching manager profile: $e");
    }
  }

  Future<void> _fetchTeamScope() async {
    if (managerProfile == null) return;
    
    final myId = managerProfile!['id'];
    final role = managerProfile!['emp_role'] ?? 'manager';
    final orgId = managerProfile!['organization_id'];

    if (role == 'hr_head' || role == 'admin' || role == 'hr_manager' || role == 'super_admin') {
      final res = await supabase.from('employee_records').select('id').eq('organization_id', orgId).eq('status', 'active');
      allTeamMemberIds = (res as List).map((e) => e['id'].toString()).toList();
      return;
    }

    try {
      final basicReports = await supabase
          .from('employee_records')
          .select('id')
          .or('manager_id.eq.$myId,secondary_manager_id.eq.$myId,reviewer_id.eq.$myId')
          .eq('status', 'active');

      final Set<String> ids = (basicReports as List).map((e) => e['id'].toString()).toSet();

      final reviewerManaged = await supabase
          .from('employee_records')
          .select('id')
          .eq('reviewer_id', myId)
          .eq('status', 'active');
      
      final reviewerManagedIds = (reviewerManaged as List).map((e) => e['id'].toString()).toList();
      
      if (reviewerManagedIds.isNotEmpty) {
        final subReports = await supabase
            .from('employee_records')
            .select('id')
            .inFilter('manager_id', reviewerManagedIds)
            .eq('status', 'active');
        for (var item in (subReports as List)) { ids.add(item['id'].toString()); }
      }

      try {
        final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
        if (hierarchy is List) {
          for (var item in hierarchy) {
            if (item is Map) ids.add(item['id'].toString());
            else ids.add(item.toString());
          }
        }
      } catch (_) {}

      allTeamMemberIds = ids.toList();
    } catch (e) {
      debugPrint("Team Scope Error: $e");
      allTeamMemberIds = [];
    }
  }

  Future<void> _fetchCounts() async {
    if (allTeamMemberIds.isEmpty) return;
    final role = managerProfile!['emp_role'] ?? 'manager';
    final isHR = (role == 'hr_head' || role == 'admin' || role == 'hr_manager' || role == 'super_admin');

    try {
      final approvedStatuses = isHR 
          ? ['reviewer_approved', 'approved'] 
          : ['manager_approved', 'reviewer_approved', 'approved'];

      final results = await Future.wait([
        supabase.from('leave_applications').select('id').inFilter('employee_id', allTeamMemberIds).eq('status', 'pending'),
        supabase.from('leave_applications').select('id').inFilter('employee_id', allTeamMemberIds).inFilter('status', approvedStatuses),
        supabase.from('leave_applications').select('id').inFilter('employee_id', allTeamMemberIds).inFilter('status', ['rejected', 'reviewer_rejected']),
      ]);

      if (mounted) {
        setState(() {
          pendingCount = (results[0] as List).length;
          approvedCount = (results[1] as List).length;
          rejectedCount = (results[2] as List).length;
        });
      }
    } catch (e) {
      debugPrint("Error fetching counts: $e");
    }
  }

  Future<void> _fetchRequests() async {
    if (allTeamMemberIds.isEmpty) return;

    try {
      // Robust join syntax for disambiguating multiple FKs to employee_records
      final res = await supabase
          .from('leave_applications')
          .select('*, applicant:employee_id(full_name, employee_id, designation, department), manager:manager_id(full_name), approver:approved_by(full_name)')
          .inFilter('employee_id', allTeamMemberIds)
          .order('created_at', ascending: false);
      
      if (mounted) setState(() => allRequests = res);
    } catch (e) {
      debugPrint("Join query failed, trying fallback: $e");
      try {
        final fallback = await supabase
            .from('leave_applications')
            .select('*, employee_records!employee_id(full_name, employee_id, designation, department)')
            .inFilter('employee_id', allTeamMemberIds)
            .order('created_at', ascending: false);
        if (mounted) setState(() => allRequests = fallback);
      } catch (innerE) {
        if (mounted) setState(() => fetchError = "Data fetch failed: $innerE");
      }
    }
  }

  List<dynamic> _getFilteredRequests() {
    String statusFilter = 'pending';
    if (_tabController.index == 1) statusFilter = 'approved';
    if (_tabController.index == 2) statusFilter = 'rejected';

    final role = managerProfile!['emp_role'] ?? 'manager';
    final isHR = (role == 'hr_head' || role == 'admin' || role == 'hr_manager' || role == 'super_admin');

    final filteredByStatus = allRequests.where((r) {
      final s = r['status'];
      if (statusFilter == 'pending') return s == 'pending';
      if (statusFilter == 'approved') {
        final approvedStatuses = isHR ? ['reviewer_approved', 'approved'] : ['manager_approved', 'reviewer_approved', 'approved'];
        return approvedStatuses.contains(s);
      }
      if (statusFilter == 'rejected') return s == 'rejected' || s == 'reviewer_rejected';
      return false;
    }).toList();

    if (searchQuery.isEmpty) return filteredByStatus;

    return filteredByStatus.where((r) {
      final emp = (r['applicant'] ?? r['employee_records']) ?? {};
      final name = (emp['full_name'] ?? '').toString().toLowerCase();
      final code = (emp['employee_id'] ?? '').toString().toLowerCase();
      final q = searchQuery.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  Future<void> handleReviewAction(dynamic request, String action, String comments) async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];
    
    Map<String, dynamic> updatePayload = {
      'updated_at': DateTime.now().toIso8601String(),
      'manager_comments': comments,
      'approved_at': DateTime.now().toIso8601String(),
      'approved_by': myId,
      'status': action == 'approve' ? 'manager_approved' : 'rejected',
    };

    try {
      await supabase.from('leave_applications').update(updatePayload).eq('id', request['id']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Action completed successfully.")));
      _initWorkflow();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
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
          Expanded(child: Center(child: Text("Error: $fetchError", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))))
        else ...[
          _buildKPIs(),
          _buildTabs(),
          _buildSearchBox(),
          Expanded(child: _buildList()),
        ]
      ],
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? "GOOD MORNING" : now.hour < 17 ? "GOOD AFTERNOON" : "GOOD EVENING";
    final firstName = (managerProfile?['full_name'] ?? widget.userData['full_name'] ?? 'MANAGER').toString().split(' ')[0].toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$greeting, $firstName — ${DateFormat('EEEE, d MMM').format(now).toUpperCase()} — $pendingCount REQUESTS PENDING", style: GoogleFonts.montserrat(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
          const SizedBox(height: 10),
          RichText(text: TextSpan(style: GoogleFonts.montserrat(fontSize: 22, color: Colors.black, fontWeight: FontWeight.bold), children: [const TextSpan(text: "Decisions "), TextSpan(text: "waiting on you", style: TextStyle(color: Colors.blue.shade600))])),
          const SizedBox(height: 16),
          InkWell(onTap: widget.onBack, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.arrow_back, size: 14, color: Colors.blue), const SizedBox(width: 4), Text("Back to inbox", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600))])),
        ],
      ),
    );
  }

  Widget _buildKPIs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 24) / 3;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _kpiCard("Pending", pendingCount, Colors.blue, Icons.access_time, cardWidth),
            _kpiCard("Approved", approvedCount, Colors.green, Icons.check_circle_outline, cardWidth),
            _kpiCard("Rejected", rejectedCount, Colors.red, Icons.cancel_outlined, cardWidth),
          ],
        );
      }),
    );
  }

  Widget _kpiCard(String label, int count, Color color, IconData icon, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(label, style: GoogleFonts.montserrat(fontSize: 7, color: Colors.grey.shade600, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)), Icon(icon, size: 10, color: color.withOpacity(0.4))]),
          const SizedBox(height: 4),
          Text("$count", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
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
        labelStyle: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold),
        tabs: [Tab(text: "Pending ($pendingCount)"), Tab(text: "Approved ($approvedCount)"), Tab(text: "Rejected ($rejectedCount)")],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        onChanged: (v) => setState(() => searchQuery = v),
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: "Search employee...",
          hintStyle: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey.shade400),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue.shade200)),
        ),
      ),
    );
  }

  Widget _buildList() {
    final list = _getFilteredRequests();
    if (list.isEmpty) return Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text("No requests found", style: GoogleFonts.montserrat(color: Colors.grey.shade400, fontSize: 12))));
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _RequestCard(request: list[index], currentTab: _tabController.index, onReview: (action, comments) => handleReviewAction(list[index], action, comments)),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final dynamic request;
  final int currentTab;
  final Function(String, String) onReview;
  const _RequestCard({required this.request, required this.currentTab, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final emp = (request['applicant'] ?? request['employee_records']) ?? {};
    final status = request['status'] ?? 'pending';
    final manager = request['manager'] ?? {};
    final approver = request['approver'] ?? {};
    final lTypeName = request['type']?['name'] ?? request['leave_type'] ?? '-';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 18, backgroundColor: Colors.blue.shade50, child: Text(emp['full_name']?[0] ?? '?', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(emp['full_name'] ?? 'Unknown', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Text(emp['employee_id'] ?? '', style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                        ]),
                        Text("${emp['designation'] ?? ''} · ${emp['department'] ?? ''}", style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black54)),
                      ]),
                    ),
                    _buildStatusPill(status),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  _detailBlock("Leave Type", lTypeName),
                  _detailBlock("From", _formatDate(request['from_date'])),
                  _detailBlock("To", _formatDate(request['to_date'])),
                  _detailBlock("Days", "${request['total_days']} day(s)"),
                ]),
                const SizedBox(height: 12),
                _detailBlock("Reason", request['reason'] ?? 'No reason provided'),
                const Divider(height: 24),
                _detailBlock("Reporting Manager", manager['full_name'] ?? 'Not Assigned'),
                if (status.contains('approved')) ...[const SizedBox(height: 12), _infoBlock("Approved by ${approver['full_name'] ?? 'Approver'}", request, Colors.green)]
                else if (status.contains('rejected')) ...[const SizedBox(height: 12), _infoBlock("Rejection Reason", request, Colors.red)],
              ],
            ),
          ),
          if (currentTab == 0)
            InkWell(
              onTap: () => _showReviewDialog(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.assignment_turned_in_outlined, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text("Review Request", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoBlock(String label, dynamic r, Color color) {
    final comments = r['reviewer_comments'] ?? r['manager_comments'] ?? 'No comments provided';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(comments, style: GoogleFonts.montserrat(fontSize: 11, color: color.withOpacity(0.8))),
      ]),
    );
  }

  Widget _detailBlock(String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(val, style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
    ]);
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('dd MMM').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  Widget _buildStatusPill(String status) {
    Color color = status.contains('approved') ? Colors.green : (status.contains('rejected') ? Colors.red : Colors.orange);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(6)), child: Text(status.replaceAll('_', ' ').toUpperCase(), style: GoogleFonts.montserrat(color: color, fontSize: 8, fontWeight: FontWeight.bold)));
  }

  void _showReviewDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Review Leave Request", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Comments", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: controller, maxLines: 3, decoration: InputDecoration(hintText: "Enter decision comments...", hintStyle: GoogleFonts.montserrat(fontSize: 12), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
        ]),
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () { Navigator.pop(ctx); onReview('reject', controller.text); }, 
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red, 
                  side: const BorderSide(color: Colors.red), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
