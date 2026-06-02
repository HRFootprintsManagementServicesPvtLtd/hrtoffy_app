
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';   // for SkeletonProfile or we make a new one
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/bottom_nav_toffy_button.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'payslip_screen.dart';
import '../widgets/drawer_route.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';
import 'live_tracking_screen.dart';
import '../services/geo_tracker_service.dart';



const String googleGeocodingApiKey = 'AIzaSyB4um8D3zbPD4QnrRkZEqCs30Bp6HCR5a0';
class TimeAttendanceScreen extends StatefulWidget {
  // ================= ATTENDANCE RECORDING METHOD HELPERS =================

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

  int _bottomTabIndex = 2; // Attendance tab selected
  String? companyLogoUrl;

  final SupabaseClient supabase = Supabase.instance.client;
  TabController? _tabController;
  Map<String, dynamic>? employee;
  @override
  void initState() {
    super.initState();
    companyLogoUrl = widget.userData['company_logo_url'];
    _tabController = TabController(length: 3, vsync: this);
    startLoad();   // this triggers skeleton + loads data
  }

  @override
  Future<void> loadData() async {
    try {
      final email = widget.userEmail ?? supabase.auth.currentUser?.email;
      if (email == null) {
        employee = null;
        return;
      }

      final emp = await supabase
          .from('employee_records')
          .select()
          .eq('email', email.toLowerCase())
          .maybeSingle();

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
        if (employee == null) {
          return const Center(
            child: Text("Employee data not found"),
          );
        }
        return Scaffold(
          key: _scaffoldKey,

          endDrawer: AppDrawer(
            userEmail: widget.userEmail,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
            currentRoute: DrawerRoute.attendance,

            companyLogoUrl: companyLogoUrl,
          ),

          appBar: AppBar(
            title: Text(
              'Attendance',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
            ),
          ),

          body: Stack(
            children: [
              Column(
                children: [
                  // ⭐ Your existing content
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.blue, // ✅ ACTIVE TAB COLOR
                        borderRadius: BorderRadius.circular(30),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white, // ✅ ACTIVE TEXT
                      unselectedLabelColor: Colors.black87, // ✅ INACTIVE TEXT
                      labelStyle: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent, // ❌ removes bottom line
                      tabs: const [
                        Tab(text: 'Attendance'),
                        Tab(text: 'My History'),
                        Tab(text: 'Regularization'),
                      ],
                    ),
                  ),

                  Expanded(
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

              // ✅ Toffy overlay (THIS IS THE CORRECT PLACE)

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
              if (index == 0) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                      email: widget.userEmail,
                      employeeId: widget.userData['id'].toString(),
                    ),
                  ),
                );
                return;
              }

              if (index == 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LeavesScreen(
                      email: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),

                  ),
                );
                return;
              }

              if (index == 2) {
                return; // already on attendance
              }

              if (index == 3) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PayslipScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),

                  ),
                );
                return;
              }

              if (index == 4) {
                _scaffoldKey.currentState?.openEndDrawer();
                return;
              }

            },

            items: [
              BottomNavigationBarItem(
                icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22),
                label: 'Leave',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22),
                label: 'Attendance',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22),
                label: 'Payslip',
              ),
              BottomNavigationBarItem(
                icon: SvgPicture.asset("assets/icons/menu.svg", width: 22),
                label: 'More',
              ),

            ],
          ),

        );
      },
    );
  }
}
   //Attendance Tab
class AttendanceTab extends StatefulWidget {
  final Map<String, dynamic> employee;
  const AttendanceTab({Key? key, required this.employee}) : super(key: key);
  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}
class _AttendanceTabState extends State<AttendanceTab> with TickerProviderStateMixin {
  String? attendanceRecordingMethod;
  // ================= ATTENDANCE RECORDING HELPERS =================
  bool get isBiometricOnly {
    return attendanceRecordingMethod == 'biometric';
  }
  bool get isInSystemAllowed {
    return attendanceRecordingMethod == 'in_system' ||
        attendanceRecordingMethod == 'both';
  }
  final supabase = Supabase.instance.client;
  bool loading = false;
  bool hasPunchedIn = false;

  Map<String, dynamic>? todayAttendance;
  List<Map<String, dynamic>> punchLogs = [];
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  // ================= SNACKBAR HELPERS =================

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // Work type options exactly as required
  final Map<String, String> workTypes = {
    'On-Duty': 'on-duty',
    'Work From Home': 'work-from-home',
    'On-Site': 'on-site'
  };
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
  RealtimeChannel? punchChannel;


  LocationPermission? currentPermission;

