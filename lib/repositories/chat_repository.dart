import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import '../models/chat_conversation.dart';
import 'base_repository.dart';
import 'file_repository.dart';

/// A short message that is safe to show for a failed chat call: nothing about URLs, tokens or server internals.
/// Refusals the server words for the user (403/404/409/422...) are passed on; everything else is [fallback].
/// [notFound] replaces the server's 404 text where that text would mislead (starting a chat: "Employee not found" reads as if
/// the colleague does not exist, while the colleague was just listed in the directory).
String chatErrorText(Object e, String fallback, {String? notFound}) {
  if (e is ApiException) {
    if (e.isNetworkError)
      return 'No connection. Please check your internet and try again.';
    if (e.isNotFound && notFound != null) return notFound;
    if (e.isServerError || e.isUnauthorized) return fallback;
    return e.message.isEmpty ? fallback : e.message;
  }
  return fallback;
}

/// The organization's chat settings, with the API's own defaults when a value is missing.
class ChatSettings {
  const ChatSettings({
    this.allowFileSharing = true,
    this.maxFileSizeMb = 10,
    this.allowGroupChannels = true,
  });

  final bool allowFileSharing;
  final num maxFileSizeMb;
  final bool allowGroupChannels;

  factory ChatSettings.fromMap(Map<String, dynamic> m) => ChatSettings(
    allowFileSharing: m['allow_file_sharing'] != false,
    maxFileSizeMb: asNum(m['max_file_size_mb']) ?? 10,
    allowGroupChannels: m['allow_group_channels'] != false,
  );
}

/// Messages and channels of the signed-in user. Used by employees and managers alike (same routes).
///
/// The chat tables are keyed by the signed-in USER id ([currentUserId]), which is also what the API
/// stores as `sender_user_id`. There is no push channel: screens poll (see `core/polling.dart`).
class ChatRepository extends BaseRepository {
  ChatRepository({super.auth});

  static const attachmentBucket = 'chat-attachments';

  late final FileRepository _files = FileRepository(auth: auth);

  /// The signed-in user's id, as the server records it in `sender_user_id`.
  String get currentUserId => user.id;

  // ---- channels ---------------------------------------------------------------------------------

  /// `GET /organizations/:orgId/chat/channels` - one call for the whole list, newest activity first.
  Future<List<ChatConversation>> channels() async {
    final data = await api.get(orgPath('/chat/channels'));
    final list = asMapList(data).map(_conversation).toList();
    list.sort(
      (a, b) => (b.latestTime ?? DateTime(2000)).compareTo(
        a.latestTime ?? DateTime(2000),
      ),
    );
    return list;
  }

  static ChatConversation _conversation(Map<String, dynamic> c) {
    final type = (c['channel_type'] ?? '').toString();
    final name = c['name']?.toString();
    final other = c['other_member_name']?.toString();
    final title = type == 'dm'
        ? ((other != null && other.isNotEmpty)
              ? other
              : ((name != null && name.isNotEmpty) ? name : 'Direct Message'))
        : ((name != null && name.isNotEmpty) ? name : 'Group Chat');
    return ChatConversation.fromMap({
      'id': c['id'].toString(),
      'title': title,
      'type': type,
      'latest_message': c['last_message'] ?? 'No messages yet',
      'latest_time': c['last_message_at'] ?? c['created_at'],
      'unread_count': asInt(c['unread_count']),
    });
  }

  /// `POST /organizations/:orgId/chat/channels/dm` - the server finds the existing DM or creates one.
  /// Returns the channel id.
  Future<String> openDirectMessage({
    required String otherUserId,
    required String otherEmployeeId,
  }) async {
    final data = await api.post(
      orgPath('/chat/channels/dm'),
      body: {'otherUserId': otherUserId, 'otherEmployeeId': otherEmployeeId},
    );
    return _channelId(data);
  }

