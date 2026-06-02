import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'widgets/reviewer_leaves_view.dart';
import 'widgets/regularization_approval_view.dart';
import 'widgets/loan_approval_panel.dart';
import 'widgets/travel_approval_panel.dart';
import 'widgets/manager_requests_dashboard.dart';
import 'widgets/benefit_approval_panel.dart';

class PendingApprovalsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;

  const PendingApprovalsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
  });

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  String? activeTab; // null means Inbox

  Map<String, int> counts = {
    'leaves': 0,
    'regularization': 0,
    'benefits': 0,
    'loans': 0,
    'travel': 0,
    'general': 0,
  };

  @override
  void initState() {
    super.initState();
    fetchCounts();
  }

  Future<void> fetchCounts() async {
    try {
      var managerData = widget.userData;
      if (managerData['id'] == null) {
        final email = widget.userEmail;
        final res = await supabase.from('employee_records').select().eq('email', email).maybeSingle();
        if (res != null) {
          managerData = res;
        }
      }
      
      final managerId = managerData['id'];
      if (managerId == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      // Robust scoping for team requests
      List<String> teamIds = [];
      try {
        final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': managerId});
        if (hierarchy is List) {
          teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
        }
      } catch (_) {
        teamIds = [managerId.toString()];
      }

      // Parallel fetch for efficiency
      final results = await Future.wait<dynamic>([
        // Leaves
        supabase.from('leave_applications').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        // Regularization
        supabase.from('attendance_regularization_requests').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        // Benefits
        supabase.from('benefit_claims').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        // Loans
        supabase.from('loans_advances').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        // Travel
        supabase.from('travel_claims').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        // General
        supabase.from('support_requests').select('id').inFilter('employee_id', teamIds).eq('status', 'open'),
      ]);

      if (mounted) {
        setState(() {
          counts['leaves'] = (results[0] as List).length;
          counts['regularization'] = (results[1] as List).length;
          counts['benefits'] = (results[2] as List).length;
          counts['loans'] = (results[3] as List).length;
          counts['travel'] = (results[4] as List).length;
          counts['general'] = (results[5] as List).length;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching approval counts: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          activeTab == null ? "Approvals" : _getTabTitle(activeTab!),
          style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: activeTab != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => activeTab = null),
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchCounts,
              child: activeTab == null
                  ? _buildInbox()
                  : activeTab == 'leaves'
                      ? ReviewerLeavesView(
                          userData: widget.userData,
                          onBack: () => setState(() => activeTab = null),
                        )
                      : activeTab == 'regularization'
                          ? RegularizationApprovalView(
                              userData: widget.userData,
                              onBack: () => setState(() => activeTab = null),
                            )
                          : activeTab == 'loans'
                              ? LoanApprovalPanel(
                                  userData: widget.userData,
                                  onBack: () => setState(() => activeTab = null),
                                )
                              : activeTab == 'travel'
                                  ? TravelApprovalPanel(
                                      userData: widget.userData,
                                      onBack: () => setState(() => activeTab = null),
                                    )
                                  : activeTab == 'general'
                                      ? ManagerRequestsDashboard(
                                          userData: widget.userData,
                                          onBack: () => setState(() => activeTab = null),
                                        )
                                      : activeTab == 'benefits'
                                          ? BenefitApprovalPanel(
                                              userData: widget.userData,
                                              onBack: () => setState(() => activeTab = null),
                                            )
                                          : _buildCategoryPanel(activeTab!),
            ),
    );
  }

  Widget _buildInbox() {
    final totalPending = counts.values.reduce((a, b) => a + b);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFFE3F2FD).withOpacity(0.5), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "GOOD AFTERNOON, ${widget.userData['full_name']?.toString().split(' ')[0].toUpperCase() ?? 'USER'} — $totalPending REQUESTS PENDING",
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.montserrat(
                      fontSize: 28,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      const TextSpan(text: "Decisions "),
                      TextSpan(
                        text: "waiting on you",
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "$totalPending requests waiting on you — pick a category below to start clearing them.",
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          Text(
            "WAITING ON YOU",
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Tiles Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildTile("Leave Requests", "leaves", const Color(0xFFE8F5E9), Icons.calendar_month, counts['leaves']!),
              _buildTile("Regularization", "regularization", const Color(0xFFF1F8E9), Icons.access_time, counts['regularization']!),
              _buildTile("Loan Requests", "loans", const Color(0xFFE0F7FA), Icons.account_balance_wallet, counts['loans']!),
              _buildTile("Travel Claims", "travel", const Color(0xFFE3F2FD), Icons.flight_takeoff, counts['travel']!),
              _buildTile("General Requests", "general", const Color(0xFFFAFAFA), Icons.chat_bubble_outline, counts['general']!),
            ],
          ),

          const SizedBox(height: 30),
          Text(
            "ALL CLEAR",
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _buildTile("Benefits Claims", "benefits", const Color(0xFFF5F5F5), Icons.card_giftcard, counts['benefits']!, isFullWidth: true),
        ],
      ),
    );
  }

  Widget _buildTile(String title, String tab, Color color, IconData icon, int count, {bool isFullWidth = false}) {
    return GestureDetector(
      onTap: () => setState(() => activeTab = tab),
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: Colors.black54),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "$count",
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getSubtitle(tab),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getSubtitle(String tab) {
    switch (tab) {
      case 'leaves': return "Time-off applications from your team awaiting approval.";
      case 'regularization': return "Missed punches and attendance corrections to review.";
      case 'loans': return "Salary advances and employee loan applications.";
      case 'travel': return "Travel expense claims with bills and approvals.";
      case 'general': return "Miscellaneous requests routed to you.";
      case 'benefits': return "Reimbursement claims under benefit policies.";
      default: return "";
    }
  }

  String _getTabTitle(String tab) {
    switch (tab) {
      case 'leaves': return "Leave Requests";
      case 'regularization': return "Regularization";
      case 'loans': return "Loan Requests";
      case 'travel': return "Travel Claims";
      case 'general': return "General Requests";
      case 'benefits': return "Benefits Claims";
      default: return "Approvals";
    }
  }

  Widget _buildCategoryPanel(String tab) {
    return Column(
      children: [
        // Category Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Decisions waiting on you".toUpperCase(),
                style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                "${_getTabTitle(tab)} — ${_getSubtitle(tab)}",
                style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => activeTab = null),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      "Back to inbox",
                      style: GoogleFonts.montserrat(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _CategoryList(
            tab: tab,
            managerId: widget.userData['id'],
            onActionCompleted: fetchCounts,
          ),
        ),
      ],
    );
  }

  String _getTabSubtitle(String tab) => _getSubtitle(tab);
}

