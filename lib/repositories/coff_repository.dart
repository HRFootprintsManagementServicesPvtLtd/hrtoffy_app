import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Compensatory-off (C-Off) requests of the caller's team, for the manager Time hub.
class CoffRepository extends BaseRepository {
  CoffRepository({super.auth});

  /// `GET /organizations/:orgId/leaves/coff-requests?scope=team&status=` (newest first, up to 500). [history] asks for
  /// `approved,rejected`, otherwise `pending`. Rows carry `employee_records {full_name, employee_id, department}`, and the
  /// server says per row whether the caller may decide it now (`can_decide`) and, if not, who it waits for (`required_role`).
  /// The caller's own rows are never included for `scope=team`. Throws [ApiException] (a 404 means an older server).
  Future<List<Map<String, dynamic>>> teamRequests({
    required bool history,
  }) async {
    final data = await api.get(
      orgPath('/leaves/coff-requests'),
      query: {
        'scope': 'team',
        'status': history ? 'approved,rejected' : 'pending',
      },
    );
    return asMapList(
      data,
    ).map((m) => Map<String, dynamic>.from(snakeKeys(m) as Map)).toList();
  }

  /// `POST /organizations/:orgId/leaves/coff-requests/:id/decide` with `{decision, comments?}`. A rejection needs a
  /// reason (refused here before any request). The server answers 409 when the request is no longer pending or the credit
  /// is refused (for example the monthly cap).
  Future<void> decide(
    String id, {
    required bool approve,
    String? comments,
  }) async {
    final text = comments?.trim() ?? '';
    if (!approve && text.isEmpty) throw ArgumentError('A reason is required');
    await api.post(
      orgPath('/leaves/coff-requests/$id/decide'),
      body: {
        'decision': approve ? 'approve' : 'reject',
        if (text.isNotEmpty) 'comments': text,
      },
    );
  }
}
