import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/manager_attendance_repository.dart';
import '../../repositories/manager_repository.dart';
import '../../widgets/drawer_route.dart';
import '../../widgets/manager_drawer.dart';
import 'widgets/ask_toffy_card.dart';
import 'widgets/attendance_muster_table.dart';
import 'widgets/employee_geo_dialog.dart';

/// Shown in place of the leave details when the server has no manager-callable answer for them.
const String kLeaveUnavailableMessage = "Leave details aren't available yet.";

/// Shown when the team is empty (nobody has this manager as their manager).
const String kNoTeamMessage = 'No one reports to you yet.';

/// How many days back the overview and the day picker reach.
const int kAttendanceWindowDays = 30;

const int _trackerRowCap = 100;

/// Manager attendance page: KPIs for a chosen day, the team's status that day, the last 30 days of records, leave still
/// to come and the month muster. All data is read through [ManagerRepository] and [ManagerAttendanceRepository].
class TeamAttendanceScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final ManagerRepository? managerRepository;
  final ManagerAttendanceRepository? attendanceRepository;

  /// The current time (tests pass a fixed one).
  final DateTime Function()? now;

  /// True when shown as a tab of the Time hub: no Scaffold, app bar or drawer of its own (the hub provides them).
  final bool embedded;

  const TeamAttendanceScreen({
    super.key,
    this.embedded = false,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.managerRepository,
    this.attendanceRepository,
    this.now,
  });

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final ManagerRepository _manager =
      widget.managerRepository ?? ManagerRepository();
  late final ManagerAttendanceRepository _extra =
      widget.attendanceRepository ?? ManagerAttendanceRepository();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  DateTime get _now => (widget.now ?? DateTime.now)();
  DateTime get _today {
    final n = _now;
    return DateTime(n.year, n.month, n.day);
  }

  bool teamLoading = true;
  String? teamError;
  ManagerTeam? team;
  List<Map<String, dynamic>> members = [];

  /// Last [kAttendanceWindowDays] days, newest first. Null while loading or when it failed ([attendanceError]).
  List<Map<String, dynamic>>? attendance;
  String? attendanceError;

  /// `yyyy-MM-dd` -> holiday name, over every window loaded so far.
  final Map<String, String> holidays = {};

  /// Null when the organization's working days are unknown: then no weekly off is assumed.
  Set<String>? workingDays;

  /// Null when the team leave summary could not be read: leave parts say "not available".
  Map<String, List<UpcomingLeave>>? upcomingLeaves;

  late DateTime selectedDay;
  late DateTime selectedMonth;
  String searchQuery = '';

  bool musterLoading = false;
  String? musterError;
  Map<String, Map<String, dynamic>>? musterRecords;
  int _loadId = 0;
  int _musterId = 0;

  @override
  void initState() {
    super.initState();
    selectedDay = _today;
    selectedMonth = DateTime(_today.year, _today.month);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1 && musterRecords == null) _loadMuster();
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      teamLoading = true;
      teamError = null;
      attendance = null;
      attendanceError = null;
      musterRecords = null;
    });
    ManagerTeam loaded;
    try {
      loaded = await _manager.team();
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() {
        teamLoading = false;
        teamError = friendlyManagerAttendanceError(e);
      });
      return;
    }
    if (!mounted || id != _loadId) return;
    final sorted = [...loaded.tree]
      ..sort(
        (a, b) => (a['full_name'] ?? '').toString().toLowerCase().compareTo(
          (b['full_name'] ?? '').toString().toLowerCase(),
        ),
      );
    setState(() {
      team = loaded;
      members = sorted;
      teamLoading = false;
    });
    if (sorted.isEmpty) return;

    final to = _today;
    final from = to.subtract(const Duration(days: kAttendanceWindowDays));
    await Future.wait([
      _loadAttendance(id, from, to),
      _loadHolidays(from, to),
      _loadWorkingDays(),
      _loadLeaves(),
    ]);
    if (mounted && id == _loadId && _tabController.index == 1) _loadMuster();
  }

  Future<void> _loadAttendance(int id, DateTime from, DateTime to) async {
    try {
      final rows = await _manager.teamAttendance(
        members.map((m) => m['id'].toString()).toList(),
        from: from,
        to: to,
      );
      if (!mounted || id != _loadId) return;
      setState(() => attendance = rows);
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() => attendanceError = friendlyManagerAttendanceError(e));
    }
  }

  Future<void> _loadHolidays(DateTime from, DateTime to) async {
    try {
      final list = await _extra.holidays(from: from, to: to);
      if (!mounted) return;
      setState(() {
        for (final h in list) {
          holidays[h['date'].toString()] = (h['name'] ?? 'Holiday').toString();
        }
      });
    } catch (_) {
      // Without holidays a holiday shows as "no record", never as an absence.
    }
  }

  Future<void> _loadWorkingDays() async {
    try {
      final days = await _extra.workingDays();
      if (!mounted) return;
      setState(() => workingDays = days);
    } catch (_) {}
  }

  Future<void> _loadLeaves() async {
    try {
      final leaves = await _extra.upcomingLeaves();
      if (!mounted) return;
      setState(() => upcomingLeaves = leaves);
    } catch (_) {
      if (!mounted) return;
      setState(() => upcomingLeaves = null);
    }
  }

  Future<void> _loadMuster() async {
    if (members.isEmpty) return;
    final id = ++_musterId;
    final month = selectedMonth;
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    setState(() {
      musterLoading = true;
      musterError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _manager.teamAttendance(
          members.map((m) => m['id'].toString()).toList(),
          from: first,
          to: last,
        ),
        _extra
            .holidays(from: first, to: last)
            .then<List<Map<String, dynamic>>?>((v) => v)
            .catchError((_) => null),
      ]);
      if (!mounted || id != _musterId) return;
      final rows = results[0] as List<Map<String, dynamic>>;
      final hol = results[1] as List<Map<String, dynamic>>?;
      setState(() {
        musterRecords = {
          for (final r in rows)
            if (r['employee_id'] != null && r['date'] != null)
              AttendanceMusterTable.recordKey(
                r['employee_id'].toString(),
                r['date'].toString(),
              ): r,
        };
        if (hol != null) {
          for (final h in hol) {
            holidays[h['date'].toString()] = (h['name'] ?? 'Holiday')
                .toString();
          }
        }
        musterLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _musterId) return;
      setState(() {
        musterLoading = false;
        musterError = friendlyManagerAttendanceError(e);
      });
    }
  }

  // ---- day figures ---------------------------------------------------------------------------------------------

  String get _dayKey => ManagerAttendanceRepository.ymd(selectedDay);
  bool get _dayIsToday => selectedDay == _today;

  Map<String, Map<String, dynamic>> get _dayRows {
    final out = <String, Map<String, dynamic>>{};
    for (final r in attendance ?? const <Map<String, dynamic>>[]) {
      if (r['date'] == _dayKey && r['employee_id'] != null) {
        out[r['employee_id'].toString()] = r;
      }
    }
    return out;
  }

  bool _onLeave(String id, Map<String, dynamic>? row) {
    if ((row?['status'] ?? '') == 'on leave') return true;
    if (row != null) return false;
    return (upcomingLeaves?[id] ?? const []).any((l) => l.covers(_dayKey));
  }

  bool get _dayIsOff {
    if (holidays.containsKey(_dayKey)) return true;
    final wd = workingDays;
    if (wd == null) return false;
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    return !wd.contains(names[selectedDay.weekday - 1]);
  }

  /// A status word for one team member on the selected day.
  String _statusFor(String id, Map<String, dynamic>? row) {
    if (row != null) {
      final s = (row['status'] ?? '').toString();
      return s.isEmpty ? 'NO RECORD' : s.toUpperCase();
    }
    if (_onLeave(id, null)) return 'ON LEAVE';
    if (holidays.containsKey(_dayKey)) return 'HOLIDAY';
    if (_dayIsOff) return 'WEEKLY OFF';
    return _dayIsToday ? 'NOT CHECKED IN' : 'NO RECORD';
  }

  // ---- build ----------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody();
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(),
            const SizedBox(height: 24),
            const AskToffyCard(),
            const SizedBox(height: 24),
            if (_teamReady) ...[
              _buildDayBar(),
              const SizedBox(height: 16),
              _buildLargeKpiCards(),
              const SizedBox(height: 32),
            ] else
              const SizedBox(height: 16),
            _buildManagerPanelHeader(),
            const SizedBox(height: 16),
            _buildPanelTabs(),
            const SizedBox(height: 24),
            if (_teamReady) ...[
              _buildSmallKpiGrid(),
              const SizedBox(height: 32),
            ],
            _buildTabContent(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  bool get _teamReady =>
      !teamLoading && teamError == null && members.isNotEmpty;

  Widget _buildPageHeader() {
    final first = widget.userData['full_name']
        ?.toString()
        .trim()
        .split(' ')
        .first
        .toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "GOOD MORNING, ${(first == null || first.isEmpty) ? 'MANAGER' : first} — ${DateFormat('EEEE, d MMM').format(_now).toUpperCase()}",
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade400,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Attendance, every punch counted',
          style: GoogleFonts.montserrat(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Track presence, punches, and shift schedules across your team.',
          style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildDayBar() {
    final earliest = _today.subtract(
      const Duration(days: kAttendanceWindowDays),
    );
    return Row(
      children: [
        IconButton(
          key: const ValueKey('day-prev'),
          onPressed: selectedDay.isAfter(earliest)
              ? () => setState(
                  () => selectedDay = selectedDay.subtract(
                    const Duration(days: 1),
                  ),
                )
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        InkWell(
          key: const ValueKey('day-pick'),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: selectedDay,
              firstDate: earliest,
              lastDate: _today,
            );
            if (d != null) {
              setState(() => selectedDay = DateTime(d.year, d.month, d.day));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _dayIsToday
                      ? 'Today, ${DateFormat('d MMM').format(selectedDay)}'
                      : DateFormat('EEE, d MMM yyyy').format(selectedDay),
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('day-next'),
          onPressed: selectedDay.isBefore(_today)
              ? () => setState(
                  () => selectedDay = selectedDay.add(const Duration(days: 1)),
                )
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  /// Counts for the selected day, or null parts when the records could not be read.
  ({
    int present,
    int absent,
    int late,
    double? avgHours,
    int notIn,
    int? onLeave,
  })?
  _figures() {
    if (attendance == null) return null;
    final rows = _dayRows;
    var present = 0, absent = 0, late = 0;
    final hours = <double>[];
    final onLeaveIds = <String>{};
    var withoutRecord = 0;
    for (final m in members) {
      final id = m['id'].toString();
      final row = rows[id];
      if (row == null) {
        if (_onLeave(id, null)) {
          onLeaveIds.add(id);
        } else {
          withoutRecord++;
        }
        continue;
      }
      switch (row['status']) {
        case 'present':
          present++;
        case 'late':
          present++;
          late++;
        case 'half day':
          present++;
        case 'absent':
        case 'esi absence':
          absent++;
        case 'on leave':
          onLeaveIds.add(id);
      }
      final h = asNum(row['hours_worked']);
      if (h != null) hours.add(h.toDouble());
    }
    // Leaves under way are not in the leave summary: without it, no record cannot be told from "on leave".
    final onLeave = (upcomingLeaves == null && onLeaveIds.isEmpty)
        ? null
        : onLeaveIds.length;
    return (
      present: present,
      absent: absent,
      late: late,
      avgHours: hours.isEmpty
          ? null
          : hours.reduce((a, b) => a + b) / hours.length,
      notIn: _dayIsOff ? -1 : withoutRecord,
      onLeave: onLeave,
    );
  }

  Widget _buildLargeKpiCards() {
    final f = _figures();
    String n(int? v) => v == null ? '-' : '$v';
    final suffix = _dayIsToday ? ' TODAY' : '';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _largeKpiCard(
          'PRESENT$suffix',
          n(f?.present),
          Icons.check_circle_outline,
        ),
        _largeKpiCard(
          'ABSENT$suffix',
          n(f?.absent),
          Icons.remove_circle_outline,
        ),
        _largeKpiCard('LATE$suffix', n(f?.late), Icons.access_time),
        _largeKpiCard(
          'AVG HOURS',
          f?.avgHours == null ? '-' : '${f!.avgHours!.toStringAsFixed(1)} h',
          Icons.timer_outlined,
        ),
      ],
    );
  }

  Widget _largeKpiCard(String label, String value, IconData icon) {
    return Container(
      width: (MediaQuery.of(context).size.width - 52) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 8,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 14, color: Colors.blue.shade400),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagerPanelHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manager Attendance Dashboard',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "Monitor your team's attendance and leave status",
          style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildPanelTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.blue.shade600,
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 16),
                SizedBox(width: 8),
                Text('Team Overview'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.grid_on_outlined, size: 16),
                SizedBox(width: 8),
                Text('Attendance Muster'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallKpiGrid() {
    final f = _figures();
    String n(int? v) => (v == null || v < 0) ? '-' : '$v';
    return Row(
      children: [
        _smallKpiCard(
          'Team Members',
          '${members.length}',
          Colors.blue,
          Icons.groups_outlined,
        ),
        const SizedBox(width: 12),
        _smallKpiCard(
          'Present',
          n(f?.present),
          Colors.green,
          Icons.check_circle_outline,
        ),
        const SizedBox(width: 12),
        _smallKpiCard(
          'On Leave',
          n(f?.onLeave),
          Colors.indigo,
          Icons.calendar_today,
        ),
        const SizedBox(width: 12),
        _smallKpiCard(
          'Not Checked In',
          n(f?.notIn),
          Colors.orange,
          Icons.timer_outlined,
        ),
      ],
    );
  }

  Widget _smallKpiCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 16, color: color),
                Text(
                  value,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 9,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- tab content ---------------------------------------------------------------------------------------------

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: child,
  );

  Widget _messageCard(String message, {VoidCallback? retry}) {
    return _card(
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          if (retry != null)
            TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    if (teamLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (teamError != null) return _messageCard(teamError!, retry: _load);
    if (members.isEmpty) return _messageCard(kNoTeamMessage);
    return _tabController.index == 0
        ? _buildTeamOverviewTab()
        : _buildAttendanceMusterTab();
  }

  void _openLocation(Map<String, dynamic> member) {
    showDialog<void>(
      context: context,
      builder: (_) => EmployeeGeoDialog(
        employeeId: member['id'].toString(),
        employeeName: (member['full_name'] ?? 'Team member').toString(),
        repository: _extra,
        initialDate: selectedDay,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'half day':
        return Colors.orangeAccent;
      case 'on leave':
        return Colors.blue;
      case 'holiday':
        return Colors.purple;
      case 'weekly off':
      case 'not checked in':
      case 'no record':
        return Colors.blueGrey;
      default:
        return Colors.red;
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTeamOverviewTab() {
    final err = attendanceError;
    if (err != null) return _messageCard(err, retry: _load);
    if (attendance == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final q = searchQuery.trim().toLowerCase();
    bool matches(String? name) =>
        q.isEmpty || (name ?? '').toLowerCase().contains(q);
    final rows = _dayRows;
    final shownMembers = members
        .where((m) => matches(m['full_name']?.toString()))
        .toList();
    final records = attendance!
        .where((a) => matches(a['employee_records']?['full_name']?.toString()))
        .toList();
    final shownRecords = records.take(_trackerRowCap).toList();
    final reviewOnly = (team?.reviewees.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Team Attendance & Leave Tracker (Last 30 Days)',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search employee by name...',
                  hintStyle: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (reviewOnly) ...[
                const SizedBox(height: 8),
                Text(
                  "People you only review aren't included: attendance is shown for your reporting team.",
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Status on ${DateFormat('d MMM yyyy').format(selectedDay)}',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final m in shownMembers) _memberRow(m, rows),
              const SizedBox(height: 20),
              Text(
                'Records',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Text(
                  'No attendance records in the last 30 days.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _trackerTable(shownRecords),
                ),
              if (records.length > shownRecords.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the newest ${shownRecords.length} of ${records.length} records. Search to narrow down.',
                    style: GoogleFonts.montserrat(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildLeavesCard(),
      ],
    );
  }

  Widget _memberRow(
    Map<String, dynamic> m,
    Map<String, Map<String, dynamic>> rows,
  ) {
    final id = m['id'].toString();
    final status = _statusFor(id, rows[id]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          InkWell(
            key: ValueKey('member-location-$id'),
            onTap: () => _openLocation(m),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.location_on, size: 16, color: Colors.blue),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (m['full_name'] ?? 'Unknown').toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (m['designation'] != null)
                  Text(
                    m['designation'].toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
          _badge(status, _statusColor(status)),
        ],
      ),
    );
  }

  static String _clock(
    Map<String, dynamic> row,
    String stampKey,
    String timeKey,
  ) {
    final stamp = DateTime.tryParse('${row[stampKey] ?? ''}');
    if (stamp != null) return DateFormat('hh:mm a').format(stamp.toLocal());
    // `check_in_time` is a wall-clock time column the server sends as 1970-01-01THH:mm:ss: it is not shifted.
    final t = DateTime.tryParse('${row[timeKey] ?? ''}');
    if (t != null) return DateFormat('hh:mm a').format(t);
    return '-';
  }

  Widget _trackerTable(List<Map<String, dynamic>> shown) {
    const h = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);
    return DataTable(
      columnSpacing: 20,
      headingRowHeight: 40,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 60,
      columns: const [
        DataColumn(label: Text('Employee', style: h)),
        DataColumn(label: Text('Date', style: h)),
        DataColumn(label: Text('Check In', style: h)),
        DataColumn(label: Text('Check Out', style: h)),
        DataColumn(label: Text('Hours', style: h)),
        DataColumn(label: Text('Work Type', style: h)),
        DataColumn(label: Text('Status', style: h)),
        DataColumn(label: Text('Leave Status', style: h)),
      ],
      rows: [
        for (final a in shown)
          DataRow(
            cells: [
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (a['employee_records']?['full_name'] ?? 'Unknown')
                          .toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      (a['employee_records']?['employee_id'] ?? '').toString(),
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  _dateLabel(a['date']),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              DataCell(
                Text(
                  _clock(a, 'punch_in_time', 'check_in_time'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              DataCell(
                Text(
                  _clock(a, 'punch_out_time', 'check_out_time'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              DataCell(
                Text(
                  asNum(a['hours_worked']) == null
                      ? '-'
                      : '${asNum(a['hours_worked'])!.toStringAsFixed(1)}h',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              DataCell(
                Text(
                  (a['work_type'] ?? '-').toString(),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              DataCell(
                _badge(
                  (a['status'] ?? '').toString().toUpperCase(),
                  _statusColor((a['status'] ?? '').toString()),
                ),
              ),
              DataCell(_leaveBadge(a)),
            ],
          ),
      ],
    );
  }

  Widget _leaveBadge(Map<String, dynamic> a) {
    if (a['status'] == 'on leave') return _badge('ON LEAVE', Colors.blue);
    // Without the leave summary "not on leave" is unknown, so no "AVAILABLE" is claimed.
    if (upcomingLeaves == null) return _badge('-', Colors.grey);
    final id = a['employee_id']?.toString();
    final covered = (upcomingLeaves![id] ?? const []).any(
      (l) => l.covers((a['date'] ?? '').toString()),
    );
    return covered
        ? _badge('ON LEAVE', Colors.blue)
        : _badge('AVAILABLE', Colors.grey);
  }

  String _dateLabel(dynamic ymd) {
    final d = DateTime.tryParse('${ymd ?? ''}');
    return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
  }

  Widget _buildLeavesCard() {
    final leaves = upcomingLeaves;
    final items = <Widget>[];
    if (leaves != null) {
      for (final m in members) {
        final list = leaves[m['id'].toString()] ?? const [];
        for (final l in list) {
          items.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (m['full_name'] ?? 'Unknown').toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${_dateLabel(l.from)} - ${_dateLabel(l.to)}${l.leaveType == null ? '' : '  ${l.leaveType}'}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming Leaves',
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (leaves == null)
            Text(
              kLeaveUnavailableMessage,
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
            )
          else if (items.isEmpty)
            Text(
              'No approved leaves coming up.',
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
            )
          else
            ...items,
        ],
      ),
    );
  }

  Widget _buildAttendanceMusterTab() {
    final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final canNext = monthEnd.isBefore(_today);
    Widget body;
    if (musterLoading || (musterRecords == null && musterError == null)) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (musterError != null) {
      body = _messageCard(musterError!, retry: _loadMuster);
    } else {
      body = AttendanceMusterTable(
        members: members,
        month: selectedMonth,
        today: _today,
        recordsByKey: musterRecords ?? const {},
        holidays: holidays,
        workingDays: workingDays,
        upcomingLeaves: upcomingLeaves,
        onLocation: _openLocation,
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(selectedMonth),
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('month-prev'),
                    onPressed: () {
                      setState(() {
                        selectedMonth = DateTime(
                          selectedMonth.year,
                          selectedMonth.month - 1,
                        );
                        musterRecords = null;
                      });
                      _loadMuster();
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const ValueKey('month-next'),
                    onPressed: canNext
                        ? () {
                            setState(() {
                              selectedMonth = DateTime(
                                selectedMonth.year,
                                selectedMonth.month + 1,
                              );
                              musterRecords = null;
                            });
                            _loadMuster();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
          const SizedBox(height: 12),
          Text(
            'P present, LT late, HD half day, A absent, L leave, H holiday, OFF weekly off, NR no record, - day not over',
            style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
          ),
          if (workingDays == null)
            Text(
              "Weekly offs aren't marked: the working days aren't available.",
              style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
            ),
          if (upcomingLeaves == null)
            Text(
              'Leave shows only where the attendance record says so. $kLeaveUnavailableMessage',
              style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
