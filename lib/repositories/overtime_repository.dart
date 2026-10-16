import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in employee's own overtime records (read-only).
class OvertimeRepository extends BaseRepository {
  OvertimeRepository({super.auth});

  /// `GET /organizations/:orgId/employees/:employeeId/overtime/records`, newest `ot_date` first.
  ///
  /// The employee is the signed-in one (from the session, never looked up by email). The backend
  /// returns the raw `overtime_records` rows, so the UI reads them as-is: `ot_date`, `status`,
  /// `total_hours`, `rate_multiplier`, `ot_amount`, `ot_type`. Decimal columns arrive as strings
  /// (`"2.50"`) and are left untouched for display.
  Future<List<Map<String, dynamic>>> records() async {
    final data = await api.get(
      orgPath('/employees/$employeeId/overtime/records'),
    );
    final rows = asMapList(
      data,
    ).map((r) => Map<String, dynamic>.from(snakeKeys(r) as Map)).toList();
    rows.sort(
      (a, b) => (asDate(b['ot_date']) ?? DateTime(0)).compareTo(
        asDate(a['ot_date']) ?? DateTime(0),
      ),
    );
    return rows;
  }
}
