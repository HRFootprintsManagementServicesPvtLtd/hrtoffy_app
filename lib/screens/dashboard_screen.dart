import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:app_badge_plus/app_badge_plus.dart';
import 'dart:convert';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'benefits_screen.dart';
import 'loans_advances_screens.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'overtime_screen.dart';
import 'payslip_screen.dart';
import 'attendance_screen.dart';
import 'leaves_screen.dart';
import 'tax_deduction_screen.dart';
import 'faqs_screen.dart';
import 'events_calendar_screen.dart';
import 'surveys_screen.dart';
import 'announcements_screen.dart';

import '../main.dart'; // for _showLocalNotification
import 'notification.dart';
import 'dart:async';
import 'dart:math' as math;
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';
import '../services/geo_tracker_service.dart';


// ----------- Main DashboardScreen --------------------
const kBorderColor = Color(0xFFE0E0E0);
const String googleGeocodingApiKey = 'AIzaSyB4um8D3zbPD4QnrRkZEqCs30Bp6HCR5a0';
class LiveClock extends StatelessWidget {
  const LiveClock({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now().toLocal();
        return Text(
          DateFormat('hh:mm:ss a').format(now),
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueAccent,
          ),
        );
      },
    );
  }
}
Widget _buildQuickCard({
  required String svgPath,
  required Color iconColor,
  required String label,
  required Color cardColor,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 110, // 🔥 increased width to reduce spacing between cards
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            svgPath,
            width: 32,
            height: 32,
            colorFilter: ColorFilter.mode(
              iconColor,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
class DashboardScreen extends StatefulWidget {

  // ===================== HELPER FUNCTIONS FOR ATTENDANCE =====================
  String _formatLocalTime(String timeStr) {
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      return DateFormat('yyyy-MM-dd hh:mm a').format(dt);
    } catch (_) {
      return timeStr;
    }
  }
  String? getLastPunchIn(List<Map<String, dynamic>> logs) {
    final list = logs
        .where((e) => e['punch_type'] == 'punch_in')
        .map((e) => e['punch_time'])
        .toList();
    return list.isNotEmpty ? list.last : null;
  }

  String generateVoucherCode(String empId) {
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final suffix = empId.substring(empId.length - 6).toUpperCase();
    return 'MV-$date-$suffix';
  }


  String? getLastPunchOut(List<Map<String, dynamic>> logs) {
    final list = logs
        .where((e) => e['punch_type'] == 'punch_out')
        .map((e) => e['punch_time'])
        .toList();
    return list.isNotEmpty ? list.last : null;
  }

  Widget _attRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
  final String email;
  final String employeeId;

  // 🔥 ADD THIS


  const DashboardScreen({
    Key? key,
    required this.email,
    required this.employeeId,
  }) : super(key: key);


  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool showMealVoucher = false;

  Map<String, dynamic>? mealVoucherState; // ✅ ADD THIS

  // ================= ATTENDANCE RECORDING METHOD HELPERS =================

  bool get isBiometricOnly {
    final method = orgDetails?['attendance_recording_method'];
    return method == 'biometric';
  }

  bool get isInSystemAllowed {
    final method = orgDetails?['attendance_recording_method'];
    return method == 'in_system' || method == 'both';
  }

  String generateVoucherCode(String empId) {
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final suffix = empId.substring(empId.length - 6).toUpperCase();
    return 'MV-$date-$suffix';
  }

  Widget buildMealVoucherCard() {
    if (!showMealVoucher || mealVoucherState == null) {
      return const SizedBox.shrink();
    }

    final amount = mealVoucherState!['amount'];
    final order = mealVoucherState!['order'];
    final bool isOrdered = order != null;
    final voucherCode = order?['voucher_code'];
    final allowCancel = mealVoucherState!['allow_cancellation'] == true;

    final now = DateTime.now();
    final dateText = DateFormat('MMM dd, yyyy').format(now);
    final dayText = DateFormat('EEEE').format(now);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOrdered
              ? [Color(0xFFE8F5E9), Color(0xFFF1F8E9)]
              : [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOrdered ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(
            children: [
              Icon(
                Icons.restaurant,
                color: isOrdered ? Colors.green : Colors.deepOrange,
              ),
              const SizedBox(width: 8),
              Text(
                "Meal Order",
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                "₹$amount / meal",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            "$dateText • $dayText",
            style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
          ),

          const SizedBox(height: 14),

          // ================= STATES =================
          if (!isOrdered) ...[
            Text(
              "Order your meal for today. It will be arranged as per your shift timing.",
              style: GoogleFonts.montserrat(fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: placeMealOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "Order Meal",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text(
                  "Meal Ordered for Today",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Voucher Code",
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
            ),
            Text(
              voucherCode ?? "--",
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ],
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
          const Icon(
            Icons.fingerprint,
            size: 40,
            color: Colors.deepOrange,
          ),
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
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // Bottom navigation scaffold key & active tab
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;

  final supabase = Supabase.instance.client;
  Map<String, dynamic>? userData;
  Map<String, dynamic>? managerData;
  String managerId = '--';
  String managerName = '--';
  String managerEmail = '--';
  String? profileUrl;
  bool loadingProfile = false;
  String? organizationName;
  String? dashboardError;
  Map<String, dynamic>? orgDetails;
  bool refreshingProfile = false;
  Map<String, dynamic>? mealVoucherBenefit;
  String? companyLogoUrl;
  List<Map<String, dynamic>> todayPunchLogs = [];
  bool punchedIn = false;
  String? attendanceIn = '--';
  String? attendanceInLocation = '--';
  String? attendanceOut = '--';
  String? attendanceOutLocation = '--';
  String? lastPunchType;
  List<Map<String, dynamic>> notifications = [];
  int unreadCount = 0;

  bool loadingNotifications = false;
  bool loading = false;
  bool showOrgLogo = false;
  bool punchedInNow = false;   // 🔥 Add this line
  Timer? logoTimer;
  String selectedWorkType = "On-Duty";   // LABEL
  late Future<Map<String, dynamic>> leaveSummaryFuture = Future.value({
    "available": 0,
    "used": 0,
    "pending": 0,
    "year": DateTime.now().year,
  });


  final Map<String, String> workTypeOptions = {
    'On-Duty': 'on-duty',
    'Work From Home': 'work-from-home',
    'On-Site': 'on-site',
  };

  final ValueNotifier<bool> drawerNotifier = ValueNotifier(false);
  Map<String, dynamic>? geoPolicy;

  List<WorkSite> workSites = [];

  bool geoChecking = false;

  bool geoInFence = false;

  double? geoDistance;

  String? nearestSiteName;

  String geoMode = 'strict';

  bool geoEnabled = false;

  bool geoTrackOnly = false;

  double? gpsAccuracy;

  bool geoPermissionDenied = false;


  @override
  void initState() {
    super.initState();

    print("DASHBOARD INITSTATE CALLED for email = ${widget.email}");
    // ✅ Initialize and fetch user data first
    _initialize().then((_) async {

      _loadGeoFencePolicy();

      // ✅ START LIVE GEO TRACKING
      await initializeGeoTracking();

      if (companyLogoUrl != null &&
          companyLogoUrl!.isNotEmpty) {

        precacheImage(
          NetworkImage(companyLogoUrl!),
          context,
        );
      }

      logoTimer = Timer.periodic(
        Duration(seconds: 4),
            (_) {

          setState(() {
            showOrgLogo = !showOrgLogo;
          });
        },
      );

      fetchNotifications();
    });


    // ✅ Real-time Notifications Channel
    final notifChannel = supabase.channel('notifications_updates');
    notifChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        debugPrint("📩 Real-time new notification received: $payload");
        fetchNotifications(); // instantly refresh count + list
      },
    );
    notifChannel.subscribe();
    // ✅ Save FCM token to Supabase
    _saveFcmToken();
    // ✅ Fetch latest attendance logs
    fetchLatestPunchLogs();
    // ✅ Real-time attendance updates
    final attendanceChannel = supabase.channel('attendance_updates');
    attendanceChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'attendance_punch_logs',
      callback: (payload) {
        print("📢 attendance_punch_logs inserted: $payload");
        fetchLatestPunchLogs();
      },
    );
    attendanceChannel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'attendance',
      callback: (payload) {
        print("📢 attendance table updated: $payload");
        fetchLatestPunchLogs();
        todayLogsFuture = fetchTodaysLogs();
      },
    );
    attendanceChannel.subscribe();
    // ✅ Firebase Messaging: Foreground + Tap Handlers
    // ✅ Set up FCM for this logged-in user
    FirebaseNotificationService.setupFCM(userEmail: widget.email);
    // ✅ Optional: listen for new messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📩 Foreground message received: ${message.notification?.title}');
      // Notifications will automatically show via FirebaseNotificationService
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🟢 Notification tapped: ${message.data}');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NotificationsScreen(
            employeeId: userData?['id']?.toString() ?? '',
            userEmail: widget.email!,
            userData: userData!,
            fetchHrmsContext: fetchHrmsContext,
          ),
        ),
      );

    });
  }

  String _getGreetingMessage() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  @override
  void dispose() {
    logoTimer?.cancel(); // stop periodic timer
    drawerNotifier.dispose();

    // If you created any StreamSubscriptions store and cancel them here
    super.dispose();
  }

  Future<void> _saveFcmToken() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      // Request notification permissions (especially for Android 13+)
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // Get the FCM token
      String? token = await messaging.getToken();
      print("🔑 FCM Token: $token");
      // Save the token to Supabase (for the current user)
      if (token != null) {
        await supabase
            .from('employee_records')
            .update({'fcm_token': token})
            .eq('email', widget.email);
        print("✅ Token saved to Supabase successfully!");
      }
      // Listen for foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("📢 Foreground message received: ${message.notification?.title}");
      });
      // Listen for notification taps
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("🟢 Notification opened: ${message.notification?.title}");
      });
    } catch (e) {
      print("⚠️ Error saving FCM token: $e");
    }
  }

  Future<void> initializeGeoTracking() async {

    try {

      final currentUser =
          supabase.auth.currentUser;

      if (currentUser == null) return;

      // ✅ ASK GPS PERMISSION
      await Geolocator.requestPermission();

      final employeeId =
      userData?['id'];

      final organizationId =
      userData?['organization_id'];

      if (employeeId == null ||
          organizationId == null) {
        return;
      }

      // ✅ FETCH HR SETTINGS
      final result = await supabase.rpc(
        'geo_mapping_get_my_config',
        params: {
          '_org': organizationId,
        },
      );

      print("GEO CONFIG => $result");

      // ✅ START TRACKING
      if (result != null &&
          result['enabled'] == true) {

        final attendanceId =
        await getOrCreateAttendanceId();

        final shift =
        await getAssignedShift();

        if (attendanceId != null &&
            shift != null) {

          final end =
          shift['end_time'];

          final parts =
          end.split(":");

          final now = DateTime.now();

          final shiftEndTime = DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          );

          await GeoTrackerService.startTracking(

            organizationId:
            organizationId.toString(),

            employeeId:
            employeeId.toString(),

            attendanceId:
            attendanceId.toString(),

            intervalMinutes:
            result['interval_minutes'] ?? 5,

            shiftEndTime:
            shiftEndTime,
          );
        }
      }

    } catch (e) {

      print(
        "initializeGeoTracking error => $e",
      );
    }
  }
  Future<List<Map<String, dynamic>>>? todayLogsFuture;

  Future<List<Map<String, dynamic>>> fetchTodaysLogs() async {
    if (userData == null || userData!['id'] == null) {
      return [];
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final res = await supabase
        .from('attendance_punch_logs')
        .select()
        .eq('employee_id', userData!['id'])
        .gte('punch_time', '$today 00:00:00')
        .lte('punch_time', '$today 23:59:59')
        .order('punch_time', ascending: true);

    return List<Map<String, dynamic>>.from(res ?? []);
  }
  Future<void> _initialize() async {
    print("INITIALIZE STARTED for email = ${widget.email}");

    setState(() {
      loadingProfile = true;
      dashboardError = null;

    });
    try {
      final resp = await supabase
          .from('employee_records')
          .select()
          .eq('email', widget.email)  // <-- DO NOT lowercase
          .maybeSingle();

      print('Supabase response for user: $resp');

      userData = resp;

      if (userData == null) {
        setState(() {
          dashboardError = "Your employee profile was not found.";
          loadingProfile = false;
        });
        return;
      }

// ✅ NOW SAFE TO USE userData
      await fetchMealVoucher();

      setState(() {
        leaveSummaryFuture = fetchLeaveSummary(userData!['id']);
      });

// ✅ MOVE HERE
      todayLogsFuture = fetchTodaysLogs();

      if (userData!['organization_id'] != null) {
        await fetchOrganizationDetails(userData!['organization_id']);
        await fetchProfilePic();

        if (userData!['manager_email'] != null) {
          await fetchManagerData(userData!['manager_email']);
        }

        await fetchLatestPunchLogs();
        await fetchCompanyLogo();
        await _requestNotificationPermission();
      }

    } catch (e) {
      print("DashboardScreen error: ${e.toString()}");
      setState(() {
        dashboardError =
        "There was a problem loading your dashboard. Please try again.";
        userData = null;
      });
    } finally {
      setState(() => loadingProfile = false);
    }
  }

  // Put this inside _DashboardScreenState
  Future<Map<String, dynamic>> fetchLeaveSummary(String? employeeId) async {
    final client = Supabase.instance.client;

    if (employeeId == null) {
      return {
        "available": 0,
        "used": 0,
        "pending": 0,
        "year": DateTime.now().year,
      };
    }

    try {
      // get the latest leave_balances row for the employee (most recent year)
      final lbRes = await client
          .from('leave_balances')
          .select()
          .eq('employee_id', employeeId)
          .order('year', ascending: false)
          .limit(1);

      Map<String, dynamic>? lb;
      if (lbRes != null && lbRes.isNotEmpty) {
        lb = Map<String, dynamic>.from(lbRes.first);
      }

      // Sum pending leave applications
      final pendingRes = await client
          .from('leave_applications')
          .select('total_days')
          .eq('employee_id', employeeId)
          .eq('status', 'pending');

      double pending = 0;
      if (pendingRes != null) {
        for (final item in pendingRes) {
          pending += double.tryParse(item['total_days']?.toString() ?? '0') ?? 0;
        }
      }

      final available = lb != null ? (lb['remaining_days'] ?? 0) : 0;
      final used = lb != null ? (lb['used_days'] ?? 0) : 0;
      final year = lb != null ? (lb['year'] ?? DateTime.now().year) : DateTime.now().year;

      return {
        "available": available,
        "used": used,
        "pending": pending,
        "year": year,
      };
    } catch (e) {
      debugPrint('fetchLeaveSummary error: $e');
      return {
        "available": 0,
        "used": 0,
        "pending": 0,
        "year": DateTime.now().year,
      };
    }
  }


  Future<void> fetchNotifications() async {
    try {
      setState(() => loadingNotifications = true);

      if (userData == null || userData?['id'] == null) return;

      final employeeId = userData!['id'];
      final res = await supabase
          .from('notifications')
          .select()
          .eq('recipient_employee_id', employeeId)
          .order('created_at', ascending: false);

      final unread = res.where((n) => n['read'] == false).length;

      setState(() {
        notifications = List<Map<String, dynamic>>.from(res);
        unreadCount = unread;
      });
      // ✅ Update badge count dynamically
      if (unreadCount > 0) {
        await AppBadgePlus.updateBadge(unreadCount);
      } else {
        await AppBadgePlus.updateBadge(0); // clears the badge
      }
    } catch (e) {
      debugPrint("⚠️ fetchNotifications error: $e");
    } finally {
      setState(() => loadingNotifications = false);
    }
  }

  Future<void> fetchMealVoucher() async {
    try {
      final empId = userData?['id'];
      final orgId = userData?['organization_id'];

      if (empId == null || orgId == null) {
        setState(() => showMealVoucher = false);
        return;
      }

      // 1️⃣ ELIGIBILITY CHECK
      final eligibility = await supabase
          .from('employee_eligibility')
          .select('is_meal_voucher_eligible')
          .eq('employee_id', empId)
          .maybeSingle();

      if (eligibility?['is_meal_voucher_eligible'] != true) {
        setState(() => showMealVoucher = false);
        return;
      }

      // 2️⃣ CONFIG FETCH
      final config = await supabase
          .from('meal_voucher_configuration')
          .select()
          .eq('organization_id', orgId)
          .maybeSingle();

      if (config == null) {
        setState(() => showMealVoucher = false);
        return;
      }

      final amount = config['per_meal_amount'];
      final cutoffHours = config['order_cutoff_hours'] ?? 6;

      // 3️⃣ TODAY’S ORDER
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final orders = await supabase
          .from('meal_orders')
          .select()
          .eq('employee_id', empId)
          .eq('order_date', today)
          .neq('status', 'cancelled')
          .limit(1);

      setState(() {
        showMealVoucher = true;
        mealVoucherState = {
          'amount': amount,
          'cutoff_hours': cutoffHours,
          'order': orders.isNotEmpty ? orders.first : null,
        };
      });
    } catch (e) {
      debugPrint('❌ fetchMealVoucher error: $e');
      setState(() => showMealVoucher = false);
    }
  }

  Future<void> placeMealOrder() async {
    try {
      final empId = userData?['id'];
      final orgId = userData?['organization_id'];

      if (empId == null || orgId == null) return;

      final res = await supabase.rpc(
        'place_meal_order',
        params: {
          'p_employee_id': empId,
          'p_organization_id': orgId,
        },
      );

      if (res == null || res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res?['error'] ?? 'Unable to place meal order')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Meal ordered successfully')),
      );

      // 🔁 Refresh state like web hook
      await fetchMealVoucher();
    } catch (e) {
      debugPrint('❌ placeMealOrder error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal order failed')),
      );
    }
  }




  Future<void> fetchOrganizationDetails(String orgId) async {
    try {
      final org = await supabase
          .from('organizations')
          .select()
          .eq('id', orgId)
          .maybeSingle();
      setState(() {
        orgDetails = org;
        organizationName = org != null ? org['name'] : '--';
        userData?['organizationname'] = org != null ? org['name'] : '--';
      });
    } catch (_) {
      setState(() {
        organizationName = '--';
        orgDetails = null;
        userData?['organizationname'] = '--';
      });
    }
  }
  Future<void> fetchProfilePic() async {
    final avatarUrlFromDb = userData?['avatar_url'] ?? '';

    // ✅ If DB already has avatar_url, ALWAYS USE IT
    if (avatarUrlFromDb.isNotEmpty) {
      setState(() => profileUrl = avatarUrlFromDb);
      print("Using avatar from DB: $avatarUrlFromDb");
      return;
    }

    // ✅ If DB has no avatar_url, only THEN build fallback storage URL
    final path = '${widget.email}.jpg';

    try {
      final url = Supabase.instance.client
          .storage
          .from('avatars')
          .getPublicUrl(path);

      setState(() => profileUrl = url);
    } catch (e) {
      debugPrint("fetchProfilePic error: $e");
      setState(() => profileUrl = null);
    }
  }

  Future<void> fetchManagerData(String email) async {
    try {
      final resp = await supabase
          .from('employee_records')
          .select('id, employee_id, full_name, email, department, designation')
          .eq('email', email)
          .maybeSingle();

      if (resp != null) {
        setState(() {
          managerData = resp;
          managerId = resp['employee_id'] ?? '--'; // ✅ now we store the manager’s employee ID
          managerName = resp['full_name'] ?? '--';
          managerEmail = resp['email'] ?? '--';
        });
      } else {

      }
    } catch (e) {
      debugPrint('Error fetching manager data: $e');
    }
  }
  Future<void> fetchCompanyLogo() async {
    try {
      final orgId = userData?['organization_id']?.toString();
      if (orgId == null || orgId.isEmpty) return;

      String? logo;

      final orgResp = await supabase
          .from('organizations')
          .select()
          .eq('id', orgId)
          .maybeSingle();

      if (orgResp != null &&
          orgResp['logo_url'] != null &&
          orgResp['logo_url'].toString().isNotEmpty) {

        logo = orgResp['logo_url'].toString();

      } else {
        final files = await supabase.storage
            .from('company-logos')
            .list(path: orgId);

        if (files.isNotEmpty) {
          final fileObj = files.firstWhere(
                (f) {
              final n = (f as Map)['name']?.toString().toLowerCase() ?? '';
              return n.endsWith('.png') ||
                  n.endsWith('.jpg') ||
                  n.endsWith('.jpeg') ||
                  n.endsWith('.webp');
            },
            orElse: () => files.first,
          );

          final fileName = (fileObj as Map)['name'];
          if (fileName != null) {
            logo = supabase.storage
                .from('company-logos')
                .getPublicUrl('$orgId/$fileName');
          }
        }
      }

      setState(() {
        companyLogoUrl = logo;
      });
      drawerNotifier.value = !drawerNotifier.value;

    } catch (e) {
      setState(() => companyLogoUrl = null);
      drawerNotifier.value = !drawerNotifier.value;
    }
  }
  Future<void> _recomputeAndUpdateAttendance(String attendanceId) async {
    try {
      if (attendanceId.isEmpty) return; // safety check

      final logs = await supabase
          .from('attendance_punch_logs')
          .select('punch_type, punch_time')
          .eq('attendance_id', attendanceId)
          .order('punch_time', ascending: true);
      if (logs == null || logs.isEmpty) return;
      DateTime? firstIn;
      DateTime? lastOut;
      for (final l in logs) {
        final timeStr = l['punch_time'];
        if (timeStr == null) continue;
        final t = DateTime.parse(timeStr).toLocal();
        if (l['punch_type'] == 'punch_in') {
          firstIn ??= t;
        } else if (l['punch_type'] == 'punch_out') {
          lastOut = t;
        }
      }
      if (firstIn != null && lastOut != null) {
        final diff = lastOut.difference(firstIn);
        final hours = diff.inHours;
        final minutes = diff.inMinutes.remainder(60);
        // Format total hours as HH:mm
        final totalHours =
        (diff.inMinutes / 60).toStringAsFixed(2);

        await supabase.from('attendance').update({
          'total_hours': totalHours,
          'punch_in_time': firstIn.toIso8601String(),
          'punch_out_time': lastOut.toIso8601String(),
        }).eq('id', attendanceId);
      }
    } catch (e) {
      debugPrint("⚠️ recompute error: $e");
    }
  }  Future<void> _requestNotificationPermission() async {
    // For Android 13+ notifications require runtime permission
    final messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );
    print("🔔 Notification Permission Status: ${settings.authorizationStatus}");
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enable notifications for punch-in alerts."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  //get or create attendance
  Future<String?> getOrCreateAttendanceId() async {
    try {
      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      // ✅ Fetch existing attendance for today
      final existing = await supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', userData?['id'])
          .eq('date', todayStr)
          .order('created_at', ascending: false)
          .limit(1);

      // ✅ If we already have a record, return its ID
      if (existing.isNotEmpty) {
        return existing.first['id'];
      }
      // ✅ If not found, create a new one safely
      final insertedList = await supabase
          .from('attendance')
          .insert({
        'employee_id': userData?['id'],
        'organization_id': userData?['organization_id'],
        'date': todayStr,
        'status': 'present',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      })
          .select('id'); // ⚠️ don't use .single() or .maybeSingle()
      if (insertedList.isNotEmpty) {
        return insertedList.first['id'];
      }
      return null;
    } catch (e) {
      debugPrint("❌ getOrCreateAttendanceId error: $e");
      return null;
    }
  }
  Future<Map<String, dynamic>> getCurrentLocation() async {
    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return {'lat': pos.latitude, 'lng': pos.longitude};
  }
  Future<String> getAddress(double lat, double lng) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleGeocodingApiKey';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['results'] != null && data['results'].isNotEmpty) {
        return data['results'][0]['formatted_address'] as String;
      }
    } catch (e) {
      debugPrint('⚠️ geocoding failed: $e');
    }
    return '$lat, $lng';
  }
  Future<Position> _getLocation() async { if (!await Geolocator.isLocationServiceEnabled()) { await Geolocator.openLocationSettings(); throw Exception('Location services disabled'); } LocationPermission perm = await Geolocator.checkPermission(); if (perm == LocationPermission.denied) { perm = await Geolocator.requestPermission(); } if (perm == LocationPermission.deniedForever) { await Geolocator.openAppSettings(); throw Exception('Location permission denied'); } return await Geolocator.getCurrentPosition( desiredAccuracy: LocationAccuracy.high, ); }
  Future<void> _loadGeoFencePolicy() async { try { final orgId = userData?['organization_id']; final org = await supabase .from('organization_settings') .select('attendance_policies') .eq('organization_id', orgId) .maybeSingle(); final policy = org?['attendance_policies']; if (policy == null) return; geoPolicy = policy; geoEnabled = policy['geo_fencing_enabled'] == true; geoMode = policy['geo_fencing_mode'] ?? 'strict'; final onlyForOffice = policy['geo_only_for_office'] == true; geoTrackOnly =



      onlyForOffice &&
          workTypeOptions[selectedWorkType] != 'on-duty'; await _loadResolvedWorkSites();

  if (geoEnabled && workSites.isNotEmpty) {
    await _checkGeoFence();
  }

  setState(() {}); } catch (e) { debugPrint('geo policy error $e'); } } Future<void> _loadResolvedWorkSites() async { try { final empId = userData?['id']; final branchId = userData?['branch_id']; final entityId = userData?['entity_id']; final orgId = userData?['organization_id']; List data = []; final direct = await supabase .from('work_site_assignments') .select('work_sites(*)') .eq('employee_id', empId); if (direct.isNotEmpty) { data = direct.map((e) => e['work_sites']).toList(); } else { final branchSites = await supabase .from('work_sites') .select() .eq('branch_id', branchId) .eq('is_active', true); if (branchSites.isNotEmpty) { data = branchSites; } else { final entitySites = await supabase .from('work_sites') .select() .eq('entity_id', entityId) .eq('is_active', true); if (entitySites.isNotEmpty) { data = entitySites; } else { data = await supabase .from('work_sites') .select() .eq('organization_id', orgId) .eq('is_active', true); } } } workSites = data .map((e) => WorkSite.fromMap(e)) .toList(); } catch (e) { debugPrint('load work sites error $e'); } } Future<Map<String, dynamic>?> _checkGeoFence()
  async { try {
    geoChecking = true;
    setState(() {});
    final pos = await _getLocation(); gpsAccuracy = pos.accuracy; final nearest = findNearestSite( userLat: pos.latitude, userLng: pos.longitude, sites: workSites, ); if (nearest == null) { return null; } final site = nearest['site'] as WorkSite; geoDistance = nearest['distance']; geoInFence = nearest['inFence']; nearestSiteName = site.name; return { 'position': pos, 'site': site, 'distance': geoDistance, 'inFence': geoInFence, }; } catch (e) {
    geoInFence = false;
    return null;
  } finally {
    geoChecking = false;
    setState(() {});
  }}
  Future<bool> _showGeoConfirmDialog( String site, double distance, double allowed, ) async { return await showDialog<bool>( context: context, builder: (_) { return AlertDialog( shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(16), ), title: const Text( "You appear to be outside an allowed work site", ), content: Text( "You are ${distance.toStringAsFixed(0)}m from $site.\n" "Allowed radius is ${allowed.toStringAsFixed(0)}m.\n\n" "This punch will be flagged for HR review.", ), actions: [ TextButton( onPressed: () { Navigator.pop(context, false); }, child: const Text("Cancel"), ), ElevatedButton( onPressed: () { Navigator.pop(context, true); }, child: const Text("Confirm"), ), ], ); }, ) ?? false; }

  Future<Map<String, dynamic>?> getAssignedShift() async {
    final assigned = await supabase
        .from('shift_assignments')
        .select('shift_id')
        .eq('employee_id', userData?['id'])
        .maybeSingle();
    String? shiftId = assigned?['shift_id'];
    Map<String, dynamic>? shift;
    if (shiftId != null) {
      shift = await supabase
          .from('shift_timings')
          .select()
          .eq('id', shiftId)
          .maybeSingle();
    } else {
      final orgShifts = await supabase
          .from('shift_timings')
          .select()
          .eq('organization_id', userData?['organization_id']);
      if (orgShifts != null && orgShifts.length == 1) {
        shift = orgShifts.first;
      } else {
        return null;
      }
    }
    return shift;
  }
  Future<bool> canPunchNow({required bool isPunchIn}) async {
    final shift = await getAssignedShift();
    if (shift == null) return false;

    final now = DateTime.now(); // Local device time
    final today = now;

    final startTime = (shift['start_time'] as String).substring(0, 5);
    final endTime = (shift['end_time'] as String).substring(0, 5);

    final shiftStart = DateTime(
        today.year, today.month, today.day,
        int.parse(startTime.substring(0, 2)),
        int.parse(startTime.substring(3, 5))
    );
    final shiftEnd = DateTime(
        today.year, today.month, today.day,
        int.parse(endTime.substring(0, 2)), int.parse(endTime.substring(3, 5))
    );
    final inBefore = shift['punch_in_window_before_minutes'] ?? 60;
    final outAfter = shift['punch_out_window_after_minutes'] ?? 240;
    // Declare these variables up front!
    final minPunchIn = shiftStart.subtract(Duration(minutes: inBefore));
    final maxPunchIn = shiftEnd;
    final minPunchOut = shiftStart.subtract(Duration(minutes: inBefore));
    final maxPunchOut = shiftEnd.add(Duration(minutes: outAfter));
    print("Employee attempting punch in/out at: $now");
    if (isPunchIn) {
      print("Punch In Window: $minPunchIn to $maxPunchIn");
      print("Is now after minPunchIn? ${now.isAfter(minPunchIn)}");
      print("Is now before maxPunchIn? ${now.isBefore(maxPunchIn)}");
      return now.isAfter(minPunchIn) && now.isBefore(maxPunchIn);
    } else {
      print("Punch Out Window: $minPunchOut to $maxPunchOut");
      print("Is now after minPunchOut? ${now.isAfter(minPunchOut)}");
      print("Is now before maxPunchOut? ${now.isBefore(maxPunchOut)}");
      return now.isAfter(minPunchOut) && now.isBefore(maxPunchOut);
    }
  }

  Future<void> handlePunchInLog() async {
    if (isBiometricOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Attendance allowed only via biometric device"),
        ),
      );
      return;
    }
    setState(() => loading = true);
    await _loadGeoFencePolicy();
    try {
      final empId = userData?['id'];
      final orgId = userData?['organization_id'];
      if (empId == null || orgId == null) throw Exception('Invalid employee data');
      // 🛰 Get device location and address
      Map<String, dynamic>? geoResult;

      Position pos;

      WorkSite? site;

      bool inFence = true;

      double? distance;

      if (geoEnabled && !geoTrackOnly) {

        geoResult = await _checkGeoFence();

        if (geoResult == null) {

          if (geoMode == 'strict') {

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You are outside allowed office radius"),
              ),
            );

            return;
          }

          pos = await _getLocation();

        } else {

          pos = geoResult['position'];

          site = geoResult['site'];

          inFence = geoResult['inFence'];

          distance = geoResult['distance'];

          if (!inFence && geoMode == 'strict') {

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You are outside allowed office radius"),
              ),
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
      }

      final addr = await getAddress(
        pos.latitude,
        pos.longitude,
      );
      // 🕒 Get current UTC + IST
      // ✅ Local time (IST) for UI/date
      final localNow = DateTime.now();

