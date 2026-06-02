import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

import 'widgets/ask_toffy_card.dart';
import 'widgets/celebrations_section.dart';
import 'widgets/engagement_section.dart';
import 'widgets/manager_header.dart';
import 'widgets/manager_kpi_cards.dart';
import 'widgets/snapshot_section.dart';
import 'widgets/team_attendance_section.dart';
import 'widgets/team_members_list.dart';
import 'widgets/team_tabs.dart';

class ManagerDashboardScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic>? userData;
  final Future<Map<String, dynamic>> Function()? fetchHrmsContext;

  const ManagerDashboardScreen({
    super.key,
    required this.userEmail,
    this.userData,
    this.fetchHrmsContext,
  });

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool loading = true;
  String selectedTab = 'all';
  bool showTeamMembers = true;
  bool showAttendance = true;

  Map<String, dynamic>? employee;
  List<dynamic> allMembers = [];
  List<dynamic> filteredMembers = [];
  List<dynamic> directMembers = [];
  List<dynamic> secondaryMembers = [];
  List<dynamic> indirectMembers = [];
  List<dynamic> reviewMembers = [];

  List<dynamic> attendance = [];
  List<dynamic> birthdays = [];
  
  int announcementsCount = 0;
  int eventsCount = 0;
  int surveysCount = 0;
  int onLeaveCount = 0;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      // Fetch Manager Profile
      final employeeRecord = await supabase
          .from('employee_records')
          .select()
          .eq('email', currentUser.email!)
          .single();

      if (!mounted) return;
      setState(() => employee = employeeRecord);

      final managerId = employeeRecord['id'];
      final orgId = employeeRecord['organization_id'];

      // Fetch Members in Parallel
      final memberResults = await Future.wait([
        // Direct
        supabase.from('employee_records').select().eq('manager_id', managerId),
        // Secondary
        supabase.from('employee_records').select().eq('secondary_manager_id', managerId),
        // Review
        supabase.from('employee_records').select().eq('reviewer_id', managerId),
      ]);

      directMembers = memberResults[0];
      secondaryMembers = memberResults[1];
      reviewMembers = memberResults[2];

      // Filter Review Members (remove if already in direct/secondary)
      final directIds = {...directMembers.map((e) => e['id']), ...secondaryMembers.map((e) => e['id'])};
      reviewMembers = reviewMembers.where((e) => !directIds.contains(e['id'])).toList();

      // Fetch Indirect Members
      if (directIds.isNotEmpty) {
        indirectMembers = await supabase
            .from('employee_records')
            .select()
            .inFilter('manager_id', directIds.toList());
        
        // Remove duplicates from indirect
        indirectMembers = indirectMembers.where((e) => !directIds.contains(e['id'])).toList();
      }

      // Combine All Unique Members
      final addedIds = <dynamic>{};
      final uniqueMembers = <Map<String, dynamic>>[];
      for (final m in [...directMembers, ...secondaryMembers, ...indirectMembers, ...reviewMembers]) {
        if (!addedIds.contains(m['id'])) {
          addedIds.add(m['id']);
          uniqueMembers.add(m);
        }
      }
      allMembers = uniqueMembers;
      filteredMembers = allMembers;

      // Fetch Attendance (Last 30 Days for the team)
      if (addedIds.isNotEmpty) {
        attendance = await supabase
            .from('attendance')
            .select('*, employee_records(full_name)')
            .inFilter('employee_id', addedIds.toList())
            .order('date', ascending: false)
            .limit(20);

        // On Leave Count (Based on today's approved leave)
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final leavesRes = await supabase
            .from('leave_applications')
            .select('id')
            .eq('status', 'approved')
            .lte('start_date', todayStr)
            .gte('end_date', todayStr)
            .inFilter('employee_id', addedIds.toList());
        
        onLeaveCount = leavesRes.length;
      }

      // Engagement Counts
      final engagementRes = await Future.wait([
        supabase.from('announcements').select('id').eq('organization_id', orgId).eq('is_active', true),
        supabase.from('events').select('id').eq('organization_id', orgId),
        supabase.from('surveys').select('id').eq('organization_id', orgId).eq('status', 'active'),
      ]);

      announcementsCount = engagementRes[0].length;
      eventsCount = engagementRes[1].length;
      surveysCount = engagementRes[2].length;

      // Birthdays Today
      final monthDay = DateFormat('-MM-dd').format(DateTime.now());
      birthdays = await supabase
          .from('employee_records')
          .select()
          .like('date_of_birth', '%$monthDay');

      if (mounted) setState(() => loading = false);
    } catch (e) {
      debugPrint('Manager Dashboard Error: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  void filterMembers(String type) {
    setState(() {
      selectedTab = type;
      if (type == 'all') {
        filteredMembers = allMembers;
      } else if (type == 'direct') {
        filteredMembers = [...directMembers, ...secondaryMembers];
      } else if (type == 'indirect') {
        filteredMembers = indirectMembers;
      } else if (type == 'reviewer') {
        filteredMembers = reviewMembers;
      }
    });
  }
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500)),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: employee ?? widget.userData ?? {},
        fetchHrmsContext: widget.fetchHrmsContext ?? () async => {},
        currentRoute: DrawerRoute.dashboard,
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
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManagerHeader(employeeName: employee?['full_name'] ?? 'Manager'),
                    const SizedBox(height: 24),
                    const AskToffyCard(),
                    const SizedBox(height: 32),
                    
                    // My Team Section
                    Text(
                      "My Team",
                      style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Manage and track your team members",
                      style: GoogleFonts.montserrat(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    
                    Row(
                      children: [
                        Text("Legend: ", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
                        _buildLegendItem(Colors.blueAccent, "Direct Report"),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    ManagerKpiCards(
                      directReports: directMembers.length + secondaryMembers.length,
                      indirectReports: indirectMembers.length,
                      reviewCount: reviewMembers.length,
                      onLeaveCount: onLeaveCount,
                    ),
                    const SizedBox(height: 28),
                    TeamTabs(
                      selected: selectedTab,
                      onChanged: filterMembers,
                      allCount: allMembers.length,
                      directCount: directMembers.length + secondaryMembers.length,
                      indirectCount: indirectMembers.length,
                      reviewCount: reviewMembers.length,
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "All Team Members (${filteredMembers.length})",
                          style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => setState(() => showTeamMembers = !showTeamMembers),
                          icon: Icon(showTeamMembers ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 28),
                        ),
                      ],
                    ),
                    if (showTeamMembers) TeamMembersList(members: filteredMembers),
                    
                    const SizedBox(height: 40),
                    
                    // Attendance Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Team Attendance (Last 30 Days)",
                          style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => setState(() => showAttendance = !showAttendance),
                          icon: Icon(showAttendance ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 28),
                        ),
                      ],
                    ),
                    if (showAttendance) TeamAttendanceSection(attendance: attendance),
                    
                    const SizedBox(height: 40),
                    EngagementSection(
                      announcements: announcementsCount,
                      events: eventsCount,
                      surveys: surveysCount,
                    ),
                    
                    const SizedBox(height: 32),
                    CelebrationsSection(birthdays: birthdays),
                    
                    const SizedBox(height: 32),
                    SnapshotSection(employee: employee),
                    
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
    );
  }
}
