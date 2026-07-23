import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/employee_ui.dart';

class GoalsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function()? fetchHrmsContext;

  const GoalsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    this.fetchHrmsContext,
  });

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  bool loading = true;
  List<Map<String, dynamic>> allGoals = [];

  @override
  void initState() {
    super.initState();
    loadGoals();
  }

  Future<void> loadGoals() async {
    try {
      setState(() => loading = true);
      final employeeId = widget.userData['id'];
      final organizationId = widget.userData['organization_id'];
      final response = await supabase.from('employee_goals').select().eq('emp_id', employeeId).eq('organization_id', organizationId).order('created_at', ascending: false);
      allGoals = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Goals fetch error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
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
        fetchHrmsContext: widget.fetchHrmsContext!,
        currentRoute: DrawerRoute.performance,
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!)));
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
                    Text("My Goals", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Track your performance and targets", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: loading
                ? const SkeletonGoals()
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: allGoals.isEmpty
                        ? Container(height: 300, alignment: Alignment.center, child: Text("No goals found", style: GoogleFonts.montserrat(color: Colors.grey)))
                        : Column(
                            children: allGoals.map((g) => _buildGoalCard(g)).toList(),
                          ),
                  ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id']))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!))); return; }
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

  Widget _buildGoalCard(Map<String, dynamic> g) {
    final progress = (g['progress_percentage'] ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g['title'] ?? '-', style: EmployeeUi.title(16)),
          const SizedBox(height: 8),
          Text(g['description'] ?? '-', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Progress", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold)),
              Text("${progress.toInt()}%", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: progress / 100, minHeight: 6, backgroundColor: Colors.grey.shade100, valueColor: const AlwaysStoppedAnimation(EmployeeUi.primary)),
          ),
        ],
      ),
    );
  }
}
