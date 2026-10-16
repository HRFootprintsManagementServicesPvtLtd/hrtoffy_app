import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'core/auth/auth_service.dart';
import 'core/payslip_files.dart';
import 'repositories/employee_repository.dart';
import 'repositories/engagement_repository.dart';
import 'repositories/leave_repository.dart';
import 'providers/role_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/notification.dart';
import 'screens/login_screen.dart';
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
@pragma('vm:entry-point')
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
      payload: message.data['payload'] ?? message.data['category'] ?? 'default',
    );
  }
}

// ============================================================================
// 🔵 MAIN
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(channel);

  // Local NOTIFICATION INIT
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@drawable/ic_stat_notify');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,

    onDidReceiveNotificationResponse: (response) async {
      print("🔔 Notification clicked");

      final payload = response.payload;

      if (payload == null) return;

      final user = AuthService.instance.currentUser;

      if (user == null) return;

      final employee = await EmployeeRepository().getMe();
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
              email: user.email,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      } else if (payload == "announcement") {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AnnouncementsScreen(
              organizationId: orgId,
              userDepartment: department,
              userEmail: user.email,
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
              email: user.email,
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
              userEmail: user.email,
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
              userEmail: user.email,
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
            builder: (_) => NotificationsScreen(
              employeeId: employeeId,
              userEmail: user.email,
              userData: employee,
              fetchHrmsContext: fetchHrmsContext,
            ),
          ),
        );
      }
    },
  );

  // Auto-login check
  // AWS backend session (token store + /auth/resolve-user).
  final bool isLoggedIn = await AuthService.instance.restoreSession();
  // Push listeners (the device token is not stored: no AWS endpoint yet, see FirebaseNotificationService.persistToken).
  final restored = AuthService.instance.currentUser;
  if (isLoggedIn && restored != null) {
    FirebaseNotificationService.startForUser(restored.email);
  }
  // Downloaded payslip PDFs from an earlier run are removed once they are stale (best effort, in the background, never throws).
  PayslipFiles.instance.deleteStale();
  // A rejected refresh token ends the session: send the user to login (and the downloaded payslip PDFs go with it).
  AuthService.instance.api.onSessionExpired.listen((_) {
    PayslipFiles.instance.deleteAll();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => RoleProvider(),
      child: MyApp(isLoggedIn: isLoggedIn),
    ),
  );
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

    final punchDate = DateTime(punchTime.year, punchTime.month, punchTime.day);

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
  final user = AuthService.instance.currentUser;

  if (user == null) {
    return {"error": "User not logged in"};
  }

  final employees = EmployeeRepository();
  final employee = await employees.getMe();

  // Leave balances come from the API (best effort: the assistant context is still built if they cannot
  // be read). Punch logs are added back when the attendance group moves to the API; until then the
  // assistant context carries an empty list for them.
  final List<Map<String, dynamic>> leaveBalances = [];
  try {
    for (final b in await LeaveRepository().balances()) {
      leaveBalances.add({'leave_type': b.name, 'balance': b.remaining});
    }
  } catch (_) {}
  final List<dynamic> attendanceLogs = [];

  Map<String, dynamic> sensitive = const {};
  try {
    sensitive = await employees.getSensitiveProfile();
  } catch (_) {}
  final salaryRow = {'salary': sensitive['salary']};

  final announcements = (await EngagementRepository().announcements())
      .map((a) => {'title': a['title'], 'date': a['created_at']})
      .toList();
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
    "payroll": {"salary": salaryRow['salary']},
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
      bodySmall: TextStyle(fontSize: 14, color: AppColors.subtext),
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
  static bool _initialized = false;

  /// The device token is NOT stored anywhere: there is no verified AWS endpoint for FCM token registration
  /// yet, so nothing is written and no request is made. Always returns false.
  static Future<bool> persistToken(String token, String email) async => false;

  /// Starts the push listeners for a signed-in user; a failure here must never block sign-in.
  static Future<void> startForUser(String email) async {
    try {
      await setupFCM(userEmail: email);
    } catch (err) {
      debugPrint('Push setup failed');
    }
  }

  static Future<void> setupFCM({required String userEmail}) async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    // Get token
    final token = await messaging.getToken();

    if (token != null) {
      try {
        await persistToken(token, userEmail);
      } catch (_) {
        debugPrint('FCM token save failed');
      }
    }

    // 1. FOREGROUND LISTENER
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
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
          payload:
              message.data['payload'] ?? message.data['category'] ?? 'default',
        );
      }
    });

    // 2. WHEN USER TAPS NOTIFICATION (Background State)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      _handleNotificationClick(message.data);
    });

    // 3. INITIAL MESSAGE (Terminated State)
    messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationClick(message.data);
      }
    });
  }

  static Future<void> _handleNotificationClick(
    Map<String, dynamic> data,
  ) async {
    final payload = data['payload'] ?? data['category'];
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    try {
      final employee = await EmployeeRepository().getMe();

      final employeeId = employee['id'];

      Widget destination;
      if (payload == "leave") {
        destination = LeavesScreen(
          email: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      } else if (payload == "announcement") {
        destination = AnnouncementsScreen(
          organizationId: employee['organization_id']?.toString() ?? '',
          userDepartment: employee['department']?.toString() ?? '',
          userEmail: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      } else if (payload == "event") {
        destination = EventsCalendarScreen(
          email: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      } else if (payload == "payroll") {
        destination = PayslipScreen(
          userEmail: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      } else if (payload == "survey") {
        destination = SurveysScreen(
          userEmail: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      } else {
        destination = NotificationsScreen(
          employeeId: employeeId,
          userEmail: user.email,
          userData: employee,
          fetchHrmsContext: fetchHrmsContext,
        );
      }
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (_) {
      debugPrint('Notification click handling failed');
    }
  }
}
