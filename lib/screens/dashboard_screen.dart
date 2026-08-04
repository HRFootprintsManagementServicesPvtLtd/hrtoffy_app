import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'notification.dart';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';
import '../models/work_site.dart';
import 'leaves_screen.dart';
import 'payslip_screen.dart';
import 'attendance_screen.dart';
import '../services/attendance_service.dart';
import '../services/leave_summary_service.dart';
import '../widgets/skeleton_layouts.dart';

class LiveClock extends StatelessWidget {
  const LiveClock({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now().toLocal();
        return Text(DateFormat('hh:mm:ss a').format(now), style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blueAccent));
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final String email;
  final String employeeId;
  const DashboardScreen({Key? key, required this.email, required this.employeeId}) : super(key: key);
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  final supabase = Supabase.instance.client;
  RealtimeChannel? _notificationChannel;
  Map<String, dynamic>? userData;
  Map<String, dynamic>? orgDetails;
  Map<String, dynamic>? mealVoucherState;
  String? profileUrl, companyLogoUrl, organizationName;
  String managerName = '--', managerEmail = '--';
  bool loadingProfile = true, showMealVoucher = false, loading = false, loadingNotifications = false;
  int unreadCount = 0;
  List<Map<String, dynamic>> notifications = [];
  final Map<String, String> workTypeOptions = {'On-Duty': 'on-duty', 'Work From Home': 'work-from-home', 'On-Site': 'on-site'};
  String selectedWorkType = "On-Duty";
  Future<Map<String, dynamic>>? todayAttendanceFuture;
  late Future<LeaveSummary> leaveSummaryFuture = Future.value(LeaveSummary.empty());


  bool geoEnabled = false, geoChecking = false, geoInFence = false, geoTrackOnly = false;
  String geoMode = 'strict';
  double? geoDistance, gpsAccuracy;
  String? nearestSiteName;
  List<WorkSite> workSites = [];

  @override
  void initState() {
    super.initState();
    _initialize();
    _subscribeNotifications();
  }

  void _subscribeNotifications() {
    _notificationChannel = supabase
        .channel('notifications_updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        if (!mounted) return;
        fetchNotifications();
      },
    );

    _notificationChannel!.subscribe();
  }

  Future<void> _initialize() async {
    setState(() => loadingProfile = true);
    try {
      final resp = await supabase.from('employee_records').select().eq('email', widget.email.toLowerCase().trim()).maybeSingle();
      userData = resp;
      if (userData != null) {
        final empId = userData!['id'], orgId = userData!['organization_id'];
        leaveSummaryFuture = LeaveSummaryService.instance.fetch();

        todayAttendanceFuture = fetchTodayAttendanceData();
        if (orgId != null) {
          await Future.wait([fetchMealVoucher(), fetchOrganizationDetails(orgId), fetchCompanyLogo(), _loadGeoFencePolicy()]);
        }
        managerName = userData!['manager_name'] ?? '--';
        managerEmail = userData!['manager_email'] ?? '--';
        if (managerEmail != '--' && managerName == '--') await fetchManagerData(managerEmail);
        profileUrl = userData!['avatar_url'];
      }
      fetchNotifications();
    } catch (e) { debugPrint("Initialize error: $e"); }
    finally { if (mounted) setState(() => loadingProfile = false); }
  }

  Future<void> _loadGeoFencePolicy() async {
    final policy = await AttendanceService.getGeoFencePolicy(userData!['organization_id']);
    if (policy == null) return;
    setState(() {
      geoEnabled = policy['geo_fencing_enabled'] == true;
      geoMode = policy['geo_fencing_mode'] ?? 'strict';
      geoTrackOnly = AttendanceService.isGeoTrackOnly(policy: policy, selectedWorkType: workTypeOptions[selectedWorkType]!);
    });
    workSites = await AttendanceService.getResolvedWorkSites(userData!);
  }

  Future<void> handlePunchInLog() async => _punch('punch_in');
  Future<void> handlePunchOutLog() async => _punch('punch_out');

