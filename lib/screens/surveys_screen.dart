import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class SurveysScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const SurveysScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends State<SurveysScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  bool loading = true;
  String? errorMsg;
  Map<String, dynamic>? employeeData;
  List<Map<String, dynamic>> activeSurveys = [];
  List<Map<String, dynamic>> completedSurveys = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchEmployeeAndSurveys();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> fetchEmployeeAndSurveys() async {
    setState(() { loading = true; errorMsg = null; });
    try {
      final emp = await supabase.from('employee_records').select().eq('email', widget.userEmail).maybeSingle();
      if (emp == null) { setState(() { errorMsg = "Employee record not found."; loading = false; }); return; }
      employeeData = Map<String, dynamic>.from(emp as Map);
      final orgId = emp['organization_id'];
      final allSurveysRaw = await supabase.from('surveys').select().eq('organization_id', orgId).eq('status', 'active');
      final myResponsesRaw = await supabase.from('survey_responses').select('survey_id').eq('employee_id', emp['id']);
      final completedIds = (myResponsesRaw as List).map((r) => r['survey_id'].toString()).toSet();
      List<Map<String, dynamic>> actives = [];
      List<Map<String, dynamic>> completeds = [];
      if (allSurveysRaw is List) {
        for (final surveyRaw in allSurveysRaw) {
          final survey = Map<String, dynamic>.from(surveyRaw);
          if (completedIds.contains(survey['id'].toString())) completeds.add(survey);
          else actives.add(survey);
        }
      }
      setState(() { activeSurveys = actives; completedSurveys = completeds; loading = false; });
    } catch (e) { setState(() { errorMsg = e.toString(); loading = false; }); }
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.surveys,
        companyLogoUrl: null,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 12),
                child: _circleIconBtn(
                  icon: "assets/icons/notification.svg",
                  onTap: () {
                    final empId = (widget.userData['id'] ?? widget.userData['employee_id'])?.toString() ?? '';
                    if (empId.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer()),
              ),
              const SizedBox(width: 1),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD4F3F7), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Surveys & Polls", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Share your feedback and thoughts", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmployeeUi.border)),
                  child: TabBar(
                    controller: _tabController!,
                    indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                    unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                    tabs: const [Tab(text: 'Active'), Tab(text: 'Completed')],
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            child: loading ? const SkeletonAnnouncements() : TabBarView(
              controller: _tabController,
              children: [
                _buildSurveyList(activeSurveys, true),
                _buildSurveyList(completedSurveys, false),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) {
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: ''))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildSurveyList(List<Map<String, dynamic>> list, bool isActive) {
    if (list.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [SvgPicture.asset("assets/icons/surveys.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)), const SizedBox(height: 16), Text(isActive ? "No active surveys" : "No completed surveys", style: GoogleFonts.montserrat(color: Colors.black54))]));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      itemBuilder: (context, i) => _buildSurveyCard(list[i], isActive),
    );
  }

  Widget _buildSurveyCard(Map<String, dynamic> s, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(s['title'] ?? '', style: EmployeeUi.title(15))),
              if (!isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text("COMPLETED", style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green))),
            ],
          ),
          const SizedBox(height: 8),
          Text(s['description'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
          if (isActive) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {}, // To be implemented with form
              style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text("Participate Now", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]
        ],
      ),
    );
  }
}
