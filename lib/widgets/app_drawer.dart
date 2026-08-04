import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ================= SCREENS =================
import '../screens/dashboard_screen.dart';
import '../screens/my_profile_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/leaves_screen.dart';
import '../screens/overtime_screen.dart';
import '../screens/payslip_screen.dart';
import '../screens/benefits_screen.dart';
import '../screens/loans_advances_screens.dart';
import '../screens/travel_expenses_screen.dart';
import '../screens/tax_deduction_screen.dart';
import '../screens/announcements_screen.dart';
import '../screens/events_calendar_screen.dart';
import '../screens/surveys_screen.dart';
import '../screens/faqs_screen.dart';
import '../screens/login_screen.dart';
import 'drawer_route.dart';
import '../screens/goals_screen.dart';
import '../screens/messages_screen.dart';
import 'package:provider/provider.dart';
import '../providers/role_provider.dart';
import '../screens/manager/manager_dashboard_screen.dart';
import 'employee_ui.dart';

class AppDrawer extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final String? companyLogoUrl;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final DrawerRoute currentRoute; // 👈 ADD THIS

  const AppDrawer({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    required this.currentRoute, // 👈 ADD THIS
    this.companyLogoUrl,
  }) : super(key: key);

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  bool showOrgLogo = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => showOrgLogo = !showOrgLogo);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgId = widget.userData['organization_id'];
    final dept = widget.userData['department'];
    final roleProvider = Provider.of<RoleProvider>(context);

    final currentRole = roleProvider.activeRole;

    final hasManagerRole = widget.userData['emp_role'] == 'manager';

    return Drawer(
      width: 280,
      backgroundColor: Colors.white,
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
                  Text(
                    widget.userData['full_name']?.toString() ?? 'Employee',
                    style: EmployeeUi.title(16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.userData['designation']?.toString() ??
                        widget.userData['department']?.toString() ??
                        'Employee workspace',
                    style: EmployeeUi.body(size: 12, color: EmployeeUi.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _header("CORE & PROFILE"),
                _svg(
                  context,
                  "assets/icons/dashboard.svg",
                  "Dashboard",
                  DrawerRoute.dashboard,
                  () => _go(
                    context,
                    DashboardScreen(
                      email: widget.userEmail,
                      employeeId: widget.userData['id'].toString(),
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/profile.svg",
                  "My Profile",
                  DrawerRoute.profile,
                  () => _go(
                    context,
                    MyProfileScreen(
                      email: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _header("TIME & ATTENDANCE"),
                _svg(
                  context,
                  "assets/icons/attendance.svg",
                  "Time & Attendance",
                  DrawerRoute.attendance,
                  () => _go(
                    context,
                    TimeAttendanceScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/leaves.svg",
                  "Leaves",
                  DrawerRoute.leaves,
                  () => _go(
                    context,
                    LeavesScreen(
                      email: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/overtime.svg",
                  "Overtime",
                  DrawerRoute.overtime,
                  () => _go(
                    context,
                    OvertimeScreen(
                      email: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _header("COMPENSATION"),
                _svg(
                  context,
                  "assets/icons/payroll.svg",
                  "Payroll",
                  DrawerRoute.payroll,
                  () => _go(
                    context,
                    PayslipScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/benefits.svg",
                  "Benefits",
                  DrawerRoute.benefits,
                  () => _go(
                    context,
                    BenefitsScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),
                _svg(
                  context,
                  "assets/icons/loans.svg",
                  "Loans & Advances",
                  DrawerRoute.loans,
                  () => _go(
                    context,
                    LoansAdvancesScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),
                _svg(
                  context,
                  "assets/icons/travel.svg",
                  "Travel & Expenses",
                  DrawerRoute.travel,
                  () => _go(
                    context,
                    TravelExpensesScreen(
                      email: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),
                _svg(
                  context,
                  "assets/icons/tax.svg",
                  "Tax Deduction",
                  DrawerRoute.tax,
                  () => _go(
                    context,
                      const TaxDeductionScreen()
                  ),
                ),

                _header("PERFORMANCE"),
                _svg(
                  context,
                  "assets/icons/goals1.svg",
                  "Goals",
                  DrawerRoute.performance,
                  () => _go(
                    context,
                    GoalsScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _header("ENGAGE"),
                _svg(
                  context,
                  "assets/icons/messages.svg",
                  "Messages",
                  DrawerRoute.messages,
                  () => _go(
                    context,
                    MessagesScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),
                _icon(
                  context,
                  Icons.campaign_outlined,
                  "Announcements",
                  DrawerRoute.announcements,
                  () => _go(
                    context,
                    AnnouncementsScreen(
                      organizationId: widget.userData['organization_id'],
                      userDepartment: widget.userData['department'],
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/surveys.svg",
                  "Surveys & Polls",
                  DrawerRoute.surveys,
                  () => _go(
                    context,
                    SurveysScreen(
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                _svg(
                  context,
                  "assets/icons/faq.svg",
                  "FAQs",
                  DrawerRoute.faqs,
                  () => _go(
                    context,
                    FaqsScreen(
                      organizationId: orgId,
                      userEmail: widget.userEmail,
                      userData: widget.userData,
                      fetchHrmsContext: widget.fetchHrmsContext,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                if (hasManagerRole)
                  ListTile(
                    leading: Icon(
                      currentRole == 'employee'
                          ? Icons.admin_panel_settings
                          : Icons.person,
                      color: Colors.blueAccent,
                    ),

                    title: Text(
                      currentRole == 'employee'
                          ? "Switch to Manager"
                          : "Switch to Employee",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),

                    onTap: () {
                      Navigator.pop(context);

                      if (currentRole == 'employee') {
                        roleProvider.switchRole('manager');

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
                      } else {
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
                      }
                    },
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0xFFEEEEEE),
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(
                    "Sign Out",
                    style: EmployeeUi.body(
                      size: 14,
                      color: Colors.redAccent,
                      weight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
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

  // ================= HELPERS =================
  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Text(
      text,
      style: EmployeeUi.body(
        size: 11,
        color: EmployeeUi.muted,
        weight: FontWeight.w700,
      ),
    ),
  );

  Widget _svg(
    BuildContext context,
    String asset,
    String title,
    DrawerRoute route,
    VoidCallback onTap,
  ) {
    final bool isSelected = widget.currentRoute == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F7FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: SvgPicture.asset(
          asset,
          width: 22,
          color: isSelected ? EmployeeUi.primary : Colors.black54,
        ),
        title: Text(
          title,
          style: EmployeeUi.body(
            size: 14,
            color: isSelected ? EmployeeUi.primary : Colors.black87,
            weight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      ),
    );
  }

  Widget _icon(
    BuildContext context,
    IconData icon,
    String title,
    DrawerRoute route,
    VoidCallback onTap,
  ) {
    final bool isSelected = widget.currentRoute == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F7FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(
          icon,
          color: isSelected ? EmployeeUi.primary : Colors.black54,
        ),
        title: Text(
          title,
          style: EmployeeUi.body(
            size: 14,
            color: isSelected ? EmployeeUi.primary : Colors.black87,
            weight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      ),
    );
  }

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}
