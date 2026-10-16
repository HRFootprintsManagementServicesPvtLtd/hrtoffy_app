import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Read-only disciplinary cases for a manager. The server scopes every answer to the caller's reporting tree (a case it
/// may not show is "not found") and needs `disciplinary.view`; opening, acting on and closing a case need
/// `disciplinary.manage` (HR) and are deliberately not part of this class.
///
/// Shapes (from the backend's Prisma rows, snake_case): a case has `id`, `employee_id`, `case_number`, `category`,
/// `severity`, `status`, `incident_date`, `incident_description`, `issued_at`, `response_due_at`, `closed_at`,
/// `final_action`, `final_remarks`, plus embedded `disciplinary_actions` / `disciplinary_responses`. An action has
/// `action_type`, `action_date`, `effective_date`, `suspension_days`, `fine_amount`, `remarks`, `created_at`; a response
/// has `employee_id`, `response_text`, `attachment_name`, `submitted_at`. Every field is read tolerantly.
class DisciplinaryRepository extends BaseRepository {
  DisciplinaryRepository({super.auth});

  static const _pageSize = 200;
  static const _maxPages = 10;

  /// `GET /organizations/:orgId/disciplinary/cases?limit=200&page=n` -> `{items, total, page, limit}`, newest first.
  /// [status] narrows by the exact status value; null reads every case.
  Future<List<Map<String, dynamic>>> cases({String? status}) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final data = await api.get(
        orgPath('/disciplinary/cases'),
        query: {
          'limit': '$_pageSize',
          'page': '$page',
          if (status != null) 'status': status,
        },
      );
      final items = asMapList(data).map(_snake).toList();
      out.addAll(items);
      final total = data is Map
          ? asInt(data['total'], items.length)
          : items.length;
      if (items.isEmpty || out.length >= total) break;
    }
    return out;
  }

  /// `GET /organizations/:orgId/disciplinary/cases/:caseId` (the case with its actions and responses embedded).
  Future<Map<String, dynamic>> caseById(String caseId) async {
    final data = await api.get(orgPath('/disciplinary/cases/$caseId'));
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// `GET /organizations/:orgId/disciplinary/cases/:caseId/actions` (oldest first).
  Future<List<Map<String, dynamic>>> actions(String caseId) async {
    final data = await api.get(orgPath('/disciplinary/cases/$caseId/actions'));
    return asMapList(data).map(_snake).toList();
  }

  /// `GET /organizations/:orgId/disciplinary/cases/:caseId/responses` (oldest first).
  Future<List<Map<String, dynamic>>> responses(String caseId) async {
    final data = await api.get(
      orgPath('/disciplinary/cases/$caseId/responses'),
    );
    return asMapList(data).map(_snake).toList();
  }

  /// Employee id -> full name, one call: `GET /organizations/:orgId/employees/summaries`. The case rows carry the
  /// employee id only. A failure means "names unknown" for the caller.
  Future<Map<String, String>> employeeNames() async {
    final data = await api.get(orgPath('/employees/summaries'));
    final out = <String, String>{};
    for (final raw in asMapList(data)) {
      final e = _snake(raw);
      final id = e['id']?.toString();
      final name = e['full_name']?.toString();
      if (id != null && name != null && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  static Map<String, dynamic> _snake(Map m) =>
      Map<String, dynamic>.from(snakeKeys(m) as Map);
}