// ✅ UTC time for database
      final utcIso = localNow.toUtc().toIso8601String();

// ✅ Date must be derived from LOCAL date
      final date = DateFormat('yyyy-MM-dd').format(localNow);

      // 🔹 Check if today's attendance exists
      var attendance = await supabase
          .from('attendance')
          .select()
          .eq('employee_id', empId)
          .eq('date', date)
          .limit(1);
      if (attendance.isEmpty) {
        // ➕ First punch-in of the day → create attendance record
        final insertRes = await supabase
            .from('attendance')
            .insert({
          'employee_id': empId,
          'organization_id': orgId,
          'date': date,
          'punch_in_time': utcIso,
          'punch_in_lat': pos.latitude,
          'punch_in_lng': pos.longitude,
          'punch_in_address': addr,
          'status': 'present',
          'work_type': workTypeOptions[selectedWorkType],   // 🔥 FIX
          'created_at': utcIso,
        })
            .select('id')
            .limit(1);
        attendance = insertRes;
      }
      final attId = attendance.isNotEmpty ? attendance.first['id'] : null;
      if (attId == null) throw Exception('Failed to create or fetch attendance record');
      // 🔹 Log Punch In
      await supabase.from('attendance_punch_logs').insert({
        'attendance_id': attId,
        'employee_id': empId,
        'organization_id': orgId,
        'punch_time': utcIso,
        'punch_type': 'punch_in',
        'work_type': workTypeOptions[selectedWorkType],
        'punch_lat': pos.latitude,
        'punch_lng': pos.longitude,
        'site_id': site?.id,
        'in_fence': inFence,
        'distance_m': distance,
        'accuracy_m': gpsAccuracy,
        'punch_source': 'mobile',
        'punch_address': addr,
        'created_at': utcIso,
      });
      // 🔹 Recompute attendance hours
      await _recomputeAndUpdateAttendance(attId.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Punch In successful')),
      );
      await fetchLatestPunchLogs();
      setState(() {});
    } catch (e) {
      debugPrint('❌ Punch In failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Punch In failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => loading = false);
    }
  }
  Future<void> handlePunchOutLog() async {

    if (isBiometricOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Attendance allowed only via biometric device"),
        ),
      );
      return;
    }
    setState(() => loading = true);
    await _loadGeoFencePolicy();
    try {
      final empId = userData?['id'];
      final orgId = userData?['organization_id'];
      if (empId == null || orgId == null) throw Exception('Invalid employee data');
      // 🛰 Get location and address
      Map<String, dynamic>? geoResult;

      Position pos;

      WorkSite? site;

      bool inFence = true;

      double? distance;

      if (geoEnabled && !geoTrackOnly) {

        geoResult = await _checkGeoFence();

        if (geoResult == null) {

          if (geoMode == 'strict') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You are outside allowed office radius"),
              ),
            );
            return;
          }

          pos = await _getLocation();

        } else {

          pos = geoResult['position'];

          site = geoResult['site'];

          inFence = geoResult['inFence'];

          distance = geoResult['distance'];

          if (!inFence && geoMode == 'strict') {

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You are outside allowed office radius"),
              ),
            );

            return;
          }

          if (!inFence && geoMode == 'lenient') { final confirmed = await _showGeoConfirmDialog( site!.name, distance!, site.radiusMeters, ); if (!confirmed) return; }
        }

      } else {

        pos = await _getLocation();
      }

      final addr = await getAddress(
        pos.latitude,
        pos.longitude,
      );
      // 🕒 Get current UTC + IST
      // ✅ Local IST for UI
      final localNow = DateTime.now();

