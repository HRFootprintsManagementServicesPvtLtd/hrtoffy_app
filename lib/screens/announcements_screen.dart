import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class AnnouncementsScreen extends StatefulWidget {
  final String organizationId;
  final String userDepartment;
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  
  const AnnouncementsScreen({
    Key? key,
    required this.organizationId,
    required this.userDepartment,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen>
    with RefreshableScreen<AnnouncementsScreen> {
  String? companyLogoUrl;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> announcements = [];

  @override
  void initState() {
    super.initState();
    companyLogoUrl = widget.userData['company_logo_url'];
    startLoad();
  }

  @override
  Future<void> loadData() async {
    try {
      final response = await supabase
          .from('announcements')
          .select()
          .eq('organization_id', widget.organizationId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> filtered = [];
      if (response is List) {
        for (final annRaw in response) {
          final ann = Map<String, dynamic>.from(annRaw);
          if (ann['broadcast_type'] == 'segmented') {
            final List<dynamic> targetDepartments = ann['target_departments'] ?? [];
            if (targetDepartments.contains(widget.userDepartment)) {
              filtered.add(ann);
            }
          } else {
            filtered.add(ann);
          }
        }
      }

      setState(() {
        announcements = filtered;
      });
    } catch (e) {
      debugPrint('Failed to load announcements: $e');
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
        currentRoute: DrawerRoute.announcements,
        companyLogoUrl: companyLogoUrl,
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
                    Text("Announcements", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Stay updated with company news", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: buildRefreshable(
              skeleton: const SkeletonAnnouncements(),
              childBuilder: () {
                if (announcements.isEmpty && !isLoading) {
                  return Container(
                    height: 400,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.campaign_outlined, size: 80, color: Colors.blueGrey),
                        const SizedBox(height: 16),
                        Text("No announcements yet", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: announcements.map((ann) => _buildAnnouncementCard(ann)).toList(),
                  ),
                );
              },
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id'].toString()))); return; }
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

  Widget _buildAnnouncementCard(Map<String, dynamic> ann) {
    final createdAt = ann['created_at'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(ann['created_at'])) : '';
    final priority = (ann['priority'] ?? 'low').toString().toLowerCase();
    
    Color priorityColor;
    if (priority == 'high') priorityColor = Colors.red;
    else if (priority == 'medium') priorityColor = Colors.orange;
    else priorityColor = Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(priority.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: priorityColor)),
              ),
              const Spacer(),
              Text(createdAt, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black26, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(ann['title'] ?? "", style: EmployeeUi.title(16)),
          const SizedBox(height: 8),
          Text(ann['content'] ?? "", style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black87, height: 1.5)),
          if (ann['announcement_category'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text("# ${ann['announcement_category']}", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
            ),
          ],
        ],
      ),
    );
  }
}
