import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/employee_ui.dart';

class GoalsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function()? fetchHrmsContext;

  const GoalsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    this.fetchHrmsContext,
  });

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool loading = true;
  List<Map<String, dynamic>> allGoals = [];
  String? employeeId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => loading = true);
      
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Resolve employee strictly via user_id
      final emp = await supabase
          .from('employee_records')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (emp == null) return;
      employeeId = emp['id'].toString();

      await _fetchGoals();
    } catch (e) {
      debugPrint("Initialization error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchGoals() async {
    if (employeeId == null) return;
    try {
      final response = await supabase
          .from('employee_goals')
          .select('title, description, category, weightage, status, progress_percentage, target_date, achievement_status, manager_rating, reviewer_rating, final_rating, manager_comments, reviewer_comments, created_at, submitted_at, manager_approved_at, manager_approved_by, reviewer_approved_at, reviewer_approved_by, timeline, framework_type')
          .eq('emp_id', employeeId!)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          allGoals = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext!,
        currentRoute: DrawerRoute.performance,
        companyLogoUrl: null,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchGoals,
        color: EmployeeUi.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 12),
                  child: _circleIconBtn(
                    icon: "assets/icons/notification.svg",
                    onTap: () {
                      final id = widget.userData['id'] ?? widget.userData['employee_id'];
                      if (id != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsScreen(
                              employeeId: id.toString(),
                              userEmail: widget.userEmail,
                              userData: widget.userData,
                              fetchHrmsContext: widget.fetchHrmsContext!,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 12),
                  child: _circleIconBtn(
                    icon: "assets/icons/menu.svg",
                    onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
                const SizedBox(width: 1),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFD4F3F7), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text("My Goals", style: EmployeeUi.header(24)),
                      const SizedBox(height: 4),
                      Text(
                        "Track your performance and targets",
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: EmployeeUi.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: loading
                  ? const SkeletonGoals()
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: allGoals.isEmpty
                          ? Container(
                              height: 300,
                              alignment: Alignment.center,
                              child: Text(
                                "No goals found",
                                style: GoogleFonts.montserrat(color: Colors.grey),
                              ),
                            )
                          : Column(
                              children: allGoals.map((g) => _buildGoalCard(g)).toList(),
                            ),
                    ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: 4,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id'] ?? '')));
            return;
          }
          if (index == 1) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!)));
            return;
          }
          if (index == 2) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!)));
            return;
          }
          if (index == 3) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext!)));
            return;
          }
          if (index == 4) {
            _scaffoldKey.currentState?.openEndDrawer();
            return;
          }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.blueAccent, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildGoalCard(Map<String, dynamic> g) {
    final progress = (g['progress_percentage'] ?? 0).toDouble();
    final status = (g['status'] ?? '').toString().toUpperCase();
    final category = g['category']?.toString();
    final weightage = g['weightage'];
    
    // Stable pastel color logic matching Travel/Loans/etc.
    Color cardBg = const Color(0xFFD7E8FF); // Default blue
    if (category != null) {
      if (category.toLowerCase().contains('individual')) cardBg = const Color(0xFFD4F3F7);
      if (category.toLowerCase().contains('kpi') || category.toLowerCase().contains('okr')) cardBg = const Color(0xFFEBDFF6);
      if (category.toLowerCase().contains('learning')) cardBg = const Color(0xFFFFECE6);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(color: cardBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(6)),
                  child: Text(status, style: GoogleFonts.montserrat(fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              if (category != null)
                Text(category, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 12),
          Text(g['title'] ?? '-', style: EmployeeUi.title(16)),
          if (g['description'] != null) ...[
            const SizedBox(height: 6),
            Text(g['description'], style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, height: 1.4)),
          ],
          const Divider(height: 24, color: Colors.black12),
          _cardRow("Framework", g['framework_type']),
          _cardRow("Timeline", g['timeline']),
          _cardRow("Weightage", weightage != null ? "$weightage%" : null),
          _cardRow("Target Date", _fmt(g['target_date'])),
          _cardRow("Achievement", g['achievement_status']),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Progress", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold)),
              Text("${progress.toInt()}%", style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              backgroundColor: Colors.white38,
              valueColor: const AlwaysStoppedAnimation(EmployeeUi.primary),
            ),
          ),
          if (g['manager_rating'] != null || g['reviewer_rating'] != null || g['final_rating'] != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (g['manager_rating'] != null) _ratingBadge("Manager", g['manager_rating']),
                if (g['reviewer_rating'] != null) _ratingBadge("Reviewer", g['reviewer_rating']),
                if (g['final_rating'] != null) _ratingBadge("Final", g['final_rating']),
              ],
            ),
          ],
          if (g['manager_comments'] != null) _commentBox("Manager Remarks", g['manager_comments']),
          if (g['reviewer_comments'] != null) _commentBox("Reviewer Remarks", g['reviewer_comments']),
          
          // History / Dates
          const SizedBox(height: 16),
          _dateLine("Submitted", g['submitted_at']),
          _dateLine("Mgr Approved", g['manager_approved_at']),
          _dateLine("Rev Approved", g['reviewer_approved_at']),
        ],
      ),
    );
  }

  Widget _cardRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500)),
          Text(value.toString(), style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _ratingBadge(String label, dynamic rating) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
          Text(rating.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _commentBox(String title, String? comment) {
    if (comment == null || comment.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black38)),
          const SizedBox(height: 2),
          Text(comment, style: const TextStyle(fontSize: 11, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _dateLine(String label, dynamic date) {
    if (date == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text("$label: ${_fmt(date)}", style: const TextStyle(fontSize: 9, color: Colors.black38, fontStyle: FontStyle.italic)),
    );
  }

  String _fmt(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return DateFormat('MMM dd, yyyy').format(dt);
    } catch (_) {
      return d.toString();
    }
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: IconButton(
        icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)),
        onPressed: onTap,
      ),
    );
  }
}