// ✅ UTC for DB
      final utcNow = localNow.toUtc();
      final utcIso = utcNow.toIso8601String();

// ✅ Date from local
      final date = DateFormat('yyyy-MM-dd').format(localNow);

      // 🔹 Get today's attendance row
      var attendance = await supabase
          .from('attendance')
          .select()
          .eq('employee_id', empId)
          .eq('date', date)
          .limit(1);
      // 🚨 VALIDATE WORK TYPE BEFORE PUNCH OUT
      if (attendance.isNotEmpty) {
        final punchInWorkType = attendance.first['work_type'];
        final selectedTypeValue = workTypeOptions[selectedWorkType];

        if (punchInWorkType != selectedTypeValue) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "You selected a different work type.\n"
                    "Please select '${punchInWorkType}' to punch out.",
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => loading = false);
          return; // ⛔ STOP execution
        }
      }
      if (attendance.isEmpty) {

        final created =
        await supabase
            .from('attendance')
            .insert({

          'employee_id': empId,

          'organization_id': orgId,

          'date': date,

          'status': 'present',

          'created_at':
          DateTime.now()
              .toUtc()
              .toIso8601String(),

        })
            .select()
            .single();

        attendance = [created];
      }
      final attId = attendance.first['id'];
      // 🔹 Update punch-out time in attendance
      await supabase
          .from('attendance')
          .update({
        'punch_out_time': utcIso,
        'punch_out_lat': pos.latitude,
        'punch_out_lng': pos.longitude,
        'punch_out_address': addr,
        'updated_at': utcIso,
      })
          .eq('id', attId);
      // Log Punch Out
      await supabase.from('attendance_punch_logs').insert({
        'attendance_id': attId,
        'employee_id': empId,
        'organization_id': orgId,
        'punch_time': utcIso,
        'punch_type': 'punch_out',
        'work_type': workTypeOptions[selectedWorkType],
        'punch_lat': pos.latitude,
        'punch_lng': pos.longitude,
        'site_id': site?.id,
        'in_fence': inFence,
        'distance_m': distance,
        'accuracy_m': gpsAccuracy,
        'punch_source': 'mobile',
        'punch_address': addr,
        'created_at': utcIso,
      });
      // 🔹 Recompute worked hours
      await _recomputeAndUpdateAttendance(attId.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Punch Out successful')),
      );
      await fetchLatestPunchLogs();
      setState(() {});
    } catch (e) {
      debugPrint('❌ Punch Out failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Punch Out failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => loading = false);
    }
  }
  Future<void> fetchLatestPunchLogs() async {
    try {
      final empId = userData?['id'];
      if (empId == null) return;

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final logs = await supabase
          .from('attendance_punch_logs')
          .select()
          .eq('employee_id', empId)
          .gte('punch_time', '$todayStr 00:00:00')
          .lte('punch_time', '$todayStr 23:59:59')
          .order('punch_time', ascending: true);

      if (logs.isNotEmpty) {
        final last = logs.last;

        setState(() {
          lastPunchType = last['punch_type'];
          punchedInNow = lastPunchType == "punch_in";   // 🔥 MAIN FIX
        });
      } else {
        setState(() {
          lastPunchType = null;
          punchedInNow = false;                         // 🔥 ALSO SET THIS
        });
      }
    } catch (e) {
      debugPrint("❌ fetchLatestPunchLogs error: $e");
    }
  }

  String formatToIndianTime(String utcString) {
    try {
      final utcTime = DateTime.parse(utcString).toUtc();
      final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
      return DateFormat('yyyy-MM-dd hh:mm a').format(istTime);
    } catch (_) {
      return utcString;
    }
  }
  // ------------------- LEAVE CALCULATION HELPERS -------------------

  /// Try common numeric field names and return a usable number
  num _parseLeaveNumber(Map<String, dynamic> row) {
    final possibleKeys = [
      'available', 'balance', 'remaining',
      'entitled', 'allocated', 'used', 'days'
    ];

    for (final k in possibleKeys) {
      if (row.containsKey(k) && row[k] != null) {
        final v = row[k];
        if (v is num) return v;
        if (v is String) {
          final n = num.tryParse(v.replaceAll(',', '').trim());
          if (n != null) return n;
        }
      }
    }

    if (row.containsKey('allocated') && row.containsKey('used')) {
      final a = (row['allocated'] is num)
          ? row['allocated']
          : num.tryParse((row['allocated'] ?? '').toString()) ?? 0;

      final u = (row['used'] is num)
          ? row['used']
          : num.tryParse((row['used'] ?? '').toString()) ?? 0;

      return a - u;
    }

    return 0;
  }

  /// Build readable leave summary
  String buildLeaveSummaryFromContext(Map<String, dynamic> hrmsContext) {
    final rawLeaves = hrmsContext['leave_balances'];
    if (rawLeaves == null) return "No leave balance records available.";

    if (rawLeaves is! List) return "Leave balances format unexpected.";

    final Map<String, num> byType = {};
    num total = 0;

    for (final item in rawLeaves) {
      if (item is Map<String, dynamic>) {
        String type = item['type']?.toString()
            ?? item['leave_type']?.toString()
            ?? item['name']?.toString()
            ?? 'Other';

        final value = _parseLeaveNumber(item);
        byType[type] = (byType[type] ?? 0) + value;
        total += value;
      }
    }

    if (byType.isEmpty) return "No leave balances recorded for you.";

    final buffer = StringBuffer();
    buffer.writeln("You have a total of ${total.toString()} leave days:");
    byType.forEach((t, v) {
      buffer.writeln("- $t: ${v.toString()} days");
    });

    return buffer.toString();
  }
