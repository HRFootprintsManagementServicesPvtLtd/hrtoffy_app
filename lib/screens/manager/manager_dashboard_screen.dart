import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

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
  String? companyLogoUrl;
  String? organizationName;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      // Restore original column set with essential ID fields for filtering
      const String memberColumns = 'id, employee_id, full_name, designation, employment_status, department, email, manager_name, avatar_url, manager_id, secondary_manager_id, reviewer_id';

      debugPrint("ManagerDashboard: Step 1 - Fetching manager profile...");
      // 1. Fetch Manager Profile with full fields for SnapshotSection
      final employeeRecord = await supabase
          .from('employee_records')
          .select('id, organization_id, full_name, avatar_url, designation, department, manager_name, reviewer_name, location,  employee_id, email')
          .eq('email', currentUser.email!)
          .maybeSingle();
      
      if (employeeRecord == null) {
        debugPrint("ManagerDashboard: Profile not found.");
        if (mounted) setState(() => loading = false);
        return;
      }
      debugPrint("ManagerDashboard: Profile fetched for ${employeeRecord['full_name']}.");

      if (!mounted) return;
      setState(() => employee = employeeRecord);

      final managerId = employeeRecord['id'];
      final orgId = employeeRecord['organization_id'];

      debugPrint("ManagerDashboard: Step 2 - Fetching team segments...");
      // 2. Fetch all direct/secondary/review team segments in one query using OR
      final teamRes = await supabase
          .from('employee_records')
          .select(memberColumns)
          .or('manager_id.eq.$managerId,secondary_manager_id.eq.$managerId,reviewer_id.eq.$managerId');
      
      debugPrint("ManagerDashboard: Team segments fetched: ${teamRes.length} records.");

      directMembers = teamRes.where((m) => m['manager_id']?.toString() == managerId.toString()).toList();
      secondaryMembers = teamRes.where((m) => m['secondary_manager_id']?.toString() == managerId.toString()).toList();
      reviewMembers = teamRes.where((m) => m['reviewer_id']?.toString() == managerId.toString()).toList();

      // Filter Review Members (remove if already in direct/secondary)
      final directIds = {...directMembers.map((e) => e['id']), ...secondaryMembers.map((e) => e['id'])};
      reviewMembers = reviewMembers.where((e) => !directIds.contains(e['id'])).toList();

      // 3. Fetch Indirect Members
      if (directIds.isNotEmpty) {
        debugPrint("ManagerDashboard: Step 3 - Fetching indirect members for ${directIds.length} direct reports...");
        // Optimization: limit count of IDs in filter if extremely large, but keep functionality
        indirectMembers = await supabase
            .from('employee_records')
            .select(memberColumns)
            .inFilter('manager_id', directIds.toList());
        
        // Remove duplicates from indirect
        indirectMembers = indirectMembers.where((e) => !directIds.contains(e['id'])).toList();
        debugPrint("ManagerDashboard: Indirect members fetched: ${indirectMembers.length} records.");
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

      debugPrint("ManagerDashboard: Initial data loaded. Passing to progressive loader...");
      if (mounted) setState(() => loading = false);

      // 6. Background Load remaining metrics and organization data
      _loadSecondaryData(addedIds, orgId);

    } catch (e) {
      debugPrint('Manager Dashboard Critical Error: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadSecondaryData(Set<dynamic> addedIds, dynamic orgId) async {
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      debugPrint("ManagerDashboard: Progressive Step 4 - Fetching attendance and engagement...");
      
      // OPTIMIZATION: Only fetch attendance if addedIds is not massive, otherwise limit or batch
      // For now, restoring original logic with a safety limit to prevent timeout
      final parallelResults = await Future.wait([
        // Attendance logs
        addedIds.isNotEmpty 
          ? supabase.from('attendance').select('id, date, status, punch_in_time, punch_out_time, employee_id, employee_records!employee_id(full_name)').inFilter('employee_id', addedIds.toList()).order('date', ascending: false).limit(50)
          : Future.value([]),
        // On Leave Count
        addedIds.isNotEmpty
          ? supabase.from('leave_applications').select('id').eq('status', 'approved').lte('from_date', todayStr).gte('to_date', todayStr).inFilter('employee_id', addedIds.toList())
          : Future.value([]),
        // Engagement
        supabase.from('announcements').select('id').eq('organization_id', orgId).eq('is_active', true),
        supabase.from('events').select('id').eq('organization_id', orgId),
        supabase.from('surveys').select('id').eq('organization_id', orgId).eq('status', 'active'),
      ]);

      if (!mounted) return;
      setState(() {
        attendance = parallelResults[0];
        onLeaveCount = parallelResults[1].length;
        announcementsCount = parallelResults[2].length;
        eventsCount = parallelResults[3].length;
        surveysCount = parallelResults[4].length;
      });
      debugPrint("ManagerDashboard: Attendance/Engagement data populated.");

      debugPrint("ManagerDashboard: Progressive Step 5 - Fetching org details and birthdays...");
      // Organization details
      final orgRes = await supabase.from('organizations').select('name, logo_url').eq('id', orgId).maybeSingle();
      if (orgRes != null && mounted) {
        setState(() {
          organizationName = orgRes['name'];
          companyLogoUrl = orgRes['logo_url'];
        });
      }

      // Birthdays (Only active employees with DOB set) - This was the primary cause of 57014 timeout
      // FIXED: Added active filter and limit
      final monthDay = DateFormat('MM-dd').format(DateTime.now());
      final birthdayEmps = await supabase
          .from('employee_records')
          .select('id, full_name, date_of_birth, avatar_url')
          .eq('organization_id', orgId)
          .not('date_of_birth', 'is', null)
          .eq('employment_status', 'active')
          .limit(200); 
      
      final filteredBirthdays = birthdayEmps.where((e) {
        final dob = e['date_of_birth']?.toString() ?? '';
        return dob.contains(monthDay);
      }).toList();

      if (mounted) {
        setState(() => birthdays = filteredBirthdays);
      }
      debugPrint("ManagerDashboard: Background data fully loaded.");

    } catch (e) {
      debugPrint("ManagerDashboard Progressive Load Error: $e");
    }
  }

  void filterMembers(String type) {
    if (!mounted) return;
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
        companyLogoUrl: companyLogoUrl,
        organizationName: organizationName,
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
                      userEmail: widget.userEmail,
                      userData: employee ?? widget.userData ?? {},
                      fetchHrmsContext: widget.fetchHrmsContext ?? () async => {},
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
