import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../repositories/engagement_repository.dart';
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
import 'survey_response_screen.dart';

class SurveysScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  /// Tests only: the repository and session to use (default to the signed-in session's).
  final EngagementRepository? repository;
  final AuthService? auth;

  const SurveysScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.repository,
    this.auth,
  }) : super(key: key);

  @override
  State<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends State<SurveysScreen> with SingleTickerProviderStateMixin {
  late final EngagementRepository _engagement = widget.repository ?? EngagementRepository();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  bool loading = true;
  String? errorMsg;
  Map<String, dynamic>? employeeData;
  List<Map<String, dynamic>> activeSurveys = [];
  List<Map<String, dynamic>> completedSurveys = [];

  /// True when the answered-or-not lookup failed for at least one survey. Those surveys stay in Active (the server
  /// refuses a second submission with 409) and none of them is shown as completed.
  bool completionUnknown = false;

  /// Survey id -> when the employee submitted it (as the server reported it), for the completed ones.
  Map<String, String?> submittedAt = const {};


  final List<Color> pastelColors = [
    const Color(0xFFFFF3E0),
    const Color(0xFFE8F5E9),
    const Color(0xFFE3F2FD),
    const Color(0xFFF3E5F5),
    const Color(0xFFFFEBEE),
    const Color(0xFFE0F7FA),
    const Color(0xFFF9FBE7),
    const Color(0xFFFFF8E1),
  ];


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

  /// A short message for the user; never the raw exception text.
  String _friendlyError(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) return 'Network problem. Check your connection and retry.';
      if (e.isUnauthorized) return 'Session expired. Please sign in again.';
      if (e.isForbidden) return "You don't have permission to view surveys.";
      if (e.isServerError) return 'The server is busy right now. Please try again.';
    }
    return "We couldn't load surveys right now. Please try again.";
  }

  Future<void> fetchEmployeeAndSurveys() async {
    setState(() { loading = true; errorMsg = null; completionUnknown = false; });
    try {
      final me = (widget.auth ?? AuthService.instance).currentUser;
      if (me == null || (me.employeeId ?? '').isEmpty) { setState(() { errorMsg = "Employee record not found."; loading = false; }); return; }
      employeeData = {'id': me.employeeId, 'organization_id': me.organizationId};
      // The surveys come first; which of them the employee already answered is asked per survey afterwards. A failed
      // lookup only makes THAT survey's completion unknown: it stays in Active (never shown as completed) and the
      // screen says so, while the surveys that were answered are still shown as completed.
      final surveys = (await _engagement.mySurveys()).map((s) => Map<String, dynamic>.from(s)).toList();
      final completion = surveys.isEmpty
          ? const SurveyCompletion(submittedAt: {}, unknown: {})
          : await _engagement.surveyCompletion(surveys.map((s) => s['id'].toString()));
      final actives = <Map<String, dynamic>>[];
      final completeds = <Map<String, dynamic>>[];
      for (final survey in surveys) {
        if (completion.isCompleted(survey['id'].toString())) {
          completeds.add(survey);
        } else {
          actives.add(survey);
        }
      }
      if (!mounted) return;
      setState(() {
        activeSurveys = actives;
        completedSurveys = completeds;
        submittedAt = completion.submittedAt;
        completionUnknown = completion.unknown.isNotEmpty;
        loading = false;
      });
    } catch (e) {
      debugPrint('fetchEmployeeAndSurveys error: $e');
      if (!mounted) return;
      setState(() { errorMsg = _friendlyError(e); loading = false; });
    }
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
            child: loading ? const SkeletonAnnouncements() : errorMsg != null ? _buildError() : Column(
              children: [
                if (completionUnknown) _buildUnknownCompletionNotice(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSurveyList(activeSurveys, true),
                      completionUnknown && completedSurveys.isEmpty ? _buildCompletedUnavailable() : _buildSurveyList(completedSurveys, false),
                    ],
                  ),
                ),
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

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMsg!, textAlign: TextAlign.center, style: GoogleFonts.montserrat(color: Colors.black54)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: fetchEmployeeAndSurveys, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  /// "Submitted 27/4/2026" when the server reported when, otherwise just "Submitted".
  String _submittedLabel(Map<String, dynamic> survey) {
    final raw = submittedAt[survey['id'].toString()];
    final d = raw == null ? null : DateTime.tryParse(raw);
    return d == null ? 'Submitted' : 'Submitted ${DateFormat('d/M/yyyy').format(d.toLocal())}';
  }

  Widget _buildUnknownCompletionNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
      child: Text(
        "We couldn't confirm which surveys you've completed. Some listed here may already be submitted.",
        style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
      ),
    );
  }

  Widget _buildCompletedUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text("Completed surveys can't be shown right now.", textAlign: TextAlign.center, style: GoogleFonts.montserrat(color: Colors.black54)),
      ),
    );
  }

  Widget _buildSurveyList(List<Map<String, dynamic>> list, bool isActive) {
    if (list.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [SvgPicture.asset("assets/icons/surveys.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)), const SizedBox(height: 16), Text(isActive ? "No active surveys" : "No completed surveys", style: GoogleFonts.montserrat(color: Colors.black54))]));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      itemBuilder: (context, i) =>
          _buildSurveyCard(list[i], isActive, i),
    );
  }

  Widget _buildSurveyCard(
      Map<String, dynamic> s,
      bool isActive,
      int index,
      ){
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: pastelColors[index % pastelColors.length],
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(s['title'] ?? '', style: EmployeeUi.title(15))),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "COMPLETED",
                        style: GoogleFonts.montserrat(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _submittedLabel(s),
                        style: GoogleFonts.montserrat(
                          fontSize: 8,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s['description'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
          if (s['questions'] is List) ...[
            const SizedBox(height: 6),
            Text('${(s['questions'] as List).length} questions', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black45)),
          ],
          if (isActive) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final done = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurveyResponseScreen(
                      survey: s,
                      employeeId: employeeData!['id'],
                      organizationId: employeeData!['organization_id'],
                      userEmail: widget.userEmail,
                    ),
                  ),
                );

                if (done == true) {
                  await fetchEmployeeAndSurveys();
                }
              }, // To be implemented with form
              style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text("Participate Now", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]
        ],
      ),
    );
  }
}