  /// `POST /organizations/:orgId/chat/channels/group`. Each member is `{employeeId, userId}`. Returns the channel id.
  Future<String> createGroup({
    required String name,
    String? description,
    required List<({String employeeId, String userId})> members,
  }) async {
    final data = await api.post(
      orgPath('/chat/channels/group'),
      body: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'members': [
          for (final m in members)
            {'employeeId': m.employeeId, 'userId': m.userId},
        ],
      },
    );
    return _channelId(data);
  }

  static String _channelId(dynamic data) {
    final id = data is Map ? data['id']?.toString() : null;
    if (id == null || id.isEmpty)
      throw const ApiException(500, 'Unexpected response from the server');
    return id;
  }

  // ---- directory and settings -------------------------------------------------------------------

  /// `GET /organizations/:orgId/chat/employees` - colleagues the caller may chat with
  /// (`id`, `full_name`, `department`, `designation`, `avatar_url`, `user_id`).
  Future<List<Map<String, dynamic>>> directory() async {
    final data = await api.get(orgPath('/chat/employees'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/chat/settings`
  Future<ChatSettings> settings() async {
    final data = await api.get(orgPath('/chat/settings'));
    return ChatSettings.fromMap(
      data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }

  // ---- messages ---------------------------------------------------------------------------------

  /// `GET /organizations/:orgId/chat/channels/:channelId/messages` - `data.messages`, oldest first,
  /// without deleted ones. File messages carry `attachments: [{file_name, file_url, file_type, file_size}]`
  /// where `file_url` is a private `bucket/path` reference (open it with [attachmentUrl]).
  ///
  /// Known server limit: it returns the OLDEST 200 messages of the channel.
  Future<List<Map<String, dynamic>>> messages(String channelId) async {
    final data = await api.get(orgPath('/chat/channels/$channelId/messages'));
    final raw = data is Map ? data['messages'] : data;
    final rows = asMapList(raw).where((m) => m['is_deleted'] != true).map((m) {
      final atts = m['attachments'];
      return <String, dynamic>{
        ...m,
        'attachments': atts is List
            ? [
                for (final a in atts)
                  if (a is Map) Map<String, dynamic>.from(a),
              ]
            : <Map<String, dynamic>>[],
      };
    }).toList();
    rows.sort(
      (a, b) => (asDate(a['created_at']) ?? DateTime(0)).compareTo(
        asDate(b['created_at']) ?? DateTime(0),
      ),
    );
    return rows;
  }

  /// `POST /organizations/:orgId/messages` with `{channelId, content, messageType: 'text'}`.
  /// (`sender_user_id` is set by the server.) Returns the created message.
  Future<Map<String, dynamic>> sendText(String channelId, String content) =>
      _postMessage(channelId, content, 'text');

  Future<Map<String, dynamic>> _postMessage(
    String channelId,
    String content,
    String type,
  ) async {
    final data = await api.post(
      orgPath('/messages'),
      body: {'channelId': channelId, 'content': content, 'messageType': type},
    );
    if (data is! Map || data['id'] == null)
      throw const ApiException(500, 'Unexpected response from the server');
    return Map<String, dynamic>.from(data);
  }

  /// Sends a file: upload to the private `chat-attachments` bucket (with the channel), then a
  /// `file` message, then its attachment record. Returns the created message.
  ///
  /// If the last step fails the message exists without its file (the API has no single call for this).
  Future<Map<String, dynamic>> sendFile(
    String channelId, {
    required List<int> bytes,
    required String fileName,
    String? contentType,
  }) async {
    final up = await _files.upload(
      bucket: attachmentBucket,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      channelId: channelId,
    );
    final message = await _postMessage(channelId, '📎 $fileName', 'file');
    await api.post(
      orgPath('/message-attachments'),
      body: {
        'messageId': message['id'].toString(),
        'fileName': fileName,
        'fileUrl': up.ref,
        'fileSize': up.size,
        'fileType': contentType,
      },
    );
    return message;
  }

  /// A short-lived signed link for an attachment reference (`GET /organizations/:orgId/files/url`).
  Future<String> attachmentUrl(String ref) =>
      _files.url(ref, bucketHint: attachmentBucket);

  // ---- read state (available, not used by the screens yet) ------------------------------------------

  /// `PUT /organizations/:orgId/chat/channels/:channelId/read`
  Future<void> markRead(String channelId) async {
    await api.put(orgPath('/chat/channels/$channelId/read'));
  }

  /// `GET /organizations/:orgId/chat/unread-count` - `data.total`.
  Future<int> unreadCount() async {
    final data = await api.get(orgPath('/chat/unread-count'));
    return data is Map ? asInt(data['total']) : 0;
  }
}

/// Shown when starting a chat or creating a channel answers 404 ("Employee not found"). The colleague WAS just listed in
/// the directory, so this is the server failing to look them up for the chat, not the colleague being absent.
const String kChatStartNotFoundMessage =
    "Couldn't start this chat: the server couldn't look this colleague up for chat right now. Please try again later or contact HR.";

/// Shown when loading the colleague directory answers 404 (the route is not on this server).
const String kChatDirectoryNotFoundMessage =
    "Couldn't load your colleagues right now. Please try again later or contact HR.";
