import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in manager's reporting team, as the server scopes it.
///
/// [tree] is the whole reporting tree below the caller (direct and indirect reports); [direct] are the ones whose
/// `manager_id` is the caller; [indirect] the rest of the tree; [reviewees] the people the caller reviews. Every list
/// holds the server's reduced "team view" of an employee in the UI's snake_case keys (`id`, `employee_id`,
/// `full_name`, `designation`, `employment_status`, ...): the server never returns pay, bank or identity data here.
class ManagerTeam {
  const ManagerTeam({
    required this.direct,
    required this.indirect,
    required this.reviewees,
  });

  final List<Map<String, dynamic>> direct;
  final List<Map<String, dynamic>> indirect;
  final List<Map<String, dynamic>> reviewees;

  /// Everyone on the reporting tree.
  List<Map<String, dynamic>> get tree => [...direct, ...indirect];

  /// The tree plus the people the caller reviews, each person once.
  List<Map<String, dynamic>> get all {
    final seen = <String>{};
    return [
      for (final m in [...tree, ...reviewees])
        if (seen.add(m['id'].toString())) m,
    ];
  }

  /// Employee ids whose attendance the server lets the caller read (the tree; see [ManagerRepository.teamAttendance]).
  List<String> get treeIds => [for (final m in tree) m['id'].toString()];
}

/// Manager-scoped reads through the HR Toffy API. Who may see whom is decided by the server (reporting line and role);
/// this class only asks and shapes the answer for the screens.
class ManagerRepository extends BaseRepository {
  ManagerRepository({super.auth});

  static const _pageSize = 100;

  /// Reporting team: `GET /organizations/:orgId/employees?managerId=<me>` (the whole tree) and `?reviewerId=<me>`,
  /// 100 per page until the server's `total` is reached. A person the caller only reports to as a *secondary*
  /// manager is not part of either list (the server has no filter for that line).
  Future<ManagerTeam> team() async {
    final me = employeeId;
    final results = await Future.wait([
      _listAll('managerId', me),
      _listAll('reviewerId', me),
    ]);
    // Everyone with this manager on record, whatever their status: the website's My Team counts and lists them all (12), so the app does too.
    bool current(Map<String, dynamic> m) => m['id'].toString() != me;
    final tree = results[0].where(current).toList();
    return ManagerTeam(
      direct: tree.where((m) => m['manager_id']?.toString() == me).toList(),
      indirect: tree.where((m) => m['manager_id']?.toString() != me).toList(),
      reviewees: results[1].where(current).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _listAll(
    String filter,
    String value,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final data = await api.get(
        orgPath('/employees'),
        query: {filter: value, 'page': '$page', 'limit': '$_pageSize'},
      );
      final map = data is Map ? data : const {};
      final items = asMapList(
        data is Map ? data['items'] : data,
      ).map((m) => Map<String, dynamic>.from(snakeKeys(m) as Map)).toList();
      out.addAll(items);
      final total = asInt(map['total'], items.length);
      if (items.isEmpty || out.length >= total) break;
    }
    return out;
  }

  /// Team attendance, newest first: `GET /organizations/:orgId/attendance/records?employeeIds=a,b&from=&to=`.
  ///
  /// The server narrows `employeeIds` to the caller's reporting tree and silently drops the rest, so people the caller only
  /// reviews, or manages as a secondary manager, never show attendance here. Ids go in chunks of 40 to keep the URL short.
  /// Each row keeps the server's fields; `date` is normalised to `yyyy-MM-dd` and `status` to words (`half day`, `on leave`).
  Future<List<Map<String, dynamic>>> teamAttendance(
    List<String> employeeIds, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (employeeIds.isEmpty) return [];
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < employeeIds.length; i += 40) {
      final chunk = employeeIds.sublist(
        i,
        i + 40 > employeeIds.length ? employeeIds.length : i + 40,
      );
      final data = await api.get(
        orgPath('/attendance/records'),
        query: {
          'employeeIds': chunk.join(','),
          'from': ymd(from),
          'to': ymd(to),
        },
      );
      rows.addAll(asMapList(data));
    }
    final shaped = rows
        .map(
          (r) => {
            ...r,
            'date': asDateOnly(r['date']) ?? r['date']?.toString(),
            'status': (r['status'] ?? 'absent').toString().replaceAll('_', ' '),
          },
        )
        .toList();
    shaped.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    return shaped;
  }

  /// Today's birthdays: `GET /organizations/:orgId/dashboard/celebrations` -> `birthdays` (`full_name`, `department`, `avatar_url`).
  /// The server shows everyone's celebrations to every member; `designation` is not part of the answer, so the department
  /// takes its place in the list.
  Future<List<Map<String, dynamic>>> birthdaysToday() async {
    final data = await api.get(orgPath('/dashboard/celebrations'));
    final list = data is Map
        ? asMapList(data['birthdays'])
        : <Map<String, dynamic>>[];
    return [
      for (final b in list)
        {...b, 'designation': b['designation'] ?? b['department']},
    ];
  }

  /// How many people of the team are on approved leave on [day] (default today): `GET /organizations/:orgId/leaves/team-applications?status=approved&from=&to=`
  /// (the server limits the rows to the caller's reporting tree, secondary reports and reviewees, never the caller).
  /// Throws when the route is not available (an older server answers 404), so the screen can show "-".
  Future<int> onLeaveCount({DateTime? day}) async {
    final d = day ?? DateTime.now();
    final ymd =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await api.get(
      orgPath('/leaves/team-applications'),
      query: {'status': 'approved', 'from': ymd, 'to': ymd},
    );
    return asMapList(data)
        .map((r) => r['employee_id']?.toString())
        .whereType<String>()
        .toSet()
        .length;
  }

  /// Pending-approval counts: `GET /organizations/:orgId/dashboard/approval-counts`, only keys with a count above zero.
  /// For a manager the server returns just the leave (`approvals-requests-leaves`) and attendance regularization
  /// (`approvals-regularization`) queues of the caller's reports; other queues are HR's and are absent, not zero.
  Future<Map<String, int>> approvalCounts() async {
    final data = await api.get(orgPath('/dashboard/approval-counts'));
    final map = data is Map ? data : const {};
    return {for (final e in map.entries) e.key.toString(): asInt(e.value)};
  }
}
