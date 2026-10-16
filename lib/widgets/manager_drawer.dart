import 'package:flutter/material.dart';
import '../core/avatar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/role_provider.dart';
import '../core/manager_access.dart';
import '../screens/dashboard_screen.dart';
import '../core/auth/sign_out.dart';
import '../screens/manager/manager_dashboard_screen.dart';
import '../screens/manager/pending_approvals_screen.dart';
import '../screens/manager/manager_benefits_screen.dart';
import '../screens/manager/manager_loans_screen.dart';
import '../screens/manager/manager_expenses_screen.dart';
import '../screens/manager/manager_travel_screen.dart';
import '../screens/manager/manager_engage_screen.dart';
import '../screens/manager/manager_compliance_screen.dart';
import '../screens/manager/manager_disciplinary_screen.dart';
import '../screens/manager/manager_requisitions_screen.dart';
import 'drawer_route.dart';

import '../screens/manager/time_hub_screen.dart';

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
  bool showOrgLogo = false;

  @override
  void initState() {
    super.initState();
    // Show Org Logo immediately if available
    showOrgLogo = true;
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
                      if (cleanAvatarUrl(widget.userData['avatar_url']) != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundImage: NetworkImage(cleanAvatarUrl(widget.userData['avatar_url'])!),
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
                        builder: (_) => managerScreenFor(ManagerFeature.dashboard, () => ManagerDashboardScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.check_circle_outline_rounded,
                  label: "Approvals",
                  route: DrawerRoute.approvals,
                  badgeUnavailable: true, // no verified approvals-count source yet: neutral "unknown", never a misleading 0
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => managerScreenFor(ManagerFeature.approvals, () => PendingApprovalsScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.teamAttendance, () => TimeHubScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.benefits, () => ManagerBenefitsScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.loans, () => ManagerLoansScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.expenses, () => ManagerExpensesScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.travel, () => ManagerTravelScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                        builder: (_) => managerScreenFor(ManagerFeature.engage, () => ManagerEngageScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.gavel_rounded,
                  label: "Disciplinary Cases",
                  route: DrawerRoute.disciplinary,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => managerScreenFor(ManagerFeature.disciplinary, () => ManagerDisciplinaryScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
                      ),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.work_outline_rounded,
                  label: "Requisitions",
                  route: DrawerRoute.requisitions,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => managerScreenFor(ManagerFeature.requisitions, () => ManagerRequisitionsScreen(
                          userEmail: widget.userEmail,
                          userData: widget.userData,
                          fetchHrmsContext: widget.fetchHrmsContext,
                        )),
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
                  onTap: () => signOutAndShowLogin(context),
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
    bool badgeUnavailable = false,
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
        trailing: badgeUnavailable
            ? Tooltip(
                message: "Approval count isn't available yet",
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  child: const Text("-", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              )
            : badgeCount != null
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
