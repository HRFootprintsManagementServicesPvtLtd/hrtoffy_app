// notifications.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


// MAIN
import '../main.dart';

// SCREENS
import 'dashboard_screen.dart';
import 'my_profile_screen.dart';
import 'attendance_screen.dart';
import 'leaves_screen.dart';
import 'overtime_screen.dart';
import 'payslip_screen.dart';
import 'benefits_screen.dart';
import 'loans_advances_screens.dart';
import 'travel_expenses_screen.dart';
import 'tax_deduction_screen.dart';
import 'announcements_screen.dart';
import 'events_calendar_screen.dart';
import 'surveys_screen.dart';
import 'faqs_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/drawer_route.dart';

// WIDGETS
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';

class NotificationsScreen extends StatefulWidget {
  final String employeeId; // e.g., UUID
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  const NotificationsScreen({
    Key? key,
    required this.employeeId,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}
class _NotificationsScreenState extends State<NotificationsScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  List<Map<String, dynamic>> notifications = [];
  bool loading = false;
  RealtimeChannel? channel;
  @override
  void initState() {
    super.initState();
    fetchNotifications();
    _subscribeToRealtime();
  }
  @override
  void dispose() {
    if (channel != null) {
      supabase.removeChannel(channel!);
      channel = null;
    }
    super.dispose();
  }

  /// Fetch notifications
  Future<void> fetchNotifications() async {
    try {
      setState(() => loading = true);

      final res = await supabase
          .from('notifications')
          .select()
          .eq('recipient_employee_id', widget.employeeId)
          .order('created_at', ascending: false);

      setState(() {
        notifications = res != null ? List<Map<String, dynamic>>.from(res) : [];
        loading = false;
      });

      print("Notifications fetched: ${notifications.length}");
    } catch (e) {
      print('❌ Error fetching notifications: $e');
      setState(() => loading = false);
    }
  }

  /// Realtime subscribe
  void _subscribeToRealtime() {
    channel = supabase.channel('notifications-updates');

    channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) async {
        final newRow = payload.newRecord as Map<String, dynamic>?;
        if (newRow == null) return;

        if (newRow['recipient_employee_id'] == widget.employeeId) {
          await _showLocalNotification(
            newRow['title'] ?? 'New Notification',
            newRow['body'] ?? '',
            payload: newRow['type'] ?? '',
          );
          fetchNotifications();
        }
      },
    );

