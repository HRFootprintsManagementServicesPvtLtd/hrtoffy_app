// lib/screens/leaves_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/refreshable_screen.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/drawer_route.dart';
import '../widgets/app_drawer.dart';
import '../widgets/employee_ui.dart';
import '../services/leave_summary_service.dart';
import '../widgets/bottom_nav_toffy_button.dart';
import 'dashboard_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';

class LeavesScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const LeavesScreen({
    Key? key,
    required this.email,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen>
    with TickerProviderStateMixin, RefreshableScreen<LeavesScreen> {
  late TabController _leaveMgmtSubTabController;
  final SupabaseClient supabase = Supabase.instance.client;
  // 🔑 STEP 2 — ADD THESE
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 1; // Leave tab index
  // 🔑 STEP 2 — END
  int _reloadTrigger = 0;

  @override
  void initState() {
    super.initState();
    _leaveMgmtSubTabController = TabController(length: 2, vsync: this);

    // Rebuild-only listener so IndexedStack follows the tab index.
    _leaveMgmtSubTabController.addListener(() {
      if (!mounted) return;
      if (_leaveMgmtSubTabController.indexIsChanging) return;
      setState(() {});
    });

    // 🔑 Kick the RefreshableScreen mixin once so buildRefreshable()
    // flips from skeleton to the real IndexedStack. Without this the
    // page stays on the skeleton forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startLoad();
    });
  }



  void _handleTabIndexChanged() {
    // Fires twice per swipe (indexIsChanging=true, then =false).
    // We only need the settled event to flip IndexedStack.
    if (_leaveMgmtSubTabController.indexIsChanging) return;
    if (!mounted) return;
    setState(() {}); // pure rebuild; no fetch, no reloadTrigger bump
  }

  @override
  void dispose() {
    _leaveMgmtSubTabController.removeListener(_handleTabIndexChanged);
    _leaveMgmtSubTabController.dispose();
    super.dispose();
  }

  @override
  Future<void> loadData() async {
    await Future.delayed(const Duration(milliseconds: 250));
  }

  Widget _buildCorrectSkeleton() {
    if (_leaveMgmtSubTabController.index == 0) {
      return const SkeletonLeaveSummaryPage();
    } else {
      return const SkeletonLeaveCalendar();
    }
  }

  Widget _buildLeaveMgmtTab() {
    return Column(
      children: [
        // Sub-tab selector (Summary / Calendar)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _leaveMgmtSubTabController.animateTo(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _leaveMgmtSubTabController.index == 0
                          ? EmployeeUi.primary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: EmployeeUi.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Summary',
                      style: TextStyle(
                        color: _leaveMgmtSubTabController.index == 0
                            ? Colors.white
                            : Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _leaveMgmtSubTabController.animateTo(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _leaveMgmtSubTabController.index == 1
                          ? EmployeeUi.primary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: EmployeeUi.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Calendar',
                      style: TextStyle(
                        color: _leaveMgmtSubTabController.index == 1
                            ? Colors.white
                            : Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: buildRefreshable(
            skeleton: _buildCorrectSkeleton(),
            childBuilder: () {
              return IndexedStack(
                index: _leaveMgmtSubTabController.index,
                children: [
                  LeaveSummaryCards(
                    email: widget.email,
                    reloadTrigger: _reloadTrigger,
                  ),
                  LeaveCalendarTab(
                    email: widget.email,
                    reloadTrigger: _reloadTrigger,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.leaves,
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
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: IconButton(
                    icon: SvgPicture.asset("assets/icons/menu.svg", width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
              ),
              const SizedBox(width: 1),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFECE6), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Leave Management", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Plan and track your time off", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _leaveMgmtSubTabController.animateTo(0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _leaveMgmtSubTabController.index == 0 ? EmployeeUi.primary : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: EmployeeUi.border),
                            ),
                            alignment: Alignment.center,
                            child: Text('Summary', style: GoogleFonts.montserrat(color: _leaveMgmtSubTabController.index == 0 ? Colors.white : Colors.black54, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _leaveMgmtSubTabController.animateTo(1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _leaveMgmtSubTabController.index == 1 ? EmployeeUi.primary : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: EmployeeUi.border),
                            ),
                            alignment: Alignment.center,
                            child: Text('Calendar', style: GoogleFonts.montserrat(color: _leaveMgmtSubTabController.index == 1 ? Colors.white : Colors.black54, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            child: buildRefreshable(
              skeleton: _buildCorrectSkeleton(),
              childBuilder: () {
                return IndexedStack(
                  index: _leaveMgmtSubTabController.index,
                  children: [
                    LeaveSummaryCards(email: widget.email, reloadTrigger: _reloadTrigger),
                    LeaveCalendarTab(email: widget.email, reloadTrigger: _reloadTrigger),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Apply for Leave')), body: LeaveApplicationForm(email: widget.email, onSubmitted: () => setState(() => _reloadTrigger++)))));
        },
        backgroundColor: EmployeeUi.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }
  // =======================================================
  // STEP 4 — BOTTOM NAVIGATION
  // =======================================================

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
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
                email: widget.email,
                employeeId: '', // keep consistent with your app
              ),
            ),
          );
          return;
        }

        if (index == 1) {
          setState(() => _bottomTabIndex = 1);
          return; // already on Leaves
        }

        if (index == 2) {
          setState(() => _bottomTabIndex = 2);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimeAttendanceScreen(
                userEmail: widget.email,
                userData: widget.userData, // ✅ FIX
                fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
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
                userEmail: widget.email,
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
            color: _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/leaves.svg",
            width: 22,
            color: _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Leave',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/attendance.svg",
            width: 22,
            color: _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Attendance',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/payroll.svg",
            width: 22,
            color: _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
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
      ],
    );
  }
}

/// ---------------------------
/// Leave Summary Cards
/// Redesigned modern card UI
/// ---------------------------
/// ---------------------------
/// Leave Summary Cards (OLD UI RESTORED WITH 5 CARDS)
/// ---------------------------
class LeaveSummaryCards extends StatefulWidget {
  final String email;
  final int reloadTrigger;

  const LeaveSummaryCards({
    Key? key,
    required this.email,
    required this.reloadTrigger,
  }) : super(key: key);

  @override
  State<LeaveSummaryCards> createState() => _LeaveSummaryCardsState();
}

class _LeaveSummaryCardsState extends State<LeaveSummaryCards> {
  final supabase = Supabase.instance.client;
  late Future<_SummaryData> _futureSummary;

  // Re-entrancy guard: prevents overlapping RPC calls when the widget
  // rebuilds rapidly (tab switches, pull-to-refresh, reloadTrigger).
  bool _inflight = false;

  @override
  void initState() {
    super.initState();
    _futureSummary = _fetchSummary();
  }

  @override
  void didUpdateWidget(covariant LeaveSummaryCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refetch when reloadTrigger actually advances.
    if (widget.reloadTrigger != oldWidget.reloadTrigger &&
        widget.reloadTrigger > oldWidget.reloadTrigger) {
      setState(() {
        _futureSummary = _fetchSummary();
      });
    }
  }

  Future<_SummaryData> _fetchSummary() async {
    if (_inflight) {
      // Return the currently pending future instead of firing a duplicate RPC.
      return _futureSummary;
    }
    _inflight = true;
    try {
      final s = await LeaveSummaryService.instance.fetch();
      return _SummaryData(
        totalAllocated: s.totalAllocated,
        totalUsed: s.totalUsed,
        totalRemaining: s.totalRemaining,
        leavePolicyCount: s.leavePolicyCount,
        pendingRequests: s.pendingRequests,
        policyBalances: s.policies
            .map((p) => _PolicyBalance(
          policyName: p.name,
          allocated: p.allocated,
          used: p.used,
          remaining: p.remaining,
        ))
            .toList(),
      );
    } catch (e, stack) {
      debugPrint("SUMMARY ERROR: $e");
      debugPrint(stack.toString());
      rethrow;
    } finally {
      _inflight = false;
    }
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SummaryData>(
      future: _futureSummary,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SkeletonLeaveSummaryPage();
        final data = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async {
            final future = _fetchSummary();
            setState(() {
              _futureSummary = future;
            });
            await _futureSummary;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _summaryCard(
                icon: Icons.calendar_month,
                color: Colors.blue,
                title: "Leaves Allocated",
                subtitle: "Days allocated for this year",
                value: data.totalAllocated.toString(),
              ),

              const SizedBox(height: 12),

              _summaryCard(
                icon: Icons.check_circle,
                color: Colors.green,
                title: "Days Used",
                subtitle: "Leave days taken so far",
                value: data.totalUsed.toString(),
              ),

              const SizedBox(height: 12),

              _summaryCard(
                icon: Icons.pending_actions,
                color: Colors.orange,
                title: "Days Remaining",
                subtitle: "Available leave days",
                value: data.totalRemaining.toString(),
              ),

              const SizedBox(height: 12),

              _summaryCard(
                icon: Icons.list_alt,
                color: Colors.teal,
                title: "Leave Applications",
                subtitle: "Policy types available",
                value: data.leavePolicyCount.toString(),
              ),

              const SizedBox(height: 12),

              _summaryCard(
                icon: Icons.access_time_filled,
                color: Colors.red,
                title: "Pending Requests",
                subtitle: "Applications under review",
                value: data.pendingRequests.toString(),
              ),

              const SizedBox(height: 25),

              const EmployeeSectionHeader(
                title: "Leave Balance by Policy",
                subtitle: "Policy-wise availability for this year",
              ),
              const SizedBox(height: 10),

              ...data.policyBalances.map((p) => _policyCard(p)),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  // ---------- REUSABLE SUMMARY CARD ----------
  Widget _summaryCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.montserrat(color: Colors.black45, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: EmployeeUi.header(24),
          ),
        ],
      ),
    );
  }

  // ---------- POLICY BALANCE CARD ----------
  Widget _policyCard(_PolicyBalance p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: EmployeeUi.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.policyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Allocated: ${p.allocated} • Used: ${p.used}",
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${p.remaining} left",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// -------- DATA MODELS ----------
class _SummaryData {
  final int totalAllocated;
  final int totalUsed;
  final int totalRemaining;
  final int leavePolicyCount;
  final int pendingRequests;
  final List<_PolicyBalance> policyBalances;

  _SummaryData({
    required this.totalAllocated,
    required this.totalUsed,
    required this.totalRemaining,
    required this.leavePolicyCount,
    required this.pendingRequests,
    required this.policyBalances,
  });

  factory _SummaryData.empty() => _SummaryData(
    totalAllocated: 0,
    totalUsed: 0,
    totalRemaining: 0,
    leavePolicyCount: 0,
    pendingRequests: 0,
    policyBalances: const [],
  );
}

class _PolicyBalance {
  final String policyName;
  final int allocated;
  final int used;
  final int remaining;

  _PolicyBalance({
    required this.policyName,
    required this.allocated,
    required this.used,
    required this.remaining,
  });
}

/// ---------------------------
/// Leave Calendar Tab
/// - Tapping a date opens a bottom sheet with styled card (detailed view)
/// ---------------------------
class LeaveCalendarTab extends StatefulWidget {
  final String email;
  final int reloadTrigger;
  const LeaveCalendarTab({
    Key? key,
    required this.email,
    required this.reloadTrigger,
  }) : super(key: key);

  @override
  State<LeaveCalendarTab> createState() => _LeaveCalendarTabState();
}

class _LeaveCalendarTabState extends State<LeaveCalendarTab> {
  final supabase = Supabase.instance.client;
  Map<DateTime, List<dynamic>> leaveEvents = {};
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;
  List? selectedEvents;
  bool _loadingEvents = true;
  bool _eventsInflight = false;
  late Future<void> _fetchFuture;

  @override
  void initState() {
    super.initState();
    _fetchFuture = _fetchEvents();
  }

  @override
  void didUpdateWidget(covariant LeaveCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTrigger != widget.reloadTrigger) {
      setState(() {
        _fetchFuture = _fetchEvents();
      });
    }
  }

  Future<void> _fetchEvents() async {
    if (_eventsInflight) return;
    _eventsInflight = true;

    if (mounted) setState(() => _loadingEvents = true);

    try {
      // debug_get_my_leaves is SECURITY DEFINER — it resolves the caller's
      // employee row via auth.email() and returns their leaves directly.
      // No need for a separate employee_records lookup here.
      final leaves = await supabase.rpc('debug_get_my_leaves');

      final Map<DateTime, List<dynamic>> events = {};
      if (leaves != null) {
        for (final leave in leaves as List) {
          DateTime start;
          DateTime end;
          try {
            start = DateTime.parse(leave['from_date'].toString());
          } catch (_) {
            continue;
          }
          try {
            end = DateTime.parse(leave['to_date'].toString());
          } catch (_) {
            end = start;
          }
          for (
          var d = start;
          !d.isAfter(end);
          d = d.add(const Duration(days: 1))
          ) {
            final normalized = DateTime(d.year, d.month, d.day);
            events.putIfAbsent(normalized, () => []).add(leave);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        leaveEvents = events;
        selectedDay = focusedDay;
        selectedEvents = _eventsForDay(focusedDay);
        _loadingEvents = false;
      });
    } catch (e) {
      debugPrint('fetchEvents error: $e');
      if (!mounted) return;
      setState(() {
        leaveEvents = {};
        selectedEvents = [];
        _loadingEvents = false;
      });
    } finally {
      _eventsInflight = false;
    }
  }


  List<dynamic> _eventsForDay(DateTime day) {
    return leaveEvents[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _onDaySelected(DateTime day, DateTime focused) {
    setState(() {
      selectedDay = day;
      focusedDay = focused;
      selectedEvents = _eventsForDay(day);
    });

    // show bottom sheet with details
    _showDayDetails(day, selectedEvents ?? []);
  }

  void _showDayDetails(DateTime day, List events) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.36,
          minChildSize: 0.18,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Container(
                      width: 60,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    DateFormat.yMMMMd().format(day),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (events.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('No approved leave on this day.'),
                    )
                  else
                    ...events.map((leave) {
                      final status = (leave['status'] ?? '')
                          .toString()
                          .toUpperCase();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.04),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    leave['leave_type'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status == 'APPROVED'
                                        ? Colors.green.shade50
                                        : (status == 'PENDING'
                                              ? Colors.orange.shade50
                                              : Colors.red.shade50),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: status == 'APPROVED'
                                          ? Colors.green.shade800
                                          : (status == 'PENDING'
                                                ? Colors.orange.shade800
                                                : Colors.red.shade800),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "${leave['from_date']} → ${leave['to_date']} (${leave['total_days']} days)",
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if ((leave['reason'] ?? '').toString().isNotEmpty)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.notes,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      "Reason: ${leave['reason'] ?? '--'}",
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (leave['manager'] != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Manager Details',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Name: ${leave['manager']['full_name']}",
                                    ),
                                    Text("Email: ${leave['manager']['email']}"),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingEvents) return const SkeletonLeaveCalendar();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
      child: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: focusedDay,
            selectedDayPredicate: (d) => isSameDay(selectedDay, d),
            eventLoader: _eventsForDay,
            calendarFormat: CalendarFormat.month,
            onDaySelected: _onDaySelected,

            headerStyle: const HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
            ),

            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox.shrink();

                final hasApproved = events.any(
                  (e) => (e as Map<String, dynamic>)['status'] == 'approved',
                );
                final hasPending = events.any(
                  (e) => (e as Map<String, dynamic>)['status'] == 'pending',
                );
                final hasRejected = events.any(
                  (e) => (e as Map<String, dynamic>)['status'] == 'rejected',
                );

                Color color = Colors.blue;
                if (hasRejected) {
                  color = Colors.red;
                } else if (hasPending) {
                  color = Colors.orange;
                } else if (hasApproved) {
                  color = Colors.green;
                }

                return Positioned(
                  bottom: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),

            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue.shade200,
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.deepPurple,
                shape: BoxShape.circle,
              ),
            ),
          ),

          const SizedBox(height: 30),

          // ✅ LEGEND ROW (THIS WAS CAUSING THE ISSUE)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(Colors.green, 'Approved'),
              _legendDot(Colors.orange, 'Pending'),
              _legendDot(Colors.red, 'Rejected'),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _legendDot(Color color, String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

/// ---------------------------
/// Leave Application Form
/// - Load leave_types (table) for employee org
/// - If none: manual leave type text field appears
/// - Submit saves to leave_applications table
/// - Snackbars: green on success, red on error
/// ---------------------------
class LeaveApplicationForm extends StatefulWidget {
  final String email;
  final VoidCallback? onSubmitted;

  const LeaveApplicationForm({Key? key, required this.email, this.onSubmitted})
    : super(key: key);

  @override
  State<LeaveApplicationForm> createState() => _LeaveApplicationFormState();
}

class _LeaveApplicationFormState extends State<LeaveApplicationForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  String? leaveType;
  DateTime? fromDate;
  DateTime? toDate;
  String? attachmentUrl;
  String? errorMessage;
  bool submitting = false;

  late TextEditingController _fromController;
  late TextEditingController _toController;
  late TextEditingController _reasonController;

  bool _loadingPolicies = true;
  List<Map<String, dynamic>> policies = [];
  String? _managerId;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    _reasonController = TextEditingController();
    _fetchPoliciesAndManager();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchPoliciesAndManager() async {
    setState(() => _loadingPolicies = true);

    try {
      final emp = await supabase
          .from('employee_records')
          .select('id, organization_id, manager_id')
          .eq('email', widget.email)
          .maybeSingle();

      if (emp == null) {
        setState(() {
          policies = [];
          _managerId = null;
          _loadingPolicies = false;
        });
        return;
      }

      final orgId = emp['organization_id'];

      debugPrint("LeavesScreen: Fetching leave balances...");
      final leaveBalances = await supabase
          .from('leave_balances')
          .select('leave_type_id, remaining_days')
          .eq('employee_id', emp['id'])
          .eq('year', DateTime.now().year);
      
      List<Map<String, dynamic>> resolvedPolicies = [];
      
      if (leaveBalances != null && leaveBalances.isNotEmpty) {
        final typeIds = leaveBalances.map((b) => b['leave_type_id'].toString()).toList();
        final leaveTypes = await supabase.from('leave_types').select('id, name').inFilter('id', typeIds);
        
        final typeMap = { for (var t in leaveTypes) t['id'].toString() : t['name'] };
        
        resolvedPolicies = leaveBalances.map((b) {
          final map = Map<String, dynamic>.from(b);
          map['leave_types'] = { 'name': typeMap[b['leave_type_id'].toString()] ?? 'Unknown' };
          return map;
        }).toList();
      }

      debugPrint("LeavesScreen: Policies resolved: ${resolvedPolicies.length}");

      setState(() {
        policies = resolvedPolicies;
        _managerId = emp['manager_id'];
        _loadingPolicies = false;
      });
    } catch (e) {
      debugPrint('fetchPolicies error: $e');
      setState(() {
        policies = [];
        _managerId = null;
        _loadingPolicies = false;
      });
    }
  }

  Future<void> submitLeaveApplication() async {
    if (!_formKey.currentState!.validate()) return;

    if (fromDate == null ||
        toDate == null ||
        (leaveType == null || leaveType!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill all required fields'),
          backgroundColor: Colors.red.shade400,
        ),
      );
      return;
    }

    setState(() {
      submitting = true;
      errorMessage = null;
    });

    try {
      final emp = await supabase
          .from('employee_records')
          .select('id')
          .eq('email', widget.email)
          .maybeSingle();

      if (emp == null) throw Exception('Employee not found');

      final empId = emp['id'];
      final days = toDate!.difference(fromDate!).inDays + 1;

      final data = {
        'employee_id': empId,
        'manager_id': _managerId ?? empId,
        'leave_type': leaveType,
        'from_date': fromDate!.toIso8601String().substring(0, 10),
        'to_date': toDate!.toIso8601String().substring(0, 10),
        'total_days': days,
        'reason': _reasonController.text.trim(),
        'attachment_url': attachmentUrl,
        'status': 'pending',
      };

      await supabase.from('leave_applications').insert([data]);

      if (!mounted) return; // 🔐 VERY IMPORTANT

      widget.onSubmitted?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Leave application submitted!'),
          backgroundColor: Colors.green.shade700,
        ),
      );

      Navigator.pop(context); // ✅ GO BACK TO LEAVES SCREEN
    } catch (e) {
      if (!mounted) return;

      setState(() {
        submitting = false;
        errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d != null) {
      setState(() {
        fromDate = d;
        _fromController.text = DateFormat('yyyy-MM-dd').format(d);
        if (toDate != null && toDate!.isBefore(fromDate!)) {
          toDate = fromDate;
          _toController.text = DateFormat('yyyy-MM-dd').format(toDate!);
        }
      });
    }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: toDate ?? fromDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d != null) {
      setState(() {
        toDate = d;
        _toController.text = DateFormat('yyyy-MM-dd').format(d);
        if (fromDate != null && toDate!.isBefore(fromDate!)) {
          fromDate = toDate;
          _fromController.text = DateFormat('yyyy-MM-dd').format(fromDate!);
        }
      });
    }
  }

  Widget _boxField({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPolicies) return const SkeletonLeaveApplicationForm();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------
              // LEAVE TYPE (BOX UI)
              // -------------------------
              _boxField(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isExpanded: true,
                    value: leaveType,
                    hint: const Text(
                      'Leave Type *',
                      style: TextStyle(fontSize: 15, color: Colors.black54),
                    ),

                    items: policies.where((p) => p['leave_types'] != null).map((
                      p,
                    ) {
                      return DropdownMenuItem<String>(
                        value: p['leave_types']['name'],
                        child: Text(
                          '${p['leave_types']['name']} (${p['remaining_days']} days)',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => leaveType = v),
                    // ===== POPUP MENU STYLE (This makes it look like image 2) =====
                    dropdownStyleData: DropdownStyleData(
                      maxHeight: 300,
                      width: MediaQuery.of(context).size.width - 50,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      elevation: 8,
                    ),

                    menuItemStyleData: const MenuItemStyleData(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      height: 45,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // -------------------------
              // FROM / TO DATES (BOX UI)
              // -------------------------
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickFromDate,
                      child: _boxField(
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: Colors.blue),
                            const SizedBox(width: 10),
                            Text(
                              _fromController.text.isEmpty
                                  ? 'From Date *'
                                  : _fromController.text,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickToDate,
                      child: _boxField(
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: Colors.blue),
                            const SizedBox(width: 10),
                            Text(
                              _toController.text.isEmpty
                                  ? 'To Date *'
                                  : _toController.text,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // -------------------------
              // REASON (BOX UI)
              // -------------------------
              _boxField(
                child: TextFormField(
                  controller: _reasonController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Reason *',
                    border: InputBorder.none,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter reason' : null,
                ),
              ),

              const SizedBox(height: 20),

              // -------------------------
              // SUBMIT BUTTON
              // -------------------------
              ElevatedButton(
                onPressed: submitting ? null : submitLeaveApplication,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Submit Leave Application',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
