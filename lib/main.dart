import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'screens/notification.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/leaves_screen.dart';
import 'screens/events_calendar_screen.dart';
import 'screens/payslip_screen.dart';
import 'screens/surveys_screen.dart';
import 'screens/announcements_screen.dart';

/// NOTIFICATION PLUGIN
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// GLOBAL NAV KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================================
// 🔵 BACKGROUND NOTIFICATION HANDLER
// ============================================================================
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final notification = message.notification;
  if (notification != null) {
    const androidDetails = AndroidNotificationDetails(
      'employee_alerts',
      'Employee Alerts',
      channelDescription: 'Alert messages from HRMS',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@drawable/ic_stat_notify',
      largeIcon: DrawableResourceAndroidBitmap('toffy_big'),
    );

    const details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? 'New Notification',
      notification.body ?? '',
      details,
    );
  }
}

// ============================================================================
// 🔵 MAIN
// ============================================================================


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase Init
  await Supabase.initialize(
    url: 'https://erjqikaafyefaujyzrax.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVyanFpa2FhZnllZmF1anl6cmF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwNjIxMTUsImV4cCI6MjA3MDYzODExNX0.11w-rm-tZ7dcW-HIQnbu15jmGNo5YuQQgcS-NwSc0EE',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;

    if (event == AuthChangeEvent.signedOut) {
      // ❌ REMOVE AUTO REDIRECT
      print("User signed out (auto). Ignoring...");
    }
  });



  // Firebase Init
  await Firebase.initializeApp();

  // Background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Notification Channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'employee_alerts',
    'Employee Alerts',
    description: 'Alert messages from HR Toffy',
    importance: Importance.high,
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

  // Local NOTIFICATION INIT
  const AndroidInitializationSettings androidInit =
  AndroidInitializationSettings('@drawable/ic_stat_notify');

  const InitializationSettings initSettings =
  InitializationSettings(android: androidInit);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,

    onDidReceiveNotificationResponse: (response) async {

      print("🔔 Notification clicked");

      final payload = response.payload;

      print("Payload => $payload");

      if (payload == null) return;

      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) return;

      final employee = await Supabase.instance.client
          .from('employee_records')
          .select()
          .eq('email', user.email!)
          .single();
      final orgId = employee['organization_id']?.toString() ?? '';
      final department = employee['department']?.toString() ?? '';

      final employeeId = employee['id'];

      // =========================
      // LEAVE
      // =========================
      if (payload == "leave") {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => LeavesScreen(
              email: user.email!,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }

      else if (payload == "announcement") {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AnnouncementsScreen(
              organizationId: orgId,
              userDepartment: department,
              userEmail: user.email!,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }

      // =========================
      // EVENT
      // =========================
      else if (payload == "event") {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => EventsCalendarScreen(
              email: user.email!,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }

      // =========================
      // PAYROLL
      // =========================
      else if (payload == "payroll") {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PayslipScreen(
              userEmail: user.email!,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }

      // =========================
      // SURVEY
      // =========================
      else if (payload == "survey") {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => SurveysScreen(
              userEmail: user.email!,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }

      // =========================
      // DEFAULT
      // =========================
      else {

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              email: user.email!,
              employeeId: employeeId,
            ),
          ),
        );
      }
    },
  );

  // Auto-login check
  final session = Supabase.instance.client.auth.currentSession;

  runApp(MyApp(isLoggedIn: session != null));
}

Map<String, dynamic> buildAttendanceSummary(List<dynamic> logs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  DateTime? todayFirstPunch;
  DateTime? todayLastPunch;
  DateTime? yesterdayFirstPunch;
  DateTime? yesterdayLastPunch;

  for (final log in logs) {
    if (log['punch_time'] == null) continue;

    final punchTime = DateTime.parse(log['punch_time']).toLocal();

    final punchDate = DateTime(
      punchTime.year,
      punchTime.month,
      punchTime.day,
    );

    if (punchDate == today) {
      todayFirstPunch ??= punchTime;
      todayLastPunch = punchTime;
    } else if (punchDate == yesterday) {
      yesterdayFirstPunch ??= punchTime;
      yesterdayLastPunch = punchTime;
    }
  }

  return {
    "today": {
      "first_punch": todayFirstPunch?.toIso8601String(),
      "last_punch": todayLastPunch?.toIso8601String(),
      "has_data": todayFirstPunch != null,
    },
    "yesterday": {
      "first_punch": yesterdayFirstPunch?.toIso8601String(),
      "last_punch": yesterdayLastPunch?.toIso8601String(),
      "has_data": yesterdayFirstPunch != null,
    },
  };
}

