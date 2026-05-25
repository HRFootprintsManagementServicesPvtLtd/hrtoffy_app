import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import '../widgets/drawer_route.dart';
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
          final dept = widget.userDepartment.trim().toLowerCase();

          if (ann['broadcast_type'] == 'segmented') {
            final List<dynamic> targetDepartments =
                ann['target_departments'] ?? [];

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load announcements: $e')));
    }
  }


  Color badgeColor(String? priority) {
    switch (priority) {
      case 'high':
        return Colors.red.shade700;
      case 'medium':
        return Colors.orange.shade700;
      case 'low':
      default:
        return Colors.grey.shade400;
    }
  }

  IconData broadcastIcon(String? broadcastType) {
    switch (broadcastType) {
      case 'company_wide':
        return Icons.apartment_rounded;
      case 'segmented':
        return Icons.group;
      case 'employee_engagement':
        return Icons.favorite;
      default:
        return Icons.campaign;
    }
  }

  Color broadcastIconColor(String? broadcastType) {
    switch (broadcastType) {
      case 'company_wide':
        return Colors.purple;
      case 'segmented':
        return Colors.blue;
      case 'employee_engagement':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.announcements,


        companyLogoUrl: companyLogoUrl,
      ),
      appBar: AppBar(title: const Text("Announcements & Broadcasts")),
      body: Stack(
        children: [
          buildRefreshable(
            skeleton: const SkeletonAnnouncements(),
            childBuilder: () {
              if (announcements.isEmpty && !isLoading) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.campaign_outlined,
                          size: 90, color: Colors.blueGrey),
                      SizedBox(height: 14),
                      Text(
                        "No announcements yet",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: announcements.length,
                itemBuilder: (context, index) =>
                    buildAnnouncementCard(announcements[index]),
              );
            },
          ),

          // 🔥 TOFFY CHAT OVERLAY

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

          // 🧡 TOFFY BUTTON


        },

        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/dashboard.svg",
              width: 22,
              height: 22,
              color: Colors.grey,
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/leaves.svg",
              width: 22,
              height: 22,
              color: Colors.grey,
            ),
            label: 'Leave',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/attendance.svg",
              width: 22,
              height: 22,
              color: Colors.grey,
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/payroll.svg",
              width: 22,
              height: 22,
              color: Colors.grey,
            ),
            label: 'Payslip',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
              height: 22,
              color: Colors.grey,
            ),
            label: 'More',
          ),


        ],
      ),


    );

  }
  Widget buildAnnouncementCard(Map<String, dynamic> ann) {
    final targetDepartments =
    ann['target_departments'] is List ? ann['target_departments'] : [];
    final createdAt = ann['created_at'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(ann['created_at']))
        : '';

    String priorityText(String? pri) {
      if (pri == null) return "";
      final p = pri.toLowerCase();
      if (p == "high") return "high priority";
      if (p == "medium") return "medium";
      if (p == "low") return "low";
      return p;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with badges and icon
            Row(
              children: [
                Expanded(
                  child: Text(
                    ann['title'] ?? "",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                if (ann['priority'] != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor(ann['priority']).withOpacity(0.16),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      priorityText(ann['priority']),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: badgeColor(ann['priority']),
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(width: 9),
                Icon(
                  broadcastIcon(ann['broadcast_type']?.toString()),
                  color:
                  broadcastIconColor(ann['broadcast_type']?.toString()),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Category badges and target departments
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (ann['broadcast_type'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ann['broadcast_type'],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),

                if (ann['announcement_category'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ann['announcement_category'],
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),

                if (ann['broadcast_type'] == 'segmented' &&
                    targetDepartments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Departments: ${targetDepartments.join(', ')}",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 11),

            // Content and Created At
            Text(
              ann['content'] ?? "",
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 11),
            Text(
              createdAt.isNotEmpty ? "Posted $createdAt" : "",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
