import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in person's own support tickets.
class HelpdeskRepository extends BaseRepository {
  HelpdeskRepository({super.auth});

  /// `GET /organizations/:orgId/helpdesk/tickets?employee_id=<own employee id>&limit=200` -> `{items, total, page, limit}`
  /// (`subject`, `category`, `status`, `created_at`, `employee_id`, `ticket_number`).
  ///
  /// For a manager the server also returns tickets that were addressed TO them (`recipient_type: manager`), and its
  /// `employee_id` filter does not narrow that. The screen is "My Tickets" (the original filtered on the caller's own
  /// employee id), so the answer is filtered again to tickets the caller raised: other people's tickets are never shown.
  Future<List<Map<String, dynamic>>> myTickets() async {
    final me = employeeId;
    final data = await api.get(
      orgPath('/helpdesk/tickets'),
      query: {'employee_id': me, 'limit': 200},
    );
    return asMapList(
      data,
    ).where((t) => t['employee_id']?.toString() == me).toList();
  }
}
