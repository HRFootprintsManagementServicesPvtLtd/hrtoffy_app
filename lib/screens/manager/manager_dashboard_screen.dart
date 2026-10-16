import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../repositories/employee_repository.dart';
import '../../repositories/engagement_repository.dart';
import '../../repositories/manager_repository.dart';
import '../../repositories/organization_repository.dart';
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

/// Shown in place of a section whose data could not be loaded (never as an empty list or a zero).
const String kTeamDataUnavailableMessage = "Team data isn't available yet.";

/// How many attendance rows the dashboard lists (the newest first, over the last [_attendanceDays] days).
const int _attendanceRows = 50;
const int _attendanceDays = 30;

class ManagerDashboardScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic>? userData;
  final Future<Map<String, dynamic>> Function()? fetchHrmsContext;
  final EmployeeRepository? employeeRepository;
  final OrganizationRepository? organizationRepository;
  final EngagementRepository? engagementRepository;
  final ManagerRepository? managerRepository;

  const ManagerDashboardScreen({
    super.key,
    required this.userEmail,
    this.userData,
    this.fetchHrmsContext,
    this.employeeRepository,
    this.organizationRepository,
    this.engagementRepository,
    this.managerRepository,
  });

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();
  late final OrganizationRepository _orgs =
      widget.organizationRepository ?? OrganizationRepository();
  late final EngagementRepository _engagement =
      widget.engagementRepository ?? EngagementRepository();
  late final ManagerRepository _manager =
      widget.managerRepository ?? ManagerRepository();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool loading = true;
  String? loadError;
  String selectedTab = 'all';
  bool showTeamMembers = true;
  bool showAttendance = true;

  Map<String, dynamic>? employee;

  /// Null while loading or when that part could not be loaded (then its section says so).
  ManagerTeam? team;
  bool teamFailed = false;
  List<Map<String, dynamic>>? attendance;
  bool attendanceFailed = false;
  List<Map<String, dynamic>>? birthdays;
  bool birthdaysFailed = false;

  /// People of the team on approved leave today; null while loading or when it could not be loaded ("-", never 0).
  int? onLeaveCount;

  /// Null while unknown or when that list could not be loaded: shown as "unavailable", never as 0.
  int? announcementsCount;
  int? eventsCount;
  int? surveysCount;
  String? companyLogoUrl;
  String? organizationName;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }
    try {
      final me = await _employees.getMe();
      if (me.isEmpty) throw StateError('no employee record');
      employee = me;
    } catch (_) {
      // The server's text is never shown.
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = "Couldn't load your profile. Pull down to try again.";
      });
      return;
    }
    if (!mounted) return;
    setState(() => loading = false);

    // Everything below is optional: a failure leaves that part "unavailable" and nothing else is affected.
    await Future.wait([
      _loadOrganization(),
      _loadEngagement(),
      _loadTeam(),
      _loadBirthdays(),
      _loadOnLeave(),
    ]);
  }

  Future<void> _loadOrganization() async {
    try {
      final org = await _orgs.getOrganization();
      if (!mounted) return;
      setState(() {
        organizationName = org['name']?.toString();
        companyLogoUrl = org['logo_url']?.toString();
        if (organizationName != null)
          employee = {...?employee, 'organization_name': organizationName};
      });
    } catch (_) {}
  }

  Future<void> _loadEngagement() async {
    Future<int?> count(
      Future<List<Map<String, dynamic>>> Function() load,
    ) async {
      try {
        return (await load()).length;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      count(_engagement.announcements),
      count(_engagement.events),
      count(_engagement.activeSurveys),
    ]);
    if (!mounted) return;
    setState(() {
      announcementsCount = results[0];
      eventsCount = results[1];
      surveysCount = results[2];
    });
  }

  Future<void> _loadTeam() async {
    ManagerTeam loaded;
    try {
      loaded = await _manager.team();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        teamFailed = true;
        attendanceFailed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      team = loaded;
      teamFailed = false;
    });
    try {
      final to = DateTime.now();
      final rows = await _manager.teamAttendance(
        loaded.treeIds,
        from: to.subtract(const Duration(days: _attendanceDays)),
        to: to,
      );
      if (!mounted) return;
      setState(() {
        attendance = rows.take(_attendanceRows).toList();
        attendanceFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => attendanceFailed = true);
    }
  }

  Future<void> _loadOnLeave() async {
    try {
      final n = await _manager.onLeaveCount();
      if (!mounted) return;
      setState(() => onLeaveCount = n);
    } catch (_) {
      if (!mounted) return;
      setState(() => onLeaveCount = null);
    }
  }

  Future<void> _loadBirthdays() async {
    try {
      final list = await _manager.birthdaysToday();
      if (!mounted) return;
      setState(() {
        birthdays = list;
        birthdaysFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => birthdaysFailed = true);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final t = team;
    if (t == null) return const [];
    switch (selectedTab) {
      case 'direct':
        return t.direct;
      case 'indirect':
        return t.indirect;
      case 'reviewer':
        return t.reviewees;
      default:
        return t.all;
    }
  }

  Widget _unavailableCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              kTeamDataUnavailableMessage,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingCard() => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );

  Widget _sectionHeader(String title, bool open, VoidCallback toggle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          onPressed: toggle,
          icon: Icon(
            open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 28,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold),
  );

  Widget _teamSection() {
    final t = team;
    if (teamFailed) return _unavailableCard();
    if (t == null) return _loadingCard();
    final members = _filteredMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManagerKpiCards(
          directReports: t.direct.length,
          indirectReports: t.indirect.length,
          reviewCount: t.reviewees.length,
          onLeaveCount: onLeaveCount, // "-" until the server answers, never 0
        ),
        const SizedBox(height: 28),
        TeamTabs(
          selected: selectedTab,
          onChanged: (v) => setState(() => selectedTab = v),
          allCount: t.all.length,
          directCount: t.direct.length,
          indirectCount: t.indirect.length,
          reviewCount: t.reviewees.length,
        ),
        const SizedBox(height: 12),
        _sectionHeader(
          'All Team Members (${members.length})',
          showTeamMembers,
          () => setState(() => showTeamMembers = !showTeamMembers),
        ),
        if (showTeamMembers) TeamMembersList(members: members),
      ],
    );
  }

  Widget _attendanceSection() {
    if (attendanceFailed) return _unavailableCard();
    if (attendance == null)
      return teamFailed ? _unavailableCard() : _loadingCard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Team Attendance (Last 30 Days)',
          showAttendance,
          () => setState(() => showAttendance = !showAttendance),
        ),
        if (showAttendance) TeamAttendanceSection(attendance: attendance!),
      ],
    );
  }

  Widget _celebrationsSection() {
    final titled = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Celebrations Today'),
        const SizedBox(height: 12),
      ],
    );
    if (birthdaysFailed)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...titled.children, _unavailableCard()],
      );
    if (birthdays == null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...titled.children, _loadingCard()],
      );
    return CelebrationsSection(birthdays: birthdays!);
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
              child: loadError != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 80),
                        Text(
                          loadError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(color: Colors.red[700]),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: loadDashboard,
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ManagerHeader(
                            employeeName: employee?['full_name'] ?? 'Manager',
                          ),
                          const SizedBox(height: 24),
                          Text(
                            "My Team",
                            style: GoogleFonts.montserrat(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Manage and track your team members",
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _teamSection(),
                          const SizedBox(height: 40),
                          _attendanceSection(),
                          const SizedBox(height: 40),
                          EngagementSection(
                            announcements: announcementsCount,
                            events: eventsCount,
                            surveys: surveysCount,
                            userEmail: widget.userEmail,
                            userData: employee ?? widget.userData ?? {},
                            fetchHrmsContext:
                                widget.fetchHrmsContext ?? () async => {},
                          ),
                          const SizedBox(height: 32),
                          _celebrationsSection(),
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
