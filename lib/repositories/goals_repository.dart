import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in employee's own performance goals (read-only).
///
/// The PMS API is NOT organization-prefixed (`/pms/...`): the caller's organization and employee
/// come from the access token.
class GoalsRepository extends BaseRepository {
  GoalsRepository({super.auth});

  /// Columns the API returns as decimals/integers; the UI gets numbers whatever the wire format.
  static const _numeric = [
    'weightage',
    'progress_percentage',
    'achievement_status',
    'self_rating',
    'manager_rating',
    'reviewer_rating',
    'final_rating',
  ];

  /// `GET /pms/goals`: the goals of the ACTIVE performance cycle (no `employeeId` or `cycleId` is
  /// sent, so the token identifies the employee and the server picks the active cycle). Newest first.
  ///
  /// The server withholds the manager's and reviewer's ratings and comments and the final rating from
  /// the owner until their report for the cycle is final: those fields arrive as `null` and are
  /// passed on exactly like that.
  Future<List<Map<String, dynamic>>> goals() async {
    final data = await api.get('/pms/goals');
    final rows = asMapList(data).map(_normalize).toList();
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(snakeKeys(raw) as Map);
    for (final k in _numeric) {
      if (m.containsKey(k)) m[k] = asNum(m[k]);
    }
    return m;
  }
}
