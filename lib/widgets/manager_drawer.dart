import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/role_provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/manager/manager_dashboard_screen.dart';
import '../screens/manager/pending_approvals_screen.dart';
import 'drawer_route.dart';

import '../screens/manager/team_attendance_screen.dart';

class ManagerDrawer extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final DrawerRoute currentRoute;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerDrawer({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.currentRoute,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerDrawer> createState() => _ManagerDrawerState();
}

class _ManagerDrawerState extends State<ManagerDrawer> {
  int totalApprovals = 0;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchTotalApprovals();
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

      final results = await Future.wait([
        supabase.from('leave_applications').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        supabase.from('attendance_regularization_requests').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        supabase.from('benefit_claims').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        supabase.from('loans_advances').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        supabase.from('travel_claims').select('id').inFilter('employee_id', teamIds).eq('status', 'pending'),
        supabase.from('support_requests').select('id').inFilter('employee_id', teamIds).eq('status', 'open'),
      ]);

      int count = 0;
      for (var res in results) {
        count += (res as List).length;
      }

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
          // Top Spacer for Status Bar
          const SizedBox(height: 50),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _drawerItem(
                  icon: Icons.auto_awesome_outlined,
                  label: "Ask Toffy",
                  route: DrawerRoute.askToffy,
                  onTap: () {
                    // Navigate to Ask Toffy
                  },
                ),
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
                    // Navigate to Benefits
                  },
                ),
                _drawerItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: "Loan & Advances",
                  route: DrawerRoute.loans,
                  onTap: () {
                    // Navigate to Loans
                  },
                ),
                _drawerItem(
                  icon: Icons.receipt_long_outlined,
                  label: "Expenses",
                  route: DrawerRoute.expenses,
                  onTap: () {
                    // Navigate to Expenses
                  },
                ),
                _drawerItem(
                  icon: Icons.flight_takeoff_rounded,
                  label: "Travel",
                  route: DrawerRoute.travel,
                  onTap: () {
                    // Navigate to Travel
                  },
                ),
                _drawerItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: "Engage",
                  route: DrawerRoute.engage,
                  onTap: () {
                    // Navigate to Engage
                  },
                ),
                _drawerItem(
                  icon: Icons.verified_user_outlined,
                  label: "Compliance",
                  route: DrawerRoute.compliance,
                  onTap: () {
                    // Navigate to Compliance
                  },
                ),
                _drawerItem(
                  icon: Icons.business_center_outlined,
                  label: "Extended Modules",
                  route: DrawerRoute.extendedModules,
                  hasDropdown: true,
                  onTap: () {
                    // Handle Dropdown
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
                ),

                _drawerItem(
                  icon: Icons.settings_outlined,
                  label: "Settings",
                  route: DrawerRoute.settings,
                  onTap: () {
                    // Navigate to Settings
                  },
                ),
                _drawerItem(
                  icon: Icons.help_outline_rounded,
                  label: "How-To Guide",
                  route: DrawerRoute.howToGuide,
                  onTap: () {
                    // Navigate to How-To Guide
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
