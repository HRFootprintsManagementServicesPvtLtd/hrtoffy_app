import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/role_provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/manager/manager_dashboard_screen.dart';
import '../screens/manager/pending_approvals_screen.dart';
import '../screens/manager/manager_benefits_screen.dart';
import '../screens/manager/manager_loans_screen.dart';
import '../screens/manager/manager_expenses_screen.dart';
import '../screens/manager/manager_travel_screen.dart';
import '../screens/manager/manager_engage_screen.dart';
import '../screens/manager/manager_compliance_screen.dart';
import 'drawer_route.dart';

import '../screens/manager/team_attendance_screen.dart';

import 'employee_ui.dart';
import 'dart:math' as math;

class ManagerDrawer extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final DrawerRoute currentRoute;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final String? companyLogoUrl;
  final String? organizationName;

  const ManagerDrawer({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.currentRoute,
    required this.fetchHrmsContext,
    this.companyLogoUrl,
    this.organizationName,
  });

  @override
  State<ManagerDrawer> createState() => _ManagerDrawerState();
}

class _ManagerDrawerState extends State<ManagerDrawer> {
  int totalApprovals = 0;
  final supabase = Supabase.instance.client;
  bool showOrgLogo = false;

  @override
  void initState() {
    super.initState();
    _fetchTotalApprovals();
    // Show Org Logo immediately if available
    showOrgLogo = true;
  }

  Future<void> _fetchTotalApprovals() async {
    try {
      final managerId = widget.userData['id'];
      if (managerId == null) return;

      List<String> teamIds = [];
      try {
        final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': managerId});
        if (hierarchy is List) {
          teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
        }
      } catch (_) {
        teamIds = [managerId.toString()];
      }

      debugPrint("ManagerDrawer: Fetching total approvals for ${teamIds.length} team members...");
      
      int count = 0;
      
      // Execute sequentially to avoid overloading and hitting aggregate timeout
      final tables = [
        {'name': 'leave_applications', 'statusCol': 'status', 'statusVal': 'pending'},
        {'name': 'attendance_regularization_requests', 'statusCol': 'status', 'statusVal': 'pending'},
        {'name': 'benefit_claims', 'statusCol': 'status', 'statusVal': 'pending'},
        {'name': 'loans_advances', 'statusCol': 'status', 'statusVal': 'pending'},
        {'name': 'travel_claims', 'statusCol': 'status', 'statusVal': 'pending'},
        {'name': 'support_requests', 'statusCol': 'status', 'statusVal': 'open'},
      ];

      for (var table in tables) {
        try {
          final res = await supabase
              .from(table['name']!)
              .select('id')
              .inFilter('employee_id', teamIds)
              .eq(table['statusCol']!, table['statusVal']!)
              .limit(50); // Cap per table for the badge count speed
          
          if (res is List) {
            count += res.length;
          }
        } catch (e) {
          debugPrint("Error counting ${table['name']}: $e");
        }
      }
      
      debugPrint("ManagerDrawer: Total approvals counted: $count");

      if (mounted) {
        setState(() => totalApprovals = count);
      }
    } catch (e) {
      debugPrint("Error fetching drawer approval count: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<RoleProvider>(context);

    return Drawer(
      backgroundColor: Colors.white,
      width: 280,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // ================= HEADER =================
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    transitionBuilder: (child, animation) {
                      final rotate = Tween(
                        begin: math.pi / 2,
                        end: 0.0,
                      ).animate(animation);

                      return AnimatedBuilder(
                        animation: rotate,
                        child: child,
                        builder: (_, child) {
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.002)
                              ..rotateX(rotate.value),
                            child: child,
                          );
                        },
                      );
                    },
                    child: showOrgLogo && widget.companyLogoUrl != null
                        ? Image.network(
                            widget.companyLogoUrl!,
                            key: const ValueKey("org"),
                            height: 40,
                          )
                        : Image.asset(
                            "assets/HR TOFFY.png",
                            key: const ValueKey("hr"),
                            height: 40,
                          ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (widget.userData['avatar_url'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundImage: NetworkImage(widget.userData['avatar_url']),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              (widget.userData['full_name']?.toString() ?? 'M')[0].toUpperCase(),
                              style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userData['full_name']?.toString() ?? 'Manager',
                              style: EmployeeUi.title(15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.userData['designation']?.toString() ??
                                  widget.userData['department']?.toString() ??
                                  'Manager workspace',
                              style: EmployeeUi.body(size: 11, color: EmployeeUi.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.organizationName != null || widget.userData['organization_name'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  widget.organizationName ?? widget.userData['organization_name'] ?? '',
                                  style: EmployeeUi.body(size: 10, color: Colors.blue.shade700, weight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _drawerItem(
                  icon: Icons.grid_view_rounded,
                  label: "Dashboard",
                  route: DrawerRoute.dashboard,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerDashboardScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.check_circle_outline_rounded,
                  label: "Approvals",
                  route: DrawerRoute.approvals,
                  badgeCount: totalApprovals > 0 ? totalApprovals : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PendingApprovalsScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                        ),
                      ),
                    );
                  },
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
                ),

                _drawerItem(
                  icon: Icons.access_time_rounded,
                  label: "Time",
                  route: DrawerRoute.attendance,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeamAttendanceScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.card_giftcard_rounded,
                  label: "Benefits",
                  route: DrawerRoute.benefits,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerBenefitsScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: "Loan & Advances",
                  route: DrawerRoute.loans,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerLoansScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.receipt_long_outlined,
                  label: "Expenses",
                  route: DrawerRoute.expenses,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerExpensesScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.flight_takeoff_rounded,
                  label: "Travel",
                  route: DrawerRoute.travel,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerTravelScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: "Engage",
                  route: DrawerRoute.engage,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagerEngageScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Role Switcher and Logout at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, color: Color(0xFF1E90FF)),
                  title: Text(
                    "Switch to Employee",
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E90FF),
                    ),
                  ),
                  onTap: () {
                    roleProvider.switchRole('employee');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DashboardScreen(
                          email: widget.userEmail,
                          employeeId: widget.userData['id'].toString(),
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(
                    "Sign Out",
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                  onTap: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required DrawerRoute? route,
    required VoidCallback onTap,
    int? badgeCount,
    bool hasDropdown = false,
  }) {
    final isSelected = widget.currentRoute == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F7FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: onTap,
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF1E90FF) : Colors.black54,
          size: 22,
        ),
        title: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF1E90FF) : Colors.black87,
          ),
        ),
        trailing: badgeCount != null
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFF44336),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : hasDropdown
                ? const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.black54)
                : null,
      ),
    );
  }
}
