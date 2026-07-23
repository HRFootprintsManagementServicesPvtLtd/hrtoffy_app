import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class FaqsScreen extends StatefulWidget {
  final String organizationId;
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const FaqsScreen({
    Key? key,
    required this.organizationId,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<FaqsScreen> createState() => _FaqsScreenState();
}

class _FaqsScreenState extends State<FaqsScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  List<Map<String, dynamic>> faqs = [];
  bool loading = true;
  String selectedCategory = 'All Categories';
  String search = '';

  final List<String> allCategories = ['All Categories', 'General', 'Leave', 'Attendance', 'Payroll', 'Policies', 'Benefits', 'Performance', 'Training'];

  @override
  void initState() {
    super.initState();
    fetchFaqs();
  }

  Future<void> fetchFaqs() async {
    setState(() => loading = true);
    final results = await supabase.from('faqs').select().eq('organization_id', widget.organizationId)
        .eq('is_active', true).order('category').order('created_at', ascending: false);

    setState(() {
      faqs = (results as List<dynamic>).map((faq) => Map<String, dynamic>.from(faq)).toList();
      loading = false;
    });
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = faqs.where((faq) {
      final q = search.trim().toLowerCase();
      final question = (faq['question'] ?? '').toString().toLowerCase();
      final answer = (faq['answer'] ?? '').toString().toLowerCase();
      final category = (faq['category'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty) return question.contains(q) || answer.contains(q) || category.contains(q);
      return selectedCategory == 'All Categories' || category == selectedCategory.toLowerCase();
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.faqs,
        companyLogoUrl: null,
      ),
      body: CustomScrollView(
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
                    final empId = (widget.userData['id'] ?? widget.userData['employee_id'])?.toString() ?? '';
                    if (empId.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer()),
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
                    Text("Support & FAQ", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Find answers to your common questions", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: EmployeeUi.cardDecoration(),
                    child: TextField(
                      decoration: const InputDecoration(icon: Icon(Icons.search, color: Colors.grey), hintText: "Search help articles...", border: InputBorder.none),
                      onChanged: (v) => setState(() => search = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: allCategories.map((cat) {
                        final isSelected = selectedCategory == cat;
                        return GestureDetector(
                          onTap: () => setState(() => selectedCategory = cat),
                          child: Container(
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(color: isSelected ? EmployeeUi.primary : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? EmployeeUi.primary : EmployeeUi.border)),
                            child: Text(cat, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black54)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (loading) const SkeletonAnnouncements()
                  else if (filtered.isEmpty) Container(height: 200, alignment: Alignment.center, child: Text("No FAQ entries found.", style: GoogleFonts.montserrat(color: Colors.grey)))
                  else Column(
                    children: filtered.map((f) => _buildFaqCard(f)).toList(),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: ''))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildFaqCard(Map<String, dynamic> f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: EmployeeUi.cardDecoration(),
      child: ExpansionTile(
        title: Text(f['question'] ?? '', style: EmployeeUi.title(14)),
        children: [Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Text(f['answer'] ?? '', style: GoogleFonts.montserrat(fontSize: 13, height: 1.5, color: Colors.black87)))],
        shape: const RoundedRectangleBorder(side: BorderSide.none),
      ),
    );
  }
}
