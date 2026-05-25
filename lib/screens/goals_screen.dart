import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import '../widgets/skeleton_layouts.dart';

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
  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  int _bottomTabIndex = 4;
  final List<Color> pastelColors = [
    const Color(0xFFCCC9C9),
    const Color(0xFFE8F7EE),
    const Color(0xFFEAF2FF),
    const Color(0xFFFFEEF2),
    const Color(0xFFF4EEFF),
    const Color(0xFFEFFFFA),
  ];

  bool loading = true;

  List<Map<String, dynamic>> allGoals = [];

  String selectedTab = 'all';

  @override
  void initState() {
    super.initState();
    loadGoals();
  }

  Future<void> loadGoals() async {
    try {
      setState(() {
        loading = true;
      });

      final employeeId = widget.userData['id'];
      final organizationId = widget.userData['organization_id'];

      final response = await supabase
          .from('employee_goals')
          .select()
          .eq('emp_id', employeeId)
          .eq('organization_id', organizationId)
          .order('created_at', ascending: false);

      allGoals = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Goals fetch error: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load goals: $e"),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get filteredGoals {
    if (selectedTab == 'all') {
      return allGoals;
    }

    return allGoals.where((goal) {
      final status =
      (goal['status'] ?? '').toString().toLowerCase();

      return status == selectedTab;
    }).toList();
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF219653);

      case 'submitted':
        return const Color(0xFF2F80ED);

      case 'needs revision':
        return const Color(0xFFF2994A);

      case 'draft':
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext!,
        currentRoute: DrawerRoute.performance,
        companyLogoUrl: null,
      ),
      backgroundColor: const Color(0xFFF7F9FC),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          "Goals",
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
              height: 22,
            ),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),

      body: loading
          ? const SkeletonGoals()
          : RefreshIndicator(
        onRefresh: loadGoals,
        child: Column(
          children: [
            const SizedBox(height: 14),

            // ================= FILTER TABS =================



            // ================= GOALS LIST =================
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
              ),
              child: Row(
                children: [
                  Text(
                    "All Goals",
                    style: GoogleFonts.montserrat(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Expanded(
              child: filteredGoals.isEmpty
                  ? Center(
                child: Text(
                  "No goals found",
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: filteredGoals.length,
                itemBuilder: (context, index) {
                  final goal =
                  filteredGoals[index];

                  final title =
                      goal['title'] ?? '-';

                  final description =
                      goal['description'] ?? '-';

                  final category =
                      goal['category'] ?? '-';

                  final status =
                      goal['status'] ?? 'draft';

                  final weightage =
                      goal['weightage']
                          ?.toString() ??
                          '0';

                  final progress =
                      goal['progress_percentage'] ??
                          0;

                  final milestones =
                      (goal['milestones']
                      as List?) ??
                          [];

                  return Container(
                    margin:
                    const EdgeInsets.only(
                        bottom: 18),

                    decoration: BoxDecoration(
                      color: pastelColors[
                      index % pastelColors.length
                      ],
                      borderRadius:
                      BorderRadius.circular(
                          24),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(0.04),
                          blurRadius: 10,
                          offset:
                          const Offset(0, 4),
                        ),
                      ],
                    ),

                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,

                      children: [
                        Padding(
                          padding:
                          const EdgeInsets
                              .all(18),

                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,

                            children: [
                              // TITLE

                              Text(
                                title,
                                style:
                                GoogleFonts
                                    .montserrat(
                                  fontSize: 24,
                                  fontWeight:
                                  FontWeight
                                      .w700,
                                  color: const Color(
                                      0xFF2D3436),
                                ),
                              ),

                              const SizedBox(
                                  height: 14),

                              // CHIPS

                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  buildChip(
                                    status
                                        .toString(),
                                    getStatusColor(
                                      status
                                          .toString(),
                                    ),
                                  ),

                                  buildChip(
                                    category
                                        .toString(),
                                    Colors
                                        .black54,
                                  ),

                                  buildChip(
                                    "Weightage: $weightage%",
                                    Colors
                                        .black45,
                                  ),
                                ],
                              ),

                              const SizedBox(
                                  height: 18),

                              // DESCRIPTION

                              Text(
                                description,
                                style:
                                GoogleFonts
                                    .montserrat(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: Colors
                                      .grey
                                      .shade700,
                                ),
                              ),

                              const SizedBox(
                                  height: 20),

                              // PROGRESS

                              Row(
                                children: [
                                  Expanded(
                                    child:
                                    LinearProgressIndicator(
                                      value:
                                      progress /
                                          100,

                                      minHeight:
                                      8,

                                      borderRadius:
                                      BorderRadius.circular(
                                          20),

                                      backgroundColor:
                                      Colors
                                          .grey
                                          .shade200,

                                      valueColor:
                                      AlwaysStoppedAnimation(
                                        getStatusColor(
                                          status
                                              .toString(),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(
                                      width:
                                      12),

                                  Text(
                                    "$progress%",
                                    style:
                                    GoogleFonts
                                        .montserrat(
                                      fontWeight:
                                      FontWeight
                                          .w700,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                  height: 24),

                              // MILESTONES

                              Text(
                                "Milestones:",
                                style:
                                GoogleFonts
                                    .montserrat(
                                  fontSize: 16,
                                  fontWeight:
                                  FontWeight
                                      .w700,
                                ),
                              ),

                              const SizedBox(
                                  height: 10),

                              if (milestones
                                  .isEmpty)
                                Text(
                                  "No milestones added",
                                  style:
                                  GoogleFonts
                                      .montserrat(
                                    color: Colors
                                        .grey
                                        .shade600,
                                  ),
                                ),

                              ...milestones.map(
                                    (milestone) =>
                                    Padding(
                                      padding:
                                      const EdgeInsets
                                          .only(
                                        bottom: 8,
                                      ),

                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,

                                        children: [
                                          const Padding(
                                            padding:
                                            EdgeInsets.only(
                                              top:
                                              7,
                                            ),
                                            child:
                                            Icon(
                                              Icons
                                                  .circle,
                                              size:
                                              6,
                                            ),
                                          ),

                                          const SizedBox(
                                              width:
                                              10),

                                          Expanded(
                                            child:
                                            Text(
                                              milestone
                                                  .toString(),

                                              style:
                                              GoogleFonts.montserrat(
                                                fontSize:
                                                14,

                                                height:
                                                1.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),

                        // FOOTER

                        Container(
                          width: double.infinity,

                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),

                          decoration:
                          BoxDecoration(
                            color: Colors
                                .grey.shade50,

                            borderRadius:
                            const BorderRadius
                                .only(
                              bottomLeft:
                              Radius.circular(
                                  24),

                              bottomRight:
                              Radius.circular(
                                  24),
                            ),
                          ),

                          child: Row(
                            mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,

                            children: [
                              Text(
                                "Created: ${formatDate(goal['created_at'])}",

                                style:
                                GoogleFonts
                                    .montserrat(
                                  fontSize: 12,

                                  color: Colors
                                      .grey
                                      .shade600,
                                ),
                              ),

                              Text(
                                "Updated: ${formatDate(goal['updated_at'])}",

                                style:
                                GoogleFonts
                                    .montserrat(
                                  fontSize: 12,

                                  color: Colors
                                      .grey
                                      .shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
                  employeeId: widget.userData['id'],
                ),
              ),
            );
          }

          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LeavesScreen(
                  email: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext:
                  widget.fetchHrmsContext!,
                ),
              ),
            );
          }

          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TimeAttendanceScreen(
                  userEmail: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext:
                  widget.fetchHrmsContext!
                ),
              ),
            );
          }

          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayslipScreen(
                  userEmail: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext:
                  widget.fetchHrmsContext!
                ),
              ),
            );
          }

          if (index == 4) {
            _scaffoldKey.currentState
                ?.openEndDrawer();
          }
        },

        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/dashboard.svg",
              width: 22,
            ),
            label: 'Dashboard',
          ),

          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/leaves.svg",
              width: 22,
            ),
            label: 'Leave',
          ),

          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/attendance.svg",
              width: 22,
            ),
            label: 'Attendance',
          ),

          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/payroll.svg",
              width: 22,
            ),
            label: 'Payslip',
          ),

          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
            ),
            label: 'More',
          ),
        ],
      ),
    );

  }

  // ================= TAB =================

  Widget buildTab(String value, String label) {
    final selected = selectedTab == value;

    return Padding(
      padding: const EdgeInsets.only(right: 10),

      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = value;
          });
        },

        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),

          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.transparent,

            borderRadius:
            BorderRadius.circular(12),

            border: Border.all(
              color: selected
                  ? Colors.grey.shade300
                  : Colors.transparent,
            ),
          ),

          child: Text(
            label,

            style: GoogleFonts.montserrat(
              fontWeight: selected
                  ? FontWeight.w700
                  : FontWeight.w500,

              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  // ================= CHIP =================

  Widget buildChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),

      decoration: BoxDecoration(
        color: color.withOpacity(0.08),

        borderRadius:
        BorderRadius.circular(30),

        border: Border.all(
          color: color.withOpacity(0.25),
        ),
      ),

      child: Text(
        text,

        style: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ================= DATE FORMAT =================

  String formatDate(dynamic value) {
    if (value == null) return '-';

    try {
      final date =
      DateTime.parse(value.toString()).toLocal();

      return "${date.day}/${date.month}/${date.year}";
    } catch (_) {
      return '-';
    }
  }
}