  String _formatLocalTime(String timeStr) {
    try {
      final dt = DateTime.parse(timeStr).toLocal(); // UTC → IST
      return DateFormat('yyyy-MM-dd hh:mm a').format(dt);
    } catch (_) {
      return timeStr;
    }
  }
  @override
  void initState() {
    super.initState();
    _startClock();
    _loadAttendance();
    _loadAttendanceRecordingMethod(); // ✅ ADD THIS LINE
    _subscribePunchLogs();
    _loadGeoFencePolicy();
  }
  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }
  void _subscribePunchLogs() {
    final empId = widget.employee['id'];

    punchChannel = supabase
        .channel('attendance-live-$empId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'attendance_punch_logs',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'employee_id',
        value: empId.toString(),
      ),
      callback: (payload) async {
        await _loadAttendance();

        if (geoEnabled &&
            workSites.isNotEmpty) {
          await _checkGeoFence();
        }
      },
    )
        .subscribe();
  }
  @override
  void dispose() {
    if (punchChannel != null) {
      supabase.removeChannel(punchChannel!);
    }
    _clockTimer?.cancel();
    super.dispose();
  }
  Future<String> _getAddress(double lat, double lng) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleGeocodingApiKey';

      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);

      if (data['results'] != null && data['results'].isNotEmpty) {
        // 🔥 Prefer NON plus-code addresses
        for (final r in data['results']) {
          final formatted = r['formatted_address'] as String;

          // Skip Plus Codes like "G96M+GW"
          if (!formatted.contains('+')) {
            return formatted;
          }
        }

        // Fallback to first result if all contain plus codes
        return data['results'][0]['formatted_address'];
      }
    } catch (e) {
      debugPrint('geocode error: $e');
    }

    return '$lat, $lng';
  }

  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings(); // 🔥 opens settings
      throw Exception('Location services disabled');
    }

    LocationPermission perm = await Geolocator.checkPermission();
    currentPermission = perm;

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings(); // 🔥 opens app settings
      throw Exception('Location permission denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _loadAttendanceRecordingMethod() async {
    try {
      final orgId = widget.employee['organization_id'];
      if (orgId == null) return;

      final org = await supabase
          .from('organizations')
          .select('attendance_recording_method')
          .eq('id', orgId)
          .maybeSingle();

      setState(() {
        attendanceRecordingMethod =
            org?['attendance_recording_method'] ?? 'in_system';
      });
    } catch (e) {
      debugPrint('loadAttendanceRecordingMethod error: $e');
    }
  }

  Future<void> _loadGeoFencePolicy() async {
    try {
      final orgId = widget.employee['organization_id'];

      final org = await supabase
          .from('organization_settings')
          .select('attendance_policies')
          .eq('organization_id', orgId)
          .maybeSingle();

      final policy = org?['attendance_policies'];

      if (policy == null) return;

      geoPolicy = policy;

      geoEnabled = policy['geo_fencing_enabled'] == true;

      geoMode = policy['geo_fencing_mode'] ?? 'strict';

      final onlyForOffice =
          policy['geo_only_for_office'] == true;

      geoTrackOnly =
          onlyForOffice &&
              selectedWorkType != 'on-duty';

      await _loadResolvedWorkSites();
      if (geoEnabled && workSites.isNotEmpty) {
        await _checkGeoFence();
      }
      if (geoEnabled && workSites.isNotEmpty) {
        _checkGeoFence();
      }

      setState(() {});
    } catch (e) {
      debugPrint('geo policy error $e');
    }
  }

  Future<void> _loadResolvedWorkSites() async {
    try {
      final empId = widget.employee['id'];

      final branchId = widget.employee['branch_id'];

      final entityId = widget.employee['entity_id'];

      final orgId = widget.employee['organization_id'];

      List data = [];

      final direct = await supabase
          .from('work_site_assignments')
          .select('work_sites(*)')
          .eq('employee_id', empId);

      if (direct.isNotEmpty) {
        data = direct.map((e) => e['work_sites']).toList();
      } else {
        final branchSites = await supabase
            .from('work_sites')
            .select()
            .eq('branch_id', branchId)
            .eq('is_active', true);

        if (branchSites.isNotEmpty) {
          data = branchSites;
        } else {
          final entitySites = await supabase
              .from('work_sites')
              .select()
              .eq('entity_id', entityId)
              .eq('is_active', true);

          if (entitySites.isNotEmpty) {
            data = entitySites;
          } else {
            data = await supabase
                .from('work_sites')
                .select()
                .eq('organization_id', orgId)
                .eq('is_active', true);
          }
        }
      }

      workSites = data
          .map((e) => WorkSite.fromMap(e))
          .toList();
    } catch (e) {
      debugPrint('load work sites error $e');
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => loading = true);
    try {
      final empId = widget.employee['id'];
      if (empId == null) return;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final att = await supabase
          .from('attendance')
          .select()
          .eq('employee_id', empId)
          .eq('date', today)
          .maybeSingle();
      final logs = await supabase
          .from('attendance_punch_logs')
          .select()
          .eq('employee_id', empId)
          .gte('punch_time', '$today 00:00:00')
          .lte('punch_time', '$today 23:59:59')
          .order('punch_time', ascending: true);
      setState(() {
        todayAttendance = att;
        punchLogs = List<Map<String, dynamic>>.from(logs);
        // Determine punch state from latest log
        if (punchLogs.isNotEmpty) {
          final lastPunch = punchLogs.last['punch_type'];
          hasPunchedIn = lastPunch == 'punch_in';
        } else {
          hasPunchedIn = att != null && att['punch_in_time'] != null && att['punch_out_time'] == null;
        }
      });
    } catch (e) {
      debugPrint('loadAttendance error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<Map<String, dynamic>?> _checkGeoFence() async {
    try {
      geoChecking = true;

      setState(() {});

      final pos = await _getLocation();

      gpsAccuracy = pos.accuracy;

      final nearest = findNearestSite(
        userLat: pos.latitude,
        userLng: pos.longitude,
        sites: workSites,
      );

      if (nearest == null) {
        return null;
      }

      final site = nearest['site'] as WorkSite;

      geoDistance = nearest['distance'];

      geoInFence = nearest['inFence'];

      nearestSiteName = site.name;

      setState(() {});

      return {
        'position': pos,
        'site': site,
        'distance': geoDistance,
        'inFence': geoInFence,
      };
    } catch (e) {
      geoPermissionDenied = true;

      return null;
    } finally {
      geoChecking = false;

      setState(() {});
    }
  }
  // compute hours worked and overtime and update attendance row
  Future<void> _recomputeAndUpdateAttendance(String attendanceId) async {
    try {
      // fetch all logs for attendance id
      final logs = await supabase
          .from('attendance_punch_logs')
          .select()
          .eq('attendance_id', attendanceId)
          .order('punch_time', ascending: true);
      if (logs == null || (logs as List).isEmpty) return;
      // Pair punch_in / punch_out pairs to compute total worked minutes
      final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(logs);
      Duration totalWorked = Duration.zero;
      String? firstInIso;
      DateTime? lastOut;
      for (int i = 0; i < items.length; i++) {
        final row = items[i];
        final type = (row['punch_type'] ?? '').toString();
        final dt = DateTime.tryParse(row['punch_time'] ?? '');
        if (dt == null) continue;
        if (type == 'punch_in' && firstInIso == null) {
          firstInIso = row['punch_time'];
        }
        if (type == 'punch_in') {
          // look ahead for next punch_out
          for (int j = i + 1; j < items.length; j++) {
            final next = items[j];
            if ((next['punch_type'] ?? '') == 'punch_out') {
              final dtOut = DateTime.tryParse(next['punch_time'] ?? '');
              if (dtOut != null) {
                totalWorked += dtOut.difference(dt);
                lastOut = dtOut;
                break;
              }
            }
          }
        }
      }
      // fetch attendance row and shift info for OT rules
      final attResp = await supabase.from('attendance').select().eq('id', attendanceId).maybeSingle();
      if (attResp == null) return;
      final att = Map<String, dynamic>.from(attResp);
      final empId = att['employee_id'];
      final isOtEligible = await _isEmployeeOtEligible(empId);
      double hoursWorked = double.parse(
        (totalWorked.inMinutes / 60.0).toStringAsFixed(2),
      );
      double overtimeHours = 0.0;
      if (isOtEligible == true) {
        // try to compute scheduled shift minutes for date
        final scheduledMinutes = await _getScheduledShiftMinutes(empId, att['date']);
        if (scheduledMinutes != null) {
          final workedMinutes = totalWorked.inMinutes;
          final otMinutes = (workedMinutes - scheduledMinutes).clamp(0, 24 * 60);
          // apply max_ot_hours_per_day from shift if available
          final maxOt = await _getShiftMaxOt(empId, att['date']);
          final maxOtMinutes = (maxOt != null) ? (maxOt * 60).toInt() : (4 * 60);
          final appliedOtMinutes = otMinutes > maxOtMinutes ? maxOtMinutes : otMinutes;
          overtimeHours = appliedOtMinutes / 60.0;
        } else {
          // fallback: no shift info, consider anything beyond 8 hours as OT
          if (hoursWorked > 8) overtimeHours = hoursWorked - 8;
        }
      }
      // Update attendance row
      await supabase.from('attendance').update({
        'hours_worked': hoursWorked,
        'overtime_hours': overtimeHours,
        'punch_in_time': firstInIso ?? att['punch_in_time'],
        'punch_out_time': lastOut?.toIso8601String() ?? att['punch_out_time'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', attendanceId);
    } catch (e) {
      debugPrint('recompute error: $e');
    }
  }
  Future<bool?> _isEmployeeOtEligible(dynamic empId) async {
    try {
      final r = await supabase.from('employee_records').select('is_ot_eligible').eq('id', empId).maybeSingle();
      if (r == null) return null;
      return r['is_ot_eligible'] == true;
    } catch (_) {
      return null;
    }
  }
  // Returns scheduled minutes for shift for emp on date or null if not found
  Future<int?> _getScheduledShiftMinutes(dynamic empId, String? dateIso) async {
    try {
      // Find assignment for that date
      final assign = await supabase
          .from('shift_assignments')
          .select('shift_id')
          .eq('employee_id', empId)
          .eq('scheduled_date', dateIso ?? '')
          .maybeSingle();
      if (assign == null || assign['shift_id'] == null) {
        return null;
      }
      final shiftId = assign['shift_id'];
      final timing = await supabase
          .from('shift_timings')
          .select('start_time,end_time,break_duration_minutes')
          .eq('id', shiftId)
          .maybeSingle();
      if (timing == null) return null;
      final start = timing['start_time'] as String;
      final end = timing['end_time'] as String;
      final breakMin = (timing['break_duration_minutes'] ?? 0) as int;
      final parseTime = (String t) {
        final parts = t.split(':');
        return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]));
      };
      final dStart = parseTime(start);
      final dEnd = parseTime(end);
      int minutes = (dEnd - dStart).inMinutes - breakMin;
      if (minutes < 0) minutes = (24 * 60 + (dEnd - dStart).inMinutes) - breakMin;
      return minutes;
    } catch (e) {
      debugPrint('getScheduledShiftMinutes: $e');
      return null;
    }
  }
  Future<double?> _getShiftMaxOt(dynamic empId, String? dateIso) async {
    try {
      final assign = await supabase
          .from('shift_assignments')
          .select('shift_id')
          .eq('employee_id', empId)
          .eq('scheduled_date', dateIso ?? '')
          .maybeSingle();
      if (assign == null || assign['shift_id'] == null) return null;
      final shiftId = assign['shift_id'];
      final timing = await supabase.from('shift_timings').select('max_ot_hours_per_day').eq('id', shiftId).maybeSingle();
      if (timing == null) return null;
      return (timing['max_ot_hours_per_day'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }
  Future<void> _punch(String type) async {

    // 🚫 BIOMETRIC ONLY — BLOCK SYSTEM ATTENDANCE
    if (isBiometricOnly) {
      _showError("Attendance allowed only via biometric device");
      return;
    }

    setState(() => loading = true);
    try {

      final emp = widget.employee;
      final empId = emp['id'];
      final orgId = emp['organization_id'];
      if (empId == null || orgId == null) throw Exception('Invalid employee data');
      // 🛰 Get location + address
      Map<String, dynamic>? geoResult;

      Position pos;

      WorkSite? site;

      bool inFence = true;

      double? distance;

      if (geoEnabled && !geoTrackOnly) {
        geoResult = await _checkGeoFence();

        if (geoResult == null) {
          if (geoMode == 'strict') {
            _showError("Location required to punch");
            return;
          }

          pos = await _getLocation();
        } else {
          pos = geoResult['position'];

          site = geoResult['site'];

          inFence = geoResult['inFence'];

          distance = geoResult['distance'];

          if (!inFence && geoMode == 'strict') {
            _showError(
              "You are outside allowed office radius",
            );
            return;
          }

          if (!inFence && geoMode == 'lenient') {
            final confirmed = await _showGeoConfirmDialog(
              site!.name,
              distance!,
              site.radiusMeters,
            );

            if (!confirmed) return;
          }
        }
      } else {
        pos = await _getLocation();

        if (geoTrackOnly) {
          final nearest = findNearestSite(
            userLat: pos.latitude,
            userLng: pos.longitude,
            sites: workSites,
          );

          if (nearest != null) {
            final siteObj = nearest['site'] as WorkSite;

            site = siteObj;

            inFence = nearest['inFence'];

            distance = nearest['distance'];

            geoDistance = distance;

            nearestSiteName = site.name;

            geoInFence = inFence;
          }
        }
      }
      final addr = await _getAddress(pos.latitude, pos.longitude);
      // 🕒 Local time formatting (IST)
      // 🕒 Get Indian Standard Time explicitly
      // ✅ Local time (IST) — ONLY for UI
      final localNow = DateTime.now();

// ✅ UTC time — ONLY for DB storage
      final utcNow = localNow.toUtc();

// ✅ Date should be derived from LOCAL date
      final date = DateFormat('yyyy-MM-dd').format(localNow);

// ✅ Always send ISO UTC to Supabase
      final utcIso = utcNow.toIso8601String();

      // 🔹 Fetch today's attendance row (only one per day)
      var attendance = await supabase
          .from('attendance')
          .select()
          .eq('employee_id', empId)
          .eq('date', date)
          .maybeSingle();
      // 🚨 VALIDATE WORK TYPE ON PUNCH OUT
      if (attendance != null && type == 'punch_out') {
        final punchInWorkType = attendance['work_type'];

        if (punchInWorkType != selectedWorkType) {
          _showError(
              "You selected a different work type.\n"
                  "Please select '$punchInWorkType' to punch out."
          );
          setState(() => loading = false);
          return; // ⛔ STOP execution
        }
      }
      if (attendance == null && type == 'punch_in') {
        // 🔹 First punch-in of the day → insert new attendance record
        attendance = await supabase.from('attendance').insert({
          'employee_id': empId,
          'organization_id': orgId,
          'date': date,
          'punch_in_time': utcIso,
          'punch_in_lat': pos.latitude,
          'punch_in_lng': pos.longitude,
          'punch_in_address': addr,
          'status': 'present',
          'work_type': selectedWorkType,
          'created_at': utcIso,
        }).select().maybeSingle();
      }
      else if (attendance != null && type == 'punch_out') {
        await supabase.from('attendance').update({
          'punch_out_time': utcIso,
          'punch_out_lat': pos.latitude,
          'punch_out_lng': pos.longitude,
          'punch_out_address': addr,
          'updated_at': utcIso,
        }).eq('id', attendance['id']);
      }
      // 🔹 Insert punch log for every punch in/out
      // ✅ Safely extract attendance id
      final attId = (attendance != null && attendance.containsKey('id')) ? attendance['id'] : null;
      if (attId != null) {
        await supabase.from('attendance_punch_logs').insert({
          'attendance_id': attId,
          'employee_id': empId,
          'organization_id': orgId,
          'punch_time': utcIso,

          'punch_type': type,
          'work_type': selectedWorkType,
          'punch_lat': pos.latitude,
          'punch_lng': pos.longitude,
          'punch_address': addr,
          'created_at': utcIso,
          'site_id': site?.id,
          'in_fence': inFence,
          'distance_m': distance,
          'accuracy_m': gpsAccuracy,
          'punch_source': 'mobile',
        });
        //
        //
        // ✅ Recompute hours/overtime safely
        await _recomputeAndUpdateAttendance(attId.toString());
      } else {
        debugPrint('⚠️ Attendance ID missing after punch ${type == 'punch_in' ? 'in' : 'out'} insert');
      }
      // ✅ Notify user
// ✅ Update punch button state immediately
      // ✅ Update punch button state immediately
      setState(() {
        hasPunchedIn = type == 'punch_in';
      });

// ✅ Reload latest attendance + refresh UI
      await _loadAttendance();
      if (type == 'punch_in') {

        final shiftEndTime =
        DateTime.now().copyWith(
          hour: 17,
          minute: 0,
        );

        await GeoTrackerService.startTracking(

          organizationId:
          orgId.toString(),

          employeeId:
          empId.toString(),

          attendanceId:
          attendance!['id'].toString(),

          intervalMinutes: 2,

          shiftEndTime:
          shiftEndTime,
        );
      }

// ✅ SHOW SUCCESS (GREEN)
      _showSuccess(
        type == 'punch_in'
            ? 'Punch In successful'
            : 'Punch Out successful',
      );

    } catch (e) {
      if (e.toString().contains('Location services disabled')) {
        _showError('Please turn on Location (GPS)');
      } else if (e.toString().contains('permission')) {
        _showError('Please allow location permission');
      } else {
        _showError('Something went wrong. Try again.');
      }
    } finally {
      setState(() => loading = false);
    }
  }
  Future<bool> _showGeoConfirmDialog(
      String site,
      double distance,
      double allowed,
      ) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("You appear to be outside an allowed work site"),
          content: Text(
            "You are ${distance.toStringAsFixed(0)}m from $site.\n"
                "Allowed radius is ${allowed.toStringAsFixed(0)}m.\n\n"
                "This punch will be flagged for HR review.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    ) ??
        false;
  }
  Widget _geoStatusCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDFF6E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Geo Fence Status",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 10),

          if (workSites.isEmpty)
            Text(
              "No work sites configured",
              style: GoogleFonts.montserrat(),
            ),

          if (nearestSiteName != null)
            Text(
              "You are ${geoDistance?.toStringAsFixed(0)}m from $nearestSiteName",
              style: GoogleFonts.montserrat(),
            ),

          const SizedBox(height: 10),

          Row(
            children: [
              Icon(
                geoInFence == true
                    ? Icons.verified
                    : geoInFence == false
                    ? Icons.warning_amber_rounded
                    : Icons.location_searching,
                color:
                geoInFence == true
                    ? Colors.green
                    : geoInFence == false
                    ? Colors.orange
                    : Colors.blueGrey,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  geoInFence == true
                      ? "Inside allowed area"
                      : geoInFence == false
                      ? "You appear to be outside an allowed work site"
                      : "Location not checked yet",

                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.black87,
                  ),

                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),



          if (gpsAccuracy != null &&
              gpsAccuracy! > 100)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                "Low GPS accuracy",
                style: GoogleFonts.montserrat(
                  color: Colors.orange,
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _todayCard(Map<String, dynamic>? att) {
    // Derive latest punch in/out from logs dynamically
    final latestIn = punchLogs
        .where((r) => r['punch_type'] == 'punch_in')
        .map((r) => r['punch_time'])
        .toList()
        .cast<String?>();
    final latestOut = punchLogs
        .where((r) => r['punch_type'] == 'punch_out')
        .map((r) => r['punch_time'])
        .toList()
        .cast<String?>();
    final lastPunchIn = latestIn.isNotEmpty ? latestIn.last : null;
    final lastPunchOut = latestOut.isNotEmpty ? latestOut.last : null;
    final lastPunchInAddr = punchLogs.isNotEmpty
        ? punchLogs.lastWhere(
          (r) => r['punch_type'] == 'punch_in',
      orElse: () => <String, dynamic>{},
    )['punch_address']
        : null;
    final lastPunchOutAddr = punchLogs.isNotEmpty
        ? punchLogs.lastWhere(
          (r) => r['punch_type'] == 'punch_out',
      orElse: () => <String, dynamic>{},
    )['punch_address']
        : null;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Status",
                style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _info("Punch In", lastPunchIn),
            _info("Punch In Location", lastPunchInAddr),
            _info("Punch Out", lastPunchOut),
            _info("Punch Out Location", lastPunchOutAddr),
            _info("Work Type", att?['work_type']),
          ],
        ),
      ),
    );
  }

  Widget _biometricOnlyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD180)),
      ),
      child: Column(
        children: [
          const Icon(Icons.fingerprint, size: 40, color: Colors.deepOrange),
          const SizedBox(height: 10),
          Text(
            "Biometric Only",
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Your organization requires attendance via biometric device",
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, dynamic val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: GoogleFonts.montserrat(color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              val == null || val.toString().trim().isEmpty
                  ? '-'
                  : _formatLocalTime(val.toString()),  // ✅ Convert UTC → Local time
              style: GoogleFonts.montserrat(),
            ),
          ),
        ],
      ),
    );
  }
  String _formatDisplay(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal(); // UTC → IST
      return DateFormat('yyyy-MM-dd hh:mm a').format(d);
    } catch (_) {
      return iso;
    }
  }
  @override
  Widget build(BuildContext context) {
    final att = todayAttendance;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.access_time, color: Colors.blue),
          const SizedBox(width: 8),
          Text(DateFormat('MMM dd, yyyy – hh:mm:ss a').format(_now), style: GoogleFonts.montserrat(fontSize: 14)),
          const Spacer(),
          IconButton(onPressed: _loadAttendance, icon: const Icon(Icons.refresh, color: Colors.blue)),
        ]),
        const SizedBox(height: 10),
        if (geoEnabled)
          _geoStatusCard(),
        if (geoTrackOnly)
          Container(

            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Geo not enforced today. Location will still be recorded.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _todayCard(att),
        if (currentPermission == LocationPermission.denied ||
            currentPermission == LocationPermission.deniedForever)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_off,
                    color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Location blocked. Please enable location permission.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: selectedWorkType,
          decoration: InputDecoration(
            labelText: 'Work Type',
            labelStyle: GoogleFonts.montserrat(),
            border: const OutlineInputBorder(),
          ),
          items: workTypes.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: GoogleFonts.montserrat()))).toList(),
          onChanged: (v) async {
            setState(() {
              selectedWorkType = v ?? 'on-duty';
            });

            await _loadGeoFencePolicy();

            if (geoEnabled && workSites.isNotEmpty) {
              await _checkGeoFence();
            }
          },
        ),
        const SizedBox(height: 16),
        // ✅ ADD THIS BLOCK EXACTLY HERE
        if (isBiometricOnly) ...[
          const SizedBox(height: 12),
          _biometricOnlyCard(),
        ],
        // ==================== SINGLE DASHBOARD STYLE BUTTON ====================
        if (isInSystemAllowed) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
              loading ||
                  geoChecking ||
                  (geoEnabled &&
                      geoMode == 'strict' &&
                      geoTrackOnly == false &&
                      geoInFence == false)
                  ? null
                  : () => _punch(
                hasPunchedIn
                    ? 'punch_out'
                    : 'punch_in',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: loading || geoChecking
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    geoChecking
                        ? "Checking location..."
                        : "Please wait...",
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasPunchedIn
                        ? Icons.logout
                        : Icons.login,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasPunchedIn
                        ? "Punch Out Now"
                        : "Punch In Now",
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],


        const SizedBox(height: 22),
        Row(
          mainAxisAlignment:
          MainAxisAlignment.spaceBetween,

          children: [

            Text(
              'Today\'s Logs',

              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
              ),
            ),

            IconButton(

              icon: const Icon(
                Icons.map,
                color: Colors.blue,
              ),

              onPressed: () {

                if (punchLogs.isEmpty) {

                  ScaffoldMessenger.of(context)
                      .showSnackBar(

                    const SnackBar(
                      content: Text(
                        'No punch records found',
                      ),
                    ),
                  );

                  return;
                }

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (_) =>
                        LiveTrackingMapScreen(
                          logs: punchLogs,
                        ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ======================= TODAY'S LOGS (REDESIGNED) =======================
        Column(
          children: punchLogs.map((r) {
            final t = r['punch_time'];
            final type = r['punch_type'];
            final addr = r['punch_address'] ?? "-";
            final hasFenceData =
            r.containsKey('in_fence');

            final inFence =
                r['in_fence'] == true;

            final distance = r['distance_m'];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: type == 'punch_in'
                          ? Colors.green.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type == 'punch_in' ? Icons.login : Icons.logout,
                      color: type == 'punch_in' ? Colors.green : Colors.red,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.replaceAll('_', ' ').toUpperCase(),
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDisplay(t ?? ''),
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          addr,
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        )

      ]),
    );
  }
}


   //My History Tab
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
      final res = await supabase
          .from('attendance_punch_logs')
          .select()
          .eq('employee_id', empId)
          .gte('punch_time', '$day 00:00:00')
          .lte('punch_time', '$day 23:59:59')
          .order('punch_time', ascending: true);
      setState(() => logs = List<Map<String, dynamic>>.from(res ?? []));
    } catch (e) {
      debugPrint('myHistory load logs error: $e');
    } finally {
      setState(() => loading = false);
    }
  }
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ================= DATE PICKER BOX =================
          Text("Select Date", style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          TableCalendar(
            firstDay: DateTime(1990, 1, 1),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: selectedDate,
            selectedDayPredicate: (day) => isSameDay(selectedDate, day),

            // When user taps a date
            onDaySelected: (selected, focused) {
              setState(() {
                selectedDate = selected;
              });
              _loadLogs();  // reload data for selected day
            },

            // ---- STYLE matches your screenshot ----
            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
              leftChevronIcon: Icon(Icons.chevron_left, size: 22, color: Colors.black54),
              rightChevronIcon: Icon(Icons.chevron_right, size: 22, color: Colors.black54),
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),

            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              weekendTextStyle: TextStyle(color: Colors.black87),
              defaultTextStyle: TextStyle(color: Colors.black87),
              outsideTextStyle: TextStyle(color: Colors.grey.shade400),
              markersMaxCount: 0,   // ← NO DOTS
            ),

            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: Colors.black87),
              weekendStyle: TextStyle(color: Colors.black87),
            ),
          ),
          const SizedBox(height: 18),
          // ================= HISTORY HEADER =================
          Text(
            "Punch Logs",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),

          if (loading)
            Center(
              child: CircularProgressIndicator(color: Colors.blue),
            ),

          if (!loading && logs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Text(
                  "No punches for selected date",
                  style: GoogleFonts.montserrat(fontSize: 14, color: Colors.grey),
                ),
              ),
            ),

          // ================= REDESIGNED LIST OF CARDS =================
          Column(
            children: logs.map((r) {
              final time = r['punch_time'];
              final type = r['punch_type'] ?? '-';
              final addr = r['punch_address'] ?? '-';

              final isIn = type == 'punch_in';

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // LEFT ICON
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isIn
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                      ),
                      child: Icon(
                        isIn ? Icons.login : Icons.logout,
                        color: isIn ? Colors.green : Colors.red,
                        size: 22,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // TEXT INFO
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.montserrat(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('hh:mm a').format(DateTime.parse(time).toLocal()),
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            addr,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

}
/* -------------------------------------------------------------------
   Regularization Tab
   - Strict date + time pickers
   - Validation: requested_punch_in required, correct format HH:mm allowed
------------------------------------------------------------------- */
// ---------------- REGULARIZATION TAB (FULL, CLEAN, FIXED) ----------------

class RegularizationTab extends StatefulWidget {
  final Map<String, dynamic> employee;

  const RegularizationTab({Key? key, required this.employee}) : super(key: key);

  @override
  State<RegularizationTab> createState() => _RegularizationTabState();
}

class _RegularizationTabState extends State<RegularizationTab> {
  final supabase = Supabase.instance.client;

  // ⭐ REQUIRED VARIABLES — FIXES YOUR ERRORS

  DateTime? date;

  final TextEditingController inCtrl = TextEditingController();
  final TextEditingController outCtrl = TextEditingController();
  final TextEditingController reasonCtrl = TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    inCtrl.dispose();
    outCtrl.dispose();
    reasonCtrl.dispose();
    super.dispose();
  }

  // ------------------ TIME PICKER ------------------
  Future<void> _pickTime(TextEditingController ctrl) async {
    final now = TimeOfDay.now();

    final result = await showTimePicker(
      context: context,
      initialTime: now,
    );

    if (result != null) {
      final hh = result.hour.toString().padLeft(2, '0');
      final mm = result.minute.toString().padLeft(2, '0');

      setState(() {
        ctrl.text = '$hh:$mm';
      });
    }
  }

  // ------------------ TIME VALIDATION ------------------
  bool _validateTime(String v) {
    final reg = RegExp(r'^\d{2}:\d{2}$');
    if (!reg.hasMatch(v)) return false;

    final parts = v.split(':');
    final h = int.tryParse(parts[0]) ?? -1;
    final m = int.tryParse(parts[1]) ?? -1;

    return h >= 0 && h < 24 && m >= 0 && m < 60;
  }

  // ------------------ SUBMIT ------------------
  Future<void> _submit() async {
    if (date == null || inCtrl.text.isEmpty || reasonCtrl.text.isEmpty) {
      _error("Please fill all required fields");
      return;
    }

    if (!_validateTime(inCtrl.text)) {
      _error("Invalid Punch In time format. Use HH:mm");
      return;
    }

    if (outCtrl.text.isNotEmpty && !_validateTime(outCtrl.text)) {
      _error("Invalid Punch Out time format. Use HH:mm");
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("No user logged in");

      final emp = await supabase
          .from("employee_records")
          .select("id, organization_id, manager_id")
          .eq("email", user.email ?? "")
          .maybeSingle();

      if (emp == null) throw Exception("Employee not found");

      final String dateStr = DateFormat("yyyy-MM-dd").format(date!);

      final requestedInIso = _combine(dateStr, inCtrl.text);
      final requestedOutIso =
      outCtrl.text.isNotEmpty ? _combine(dateStr, outCtrl.text) : null;

      await supabase.from("attendance_regularization_requests").insert({
        "employee_id": emp["id"],
        "organization_id": emp["organization_id"],
        "manager_id": emp["manager_id"],
        "date": dateStr,
        "requested_punch_in": requestedInIso,
        "requested_punch_out": requestedOutIso,
        "reason": reasonCtrl.text,
        "status": "pending",
        "created_at": DateTime.now().toUtc().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Regularization request submitted")),
      );

      setState(() {
        date = null;
        inCtrl.clear();
        outCtrl.clear();
        reasonCtrl.clear();
      });
    } catch (e) {
      _error(e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  // Combine date + time → ISO
  String _combine(String dateIso, String hhmm) {
    final parts = hhmm.split(":");
    final dt = DateTime.parse(dateIso)
        .add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));

    return dt.toUtc().toIso8601String();
  }

  // Easy error message
  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ------------------ BUILD UI ------------------
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Regularization Request",
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),



            // ---------------- BOX → CLICK → SHOW CALENDAR ----------------
            Text("Select Date", style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),

            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );

                if (picked != null) {
                  setState(() {
                    date = picked;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.blue),
                    const SizedBox(width: 10),
                    Text(
                      date == null
                          ? "Pick a date"
                          : DateFormat("yMMMMd").format(date!),
                      style: GoogleFonts.montserrat(),
                    ),
                  ],
                ),
              ),
            ),


            // ---------------- Punch IN ----------------
            Text("Requested Punch In", style: GoogleFonts.montserrat()),
            const SizedBox(height: 6),

            InkWell(
              onTap: () => _pickTime(inCtrl),
              child: _inputBox(inCtrl.text.isEmpty ? "Select time" : inCtrl.text),
            ),

            const SizedBox(height: 16),

            // ---------------- Punch OUT ----------------
            Text("Requested Punch Out (optional)", style: GoogleFonts.montserrat()),
            const SizedBox(height: 6),

            InkWell(
              onTap: () => _pickTime(outCtrl),
              child: _inputBox(outCtrl.text.isEmpty ? "Select time" : outCtrl.text),
            ),

            const SizedBox(height: 16),

            // ---------------- Reason ----------------
            Text("Reason", style: GoogleFonts.montserrat()),
            const SizedBox(height: 6),

            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ---------------- SUBMIT BUTTON ----------------
            ElevatedButton(
              onPressed: loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text("Submit", style: GoogleFonts.montserrat(color: Colors.white)),
            ),

          ],
        ),
      ),
    );
  }

  // ---------------- INPUT BOX ----------------
  Widget _inputBox(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: Colors.blue),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.montserrat()),
        ],
      ),
    );
  }
}

