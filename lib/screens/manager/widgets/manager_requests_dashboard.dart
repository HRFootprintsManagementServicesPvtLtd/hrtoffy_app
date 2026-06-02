import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ManagerRequestsDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;

  const ManagerRequestsDashboard({
    super.key,
    required this.userData,
    required this.onBack,
  });

  @override
  State<ManagerRequestsDashboard> createState() => _ManagerRequestsDashboardState();
}

class _ManagerRequestsDashboardState extends State<ManagerRequestsDashboard> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool loading = true;
  String? fetchError;
  Map<String, dynamic>? managerProfile;
  List<String> teamMemberIds = [];

  List<dynamic> otRequests = [];
  List<dynamic> travelClaims = [];
  List<dynamic> benefitClaims = [];

  int pendingOTCount = 0;
  int pendingTravelCount = 0;
  int pendingBenefitCount = 0;

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
        if (teamMemberIds.isNotEmpty) {
          await _fetchData();
        } else {
          setState(() {
            otRequests = [];
            travelClaims = [];
            benefitClaims = [];
          });
        }
      } else {
        setState(() => fetchError = "Could not identify manager profile.");
      }
    } catch (e) {
      debugPrint("Requests Dashboard Init Error: $e");
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
    final res = await supabase.from('employee_records').select().eq('email', email).maybeSingle();
    if (res != null) managerProfile = res;
  }

  Future<void> _fetchTeamScope() async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

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

  Future<void> _fetchData() async {
    try {
      // Fetch in parallel as per Step 3
      final results = await Future.wait([
        // Overtime
        supabase
            .from('overtime_records')
            .select('*, applicant:employee_id(full_name, employee_id)')
            .inFilter('employee_id', teamMemberIds)
            .order('created_at', ascending: false),
        // Travel Claims
        supabase
            .from('travel_claims')
            .select('*, applicant:employee_id(full_name, employee_id)')
            .inFilter('employee_id', teamMemberIds)
            .order('created_at', ascending: false),
        // Benefit Claims
        supabase
            .from('benefit_claims')
            .select('*, applicant:employee_id(full_name, employee_id), catalog:benefit_id(benefit_name)')
            .inFilter('employee_id', teamMemberIds)
            .order('claim_date', ascending: false),
      ]);

      if (mounted) {
        setState(() {
          otRequests = results[0] as List;
          travelClaims = results[1] as List;
          benefitClaims = results[2] as List;

          // Locally compute pending counts as per Step 4
          pendingOTCount = otRequests.where((r) => r['status'] == 'pending').length;
          pendingTravelCount = travelClaims.where((r) => r['status'] == 'pending').length;
          pendingBenefitCount = benefitClaims.where((r) => r['status'] == 'pending').length;
        });
      }
    } catch (e) {
      debugPrint("Data Fetch Error: $e");
      if (mounted) setState(() => fetchError = "Data fetch failed: $e");
    }
  }

  Future<void> handleAction(String module, dynamic record, String action, String comments) async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    String table = '';
    if (module == 'overtime') table = 'overtime_records';
    else if (module == 'travel') table = 'travel_claims';
    else if (module == 'benefits') table = 'benefit_claims';

    try {
      final status = action == 'approve' ? 'approved' : 'rejected';
      
      await supabase.from(table).update({
        'status': status,
        'manager_comments': comments,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', record['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Request ${action == 'approve' ? 'Approved' : 'Rejected'}")),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (fetchError != null)
          Expanded(child: Center(child: Text("Error: $fetchError", style: const TextStyle(color: Colors.red))))
        else ...[
          _buildKPIs(),
          _buildTabs(),
          Expanded(child: _buildList()),
        ]
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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

  Widget _buildKPIs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 24) / 3;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _kpiCard("Pending OT", pendingOTCount, Colors.blue, Icons.access_time, cardWidth),
            _kpiCard("Pending Travel", pendingTravelCount, Colors.blue, Icons.flight_takeoff, cardWidth),
            _kpiCard("Pending Benefit", pendingBenefitCount, Colors.blue, Icons.card_giftcard, cardWidth),
          ],
        );
      }),
    );
  }

  Widget _kpiCard(String label, int count, Color color, IconData icon, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: GoogleFonts.montserrat(fontSize: 8, color: Colors.grey.shade600, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              Icon(icon, size: 12, color: color.withOpacity(0.4)),
            ],
          ),
          const SizedBox(height: 4),
          Text("$count", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
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
        tabs: [
          Tab(text: "Overtime ($pendingOTCount)"),
          Tab(text: "Travel Claims ($pendingTravelCount)"),
          Tab(text: "Benefit Claims ($pendingBenefitCount)"),
        ],
      ),
    );
  }

  Widget _buildList() {
    List<dynamic> list = [];
    String module = '';
    if (_tabController.index == 0) { list = otRequests; module = 'overtime'; }
    else if (_tabController.index == 1) { list = travelClaims; module = 'travel'; }
    else if (_tabController.index == 2) { list = benefitClaims; module = 'benefits'; }

    if (list.isEmpty) return Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text("No requests found", style: GoogleFonts.montserrat(color: Colors.grey.shade400, fontSize: 13))));

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _RequestCard(
        request: list[index],
        module: module,
        onReview: (action, comments) => handleAction(module, list[index], action, comments),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final dynamic request;
  final String module;
  final Function(String, String) onReview;

  const _RequestCard({required this.request, required this.module, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final emp = request['applicant'] ?? {};
    final status = request['status'] ?? 'pending';

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
                    _buildStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailsGrid(),
                const SizedBox(height: 12),
                if (status == 'pending')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showReviewDialog(context),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                      child: Text("Review Request", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => _showViewDialog(context),
                    child: Text("View Details", style: GoogleFonts.montserrat(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsGrid() {
    if (module == 'overtime') {
      return Wrap(spacing: 16, runSpacing: 8, children: [
        _detailBlock("Date", _formatDate(request['ot_date'])),
        _detailBlock("Hours", "${request['total_hours']} hrs"),
        _detailBlock("Type", request['ot_type'] ?? '-'),
        _detailBlock("Amount", "₹ ${NumberFormat('#,##,###').format(request['ot_amount'] ?? 0)}"),
      ]);
    } else if (module == 'travel') {
      return Wrap(spacing: 16, runSpacing: 8, children: [
        _detailBlock("From", _formatDate(request['trip_from_date'])),
        _detailBlock("To", _formatDate(request['trip_to_date'])),
        _detailBlock("Destination", request['trip_destination'] ?? '-'),
        _detailBlock("Total", "₹ ${NumberFormat('#,##,###').format(request['total_amount'] ?? 0)}"),
      ]);
    } else {
      final benefitName = request['catalog']?['benefit_name'] ?? 'Benefit';
      return Wrap(spacing: 16, runSpacing: 8, children: [
        _detailBlock("Benefit", benefitName),
        _detailBlock("Date", _formatDate(request['claim_date'])),
        _detailBlock("Amount", "₹ ${NumberFormat('#,##,###').format(request['claim_amount'] ?? 0)}"),
      ]);
    }
  }

  Widget _detailBlock(String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.montserrat(fontSize: 8, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(val, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
    ]);
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(color: color, fontSize: 8, fontWeight: FontWeight.bold)));
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  void _showReviewDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Review ${module.toUpperCase()}", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Decision Comments", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: controller, maxLines: 3, decoration: InputDecoration(hintText: "Enter comments...", hintStyle: GoogleFonts.montserrat(fontSize: 12), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
        ]),
        actions: [
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(ctx); onReview('reject', controller.text); }, style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text("Reject"))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(ctx); onReview('approve', controller.text); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text("Approve"))),
          ]),
        ],
      ),
    );
  }

  void _showViewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Request Details", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row("Status", request['status']?.toUpperCase() ?? '-'),
            if (request['manager_comments'] != null) ...[
              const SizedBox(height: 12),
              _row("Manager Comments", request['manager_comments']),
            ],
            if (request['reason'] != null) ...[
              const SizedBox(height: 12),
              _row("Reason", request['reason']),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  Widget _row(String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
      Text(val, style: const TextStyle(fontSize: 12)),
    ]);
  }
}
