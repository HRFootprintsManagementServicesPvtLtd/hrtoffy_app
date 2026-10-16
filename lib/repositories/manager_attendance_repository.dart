import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import '../core/auth/auth_service.dart';
import 'base_repository.dart';

/// A message that is safe to show for a manager attendance call: never raw server text, urls or ids.
String friendlyManagerAttendanceError(Object e) {
  if (e is ApiException) {
    if (e.isNetworkError) {
      return 'Network problem. Check your connection and retry.';
    }
    if (e.isUnauthorized) return 'Session expired - please sign in again.';
    if (e.isForbidden) {
      return "Team attendance isn't available for your role.";
    }
    if (e.isNotFound) return "This isn't available for this person.";
    if (e.isServerError) {
      return "Attendance can't be loaded right now. Please try again.";
    }
    return "Couldn't load attendance. Please try again.";
  }
  if (e is AuthFlowException) return 'Session expired - please sign in again.';
  return 'Something went wrong. Please try again.';
}

/// True when the server refused the call because of the caller's role (HTTP 403).
bool isRoleRefusal(Object e) => e is ApiException && e.isForbidden;

/// One approved leave still to come, from the team leave summary.
class UpcomingLeave {
  const UpcomingLeave({
    required this.from,
    required this.to,
    this.leaveType,
    this.totalDays,
  });

  /// `yyyy-MM-dd`.
  final String from;
  final String to;
  final String? leaveType;
  final num? totalDays;

  bool covers(String ymd) => ymd.compareTo(from) >= 0 && ymd.compareTo(to) <= 0;
}

/// The day's punch logs of one team member, split into plain punches and background tracking points.
class DayPunches {
  const DayPunches({required this.punches, required this.tracks});

  /// Punch in/out rows with a position, oldest first.
  final List<Map<String, dynamic>> punches;

  /// `punch_type == 'track'` rows with a position, oldest first (empty when the day has none).
  final List<Map<String, dynamic>> tracks;

  bool get hasTrack => tracks.isNotEmpty;

  /// What the map draws: the tracking points when the day has any, otherwise the punches.
  List<Map<String, dynamic>> get points => hasTrack ? tracks : punches;
}

/// Reads the manager attendance screen needs beyond [ManagerRepository]: holidays, working days, the team leave summary
/// and a team member's day punches. Every call is a read; who may see whom is decided by the server.
class ManagerAttendanceRepository extends BaseRepository {
  ManagerAttendanceRepository({super.auth});

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `GET /organizations/:orgId/holidays?from=&to=` (any member): `{date: yyyy-MM-dd, name}` per holiday.
  Future<List<Map<String, dynamic>>> holidays({
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await api.get(
      orgPath('/holidays'),
      query: {'from': ymd(from), 'to': ymd(to)},
    );
    return [
      for (final h in asMapList(data))
        if (asDateOnly(h['date']) != null)
          {...h, 'date': asDateOnly(h['date']), 'name': h['name']?.toString()},
    ];
  }

  static const _dayNames = {
    'monday': 'monday',
    'mon': 'monday',
    'tuesday': 'tuesday',
    'tue': 'tuesday',
    'tues': 'tuesday',
    'wednesday': 'wednesday',
    'wed': 'wednesday',
    'thursday': 'thursday',
    'thu': 'thursday',
    'thur': 'thursday',
    'thurs': 'thursday',
    'friday': 'friday',
    'fri': 'friday',
    'saturday': 'saturday',
    'sat': 'saturday',
    'sunday': 'sunday',
    'sun': 'sunday',
  };

  /// `GET /organizations/:orgId` -> `working_days` (a jsonb column, the weekdays worked). Returns lower-case weekday
  /// names (`monday` ...), or null when the organization has none set or the shape is not recognised: the caller then
  /// does not guess weekly offs. Accepts a list of names (`Monday` / `mon`) or a `{monday: true}` map.
  Future<Set<String>?> workingDays() async {
    final data = await api.get(orgPath(''));
    final raw = data is Map ? data['working_days'] : null;
    final names = <String>{};
    if (raw is List) {
      if (raw.isEmpty) return null;
      for (final v in raw) {
        final n = _dayNames[v.toString().trim().toLowerCase()];
        if (n == null) return null;
        names.add(n);
      }
    } else if (raw is Map) {
      for (final e in raw.entries) {
        final n = _dayNames[e.key.toString().trim().toLowerCase()];
        if (n == null) return null;
        if (e.value == true) names.add(n);
      }
    } else {
      return null;
    }
    return names.isEmpty ? null : names;
  }

  /// `GET /organizations/:orgId/leaves/team-summary?managerId=<me>` (leaves.routes.ts:39; service
  /// `getTeamLeaveSummary`, SQL `get_team_leave_summary`). Returns, per employee id, the leaves still to come
  /// (`from_date`, `to_date`, `leave_type`, `total_days`): approved leaves that start today or later, at most 3 per
  /// person. Leaves already under way are NOT in the answer, so this never proves someone is not on leave.
  Future<Map<String, List<UpcomingLeave>>> upcomingLeaves() async {
    final data = await api.get(leavesPath, query: {'managerId': employeeId});
    final out = <String, List<UpcomingLeave>>{};
    for (final row in asMapList(data)) {
      final id = (row['employee_id'] ?? row['employeeId'])?.toString();
      if (id == null) continue;
      final raw = row['upcoming_leaves'] ?? row['upcomingLeaves'];
      final list = <UpcomingLeave>[];
      if (raw is List) {
        for (final l in raw) {
          if (l is! Map) continue;
          final from = asDateOnly(l['from_date'] ?? l['fromDate']);
          final to = asDateOnly(l['to_date'] ?? l['toDate']) ?? from;
          if (from == null || to == null) continue;
          list.add(
            UpcomingLeave(
              from: from,
              to: to,
              leaveType: (l['leave_type'] ?? l['leaveType'])?.toString(),
              totalDays: asNum(l['total_days'] ?? l['totalDays']),
            ),
          );
        }
      }
      out[id] = list;
    }
    return out;
  }

  String get leavesPath => orgPath('/leaves/team-summary');

  /// `GET /organizations/:orgId/attendance/employees/:employeeId/day-punch-logs?date=` (attendance.routes.ts:823,
  /// service `getEmployeeDayPunchLogs`: team scoped, every punch log of the day including `track` rows, oldest first).
  /// Only rows that carry a position are kept.
  Future<DayPunches> dayPunches(
    String employeeId, {
    required DateTime date,
  }) async {
    final data = await api.get(
      orgPath('/attendance/employees/$employeeId/day-punch-logs'),
      query: {'date': ymd(date)},
    );
    final rows = <Map<String, dynamic>>[];
    for (final r in asMapList(data)) {
      final lat = asNum(r['punch_lat'])?.toDouble();
      final lng = asNum(r['punch_lng'])?.toDouble();
      if (lat == null || lng == null) continue;
      rows.add({...r, 'punch_lat': lat, 'punch_lng': lng});
    }
    bool isTrack(Map<String, dynamic> r) =>
        r['punch_type']?.toString().toLowerCase() == 'track';
    return DayPunches(
      punches: rows.where((r) => !isTrack(r)).toList(),
      tracks: rows.where(isTrack).toList(),
    );
  }

  /// `GET /organizations/:orgId/work-sites` (`id, name, latitude, longitude, radius_meters`).
  Future<List<Map<String, dynamic>>> workSites() async {
    final data = await api.get(orgPath('/work-sites'));
    return asMapList(
      data,
    ).map((s) => Map<String, dynamic>.from(snakeKeys(s) as Map)).toList();
  }
}