// ------------------- END LEAVE HELPERS -------------------

  Future<Map<String, dynamic>> fetchHrmsContext() async {
    try {
      debugPrint("🔵 userData = $userData");

      // BASIC USER VALUES
      final orgId = userData?['organization_id'];
      final employeeUuid = userData?['id'];   // UUID (CORRECT)

      if (employeeUuid == null || orgId == null) {
        return {"error": "Employee or organization info missing"};
      }

      // 🌟 MAIN EMPLOYEE IDENTIFIER = UUID
      final empId = employeeUuid;
      // 🔐 FETCH DECRYPTED SALARY FROM VIEW
      final salaryRow = await supabase
          .from('employee_salary_view')
          .select('salary')
          .eq('email', userData?['email'])
          .maybeSingle();

      debugPrint("🟡 DASHBOARD SALARY ROW => $salaryRow");


      // FETCH EVERYTHING (ALL TABLES USE UUID)
      final results = await Future.wait<dynamic>([
        // 0. EMPLOYEE RECORD (UUID)
        supabase
            .from('employee_records')
            .select()
            .eq('id', empId)
            .maybeSingle(),

        // 1. ORGANIZATION DETAILS
        supabase
            .from('organizations')
            .select()
            .eq('id', orgId)
            .maybeSingle(),

        // 2. ANNOUNCEMENTS
        supabase
            .from('announcements')
            .select()
            .eq('organization_id', orgId)
            .order('created_at', ascending: false)
            .then((res) => res ?? []),

        // 3. COMPANY POLICIES
        supabase
            .from('company_policies')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 4. LEAVE BALANCES (UUID)
        supabase
            .from('leave_balances')
            .select()
            .eq('employee_id', empId)
            .then((res) => res ?? []),

        // 5. LEAVE APPLICATIONS
        supabase
            .from('leave_applications')
            .select()
            .eq('employee_id', empId)
            .order('created_at', ascending: false)
            .then((res) => res ?? []),

        // 6. LEAVE POLICIES
        supabase
            .from('leave_policies')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 7. FAQS
        supabase
            .from('faqs')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 8. HOLIDAYS
        supabase
            .from('holidays')
            .select()
            .eq('organization_id', orgId)
            .order('date', ascending: true)
            .then((res) => res ?? []),

        // 9. SALARY CONFIG
        supabase
            .from('salary_configurations')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 10. SHIFT TIMINGS
        supabase
            .from('shift_timings')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 11. ATTENDANCE RULES
        supabase
            .from('attendance_rules')
            .select()
            .eq('organization_id', orgId)
            .maybeSingle(),

        // 12. TAX DECLARATIONS
        supabase
            .from('tax_declarations')
            .select()
            .eq('employee_id', empId)
            .then((res) => res ?? []),

        // 13. TAX REGIME SELECTION
        supabase
            .from('tax_regime_selections')
            .select()
            .eq('employee_id', empId)
            .maybeSingle(),

        // 14. TAX WINDOWS
        supabase
            .from('tax_submission_windows')
            .select()
            .eq('organization_id', orgId)
            .then((res) => res ?? []),

        // 15. ASSETS
        supabase
            .from('asset_assignments')
            .select()
            .eq('employee_id', empId)
            .then((res) => res ?? []),

        // 16. BENEFIT CLAIMS
        supabase
            .from('benefit_claims')
            .select()
            .eq('employee_id', empId)
            .then((res) => res ?? []),

        // 17. NOTIFICATIONS (UUID)
        supabase
            .from('notifications')
            .select()
            .eq('recipient_employee_id', empId)
            .order('created_at', ascending: false)
            .then((res) => res ?? []),

        // 18. ATTENDANCE (UUID)
        supabase
            .from('attendance')
            .select()
            .eq('employee_id', empId)
            .order('created_at', ascending: false)
            .then((res) => res ?? []),

        // 19. ATTENDANCE PUNCH LOGS (UUID)
        supabase
            .from('attendance_punch_logs')
            .select()
            .eq('employee_id', empId)
            .order('punch_time', ascending: true)
            .then((res) => res ?? []),

        // 20. OVERTIME RECORDS (UUID)
        supabase
            .from('overtime_records')
            .select()
            .eq('employee_id', empId)
            .order('ot_date', ascending: false)
            .then((res) => res ?? []),

        // 21. REGULARIZATION REQUESTS
        supabase
            .from('attendance_regularization_requests')
            .select()
            .eq('employee_id', empId)
            .order('created_at', ascending: false)
            .then((res) => res ?? []),
      ]);

      final employeeRecord = results[0];
      final orgRecord = results[1];

      if (employeeRecord == null) return {"error": "Employee not found"};
      if (orgRecord == null) return {"error": "Organization not found"};

      final allPunchLogs = results[19];

      final punchOutLogs = allPunchLogs
          .where((e) => e['punch_type'] == 'punch_out')
          .toList();

      punchOutLogs.sort((a, b) {
        final ta = DateTime.parse(a['punch_time']);
        final tb = DateTime.parse(b['punch_time']);
        return tb.compareTo(ta); // latest first
      });

      final List<dynamic> attendanceLogs = results[19] ?? [];
      final attendanceByDate = buildAttendanceByDate(attendanceLogs);

      return {
        "attendance": {
          "by_date": attendanceByDate
        },

        "employee_profile": {
          "full_name": employeeRecord['full_name'],
          "employee_id": employeeRecord['employee_id'],
          "department": employeeRecord['department'],
          "designation": employeeRecord['designation'],
          "employment_status": employeeRecord['employment_status'],
          "date_of_joining": employeeRecord['date_of_joining'],
          "manager_name": employeeRecord['manager_name'],
          "manager_email": employeeRecord['manager_email'],
        },
        "organization_details": orgRecord,
        "payroll": {
          "salary": salaryRow?['salary'],
        },
        // ✅ ADD THESE TWO (THIS FIXES ATTENDANCE QUESTIONS)
        // ✅ THIS IS WHAT TOFFY NEEDS
        "attendance_punch_logs": punchOutLogs,
        "announcements": results[2],
        "company_policies": results[3],
        "leave_balances": results[4],
        "leave_applications": results[5],
        "leave_policies": results[6],
        "faqs": results[7],
        "holidays": results[8],
        "salary_configurations": results[9],
        "shift_timings": results[10],
        "attendance_rules": results[11],
        "tax_declarations": results[12],
        "tax_regime_selection": results[13],
        "tax_submission_windows": results[14],
        "assets": results[15],
        "benefit_claims": results[16],
        "notifications": results[17],

        "overtime_records": results[20],
        "attendance_regularization": results[21],
      };


    } catch (e, stack) {
      debugPrint("❌ fetchHrmsContext error → $e\n$stack");
      return {"error": "Unable to load HRMS data"};
    }
  }

  Map<String, dynamic> buildAttendanceByDate(List<dynamic> logs) {
    final Map<String, Map<String, String?>> byDate = {};

    for (final log in logs) {
      if (log['punch_time'] == null) continue;

      final dt = DateTime.parse(log['punch_time']).toLocal();
      final dateKey =
          "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";

      byDate.putIfAbsent(dateKey, () => {
        "punch_in": null,
        "punch_out": null,
      });

      if (log['punch_type'] == 'punch_in') {
        // ✅ earliest punch_in
        byDate[dateKey]!['punch_in'] ??= log['punch_time'];
      }

      if (log['punch_type'] == 'punch_out') {
        // ✅ always keep latest punch_out
        byDate[dateKey]!['punch_out'] = log['punch_time'];
      }
    }

    return byDate;
  }




  @override
  Widget build(BuildContext context) {

    // ✅ ADD THIS BLOCK (VERY IMPORTANT)


    // ✅ KEEP YOUR EXISTING CODE BELOW
    final orgName = orgDetails?['name'] ?? "--";
    final designation = userData?['designation'] ?? "--";
    final employeeId = userData?['employee_id'] ?? "--";
    final managerName = userData?['manager_name'] ?? "--";
    final managerEmail = userData?['manager_email'] ?? "--";
    final managerId = managerData?['employee_id'] ?? "--";

    return Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.white,
        endDrawer: AppDrawer(
          userEmail: widget.email,
          userData: userData ?? {},
          companyLogoUrl: companyLogoUrl,
          fetchHrmsContext: fetchHrmsContext,
          currentRoute: DrawerRoute.dashboard,
        ),
        appBar: AppBar(
          automaticallyImplyLeading: false,   // ← stop auto hamburger
          leading: SizedBox.shrink(),         // ← remove default leading completely
          elevation: 0,
          backgroundColor: Colors.white,
          title: const SizedBox.shrink(),
          actions: [], // ← ADD THIS (important)// NO text here
          // ⭐ ⭐ ⭐ THIS IS WHERE YOU PLACE GREETING BLOCK ⭐ ⭐ ⭐
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),  // ↓ reduced from 90 → 70
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreetingMessage(),
                          style: GoogleFonts.montserrat(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          userData?['full_name'] ?? "--",
                          style: GoogleFonts.montserrat(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 12),   // perfect spacing

                        Text(
                          orgDetails?['name'] ?? "--",
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),


                  // RIGHT — Rounded icons like reference UI
                  Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: SvgPicture.asset(
                            "assets/icons/notification.svg",
                            width: 24,
                            height: 24,
                            color: Colors.black,
                          ),
                          onPressed: () {
                            final empId = (userData?['id'] ?? userData?['employee_id'])?.toString() ?? '';

                            if (empId.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Employee id missing. Cannot open notifications.')),
                              );
                              return;
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NotificationsScreen(
                                  employeeId: empId,
                                  userEmail: widget.email,
                                  userData: userData ?? {},
                                  fetchHrmsContext: fetchHrmsContext,
                                ),
                              ),
                            );

                          },

                        ),

                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: SvgPicture.asset(
                            "assets/icons/menu.svg",
                            width: 24,
                            height: 24,
                            color: Colors.black,
                          ),
                          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                        ),

                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        body: loadingProfile
            ? SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
          child: Column(
            children: [
              dashboardWelcomeSkeleton(),
              dashboardManagerSkeleton(),
              dashboardAttendanceSkeleton(),
            ],
          ),
        )
            : dashboardError != null
            ? Center(child: Text(
          dashboardError!,
          style: TextStyle(fontSize: 16, color: Colors.red),
        ))
            : userData == null
            ? Center(child: Text(
          "Unable to load profile. Please try again later.",
          style: TextStyle(fontSize: 16, color: Colors.red),
        ))
            : Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // ======================= TODAY'S ATTENDANCE CARD =======================
    // ======================= TODAY'S ATTENDANCE CARD =======================
    Container(
    width: double.infinity,
    decoration: BoxDecoration(
    color: const Color(0xFFF0F8FF),
    border: Border.all(color: kBorderColor),
    borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 16),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // 🔹 Header + Live Clock
    Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
    Text(
    "Today's Attendance",
    style: GoogleFonts.montserrat(
    fontWeight: FontWeight.bold,
    fontSize: 15,
    color: Colors.black87,
    ),
    ),
    const LiveClock(),
    ],
    ),

    const SizedBox(height: 12),




    // ================= FUTUREBUILDER =================
    FutureBuilder<List<Map<String, dynamic>>>(
    future: todayLogsFuture,
    builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
    return const Center(child: CircularProgressIndicator());
    }
    final logs = snapshot.data ?? [];
    // ================= BIOMETRIC ONLY MODE =================
    if (isBiometricOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show existing logs (from biometric device)
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...logs.map((e) {
              final t = e['punch_time'];
              final type = e['punch_type'];

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "${type == 'punch_in' ? 'Punch In' : 'Punch Out'} : "
                      "${DateFormat('hh:mm a').format(DateTime.parse(t).toLocal())}",
                  style: GoogleFonts.montserrat(fontSize: 13),
                ),
              );
            }).toList(),
          ],

          // Show biometric warning card
          _biometricOnlyCard(),
        ],
      );
    }

    if (!workTypeOptions.keys.contains(selectedWorkType)) {
    selectedWorkType = "On-Duty";
    }

    // =============================================================
    //                NO PUNCHES TODAY
    // =============================================================
    if (logs.isEmpty) {
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    const Text(
    "No punches yet today.",
    style: TextStyle(color: Colors.grey),
    ),
    const SizedBox(height: 12),

    // ================= WORK TYPE =================
    DropdownButtonFormField<String>(
    value: selectedWorkType,
    decoration: const InputDecoration(
    labelText: "Work Type",
    border: OutlineInputBorder(),
    ),
    items: workTypeOptions.keys
        .map((e) => DropdownMenuItem(
    value: e,
    child: Text(e),
    ))
        .toList(),
    onChanged: (v) {
    if (v != null) setState(() => selectedWorkType = v);
    },
    ),

    const SizedBox(height: 16),

    // ===================== SINGLE FULL-WIDTH BUTTON =====================
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: geoChecking
              ? null
              : (geoEnabled &&
              geoMode == 'strict' &&
              !geoInFence)
              ? null
              : (!loading)
              ? () async {
            await handlePunchInLog();
            await fetchLatestPunchLogs();
            setState(() {});
          }
              : null,

          style: ElevatedButton.styleFrom(
            backgroundColor:
            (!loading) ? Colors.blue : Colors.grey.shade300,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),

          child: loading
              ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.login, size: 22),
              SizedBox(width: 10),
              Text(
                "Punch In Now",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),

      if (geoEnabled &&
          geoMode == 'strict' &&
          !geoInFence)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              const Icon(
                Icons.location_off,
                color: Colors.red,
                size: 18,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  "You are outside allowed office radius. Move near your office location to enable punch in.",
                  style: GoogleFonts.montserrat(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
    );
    }

    // =============================================================
    //                PUNCH LOGS EXIST
    // =============================================================
    final lastIn = logs.lastWhere(
    (e) => e['punch_type'] == 'punch_in',
    orElse: () => {});
    final lastOut = logs.lastWhere(
    (e) => e['punch_type'] == 'punch_out',
    orElse: () => {});
    final punchedInNow =
    logs.isNotEmpty && logs.last['punch_type'] == 'punch_in';

    String fmt(String? val) {
      if (val == null || val.isEmpty) return "--";
      try {
        final dt = DateTime.parse(val).toLocal(); // ✅ UTC → IST
        return DateFormat('yyyy-MM-dd hh:mm a').format(dt);
      } catch (_) {
        return val;
      }
    }


    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // ===================== LAST PUNCH IN =====================
    Row(
    children: [
    const Icon(Icons.login, color: Colors.green, size: 18),
    const SizedBox(width: 6),
    Text(
    "Last Punch In:",
    style: GoogleFonts.montserrat(
    fontSize: 14,
    color: Colors.black87,
    ),
    ),
    const SizedBox(width: 6),
    Expanded(
    child: Text(
    fmt(lastIn['punch_time']),
    style: GoogleFonts.montserrat(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    ),
    ),
    ),
    ],
    ),
    if (lastIn['punch_address'] != null)
    Padding(
    padding: const EdgeInsets.only(left: 28.0, top: 4),
    child: Text(
    lastIn['punch_address'],
    style: GoogleFonts.montserrat(
    fontSize: 12,
    color: Colors.grey,
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    ),
    ),

    const SizedBox(height: 10),

    // ===================== LAST PUNCH OUT =====================
    Row(
    children: [
    const Icon(Icons.logout, color: Colors.red, size: 18),
    const SizedBox(width: 6),
    Text(
    "Last Punch Out:",
    style: GoogleFonts.montserrat(
    fontSize: 14,
    color: Colors.black87,
    ),
    ),
    const SizedBox(width: 6),
    Expanded(
    child: Text(
    fmt(lastOut['punch_time']),
    style: GoogleFonts.montserrat(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    ),
    ),
    ),
    ],
    ),
    if (lastOut['punch_address'] != null)
    Padding(
    padding: const EdgeInsets.only(left: 28.0, top: 4),
    child: Text(
    lastOut['punch_address'],
    style: GoogleFonts.montserrat(
    fontSize: 12,
    color: Colors.grey,
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    ),
    ),

    const SizedBox(height: 16),

    // ===================== WORK TYPE =====================
    DropdownButtonFormField<String>(
    value: selectedWorkType,
    decoration: const InputDecoration(
    labelText: "Work Type",
    border: OutlineInputBorder(),
    ),
    items: workTypeOptions.keys
        .map((label) => DropdownMenuItem(
    value: label,
    child: Text(label),
    ))
        .toList(),
    onChanged: (v) {
    if (v != null) setState(() => selectedWorkType = v);
    },
    ),

    const SizedBox(height: 16),

    // ===================== SINGLE FULL-WIDTH BUTTON =====================
    SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: geoChecking
          ? null
          : (geoEnabled &&
          geoMode == 'strict' &&
          !geoInFence)
          ? null
          : (!loading)
          ? () async {
        await handlePunchOutLog();
        await fetchLatestPunchLogs();
        setState(() {});
      }
          : null,
    style: ElevatedButton.styleFrom(
    backgroundColor: (!loading)
    ? Colors.blue
        : Colors.grey.shade300,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30),
    ),
    ),
      child: loading
          ? const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      )
          : Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.logout, size: 22),
          SizedBox(width: 10),
          Text(
            "Punch Out",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
    ),
    ],
    );
    },
    ),
    ],
    ),
    ),
                              buildMealVoucherCard(),

                              // ================== QUICK ACTION CARDS (Leave, Payslip, Time) ==================
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildQuickCard(
                                    svgPath: "assets/icons/leaves.svg",
                                    iconColor: Colors.blue,
                                    cardColor: const Color(0xFFEAF4FF),
                                    label: "Leave",
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => LeavesScreen(
                                            email: userData?['email'] ?? '',
                                            userData: userData ?? {},
                                            fetchHrmsContext: fetchHrmsContext,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildQuickCard(
                                    svgPath: "assets/icons/payroll.svg",
                                    iconColor: Colors.green,
                                    cardColor: const Color(0xFFEFFBF1),
                                    label: "Payslip",
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PayslipScreen(
                                            userEmail: userData?['email'] ?? '',
                                            userData: userData ?? {},
                                            fetchHrmsContext: fetchHrmsContext,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildQuickCard(
                                    svgPath: "assets/icons/attendance.svg",
                                    iconColor: Colors.indigo,
                                    cardColor: const Color(0xFFF3EEFF),
                                    label: "Time",
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TimeAttendanceScreen(
                                            userEmail: userData!['email'],
                                            userData: userData!,
                                            fetchHrmsContext: fetchHrmsContext,
                                          )

                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              FutureBuilder<Map<String, dynamic>>(
                                future: leaveSummaryFuture,
                                // <-- use existing userData id
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox(); // or a small loader
                                  }
                                  if (!snapshot.hasData) {
                                    return const SizedBox();
                                  }

                                  final data = snapshot.data!;
                                  final available = data['available'];
                                  final used = data['used'];
                                  final pending = data['pending'];
                                  final year = data['year'];

                                  String fmtNum(dynamic v) {
                                    if (v == null) return '0';
                                    if (v is num) return v.toString();
                                    return v.toString();
                                  }

                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4EA),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // HEADER
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "Leave Balance",
                                              style: GoogleFonts.montserrat(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              year.toString(),
                                              style: GoogleFonts.montserrat(
                                                fontSize: 14,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 18),

                                        // THREE COLUMNS
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            // AVAILABLE
                                            Column(
                                              children: [
                                                Text(
                                                  fmtNum(available),
                                                  style: GoogleFonts.montserrat(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Available",
                                                  style: TextStyle(color: Colors.grey.shade700),
                                                ),
                                              ],
                                            ),

                                            // USED
                                            Column(
                                              children: [
                                                Text(
                                                  fmtNum(used),
                                                  style: GoogleFonts.montserrat(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Used",
                                                  style: TextStyle(color: Colors.grey.shade700),
                                                ),
                                              ],
                                            ),

                                            // PENDING
                                            Column(
                                              children: [
                                                Text(
                                                  fmtNum(pending),
                                                  style: GoogleFonts.montserrat(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Pending",
                                                  style: TextStyle(color: Colors.grey.shade700),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFFCF5),
                                  border: Border.all(color: kBorderColor),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Assigned Manager Details",
                                        style: GoogleFonts.montserrat(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.black)),
                                    const SizedBox(height: 8),
                                    managerInfoRow(
                                        Icons.person_outline, "Manager Name",
                                        managerName),

                                    managerInfoRow(
                                        Icons.email_outlined, "Manager Email",
                                        managerEmail),
                                  ],
                                ),
                              ),

                              // 🟦 Ask Toffy header & input card

                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 10, right: 4),
                                ),
                              ),

                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,     // pushes content above the FAB
              child: SizedBox.shrink(),
            ),
            // Floating Toffy HRMS Assistant
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed, // 🔴 IMPORTANT
          selectedFontSize: 10,                // 🔽 reduced
          unselectedFontSize: 9,
          currentIndex: _bottomTabIndex,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          // 👇 SHOW LABELS BELOW ICONS
          showSelectedLabels: true,
          showUnselectedLabels: true,
          onTap: (index) async {
            if (index == 0) {
              setState(() => _bottomTabIndex = 0);
              return;
            }
            if (index == 1) {
              setState(() => _bottomTabIndex = index);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LeavesScreen(
                    email: userData?['email'] ?? '',
                    userData: userData ?? {},
                    fetchHrmsContext: fetchHrmsContext,
                  ),));
              return;
            }
            if (index == 2) {
              setState(() => _bottomTabIndex = index);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimeAttendanceScreen(
                    userEmail: userData!['email'],
                    userData: userData!,
                    fetchHrmsContext: fetchHrmsContext,
                  ),
                ),
              );
              return;
            }
            if (index == 3) {
              setState(() => _bottomTabIndex = index);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PayslipScreen(
                    userEmail: userData?['email'] ?? '',
                    userData: userData ?? {},
                    fetchHrmsContext: fetchHrmsContext,
                  ),));
              return;
            }
            if (index == 4) {
              _scaffoldKey.currentState?.openEndDrawer();
              return;   // no need to change tab index
            }

            // 👉 Handle Toffy icon tap (last item index = 5)
            // 👉 Handle Toffy icon tap (FULL PAGE)



            // 👉 Normal bottom bar navigation
            setState(() {
              _bottomTabIndex = index;
            });
          },
          // 👇 UPDATED ICONS — using your custom icons
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/dashboard.svg",
                width: 22,
                height: 22,
                color: _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Dashboard',
            ),

            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/leaves.svg",
                width: 22,
                height: 22,
                color: _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Leave',
            ),

            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/attendance.svg",
                width: 22,
                height: 22,
                color: _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Attendance',
            ),

            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/payroll.svg",
                width: 22,
                height: 22,
                color: _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Payslip',
            ),

            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/menu.svg",
                width: 22,
                height: 22,
                color: Colors.grey,   // always grey because "More" doesn't stay selected
              ),
              label: 'More',
            ),

          ],
        )
    );
  }

  Widget managerInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text("$label: ", style: GoogleFonts.montserrat(
              fontSize: 13, color: Color(0xFF888888))),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black),
              overflow: TextOverflow.ellipsis, maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
  Widget _infoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 19),
          SizedBox(width: 8),
          Text("$title: ", style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600, color: Colors.black87)),
          Expanded(
            child: Text(
                value, style: GoogleFonts.montserrat(color: Colors.black),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
        ],
      ),
    );
  }
  // 🔽 Add this right below inside the same _DashboardScreenState class)
  Widget _idField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "$label:",
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  // ✅ Add this function completely below _idInfoRow
  Widget _buildNotificationsSheet() {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: loadingNotifications
            ? const Center(child: CircularProgressIndicator())
            : notifications.isEmpty
            ? const Center(child: Text("No notifications yet."))
            : ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, i) {
            final n = notifications[i];
            final createdAt = n['created_at'] != null
                ? DateFormat('MMM dd, yyyy hh:mm a')
                .format(DateTime.parse(n['created_at']))
                : '';
            return ListTile(
              leading: Icon(
                n['read'] == true
                    ? Icons.notifications_outlined
                    : Icons.notifications_active_rounded,
                color: n['read'] == true
                    ? Colors.grey
                    : Colors.blueAccent,
              ),
              title: Text(
                n['title'] ?? '(No Title)',
                style: GoogleFonts.montserrat(
                  fontWeight: n['read'] == true
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n['body'] ?? '',
                    style: GoogleFonts.montserrat(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    createdAt,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              onTap: () async {
                if (n['read'] == false) {
                  await supabase
                      .from('notifications')
                      .update({'read': true})
                      .eq('id', n['id']);
                  await fetchNotifications();
                }
              },
            );
          },
        ),
      ),
    );
  } // ✅ closes _buildNotificationsSheet()
}
class RotationYTransition extends AnimatedWidget {
  final Widget child;
  RotationYTransition({required Animation<double> turns, required this.child})
      : super(listenable: turns);
  @override
  Widget build(BuildContext context) {

    final animation = listenable as Animation<double>;
    final double angle = animation.value * 3.14;

    return Transform(
      transform: Matrix4.rotationY(angle),
      alignment: Alignment.center,
      child: child,
    );
  }
}
