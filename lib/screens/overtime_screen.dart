import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class OvertimeScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const OvertimeScreen({
    Key? key,
    required this.email,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  String? employeeUuid;
  bool loading = true;
  List<Map<String, dynamic>> otRecords = [];

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    setState(() => loading = true);
    try {
      final profile = await supabase.from('employee_records').select('id').eq('email', widget.email).maybeSingle();
      if (profile != null) {
        employeeUuid = profile['id'];
        await fetchOTRecords();
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
    setState(() => loading = false);
  }

  Future<void> fetchOTRecords() async {
    try {
      final res = await supabase.from('overtime_records').select().eq('employee_id', employeeUuid!).order('ot_date', ascending: false);
      otRecords = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      otRecords = [];
    }
    setState(() {});
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
        userEmail: widget.email,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.overtime,
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
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
                    colors: [Color(0xFFD7E8FF), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Overtime", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Track your extra working hours", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: loading
                ? const SkeletonOTRecords()
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: otRecords.isEmpty
                        ? Container(
                            height: 400,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset("assets/icons/overtime.svg", width: 100, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)),
                                const SizedBox(height: 20),
                                Text("No overtime records found", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
                              ],
                            ),
                          )
                        : Column(
                            children: otRecords.map((r) => _buildOTCard(r)).toList(),
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.email, employeeId: employeeUuid ?? ''))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
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

  Widget _buildOTCard(Map<String, dynamic> r) {
    final date = DateFormat('dd MMM yyyy').format(DateTime.parse(r['ot_date']));
    final status = (r['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.grey;
    if (status == 'approved' || status == 'paid') statusColor = Colors.green;
    else if (status == 'pending') statusColor = Colors.orange;
    else if (status == 'rejected') statusColor = Colors.red;

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
              Text(date, style: EmployeeUi.title(15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric("Hours", "${r['total_hours']} hrs"),
              _metric("Multiplier", "${r['rate_multiplier']}x"),
              _metric("Amount", "₹${r['ot_amount'] ?? '0'}"),
            ],
          ),
          const SizedBox(height: 12),
          Text("Type: ${r['ot_type']?.toString().replaceAll('_', ' ').toUpperCase()}", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
      ],
    );
  }
}
