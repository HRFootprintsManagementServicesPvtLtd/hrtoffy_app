import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/manager_access.dart';
import '../../repositories/approvals_repository.dart';
import '../../repositories/manager_attendance_repository.dart';
import '../../repositories/manager_repository.dart';
import '../../widgets/drawer_route.dart';
import '../../widgets/manager_drawer.dart';
import 'team_attendance_screen.dart';
import 'widgets/leave_approvals_panel.dart';
import 'widgets/manager_state_views.dart';
import 'widgets/overtime_approvals_panel.dart';
import 'widgets/regularization_approvals_panel.dart';

/// The tabs of the manager Time hub, in order (the website's TimeLeaveHub for a manager).
///
/// There is deliberately no C-Off tab: the server has no manager list route for compensatory-off requests yet. It is
/// part of the backend proposal; add the tab here once that route exists.
const List<String> kTimeHubTabs = [
  'Attendance',
  'Leave',
  'Regularization',
  'Overtime',
  'Holidays',
];

/// Shown when the organisation has no holiday in the year.
const String kNoHolidaysMessage = 'No holidays are listed for this year.';

/// Manager "Time" page: Attendance (overview + muster), Leave, Regularization, Overtime and Holidays in one tabbed hub.
/// Every panel reads and decides through its own repository; the hub only arranges them.
class TimeHubScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final ManagerRepository? managerRepository;
  final ManagerAttendanceRepository? attendanceRepository;
  final ApprovalsRepository? approvalsRepository;

  /// The current time (tests pass a fixed one).
  final DateTime Function()? now;

  const TimeHubScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.managerRepository,
    this.attendanceRepository,
    this.approvalsRepository,
    this.now,
  });

  @override
  State<TimeHubScreen> createState() => _TimeHubScreenState();
}

class _TimeHubScreenState extends State<TimeHubScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TabController _tabs = TabController(
    length: kTimeHubTabs.length,
    vsync: this,
  );
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();
  late final ManagerAttendanceRepository _attendance =
      widget.attendanceRepository ?? ManagerAttendanceRepository();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The panels' own "back" link has nowhere to go inside the hub: it returns to the first tab.
  void _toFirstTab() => _tabs.animateTo(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.attendance,
        companyLogoUrl: widget.userData['company_logo_url'],
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Image.asset('assets/HR TOFFY.png', height: 35),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu, color: Colors.black),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.blue.shade700,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.blue.shade700,
          labelStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: [for (final t in kTimeHubTabs) Tab(text: t)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // Swiping would fight the panels' own horizontal scrolling (muster table); the tab bar is the way to switch.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          managerScreenFor(
            ManagerFeature.teamAttendance,
            () => TeamAttendanceScreen(
              embedded: true,
              userEmail: widget.userEmail,
              userData: widget.userData,
              fetchHrmsContext: widget.fetchHrmsContext,
              managerRepository: widget.managerRepository,
              attendanceRepository: widget.attendanceRepository,
              now: widget.now,
            ),
          ),
          LeaveApprovalsPanel(approvalsRepository: _approvals),
          RegularizationApprovalsPanel(
            repository: _approvals,
            onBack: _toFirstTab,
          ),
          OvertimeApprovalsPanel(repository: _approvals, onBack: _toFirstTab),
          _HolidaysTab(repository: _attendance, now: widget.now),
        ],
      ),
    );
  }
}

/// The organisation's holidays for the current year, grouped by month (read-only).
class _HolidaysTab extends StatelessWidget {
  const _HolidaysTab({required this.repository, this.now});

  final ManagerAttendanceRepository repository;
  final DateTime Function()? now;

  DateTime get _now => (now ?? DateTime.now)();

  Future<List<Map<String, dynamic>>> _load() async {
    final year = _now.year;
    final rows = await repository.holidays(
      from: DateTime(year),
      to: DateTime(year, 12, 31),
    );
    return [...rows]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime(_now.year, _now.month, _now.day);
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: _load,
      isEmpty: (rows) => rows.isEmpty,
      emptyText: kNoHolidaysMessage,
      builder: (context, rows) {
        final byMonth = <int, List<Map<String, dynamic>>>{};
        for (final h in rows) {
          final d = DateTime.tryParse('${h['date']}');
          if (d == null) continue;
          byMonth.putIfAbsent(d.month, () => []).add(h);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              'Holidays ${_now.year}',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            for (final month in byMonth.keys.toList()..sort()) ...[
              const SizedBox(height: 20),
              Text(
                DateFormat('MMMM').format(DateTime(_now.year, month)),
                key: ValueKey('holiday-month-$month'),
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              for (final h in byMonth[month]!) _row(h, today),
            ],
          ],
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> h, DateTime today) {
    final d = DateTime.parse('${h['date']}');
    final past = d.isBefore(today);
    final name = (h['name'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.celebration_outlined,
            size: 20,
            color: past ? Colors.grey : Colors.blue.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isEmpty ? 'Holiday' : name,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: past ? Colors.black45 : Colors.black87,
              ),
            ),
          ),
          Text(
            DateFormat('EEE, d MMM').format(d),
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: past ? Colors.black38 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
