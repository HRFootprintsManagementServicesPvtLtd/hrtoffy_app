import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'payslip_screen.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';
import '../models/work_site.dart';
import 'live_tracking_screen.dart';
import '../services/attendance_service.dart';

class TimeAttendanceScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const TimeAttendanceScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<TimeAttendanceScreen> createState() => _TimeAttendanceScreenState();
}

class _TimeAttendanceScreenState extends State<TimeAttendanceScreen>
    with TickerProviderStateMixin, RefreshableScreen<TimeAttendanceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 2;
  String? companyLogoUrl;
  final SupabaseClient supabase = Supabase.instance.client;
  TabController? _tabController;
  Map<String, dynamic>? employee;

  @override
  void initState() {
    super.initState();
    companyLogoUrl = widget.userData['company_logo_url'];
    _tabController = TabController(length: 3, vsync: this);
    startLoad();
  }

  @override
  Future<void> loadData() async {
    try {
      final email = widget.userEmail;
      final emp = await supabase.from('employee_records').select().eq('email', email.toLowerCase()).maybeSingle();
      setState(() {
        employee = emp != null ? Map<String, dynamic>.from(emp) : null;
      });
    } catch (e) {
      debugPrint('loadData error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildRefreshable(
      skeleton: const SkeletonAttendance(),
      childBuilder: () {
        if (employee == null) return const Center(child: Text("Employee data not found"));
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: EmployeeUi.pageBg,
          endDrawer: AppDrawer(
            userEmail: widget.userEmail,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
            currentRoute: DrawerRoute.attendance,
            companyLogoUrl: companyLogoUrl,
          ),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.black87),
            title: Text('Attendance', style: EmployeeUi.title(18)),
            actions: [
              IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                floating: false,
                pinned: false,
                primary: false,
                toolbarHeight: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFD4F3F7), Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text("Time & Attendance", style: EmployeeUi.header(24)),
                        const SizedBox(height: 4),
                        Text("Track your shifts and punch history", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
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
                        tabs: const [Tab(text: 'Attendance'), Tab(text: 'My History'), Tab(text: 'Regularize')],
                      ),
                    ),
                  ],
                ),
              ),
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    AttendanceTab(employee: employee!),
                    MyHistoryTab(employee: employee!),
                    RegularizationTab(employee: employee!),
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
              if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id'].toString()))); return; }
              if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
              if (index == 2) return;
              if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
              if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
            },
            items: [
              BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22), label: 'Dashboard'),
              BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22), label: 'Leave'),
              BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22), label: 'Attendance'),
              BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22), label: 'Payslip'),
              BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}

class AttendanceTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  const AttendanceTab({Key? key, required this.employee}) : super(key: key);
  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> with TickerProviderStateMixin {
  String? attendanceRecordingMethod;
  bool get isBiometricOnly => attendanceRecordingMethod == 'biometric';
  bool get isInSystemAllowed => attendanceRecordingMethod == 'in_system' || attendanceRecordingMethod == 'both';

  final supabase = Supabase.instance.client;
  bool loading = false;
  bool hasPunchedIn = false;
  Map<String, dynamic>? todayAttendance;
  List<Map<String, dynamic>> punchLogs = [];
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  final Map<String, String> workTypes = {'On-Duty': 'on-duty', 'Work From Home': 'work-from-home', 'On-Site': 'on-site'};
  String selectedWorkType = 'on-duty';

  Map<String, dynamic>? geoPolicy;
  List<WorkSite> workSites = [];
  bool geoChecking = false;
  bool? geoInFence;
  double? geoDistance;
  String? nearestSiteName;
  String geoMode = 'strict';
  bool geoEnabled = false;
  bool geoTrackOnly = false;
  double? gpsAccuracy;
  bool geoPermissionDenied = false;
  LocationPermission? currentPermission;

  @override
  void initState() {
    super.initState();
    _startClock();
    _loadAttendance();
    _loadAttendanceRecordingMethod();
    _loadGeoFencePolicy();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  Future<void> _loadAttendanceRecordingMethod() async {
    try {
      final orgId = widget.employee['organization_id'];
      if (orgId == null) return;
      final org = await supabase.from('organizations').select('attendance_recording_method').eq('id', orgId).maybeSingle();
      setState(() => attendanceRecordingMethod = org?['attendance_recording_method'] ?? 'in_system');
    } catch (e) { debugPrint('loadAttendanceRecordingMethod error: $e'); }
  }

  Future<void> _loadGeoFencePolicy() async {
    try {
      final orgId = widget.employee['organization_id'];
      final policy = await AttendanceService.getGeoFencePolicy(orgId);
      if (policy == null) return;

      setState(() {
        geoPolicy = policy;
        geoEnabled = policy['geo_fencing_enabled'] == true;
        geoMode = policy['geo_fencing_mode'] ?? 'strict';
        geoTrackOnly = AttendanceService.isGeoTrackOnly(policy: policy, selectedWorkType: selectedWorkType);
      });

      await _loadResolvedWorkSites();
      if (geoEnabled && workSites.isNotEmpty) await _checkGeoFence();
    } catch (e) { debugPrint('geo policy error $e'); }
  }

  Future<void> _loadResolvedWorkSites() async {
    try {
      workSites = await AttendanceService.getResolvedWorkSites(widget.employee);
    } catch (e) { debugPrint('load work sites error $e'); }
  }

  Future<void> _loadAttendance() async {
    setState(() => loading = true);
    try {
      final empId = widget.employee['id'];
      final att = await AttendanceService.getTodayAttendance(employeeId: empId);
      final logs = await AttendanceService.getTodayPunchLogs(employeeId: empId);
      
      setState(() {
        todayAttendance = att;
        punchLogs = logs;
        hasPunchedIn = att != null && att['punch_in_time'] != null && att['punch_out_time'] == null;
      });
    } catch (e) { debugPrint('loadAttendance error: $e'); }
    finally { setState(() => loading = false); }
  }

  Future<Map<String, dynamic>?> _checkGeoFence() async {
    try {
      setState(() => geoChecking = true);
      final geoResult = await AttendanceService.checkGeoFence(workSites: workSites);
      if (geoResult != null) {
        setState(() {
          geoDistance = geoResult['distance'];
          geoInFence = geoResult['inFence'];
          nearestSiteName = geoResult['site'].name;
          gpsAccuracy = geoResult['position'].accuracy;
        });
      }
      return geoResult;
    } catch (e) {
      setState(() => geoPermissionDenied = true);
      return null;
    } finally {
      setState(() => geoChecking = false);
    }
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

  Future<void> _punch(String type) async {
    final punchMethod = type == 'punch_in' 
        ? AttendanceService.punchIn 
        : AttendanceService.punchOut;

    await punchMethod(
      employee: widget.employee,
      selectedWorkType: selectedWorkType,
      geoEnabled: geoEnabled,
      geoMode: geoMode,
      geoTrackOnly: geoTrackOnly,
      workSites: workSites,
      onShowGeoConfirm: _showGeoConfirmDialog,
      onSuccess: () async {
        await _loadAttendance();
        _showSuccess(type == 'punch_in' ? 'Punch In successful' : 'Punch Out successful');
      },
      onError: _showError,
      onLoading: (val) => setState(() => loading = val),
    );
  }

  @override
  Widget build(BuildContext context) {
    final att = todayAttendance;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.access_time, color: Colors.blue),
            const SizedBox(width: 8),
            Text(DateFormat('MMM dd, yyyy – hh:mm:ss a').format(_now), style: GoogleFonts.montserrat(fontSize: 14)),
            const Spacer(),
            IconButton(onPressed: _loadAttendance, icon: const Icon(Icons.refresh, color: Colors.blue)),
          ]),
          const SizedBox(height: 10),
          if (geoEnabled) _geoStatusCard(),
          if (geoTrackOnly) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(14)), child: Row(children: [const Icon(Icons.info_outline, color: Colors.orange), const SizedBox(width: 10), Expanded(child: Text('Geo not enforced today. Location will still be recorded.', style: GoogleFonts.montserrat(fontSize: 13)))])) ,
          _todayCard(att),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: selectedWorkType,
            decoration: InputDecoration(labelText: 'Work Type', labelStyle: GoogleFonts.montserrat(), border: const OutlineInputBorder()),
            items: workTypes.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: GoogleFonts.montserrat()))).toList(),
            onChanged: (v) async {
              setState(() => selectedWorkType = v ?? 'on-duty');
              await _loadGeoFencePolicy();
            },
          ),
          const SizedBox(height: 16),
          if (isBiometricOnly) _biometricOnlyCard(),
          if (isInSystemAllowed) SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: loading || geoChecking || (geoEnabled && geoMode == 'strict' && geoTrackOnly == false && geoInFence == false) ? null : () => _punch(hasPunchedIn ? 'punch_out' : 'punch_in'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
            child: loading || geoChecking ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), const SizedBox(width: 12), Text(geoChecking ? "Checking location..." : "Please wait...", style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))]) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(hasPunchedIn ? Icons.logout : Icons.login, color: Colors.white, size: 22), const SizedBox(width: 10), Text(hasPunchedIn ? "Punch Out Now" : "Punch In Now", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white))]),
          )),
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Today\'s Logs', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.map, color: Colors.blue), onPressed: () { if (punchLogs.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No punch records found'))); return; } Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingMapScreen(logs: punchLogs))); })]),
          const SizedBox(height: 8),
          Column(children: punchLogs.map((r) => _buildLogCard(r)).toList()),
        ],
      ),
    );
  }

  Widget _geoStatusCard() {
    return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(20), decoration: EmployeeUi.cardDecoration(color: EmployeeUi.tealBg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Geo Fence Status", style: EmployeeUi.title(16)), Icon(geoInFence == true ? Icons.verified : Icons.location_searching, color: geoInFence == true ? Colors.green : Colors.blueGrey, size: 20)]), const SizedBox(height: 12), if (nearestSiteName != null) Text("📍 Near: $nearestSiteName (${geoDistance?.toStringAsFixed(0)}m)", style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w500)), const SizedBox(height: 8), Text(geoInFence == true ? "You are within the allowed office perimeter." : "Checking your proximity to office...", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54))]));
  }

  Widget _todayCard(Map<String, dynamic>? att) {
    final latestIn = punchLogs.where((r) => r['punch_type'] == 'punch_in').map((r) => r['punch_time']).toList();
    final latestOut = punchLogs.where((r) => r['punch_type'] == 'punch_out').map((r) => r['punch_time']).toList();
    final lastPunchIn = latestIn.isNotEmpty ? latestIn.last : null;
    final lastPunchOut = latestOut.isNotEmpty ? latestOut.last : null;
    return Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: EmployeeUi.cardDecoration(color: EmployeeUi.blueBg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Today's Summary", style: EmployeeUi.title(16)), const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_timeMetric("Punched In", lastPunchIn != null ? DateFormat('hh:mm a').format(DateTime.parse(lastPunchIn).toLocal()) : "--:--"), _timeMetric("Punched Out", lastPunchOut != null ? DateFormat('hh:mm a').format(DateTime.parse(lastPunchOut).toLocal()) : "--:--")]), const SizedBox(height: 16), Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)), child: Text("Mode: ${att?['work_type'] ?? 'On-Duty'}", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade700))))]));
  }

  Widget _timeMetric(String label, String value) => Column(children: [Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: EmployeeUi.header(18))]);

  Widget _biometricOnlyCard() => Container(width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFD180))), child: Column(children: [const Icon(Icons.fingerprint, size: 40, color: Colors.deepOrange), const SizedBox(height: 10), Text("Biometric Only", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)), const SizedBox(height: 6), Text("Your organization requires attendance via biometric device", textAlign: TextAlign.center, style: GoogleFonts.montserrat(fontSize: 13))]));

  Widget _buildLogCard(Map<String, dynamic> r) {
    final t = r['punch_time'];
    final type = r['punch_type'];
    final addr = r['punch_address'] ?? "-";
    return Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20), decoration: EmployeeUi.cardDecoration(), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: type == 'punch_in' ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(type == 'punch_in' ? Icons.login : Icons.logout, color: type == 'punch_in' ? Colors.green : Colors.red, size: 20)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(type.replaceAll('_', ' ').toUpperCase(), style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)), const SizedBox(height: 4), Text(DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.parse(t).toLocal()), style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: EmployeeUi.text)), const SizedBox(height: 4), Text(addr, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis)]))]));
  }
}

class MyHistoryTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  const MyHistoryTab({Key? key, required this.employee}) : super(key: key);
  @override
  State<MyHistoryTab> createState() => _MyHistoryTabState();
}

class _MyHistoryTabState extends State<MyHistoryTab> {
  final supabase = Supabase.instance.client;
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> logs = [];
  bool loading = false;

  Future<void> _loadLogs() async {
    setState(() => loading = true);
    try {
      final empId = widget.employee['id'];
      final day = DateFormat('yyyy-MM-dd').format(selectedDate);
      final res = await AttendanceService.getPunchLogs(employeeId: empId, date: day);
      setState(() => logs = res);
    } catch (e) { debugPrint('myHistory load logs error: $e'); }
    finally { setState(() => loading = false); }
  }

  @override
  void initState() { super.initState(); _loadLogs(); }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Select Date", style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TableCalendar(firstDay: DateTime(1990), lastDay: DateTime(2100), focusedDay: selectedDate, selectedDayPredicate: (day) => isSameDay(selectedDate, day), onDaySelected: (sel, foc) { setState(() => selectedDate = sel); _loadLogs(); }, headerStyle: const HeaderStyle(titleCentered: true, formatButtonVisible: false), calendarStyle: CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle), selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle))),
          const SizedBox(height: 18),
          Text("Punch Logs", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          if (loading) const Center(child: CircularProgressIndicator(color: Colors.blue)),
          if (!loading && logs.isEmpty) const Center(child: Padding(padding: EdgeInsets.only(top: 30), child: Text("No punches for selected date"))),
          Column(children: logs.map((r) => _buildHistoryCard(r)).toList()),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> r) {
    final isIn = r['punch_type'] == 'punch_in';
    return Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(shape: BoxShape.circle, color: isIn ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15)), child: Icon(isIn ? Icons.login : Icons.logout, color: isIn ? Colors.green : Colors.red, size: 22)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['punch_type'].toString().replaceAll('_', ' ').toUpperCase(), style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(DateFormat('hh:mm a').format(DateTime.parse(r['punch_time']).toLocal()), style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black87)), const SizedBox(height: 4), Text(r['punch_address'] ?? '-', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis)]))]));
  }
}

class RegularizationTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  const RegularizationTab({Key? key, required this.employee}) : super(key: key);
  @override
  State<RegularizationTab> createState() => _RegularizationTabState();
}

class _RegularizationTabState extends State<RegularizationTab> {
  final supabase = Supabase.instance.client;
  DateTime? date;
  final TextEditingController inCtrl = TextEditingController(), outCtrl = TextEditingController(), reasonCtrl = TextEditingController();
  bool loading = false;

  @override
  void dispose() { inCtrl.dispose(); outCtrl.dispose(); reasonCtrl.dispose(); super.dispose(); }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final res = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (res != null) setState(() => ctrl.text = '${res.hour.toString().padLeft(2, '0')}:${res.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _submit() async {
    if (date == null || inCtrl.text.isEmpty || reasonCtrl.text.isEmpty) { _error("Please fill all required fields"); return; }
    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      final emp = await supabase.from("employee_records").select("id, organization_id, manager_id").eq("email", user?.email ?? "").maybeSingle();
      if (emp == null) throw Exception("Employee not found");
      final dateStr = DateFormat("yyyy-MM-dd").format(date!);
      await supabase.from("attendance_regularization_requests").insert({"employee_id": emp["id"], "organization_id": emp["organization_id"], "manager_id": emp["manager_id"], "date": dateStr, "requested_punch_in": _combine(dateStr, inCtrl.text), "requested_punch_out": outCtrl.text.isNotEmpty ? _combine(dateStr, outCtrl.text) : null, "reason": reasonCtrl.text, "status": "pending", "created_at": DateTime.now().toUtc().toIso8601String()});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("✅ Regularization request submitted"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
      setState(() { date = null; inCtrl.clear(); outCtrl.clear(); reasonCtrl.clear(); });
    } catch (e) { _error(e.toString()); }
    finally { setState(() => loading = false); }
  }

  String _combine(String d, String t) {
    final p = t.split(":");
    return DateTime.parse(d).add(Duration(hours: int.parse(p[0]), minutes: int.parse(p[1]))).toUtc().toIso8601String();
  }

  void _error(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Regularization Request", style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Text("Select Date", style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)), const SizedBox(height: 6), InkWell(onTap: () async { final p = await showDatePicker(context: context, initialDate: date ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100)); if (p != null) setState(() => date = p); }, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300), color: Colors.grey.shade50), child: Row(children: [const Icon(Icons.calendar_month, color: Colors.blue), const SizedBox(width: 10), Text(date == null ? "Pick a date" : DateFormat("yMMMMd").format(date!))]))), const SizedBox(height: 16), Text("Requested Punch In", style: GoogleFonts.montserrat()), const SizedBox(height: 6), InkWell(onTap: () => _pickTime(inCtrl), child: _box(inCtrl.text.isEmpty ? "Select time" : inCtrl.text)), const SizedBox(height: 16), Text("Requested Punch Out (optional)", style: GoogleFonts.montserrat()), const SizedBox(height: 6), InkWell(onTap: () => _pickTime(outCtrl), child: _box(outCtrl.text.isEmpty ? "Select time" : outCtrl.text)), const SizedBox(height: 16), Text("Reason", style: GoogleFonts.montserrat()), const SizedBox(height: 6), TextField(controller: reasonCtrl, maxLines: 3, decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), const SizedBox(height: 18), ElevatedButton(onPressed: loading ? null : _submit, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit", style: TextStyle(color: Colors.white)))])));
  }

  Widget _box(String t) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: Row(children: [const Icon(Icons.access_time, color: Colors.blue), const SizedBox(width: 10), Text(t)]));
}