    channel!.subscribe();
  }

  /// Local notification popup
  Future<void> _showLocalNotification(
      String title,
      String body,
      {String? payload}
      ) async {

    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Mark all as read
  Future<void> markAllAsRead() async {
    try {
      final ids = notifications.map((n) => n['id']).toList();
      await supabase
          .from('notifications')
          .update({'read': true})
          .inFilter('id', ids);
      fetchNotifications();
    } catch (e) {
      print("❌ Error marking read: $e");
    }
  }

  // -------------------------------------------------------------
  // 🔥🔥 KEYWORD-BASED ROUTING FUNCTION (AUTO NAVIGATION)
  // -------------------------------------------------------------
  void openScreenBasedOnKeyword(Map<String, dynamic> n) {

    final title = (n['title'] ?? '').toString().toLowerCase();
    final body = (n['body'] ?? '').toString().toLowerCase();
    bool contains(String k) => title.contains(k) || body.contains(k);

    final String email = supabase.auth.currentUser?.email ?? '';
    final String employeeId = widget.employeeId;

    // Dashboard fallback (pass required args)
    void goToDashboard() {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DashboardScreen(
          email: email,
          employeeId: employeeId,
        ),
      ));
    }

    if (contains("payroll") || contains("pay"
        "slip") || contains("salary")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayslipScreen(
            userEmail: email,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    if (contains("survey") || contains("feedback")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SurveysScreen(
            userEmail: widget.userEmail,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    if (contains("benefit") || contains("allowance")) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => BenefitsScreen(
          userEmail: widget.userEmail,
          userData: widget.userData,
          fetchHrmsContext: widget.fetchHrmsContext,
        ),
      ));
      return;
    }

    if (contains("loan") || contains("advance")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LoansAdvancesScreen(
            userEmail: email,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    if (contains("announcement") || contains("notice")) {
      // If your AnnouncementsScreen needs orgId/department from your user data,
      // replace this with your actual source (userData variable you have elsewhere).
      final orgId = widget.userData['organization_id'];
      final dept = supabase.auth.currentUser?.userMetadata?['department'];

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnouncementsScreen(
            organizationId: orgId.toString(),

            userDepartment: dept?.toString() ?? '',

            userEmail: supabase.auth.currentUser?.email ?? '',

            userData: {},

            fetchHrmsContext: fetchHrmsContext,
          ),
        ),
      );

      return;
    }

    if (contains("event") || contains("meeting")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventsCalendarScreen(
            email: widget.userEmail,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );

      return;
    }

    if (contains("tax") || contains("deduction") || contains("tds")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaxDeductionScreen(
            userEmail: email,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    if (contains("travel") || contains("expense")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TravelExpensesScreen(
            email: email,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    if (contains("attendance") || contains("shift") || contains("timing")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TimeAttendanceScreen(
            userEmail: widget.userEmail,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),

        ),
      );

      return;
    }


    if (contains("leave") || contains("holiday")) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => LeavesScreen(
          email: widget.userEmail,
          userData: widget.userData,
          fetchHrmsContext: widget.fetchHrmsContext,
        ),

      ));
      return;
    }

    if (contains("profile") || contains("kyc")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MyProfileScreen(
            email: email,
            userData: widget.userData,
            fetchHrmsContext: widget.fetchHrmsContext,
          ),
        ),
      );
      return;
    }

    // Default
    goToDashboard();
  }


  // -------------------------------------------------------------
  // UI
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      // ✅ END DRAWER (MORE)
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.notification,
        companyLogoUrl: widget.userData['company_logo_url'],
      ),

      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: markAllAsRead,
            ),
        ],
      ),

      // 🔥 BODY + TOFFY OVERLAY
      body: Stack(
        children: [
          loading
              ? notificationsSkeletonList()
              : notifications.isEmpty
              ? const Center(
            child: Text(
              'No notifications yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          )
              : RefreshIndicator(
            onRefresh: fetchNotifications,
            child: ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                final time = DateFormat(
                    'MMM dd, yyyy hh:mm a')
                    .format(
                    DateTime.parse(n['created_at']).toLocal());

                final bool isRead = n['read'] == true;

                return Container(
                  margin:
                  const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead
                        ? Colors.white
                        : const Color(0xFFE7F1FF),
                    borderRadius:
                    BorderRadius.circular(12),
                    border: Border.all(
                      color: isRead
                          ? Colors.grey.shade300
                          : Colors.blue.shade300,
                      width: isRead ? 1 : 1.5,
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      if (!isRead) {
                        await supabase
                            .from('notifications')
                            .update({'read': true})
                            .eq('id', n['id']);
                        await fetchNotifications();
                      }

                      openScreenBasedOnKeyword(n);
                    },
                    child: Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isRead
                              ? Icons.notifications_none_rounded
                              : Icons.notifications_active_rounded,
                          color: isRead
                              ? Colors.grey
                              : Colors.blueAccent,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                n['title'] ??
                                    '(No Title)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                n['body'] ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isRead
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  color: Colors
                                      .grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors
                                      .grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 🤖 TOFFY CHAT
        ],
      ),

      // ✅ BOTTOM NAVIGATION (STANDARD)
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,

        onTap: (index) async {
          if (index == 0) {
            setState(() => _bottomTabIndex = 0);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardScreen(
                  email: widget.userEmail,
                  employeeId: widget.employeeId,
                ),
              ),
            );
            return;
          }

          if (index == 1) {
            setState(() => _bottomTabIndex = 1);
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
            setState(() => _bottomTabIndex = 2);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TimeAttendanceScreen(
                  userEmail: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext: widget.fetchHrmsContext,
                ),
              ),
            );
            return;
          }

          if (index == 3) {
            setState(() => _bottomTabIndex = 3);
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

          // 🤖 TOFFY


        },

        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/dashboard.svg",
              width: 22,
              color: _bottomTabIndex == 0
                  ? Colors.blueAccent
                  : Colors.grey,
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/leaves.svg",
              width: 22,
              color: _bottomTabIndex == 1
                  ? Colors.blueAccent
                  : Colors.grey,
            ),
            label: 'Leave',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/attendance.svg",
              width: 22,
              color: _bottomTabIndex == 2
                  ? Colors.blueAccent
                  : Colors.grey,
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/payroll.svg",
              width: 22,
              color: _bottomTabIndex == 3
                  ? Colors.blueAccent
                  : Colors.grey,
            ),
            label: 'Payslip',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
              color: Colors.grey,
            ),
            label: 'More',
          ),
          BottomNavigationBarItem(
            icon: BottomNavToffyButton(),
            label: '',
          ),
        ],
      ),
    );

  }
}