class _CategoryList extends StatefulWidget {
  final String tab;
  final dynamic managerId;
  final VoidCallback onActionCompleted;

  const _CategoryList({
    required this.tab,
    required this.managerId,
    required this.onActionCompleted,
  });

  @override
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> items = [];
  String currentFilter = 'pending'; // pending, approved, rejected
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        String filter = 'pending';
        if (_tabController.index == 1) filter = 'approved';
        if (_tabController.index == 2) filter = 'rejected';
        setState(() => currentFilter = filter);
        fetchItems();
      }
    });
    fetchItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchItems() async {
    setState(() => loading = true);
    try {
      String table = _getTableName(widget.tab);
      
      // Dynamic fetch based on tab and filter
      var query = supabase
          .from(table)
          .select('*, employee_records(full_name, designation, department)')
          .eq('manager_id', widget.managerId);

      if (currentFilter == 'pending') {
        query = query.inFilter('status', ['pending', 'manager_approved']);
      } else {
        query = query.eq('status', currentFilter);
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          items = response;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching category items: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  String _getTableName(String tab) {
    switch (tab) {
      case 'leaves': return 'leave_applications';
      case 'regularization': return 'attendance_regularization_requests';
      case 'benefits': return 'benefit_claims';
      case 'loans': return 'loans_advances';
      case 'travel': return 'travel_claims';
      case 'general': return 'support_requests';
      default: return 'leave_applications';
    }
  }

  Future<void> handleAction(dynamic item, String status) async {
    try {
      String table = _getTableName(widget.tab);
      
      // Update record
      await supabase.from(table).update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', item['id']);

      // Success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Request ${status == 'approved' ? 'Approved' : 'Rejected'}")),
        );
      }
      
      widget.onActionCompleted();
      fetchItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: const [
              Tab(text: "Pending Review"),
              Tab(text: "Approved"),
              Tab(text: "Rejected"),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _buildEmptyState()
                  : _buildList(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getIconForTab(widget.tab), size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text("No ${currentFilter} ${widget.tab} requests.", style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  IconData _getIconForTab(String tab) {
    switch (tab) {
      case 'leaves': return Icons.calendar_month;
      case 'regularization': return Icons.access_time;
      case 'loans': return Icons.account_balance_wallet;
      case 'travel': return Icons.flight_takeoff;
      case 'general': return Icons.chat_bubble_outline;
      case 'benefits': return Icons.card_giftcard;
      default: return Icons.check_circle_outline;
    }
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final employee = item['employee_records'];
        
        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text(employee?['full_name']?[0] ?? '?', style: const TextStyle(color: Colors.blue)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee?['full_name'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            "${employee?['designation'] ?? ''} · ${employee?['department'] ?? ''}",
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusPill(item['status']),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Divider(height: 1),
                ),
                
                // Details based on tab
                _buildDetails(item),
                
                if (currentFilter == 'pending') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => handleAction(item, 'rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => handleAction(item, 'approved'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Approve", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPill(String? status) {
    Color color = Colors.orange;
    if (status == 'approved') color = Colors.green;
    if (status == 'rejected') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        (status ?? 'PENDING').toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDetails(dynamic item) {
    switch (widget.tab) {
      case 'leaves':
        return Column(
          children: [
            _detailRow("Leave Type", item['leave_type'] ?? '-'),
            _detailRow("Dates", "${item['start_date']} to ${item['end_date']}"),
            _detailRow("Reason", item['reason'] ?? '-'),
          ],
        );
      case 'loans':
        return Column(
          children: [
            _detailRow("Loan Type", item['loan_category'] ?? '-'),
            _detailRow("Amount", "₹ ${item['requested_amount'] ?? '0'}"),
            _detailRow("Tenure", "${item['tenure_months'] ?? '-'} months"),
          ],
        );
      case 'regularization':
        return Column(
          children: [
            _detailRow("Date", item['attendance_date'] ?? '-'),
            _detailRow("New Check-in", item['requested_check_in'] ?? '-'),
            _detailRow("New Check-out", item['requested_check_out'] ?? '-'),
          ],
        );
      case 'travel':
        return Column(
          children: [
            _detailRow("Purpose", item['trip_purpose'] ?? '-'),
            _detailRow("Destination", item['trip_destination'] ?? '-'),
            _detailRow("Amount", "₹ ${item['total_amount'] ?? '0'}"),
          ],
        );
      default:
        return _detailRow("Request Details", item['description'] ?? item['title'] ?? 'No details provided');
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
