import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/employee_ui.dart';

class SendRequestScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const SendRequestScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<SendRequestScreen> createState() => _SendRequestScreenState();
}

class _SendRequestScreenState extends State<SendRequestScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  String? managerId, managerName, employeeId, orgId;
  String recipientType = "manager";
  final subjectController = TextEditingController();
  final messageController = TextEditingController();
  bool loadingProfile = true, sending = false, loadingRequests = false;
  late TabController _tabController;
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    loadProfileAndRequests();
  }

  Future<void> loadProfileAndRequests() async {
    setState(() => loadingProfile = true);
    try {
      final emp = await supabase.from('employee_records').select().eq('email', widget.userEmail).maybeSingle();
      setState(() {
        employeeId = emp?['id']?.toString();
        managerId = emp?['manager_id']?.toString();
        managerName = emp?['manager_name']?.toString();
        orgId = emp?['organization_id']?.toString();
        loadingProfile = false;
      });
      if (employeeId != null) await fetchRequests();
    } catch (e) {
      setState(() => loadingProfile = false);
    }
  }

  Future<void> fetchRequests() async {
    setState(() => loadingRequests = true);
    try {
      final resp = await supabase.from('support_requests').select().eq('employee_id', employeeId!).order('created_at', ascending: false);
      setState(() { requests = (resp as List).cast<Map<String, dynamic>>(); loadingRequests = false; });
    } catch (e) {
      setState(() => loadingRequests = false);
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
        currentRoute: DrawerRoute.dashboard, // Using dashboard as fallback
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
                    colors: [Color(0xFFFFECE6), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Support Request", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Get help from your manager or HR", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
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
                    controller: _tabController,
                    indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                    unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                    tabs: const [Tab(text: 'Send New'), Tab(text: 'My History')],
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            child: loadingProfile ? const Center(child: CircularProgressIndicator()) : TabBarView(
              controller: _tabController,
              children: [_buildForm(), _buildHistory()],
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: employeeId ?? ''))); return; }
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

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: EmployeeUi.cardDecoration(),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: recipientType, decoration: const InputDecoration(labelText: "Recipient", border: OutlineInputBorder()),
              items: [DropdownMenuItem(value: "manager", child: Text("Manager (${managerName ?? 'N/A'})")), const DropdownMenuItem(value: "hr", child: Text("HR Team"))],
              onChanged: (v) => setState(() => recipientType = v!),
            ),
            const SizedBox(height: 16),
            TextField(controller: subjectController, decoration: const InputDecoration(labelText: "Subject", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: messageController, maxLines: 5, decoration: const InputDecoration(labelText: "Message", border: OutlineInputBorder())),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Submit Request", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (loadingRequests) return const Center(child: CircularProgressIndicator());
    if (requests.isEmpty) return Center(child: Text("No requests found", style: GoogleFonts.montserrat(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(20), itemCount: requests.length,
      itemBuilder: (context, i) => _buildRequestCard(requests[i]),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.orange;
    if (status == 'resolved') statusColor = Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(r['subject'] ?? '', style: EmployeeUi.title(15))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
          ]),
          const SizedBox(height: 8),
          Text(r['message'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
          if (r['response'] != null) ...[
            const Divider(height: 24),
            Text("Response:", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(r['response'], style: GoogleFonts.montserrat(fontSize: 13, color: EmployeeUi.primary)),
          ]
        ],
      ),
    );
  }
}