Future<Map<String, dynamic>> fetchHrmsContext() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return {"error": "User not logged in"};
  }

  final employee = await supabase
      .from('employee_records')
      .select()
      .eq('email', user.email!)
      .single();

  final employeeId = employee['id']; // UUID


  final leaveBalances = await supabase
      .from('leave_balances')
      .select('leave_type, balance')
      .eq('employee_id', employeeId);

  final attendanceLogs = await supabase
      .from('attendance_punch_logs')
      .select('punch_time')
      .eq('employee_id', employeeId)
      .order('punch_time', ascending: true);
  final salaryRow = await supabase
      .from('employee_salary_view')
      .select('salary')
      .eq('email', user.email!)
      .maybeSingle();
  debugPrint("🟡 SALARY ROW => $salaryRow");
  final announcements = await supabase
      .from('announcements')
      .select('title, date')
      .order('date', ascending: true);
  debugPrint("🟡 PAYROLL CONTEXT => ${{
    "salary": salaryRow?['salary'],
  }}");
  return {
    "employee_profile": {
      "full_name": employee['full_name'],
      "department": employee['department'],
      "designation": employee['designation'],
      "manager_name": employee['manager_name'],
      "manager_id": employee['manager_id'],
      "date_of_joining": employee['date_of_joining'] != null
          ? employee['date_of_joining'].toString()
          : null,
      "employment_status": employee['employment_status'],
    },
    "leave_balances": leaveBalances
        .where((l) => (l['balance'] ?? 0) > 0)
        .toList(),
    "attendance": buildAttendanceSummary(attendanceLogs),
    "payroll": {
      "salary": salaryRow?['salary'],
    },
    "announcements": announcements,
  };
}
// ============================================================================
// 🔵 UI THEME SYSTEM (Your new design system)
// ============================================================================
class AppColors {
  static const primary = Color(0xFF1E90FF);
  static const background = Colors.white;
  static const card = Color(0xFFF9F9F9);
  static const border = Color(0xFFE0E0E0);
  static const heading = Color(0xFF222222);
  static const body = Color(0xFF444444);
  static const subtext = Color(0xFF888888);
}
class AppRadius {
  static const card = 16.0;
  static const button = 16.0;
}
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: "Montserrat",
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primary,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    // ---------------- TEXT THEME ----------------
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        fontSize: 16,
        fontFamily: "Montserrat",
        color: AppColors.body,
      ),
      bodySmall: TextStyle(
        fontSize: 14,
        color: AppColors.subtext,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.heading,
      ),
    ),
    // ---------------- APP BAR ----------------
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.heading),
      titleTextStyle: TextStyle(
        fontFamily: "Montserrat",
        color: AppColors.heading,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    // ---------------- CARDS ----------------
    // --------------- CARDS ----------------
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
    ),
    // ---------------- BUTTONS ----------------
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontSize: 16,
          fontFamily: "Montserrat",
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      ),
    ),

    // ---------------- INPUT FIELD ----------------
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(fontSize: 14, color: AppColors.subtext),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
    ),
  );
}
// ============================================================================
// 🔵 ROOT APP
// ============================================================================
class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "HR Toffy",
      theme: buildAppTheme(),
      home: isLoggedIn ? const GifSplashScreen() : const LoginScreen(),
    );
  }
}
// ============================================================================
// 🔵 FIREBASE NOTIFICATION SERVICE
// ============================================================================
class FirebaseNotificationService {
  static Future<void> setupFCM({required String userEmail}) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    print("🔑 FCM Token: $token");
    // Save token
    if (token != null) {
      await Supabase.instance.client
          .from("employee_records")
          .update({"fcm_token": token}).eq("email", userEmail);
    }
    // FOREGROUND LISTENER
    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      if (notification != null) {
        const androidDetails = AndroidNotificationDetails(
          'employee_alerts',
          'Employee Alerts',
          channelDescription: "Alerts for employee notifications",
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          icon: '@drawable/ic_stat_notify',
          largeIcon: DrawableResourceAndroidBitmap('toffy_big'),
        );
        const details = NotificationDetails(android: androidDetails);
        await flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          notification.title,
          notification.body,
          details,
        );
      }
    });
    // WHEN USER TAPS NOTIFICATION
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final ctx = navigatorKey.currentContext;
      final logged = Supabase.instance.client.auth.currentUser;
      String? empId;
      if (logged != null) {
        final res = await Supabase.instance.client
            .from("employee_records")
            .select("id")
            .eq("email", logged.email!)
            .maybeSingle();
        empId = res?['id'];
      }
      final target = message.data['employee_id'] ?? empId;
      if (ctx != null && target != null) {
      }
    });
  }
}