  Future<void> _punch(String type) async {
    final workType = workTypeOptions[selectedWorkType];
    if (workType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error: Invalid work type'), backgroundColor: Colors.red));
      return;
    }

    final punchMethod = type == 'punch_in' 
        ? AttendanceService.punchIn 
        : AttendanceService.punchOut;

    await punchMethod(
      employee: userData!,
      selectedWorkType: workType,
      geoEnabled: geoEnabled,
      geoMode: geoMode,
      geoTrackOnly: geoTrackOnly,
      workSites: workSites,
      onShowGeoConfirm: _showGeoConfirmDialog,
      onSuccess: () async {
        setState(() { todayAttendanceFuture = fetchTodayAttendanceData(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${type == 'punch_in' ? 'Punch In' : 'Punch Out'} successful'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      },
      onError: (err) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Error: $err'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      )),
      onLoading: (val) => setState(() => loading = val),
    );
  }

  Future<bool> _showGeoConfirmDialog(String site, double distance, double allowed) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("You appear to be outside an allowed work site"),
        content: Text("You are ${distance.toStringAsFixed(0)}m from $site.\nAllowed radius is ${allowed.toStringAsFixed(0)}m.\n\nThis punch will be flagged for HR review."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm")),
        ],
      ),
    ) ?? false;
  }

  Future<Map<String, dynamic>> fetchTodayAttendanceData() async {
    if (userData == null) return {'attendance': null, 'logs': []};
    try {
      final empId = userData!['id'];
      final results = await Future.wait([
        AttendanceService.getTodayAttendance(employeeId: empId),
        AttendanceService.getTodayPunchLogs(employeeId: empId),
      ]);
      debugPrint("=========== DASHBOARD FETCH ===========");
      debugPrint(results[0].toString());
      debugPrint(results[1].toString());
      debugPrint("======================================");
      return {
        'attendance': results[0],
        'logs': results[1] ?? [],
      };
    } catch (e) {
      return {'attendance': null, 'logs': []};
    }
  }

  // Kept as a thin wrapper for backward compatibility with any older
  // callers. Delegates to the shared LeaveSummaryService so Dashboard
  // and Leave screen always show identical numbers.
  Future<LeaveSummary> fetchLeaveSummary(String? _id) {
    return LeaveSummaryService.instance.fetch();
  }


  Future<void> fetchNotifications() async {
    if (!mounted || userData == null) return;

    try {
      if (mounted) {
        setState(() => loadingNotifications = true);
      }

      final res = await supabase
          .from('notifications')
          .select()
          .eq('recipient_employee_id', userData!['id'])
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        notifications = List<Map<String, dynamic>>.from(res);
        unreadCount =
            notifications.where((n) => n['read'] == false).length;
      });

      AppBadgePlus.updateBadge(unreadCount);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() => loadingNotifications = false);
      }
    }
  }

  Future<void> fetchMealVoucher() async {
    final empId = userData?['id'], orgId = userData?['organization_id'];
    if (empId == null || orgId == null) return;
    final eligibility = await supabase.from('employee_eligibility').select('is_meal_voucher_eligible').eq('employee_id', empId).maybeSingle();
    if (eligibility?['is_meal_voucher_eligible'] != true) return;
    final config = await supabase.from('meal_voucher_configuration').select().eq('organization_id', orgId).maybeSingle();
    if (config == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final orders = await supabase.from('meal_orders').select().eq('employee_id', empId).eq('order_date', today).neq('status', 'cancelled').limit(1);
    setState(() { showMealVoucher = true; mealVoucherState = {'amount': config['per_meal_amount'], 'cutoff_hours': config['order_cutoff_hours'] ?? 6, 'order': orders.isNotEmpty ? orders.first : null}; });
  }

  Future<void> placeMealOrder() async {
    final res = await supabase.rpc('place_meal_order', params: {'p_employee_id': userData?['id'], 'p_organization_id': userData?['organization_id']});
    if (res?['success'] == true) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Meal ordered successfully'))); await fetchMealVoucher(); }
  }

  Future<void> fetchOrganizationDetails(String id) async { final org = await supabase.from('organizations').select().eq('id', id).maybeSingle(); setState(() { orgDetails = org; organizationName = org?['name'] ?? '--'; }); }
  Future<void> fetchCompanyLogo() async { final orgId = userData?['organization_id']; final orgResp = await supabase.from('organizations').select('logo_url').eq('id', orgId).maybeSingle(); if (orgResp?['logo_url'] != null) setState(() => companyLogoUrl = orgResp!['logo_url']); }
  Future<void> fetchManagerData(String email) async { final resp = await supabase.from('employee_records').select().eq('email', email).maybeSingle(); if (resp != null) setState(() { managerName = resp['full_name'] ?? '--'; managerEmail = resp['email'] ?? '--'; }); }

  @override
  void dispose() {
    if (_notificationChannel != null) {
      supabase.removeChannel(_notificationChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(userEmail: widget.email, userData: userData ?? {}, companyLogoUrl: companyLogoUrl, fetchHrmsContext: fetchHrmsContext, currentRoute: DrawerRoute.dashboard),
      body: loadingProfile
          ? dashboardFullSkeleton()
          : CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

        SliverAppBar(expandedHeight: 160, floating: false, pinned: true, automaticallyImplyLeading: false, backgroundColor: Colors.white, elevation: 0, actions: [
          Padding(padding: const EdgeInsets.only(right: 8, top: 12), child: _circleIconBtn(icon: "assets/icons/notification.svg", onTap: () { final empId = (userData?['id'] ?? userData?['employee_id'])?.toString() ?? ''; if (empId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.email, userData: userData ?? {}, fetchHrmsContext: fetchHrmsContext))); })),
          Padding(padding: const EdgeInsets.only(right: 16, top: 12), child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer())),
          const SizedBox(width: 1),
        ], flexibleSpace: FlexibleSpaceBar(background: Container(padding: const EdgeInsets.fromLTRB(24, 60, 24, 16), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFD7E8FF), Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_getGreeting(), style: EmployeeUi.header(26)), const SizedBox(height: 2), Text(userData?['full_name'] ?? "--", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w600, color: EmployeeUi.text)), const SizedBox(height: 12), Text(organizationName ?? "--", style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: EmployeeUi.muted))])))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildAttendanceCard(), const SizedBox(height: 24), buildMealVoucherCard(), Text("Quick Actions", style: EmployeeUi.title(16)), const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _actionTile("Leave", "assets/icons/leaves.svg", const Color(0xFFD7E8FF), () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: userData ?? {}, fetchHrmsContext: fetchHrmsContext)))),
            _actionTile("Payslip", "assets/icons/payroll.svg", const Color(0xFFD4F3F7), () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: userData ?? {}, fetchHrmsContext: fetchHrmsContext)))),
            _actionTile("Time", "assets/icons/attendance.svg", const Color(0xFFEBDFF6), () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: userData!, fetchHrmsContext: fetchHrmsContext)))),
          ]),
          const SizedBox(height: 32), _buildLeaveBalanceSection(), const SizedBox(height: 32), _buildManagerCard(), const SizedBox(height: 50),
        ]))),
      ]),
      bottomNavigationBar: BottomNavigationBar(type: BottomNavigationBarType.fixed, selectedFontSize: 10, unselectedFontSize: 9, currentIndex: _bottomTabIndex, selectedItemColor: Colors.blueAccent, unselectedItemColor: Colors.grey, showSelectedLabels: true, showUnselectedLabels: true, onTap: (index) {
        if (index == 0) return;
        if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: userData ?? {}, fetchHrmsContext: fetchHrmsContext))); return; }
        if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: userData!, fetchHrmsContext: fetchHrmsContext))); return; }
        if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: userData ?? {}, fetchHrmsContext: fetchHrmsContext))); return; }
        if (index == 4) _scaffoldKey.currentState?.openEndDrawer();
      }, items: [
        BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: ColorFilter.mode(_bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
        BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
        BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
        BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
        BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
      ]),
    );
  }

  String _getGreeting() { final h = DateTime.now().hour; if (h < 12) return "Good Morning"; if (h < 17) return "Good Afternoon"; return "Good Evening"; }
  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) => Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]), child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap));
  Widget _actionTile(String label, String icon, Color color, VoidCallback onTap) => InkWell(onTap: onTap, child: Column(children: [Container(width: 60, height: 60, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: SvgPicture.asset(icon, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn))), const SizedBox(height: 8), Text(label, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600))]));

  Widget _buildAttendanceCard() => Container(padding: const EdgeInsets.all(24), decoration: EmployeeUi.cardDecoration(color: EmployeeUi.blueBg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Today's Attendance", style: EmployeeUi.title(16)), const LiveClock()]),
    const SizedBox(height: 20),
    FutureBuilder<Map<String, dynamic>>(future: todayAttendanceFuture, builder: (context, snapshot) {
      final data = snapshot.data;
      final att = data?['attendance'];
      final logs = List<Map<String, dynamic>>.from(data?['logs'] ?? []);
      
      // Calculate state exactly like AttendanceScreen
      final punchLogs = logs
          .where((e) =>
      e['punch_type'] == 'punch_in' ||
          e['punch_type'] == 'punch_out')
          .toList();

      final bool isPunchedIn;

      if (punchLogs.isEmpty) {
        isPunchedIn = false;
      } else {
        punchLogs.sort(
              (a, b) => DateTime.parse(a['punch_time'])
              .compareTo(DateTime.parse(b['punch_time'])),
        );

        isPunchedIn = punchLogs.last['punch_type'] == 'punch_in';
      }

      final latestIn = logs.where((r) => r['punch_type'] == 'punch_in').toList();
      final latestOut = logs.where((r) => r['punch_type'] == 'punch_out').toList();
      final lastPunchIn = latestIn.isNotEmpty ? latestIn.last['punch_time'] : null;
      final lastPunchOut = latestOut.isNotEmpty ? latestOut.last['punch_time'] : null;

      return Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _timeMetric("Punch In", lastPunchIn != null ? DateFormat('hh:mm a').format(DateTime.parse(lastPunchIn).toLocal()) : "--:--"), 
          _timeMetric("Punch Out", lastPunchOut != null ? DateFormat('hh:mm a').format(DateTime.parse(lastPunchOut).toLocal()) : "--:--")
        ]),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: loading ? null : () => isPunchedIn ? handlePunchOutLog() : handlePunchInLog(), style: ElevatedButton.styleFrom(backgroundColor: isPunchedIn ? Colors.red.shade400 : EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0), child: loading ? const CircularProgressIndicator(color: Colors.white) : Text(isPunchedIn ? "Punch Out" : "Punch In Now", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      ]);
    }),
  ]));

  Widget _timeMetric(String label, String value) => Column(children: [Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: EmployeeUi.header(18))]);

  Widget _buildLeaveBalanceSection() => FutureBuilder<LeaveSummary>(future: leaveSummaryFuture, builder: (context, snapshot) {
    final data = snapshot.data ?? LeaveSummary.empty();
    return Container(padding: const EdgeInsets.all(24), decoration: EmployeeUi.cardDecoration(color: EmployeeUi.peachBg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Leave Balance", style: EmployeeUi.title(16)), Text(data.year.toString(), style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black26))]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _balanceMetric("Allocated", data.totalAllocated.toString(), Colors.blue),
        _balanceMetric("Used", data.totalUsed.toString(), Colors.green),
        _balanceMetric("Remaining", data.totalRemaining.toString(), Colors.teal),
        _balanceMetric("Pending", data.pendingRequests.toString(), Colors.orange),
        _balanceMetric("Policies", data.leavePolicyCount.toString(), Colors.deepPurple),
      ]),
    ]));
  });


  Widget _balanceMetric(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45)), const SizedBox(height: 4), Text(value, style: EmployeeUi.header(24).copyWith(color: color))]);

  Widget _buildManagerCard() => Container(padding: const EdgeInsets.all(20), decoration: EmployeeUi.cardDecoration(color: EmployeeUi.tealBg), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.person_outline, color: Color(0xFF00ACC1))), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Reporting Manager", style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF00796B))), const SizedBox(height: 4), Text(managerName, style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)), Text(managerEmail, style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54))]))]));

  Widget buildMealVoucherCard() {
    if (!showMealVoucher || mealVoucherState == null) return const SizedBox.shrink();
    final amount = mealVoucherState!['amount'], order = mealVoucherState!['order'], isOrdered = order != null, now = DateTime.now();
    return Container(margin: const EdgeInsets.only(top: 12, bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: LinearGradient(colors: isOrdered ? [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)] : [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)]), borderRadius: BorderRadius.circular(16), border: Border.all(color: isOrdered ? Colors.green.shade200 : Colors.orange.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.restaurant, color: isOrdered ? Colors.green : Colors.deepOrange), const SizedBox(width: 8), Text("Meal Order", style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w600)), const Spacer(), Text("₹$amount / meal", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.black87))]),
      const SizedBox(height: 6), Text("${DateFormat('MMM dd, yyyy').format(now)} • ${DateFormat('EEEE').format(now)}", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 14),
      if (!isOrdered) ...[Text("Order your meal for today. It will be arranged as per your shift timing.", style: GoogleFonts.montserrat(fontSize: 13)), const SizedBox(height: 14), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: placeMealOrder, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), child: const Text("Order Meal", style: TextStyle(fontWeight: FontWeight.w600))))]
      else ...[Row(children: const [Icon(Icons.check_circle, color: Colors.green, size: 18), SizedBox(width: 6), Text("Meal Ordered for Today", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green))]), const SizedBox(height: 8), Text("Voucher Code", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)), Text(order['voucher_code'] ?? "--", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2))],
    ]));
  }

  Future<Map<String, dynamic>> fetchHrmsContext() async {
    try {
      final empId = userData?['id'], orgId = userData?['organization_id'];
      if (empId == null || orgId == null) return {"error": "Missing info"};
      final results = await Future.wait([supabase.from('employee_records').select().eq('id', empId).maybeSingle(), supabase.from('organizations').select().eq('id', orgId).maybeSingle(), supabase.from('announcements').select().eq('organization_id', orgId).order('created_at', ascending: false), supabase.from('leave_balances').select().eq('employee_id', empId), supabase.from('leave_applications').select().eq('employee_id', empId).order('created_at', ascending: false), supabase.from('notifications').select().eq('recipient_employee_id', empId).order('created_at', ascending: false), supabase.from('attendance_punch_logs').select().eq('employee_id', empId).order('punch_time', ascending: true)]);
      return {"employee_profile": results[0], "organization_details": results[1], "announcements": results[2] ?? [], "leave_balances": results[3] ?? [], "leave_applications": results[4] ?? [], "notifications": results[5] ?? [], "attendance_punch_logs": results[6] ?? []};
    } catch (e) { return {"error": e.toString()}; }
  }
}
