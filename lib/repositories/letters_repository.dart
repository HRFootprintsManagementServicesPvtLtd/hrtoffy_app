import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in person's own letters.
class LettersRepository extends BaseRepository {
  LettersRepository({super.auth});

  /// `GET /organizations/:orgId/letters/employee/<own employee id>?limit=200` -> `{rows, total, page, limit}` (`rows`, not
  /// `items`). Without letters.manage the server answers only for the caller's own id and only with letters that were
  /// sent (`sent_at` set). Rows: `letter_category`, `subject_line`, `status`, `sent_at`, `created_at`.
  Future<List<Map<String, dynamic>>> myLetters() async {
    final me = employeeId;
    final data = await api.get(
      orgPath('/letters/employee/$me'),
      query: {'limit': 200},
    );
    final raw = data is Map && data['rows'] != null ? data['rows'] : data;
    return asMapList(
      raw,
    ).where((l) => (l['employee_id']?.toString() ?? me) == me).toList();
  }
}
