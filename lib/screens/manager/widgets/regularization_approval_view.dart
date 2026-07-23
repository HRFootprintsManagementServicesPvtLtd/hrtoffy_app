import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class RegularizationApprovalView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const RegularizationApprovalView({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<RegularizationApprovalView> createState() => _RegularizationApprovalViewState();
}

class _RegularizationApprovalViewState extends State<RegularizationApprovalView> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool loading = true;
  List<String> teamMemberIds = [];
  List<dynamic> requests = [];
  String? fetchError;
  Map<String, dynamic>? managerProfile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _fetchData();
      }
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
    setState(() => loading = true);
    try {
      await _ensureManagerProfile();
      if (managerProfile != null) {
        await _fetchTeamScope();
        await _fetchData();
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
    final role = (managerProfile!['emp_role'] ?? 'manager').toString().toLowerCase();
    final isHR = ['hr_head', 'hr_manager', 'admin', 'super_admin'].contains(role);

    if (isHR) {
      teamMemberIds = []; 
    } else {
      try {
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
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => loading = true);
    
    final isHistory = _tabController.index == 1;
    final orgId = managerProfile!['organization_id'];

    try {
      dynamic query = supabase
          .from('attendance_regularization_requests')
          .select('*, applicant:employee_id(full_name, employee_id, department)');

      if (isHistory) {
        query = query.eq('organization_id', orgId).inFilter('status', ['approved', 'rejected']).limit(50).order('updated_at', ascending: false);
      } else {
        query = query.eq('status', 'pending');
        if (teamMemberIds.isNotEmpty) {
          query = query.inFilter('employee_id', teamMemberIds);
        } else {
          query = query.eq('organization_id', orgId);
        }
        query = query.order('created_at', ascending: false);
      }

      final res = await query;
      if (mounted) setState(() => requests = res);
    } catch (e) {
      debugPrint("Fetch Data Error: $e");
      if (mounted) setState(() => fetchError = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> handleAction(dynamic request, String action, String comments) async {
    if (managerProfile == null) return;
    final isApprove = action == 'approve';

    try {
      double hoursWorked = 0;
      final reqDate = request['date'];
      
      String? punchInFull;
      String? punchOutFull;
      
      if (request['requested_punch_in'] != null) {
        punchInFull = "$reqDate ${request['requested_punch_in']}";
      }
      if (request['requested_punch_out'] != null) {
        punchOutFull = "$reqDate ${request['requested_punch_out']}";
      }

      if (isApprove && punchInFull != null && punchOutFull != null) {
        try {
          final start = DateTime.parse(punchInFull);
          final end = DateTime.parse(punchOutFull);
          hoursWorked = end.difference(start).inMinutes / 60.0;
        } catch (_) {}
      }
      await supabase.from('attendance_regularization_requests').update({
        'status': isApprove ? 'approved' : 'rejected',
        'manager_comments': comments,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', request['id']);

      if (isApprove) {
        final attendanceData = {
          'employee_id': request['employee_id'],
          'organization_id': request['organization_id'],
          'date': reqDate,
          'punch_in_time': punchInFull != null ? DateTime.parse(punchInFull).toUtc().toIso8601String() : null,
          'punch_out_time': punchOutFull != null ? DateTime.parse(punchOutFull).toUtc().toIso8601String() : null,
          'check_in_time': punchInFull != null ? DateTime.parse(punchInFull).toUtc().toIso8601String() : null,
          'check_out_time': punchOutFull != null ? DateTime.parse(punchOutFull).toUtc().toIso8601String() : null,
          'hours_worked': hoursWorked,
          'actual_working_hours': hoursWorked,
          'total_hours': hoursWorked,
          'status': 'present',
          'is_override': true,
          'override_reason': request['reason'],
          'override_at': DateTime.now().toUtc().toIso8601String(),
          'comments': "Regularized: $comments",
        };

        await supabase.from('attendance').upsert(
          attendanceData,
          onConflict: 'employee_id,date',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Request ${isApprove ? 'Approved' : 'Rejected'}")),
        );
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReviewDialog(BuildContext context, dynamic request) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Review Regularization", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Reason:", style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 4),
                  Text(request['reason'] ?? '-', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("Decision Comments", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Add your decision notes...",
                hintStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    handleAction(request, 'reject', controller.text);
                  }, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600, 
                    foregroundColor: Colors.white, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ), 
                  child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    handleAction(request, 'approve', controller.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600, 
                    foregroundColor: Colors.white, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ATTENDANCE REGULARIZATION", style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text("Review Requests", style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          InkWell(
            onTap: widget.onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text("Back to inbox", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600)),
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
        indicator: BoxDecoration(
          color: Colors.blue.shade600, 
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: const [Tab(text: "Pending"), Tab(text: "History")],
      ),
    );
  }

  Widget _buildList() {
    if (requests.isEmpty) {
      return Center(child: Text("No requests found", style: GoogleFonts.montserrat(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _RegularizationCard(
        request: requests[index],
        isHistory: _tabController.index == 1,
        onShowReview: () => _showReviewDialog(context, requests[index]),
      ),
    );
  }
}

class _RegularizationCard extends StatelessWidget {
  final dynamic request;
  final bool isHistory;
  final VoidCallback onShowReview;

  const _RegularizationCard({required this.request, required this.isHistory, required this.onShowReview});

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime == "Not recorded" || isoTime == "-") return isoTime ?? "Not recorded";
    try {
      DateTime dt;
      if (isoTime.contains('T')) {
        dt = DateTime.parse(isoTime).toLocal();
      } else {
        dt = DateFormat("HH:mm:ss").parse(isoTime);
      }
      return DateFormat("hh:mm a").format(dt);
    } catch (e) {
      return isoTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = request['applicant'] ?? {};
    final status = request['status'] ?? 'pending';

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
            children: [
              CircleAvatar(radius: 18, backgroundColor: Colors.blue.shade50, child: Text(emp['full_name']?[0] ?? '?', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emp['full_name'] ?? 'Unknown', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text("${emp['employee_id'] ?? ''} · ${emp['department'] ?? ''}", style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black54)),
                  ],
                ),
              ),
              _buildStatusPill(status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _timeBlock("Date", _formatDate(request['date'])),
              _timeBlock("Original In", _formatTime(request['original_punch_in'])),
              _timeBlock("Original Out", _formatTime(request['original_punch_out'])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 60), 
              _timeBlock("Requested In", _formatTime(request['requested_punch_in']), isHighlighted: true),
              _timeBlock("Requested Out", _formatTime(request['requested_punch_out']), isHighlighted: true),
            ],
          ),
          const SizedBox(height: 16),
          Text("Reason: ${request['reason'] ?? 'No reason'}", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87)),
          if (!isHistory) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onShowReview,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
                child: const Text("Review Request"),
              ),
            ),
          ] else if (request['manager_comments'] != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text("Comments: ${request['manager_comments']}", style: GoogleFonts.montserrat(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
          ]
        ],
      ),
    );
  }

  Widget _timeBlock(String label, String time, {bool isHighlighted = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.montserrat(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            time, 
            style: GoogleFonts.montserrat(
              fontSize: 10, 
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500, 
              color: isHighlighted ? Colors.blue.shade700 : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { 
      return DateFormat('dd MMM').format(DateTime.parse(d.toString())); 
    } catch (_) { 
      return d.toString(); 
    }
  }

  Widget _buildStatusPill(String status) {
    Color color = status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }
}
