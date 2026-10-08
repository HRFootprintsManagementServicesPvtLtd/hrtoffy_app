import '../core/api/json_case.dart';
import 'base_repository.dart';

class NotificationPage {
  const NotificationPage(this.items, this.total, this.unread);

  /// Newest first. Rows keep the snake_case names the UI reads (`title`, `body`, `read`, `created_at`, ...).
  final List<Map<String, dynamic>> items;
  final int total;

  /// Unread count across ALL of the user's notifications (not just this page).
  final int unread;
}

/// In-app notifications. There is no push channel to the app for new rows, so
/// screens poll [list] (see `core/polling.dart`).
class NotificationRepository extends BaseRepository {
  NotificationRepository({super.auth});

  /// `GET /organizations/:orgId/notifications` - the server caps `limit` at 100.
  Future<NotificationPage> list({int limit = 100, int offset = 0}) async {
    final data = await api.get(orgPath('/notifications'), query: {'limit': limit, 'offset': offset});
    final items = asMapList(data);
    final map = data is Map ? data : const {};
    final unread = map['unread'] != null ? asInt(map['unread']) : items.where((n) => n['read'] == false).length;
    return NotificationPage(items, asInt(map['total'], items.length), unread);
  }

  /// `POST /organizations/:orgId/notifications/:id/read`
  Future<void> markRead(String id) async {
    await api.post(orgPath('/notifications/$id/read'));
  }

  /// `POST /organizations/:orgId/notifications/mark-all-read`
  Future<void> markAllRead() async {
    await api.post(orgPath('/notifications/mark-all-read'));
  }
}
