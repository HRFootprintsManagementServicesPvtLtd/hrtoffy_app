import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import 'widgets/ask_toffy_card.dart';
import 'widgets/manager_header.dart';
import 'widgets/employee_geo_dialog.dart';

class TeamAttendanceScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const TeamAttendanceScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  bool loading = true;
  Map<String, dynamic>? managerProfile;
  List<String> teamMemberIds = [];
  List<dynamic> teamMembers = [];
  List<String> workingDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
  List<dynamic> holidays = [];
  
  // KPI Data (Top section)
  int presentToday = 0;
  int absentToday = 0;
  int lateToday = 0;
  double avgHours = 0.0;

  // Panel KPI Data
  int onLeaveToday = 0;
  int notCheckedInToday = 0;

  List<dynamic> teamAttendance = [];
  List<dynamic> musterAttendance = [];
  List<dynamic> teamLeaves = [];
  
  String searchQuery = "";
  DateTime selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1) {
          _fetchMusterData();
        }
        setState(() {});
      }
    });
    _initData();
  }

  Future<void> _fetchMusterData() async {
    if (teamMemberIds.isEmpty || managerProfile == null) return;
    
    final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final lastDay = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    
    final startStr = DateFormat('yyyy-MM-dd').format(firstDay);
    final endStr = DateFormat('yyyy-MM-dd').format(lastDay);
    final orgId = managerProfile!['organization_id'];

    try {
      // Fetch everything in parallel
      final results = await Future.wait<dynamic>([
        // Attendance
        supabase
            .from('attendance')
            .select('employee_id, date, status, hours_worked, is_half_day')
            .inFilter('employee_id', teamMemberIds)
            .gte('date', startStr)
            .lte('date', endStr),
        // Holidays
        supabase
            .from('holidays')
            .select('date, name')
            .eq('organization_id', orgId)
            .gte('date', startStr)
            .lte('date', endStr),
        // Org config for working days
        supabase
            .from('organizations')
            .select('working_days')
            .eq('id', orgId)
            .maybeSingle(),
      ]);
      
      if (mounted) {
        setState(() {
          musterAttendance = results[0] as List<dynamic>;
          holidays = results[1] as List<dynamic>;
          if (results[2] != null && (results[2] as Map).containsKey('working_days')) {
            workingDays = List<String>.from((results[2] as Map)['working_days'] ?? workingDays);
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch Muster Data Error: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => loading = true);
    try {
      await _fetchManagerProfile();
      await _fetchTeamScope();
      await _fetchAttendanceData();
      await _fetchLeaveData();
      _computeKpis();
    } catch (e) {
      debugPrint("Error initializing attendance data: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchManagerProfile() async {
    if (widget.userData.containsKey('id') && widget.userData['id'] != null) {
      managerProfile = widget.userData;
      return;
    }
    final res = await supabase.from('employee_records').select().eq('email', widget.userEmail).maybeSingle();
    if (res != null) managerProfile = res;
  }

  Future<void> _fetchTeamScope() async {
    if (managerProfile == null) return;
    final myId = managerProfile!['id'];

    try {
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
      if (hierarchy is List && hierarchy.isNotEmpty) {
        teamMembers = hierarchy;
        teamMemberIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      } else {
        // Fallback: Just the manager or empty team handling
        teamMembers = [managerProfile];
        teamMemberIds = [myId.toString()];
      }
    } catch (e) {
      debugPrint("Hierarchy RPC Error: $e");
      teamMembers = [managerProfile];
      teamMemberIds = [myId.toString()];
    }
  }

  Future<void> _fetchAttendanceData() async {
    if (teamMemberIds.isEmpty) return;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final startDate = DateFormat('yyyy-MM-dd').format(thirtyDaysAgo);

    try {
      final res = await supabase
          .from('attendance')
          .select('*, employee_records!inner(full_name, employee_id)')
          .inFilter('employee_id', teamMemberIds)
          .gte('date', startDate)
          .order('date', ascending: false);
      
      teamAttendance = res as List<dynamic>;
    } catch (e) {
      debugPrint("Fetch Attendance Error: $e");
    }
  }

  Future<void> _fetchLeaveData() async {
    if (teamMemberIds.isEmpty) return;
    try {
      final res = await supabase
          .from('leave_applications')
          .select('*, applicant:employee_id(full_name)')
          .inFilter('employee_id', teamMemberIds)
          .eq('status', 'approved')
          .order('created_at', ascending: false);
      
      teamLeaves = res as List<dynamic>;
    } catch (e) {
      debugPrint("Fetch Leaves Error: $e");
    }
  }

  void _computeKpis() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Top KPIs (scoped to team for now as per Manager Panel logic)
    final todaysAttendance = teamAttendance.where((a) => a['date'] == todayStr).toList();
    presentToday = todaysAttendance.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
    absentToday = teamMemberIds.length - presentToday; // Simplification
    lateToday = todaysAttendance.where((a) => a['status'] == 'late' || a['status'] == 'half_day').length;
    
    if (teamAttendance.isNotEmpty) {
      final totalHours = teamAttendance.fold(0.0, (sum, item) => sum + (item['hours_worked'] ?? 0.0));
      avgHours = totalHours / teamAttendance.length;
    }

    // Panel KPIs
    onLeaveToday = teamLeaves.where((l) {
      final start = DateTime.parse(l['from_date']);
      final end = DateTime.parse(l['to_date']);
      final today = DateTime.now();
      return today.isAfter(start.subtract(const Duration(seconds: 1))) && 
             today.isBefore(end.add(const Duration(days: 1)));
    }).length;

    notCheckedInToday = teamMembers.length - presentToday - onLeaveToday;
    if (notCheckedInToday < 0) notCheckedInToday = 0;
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
        currentRoute: DrawerRoute.attendance,
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
            onRefresh: _initData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 24),
                  const AskToffyCard(),
                  const SizedBox(height: 24),
                  _buildPayrollLockBanner(),
                  const SizedBox(height: 24),
                  _buildFiltersBar(),
                  const SizedBox(height: 24),
                  _buildLargeKpiCards(),
                  const SizedBox(height: 32),
                  _buildAttendanceTrendPlaceholder(),
                  const SizedBox(height: 40),
                  _buildManagerPanelHeader(),
                  const SizedBox(height: 16),
                  _buildPanelTabs(),
                  const SizedBox(height: 24),
                  _buildSmallKpiGrid(),
                  const SizedBox(height: 32),
                  _buildTabContent(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildPageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "GOOD MORNING, ${managerProfile?['full_name']?.toString().split(' ')[0].toUpperCase() ?? 'MANAGER'} — ${DateFormat('EEEE, d MMM').format(DateTime.now()).toUpperCase()}",
          style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade400, letterSpacing: 1.1),
        ),
        const SizedBox(height: 12),
        Text(
          "Attendance, every punch counted",
          style: GoogleFonts.montserrat(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          "Track presence, punches, and shift schedules across your team.",
          style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildPayrollLockBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock_outlined, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Payroll Processing Active: Data entry for payroll cycle 5/2026 is locked. You can still work on dates outside this cycle.",
              style: GoogleFonts.montserrat(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(width: 100, child: _filterDropdown("Location", "All locations")),
        SizedBox(width: 100, child: _filterDropdown("Time frame", "Today")),
        SizedBox(width: 100, child: _filterDropdown("Employment type", "All types")),
        TextButton.icon(
          onPressed: () {}, 
          icon: const Icon(Icons.refresh, size: 16), 
          label: Text("Reset", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600)),
        )
      ],
    );
  }

  Widget _filterDropdown(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(value, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLargeKpiCards() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _largeKpiCard("PRESENT TODAY", presentToday.toString(), Colors.blue, Icons.check_circle_outline),
        _largeKpiCard("ABSENT TODAY", absentToday.toString(), Colors.blue, Icons.remove_circle_outline),
        _largeKpiCard("LATE TODAY", lateToday.toString(), Colors.blue, Icons.access_time),
        _largeKpiCard("AVG HOURS", "${avgHours.toStringAsFixed(1)} h", Colors.blue, Icons.timer_outlined),
      ],
    );
  }

  Widget _largeKpiCard(String label, String value, Color color, IconData icon) {
    return Container(
      width: (MediaQuery.of(context).size.width - 52) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: GoogleFonts.montserrat(fontSize: 8, color: Colors.blueGrey, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              Icon(icon, size: 14, color: Colors.blue.shade400),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildAttendanceTrendPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Attendance trend", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold)),
          Text("Daily present vs absent within selected window", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 40),
          const Center(child: Text("Trend chart visualization here", style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildManagerPanelHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Manager Attendance Dashboard", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold)),
        Text("Monitor your team's attendance and leave status", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildPanelTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(8)),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time, size: 16), SizedBox(width: 8), Text("Team Overview")])),
          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.grid_on_outlined, size: 16), SizedBox(width: 8), Text("Attendance Muster")])),
        ],
      ),
    );
  }

  Widget _buildSmallKpiGrid() {
    return Row(
      children: [
        _smallKpiCard("Team Members", teamMembers.length.toString(), Colors.blue, Icons.groups_outlined),
        const SizedBox(width: 12),
        _smallKpiCard("Present Today", presentToday.toString(), Colors.green, Icons.check_circle_outline),
        const SizedBox(width: 12),
        _smallKpiCard("On Leave", onLeaveToday.toString(), Colors.indigo, Icons.calendar_today),
        const SizedBox(width: 12),
        _smallKpiCard("Not Checked In", notCheckedInToday.toString(), Colors.orange, Icons.timer_outlined),
      ],
    );
  }

  Widget _smallKpiCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 16, color: color),
                Text(value, style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.montserrat(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return _tabController.index == 0
        ? _buildTeamOverviewTab()
        : _buildAttendanceMusterTab();
  }

  Widget _buildTeamOverviewTab() {
    final filteredAttendance = teamAttendance.where((a) {
      if (searchQuery.isEmpty) return true;
      final name = a['employee_records']?['full_name']?.toString().toLowerCase() ?? '';
      return name.contains(searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Team Attendance & Leave Tracker (Last 30 Days)",
                      style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => searchQuery = v),
                decoration: InputDecoration(
                  hintText: "Search employee by name...",
                  hintStyle: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowHeight: 40,
                  dataRowHeight: 60,
                  columns: const [
                    DataColumn(label: Text("Employee", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Date", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Check In", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Check Out", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Hours", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Work Type", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Status", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Leave Status", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                  rows: filteredAttendance.map((a) {
                    final emp = a['employee_records'] ?? {};
                    final String empId = a['employee_id'].toString();
                    final String dateStr = a['date'];
                    
                    final isOnLeave = teamLeaves.any((l) {
                      if (l['employee_id'].toString() != empId) return false;
                      final start = DateTime.parse(l['from_date']);
                      final end = DateTime.parse(l['to_date']);
                      final current = DateTime.parse(dateStr);
                      return current.isAfter(start.subtract(const Duration(seconds: 1))) && 
                             current.isBefore(end.add(const Duration(days: 1)));
                    });

                    return DataRow(cells: [
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp['full_name'] ?? 'Unknown', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          Text(emp['employee_id'] ?? '', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      )),
                      DataCell(Text(DateFormat('dd MMM yyyy').format(DateTime.parse(a['date'])), style: const TextStyle(fontSize: 11))),
                      DataCell(Text(_formatTime(a['check_in_time']), style: const TextStyle(fontSize: 11))),
                      DataCell(Text(_formatTime(a['check_out_time']), style: const TextStyle(fontSize: 11))),
                      DataCell(Text("${a['hours_worked']?.toStringAsFixed(1) ?? '0.0'}h", style: const TextStyle(fontSize: 11))),
                      DataCell(Text(a['work_type'] ?? 'On-Duty', style: const TextStyle(fontSize: 11))),
                      DataCell(_buildStatusBadge(a['status'])),
                      DataCell(_buildLeaveStatusBadge(isOnLeave)),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceMusterTab() {
    final daysInMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    final dayNames = List.generate(daysInMonth, (i) => (i + 1).toString());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('MMMM yyyy').format(selectedMonth), style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);
                      });
                      _fetchMusterData();
                    }, 
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
                      });
                      _fetchMusterData();
                    }, 
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          // Scrollable grid
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 10,
              horizontalMargin: 10,
              headingRowHeight: 40,
              columns: [
                DataColumn(label: Container(width: 80, child: const Text("Employee", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
                ...dayNames.map((d) => DataColumn(label: Container(width: 25, alignment: Alignment.center, child: Text(d, style: const TextStyle(fontSize: 9))))),
                const DataColumn(label: Text("P", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                const DataColumn(label: Text("PL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                const DataColumn(label: Text("H", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                const DataColumn(label: Text("A", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
              ],
              rows: teamMembers.map((emp) {
                final String empId = emp['id'].toString();
                
                int pCount = 0;
                int plCount = 0;
                int hCount = 0;
                int aCount = 0;

                final List<DataCell> musterCells = List.generate(daysInMonth, (i) {
                  final date = DateTime(selectedMonth.year, selectedMonth.month, i + 1);
                  final dateStr = DateFormat('yyyy-MM-dd').format(date);
                  final weekdayName = DateFormat('EEEE').format(date).toLowerCase();
                  
                  // 1. Check Holiday
                  final isHoliday = holidays.any((h) => h['date'] == dateStr);
                  if (isHoliday) {
                    hCount++;
                    return DataCell(_musterCell("H", Colors.purple.shade300));
                  }

                  // 2. Check Weekly Off
                  final isWorkingDay = workingDays.contains(weekdayName);
                  if (!isWorkingDay) {
                    return DataCell(_musterCell("OFF", Colors.grey.shade400));
                  }

                  // 3. Check Leave
                  final isOnLeave = teamLeaves.any((l) {
                    if (l['employee_id'].toString() != empId) return false;
                    final start = DateTime.parse(l['from_date']);
                    final end = DateTime.parse(l['to_date']);
                    return date.isAfter(start.subtract(const Duration(seconds: 1))) && 
                           date.isBefore(end.add(const Duration(days: 1)));
                  });
                  if (isOnLeave) {
                    plCount++;
                    return DataCell(_musterCell("L", Colors.blue.shade300));
                  }

                  // 4. Check Attendance
                  final matches = musterAttendance.where(
                    (a) => a['employee_id'].toString() == empId && a['date'] == dateStr,
                  ).toList();
                  
                  final Map<String, dynamic>? att = matches.isNotEmpty ? matches.first : null;

                  if (att != null) {
                    final s = (att['status'] ?? '').toLowerCase();
                    if (s == 'present') { pCount++; return DataCell(_musterCell("P", Colors.green)); }
                    if (s == 'late') { pCount++; return DataCell(_musterCell("LT", Colors.orange)); }
                    if (s == 'half_day') { pCount++; return DataCell(_musterCell("HD", Colors.orangeAccent)); }
                    if (s == 'absent') { aCount++; return DataCell(_musterCell("A", Colors.red)); }
                  }

                  // 5. Default A for past dates
                  if (date.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
                    aCount++;
                    return DataCell(_musterCell("A", Colors.red));
                  }

                  return DataCell(_musterCell("-", Colors.grey));
                });

                return DataRow(cells: [
                  DataCell(Row(
                    children: [
                      InkWell(
                        onTap: () {
                          if (managerProfile == null) return;
                          showDialog(
                            context: context,
                            builder: (_) => EmployeeGeoDialog(
                              employeeId: empId,
                              employeeName: emp['full_name'] ?? 'Unknown',
                              organizationId: managerProfile!['organization_id'].toString(),
                            ),
                          );
                        },
                        child: const Icon(Icons.location_on, size: 14, color: Colors.blue),
                      ),
                      const SizedBox(width: 4),
                      Expanded(child: Text(emp['full_name'] ?? 'Unknown', style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis)),
                    ],
                  )),
                  ...musterCells,
                  DataCell(_musterCell(pCount.toString(), Colors.black)),
                  DataCell(_musterCell(plCount.toString(), Colors.black)),
                  DataCell(_musterCell(hCount.toString(), Colors.black)),
                  DataCell(_musterCell(aCount.toString(), Colors.black)),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _musterCell(String text, Color color) {
    return Container(
      width: 25,
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return "-";
    try {
      final dt = DateTime.parse(time);
      return DateFormat('hh:mm:ss a').format(dt.toLocal());
    } catch (_) {
      return time;
    }
  }

  Widget _buildStatusBadge(String? status) {
    final s = (status ?? 'absent').toLowerCase();
    Color color = Colors.red;
    if (s == 'present') color = Colors.green;
    if (s == 'late') color = Colors.orange;
    if (s == 'half_day') color = Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(s.toUpperCase(), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLeaveStatusBadge(bool isOnLeave) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: isOnLeave ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(isOnLeave ? "ON LEAVE" : "AVAILABLE", style: TextStyle(color: isOnLeave ? Colors.blue : Colors.grey, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }
}

