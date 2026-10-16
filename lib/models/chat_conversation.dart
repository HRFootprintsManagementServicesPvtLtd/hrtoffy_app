class ChatConversation {

  final String id;

  final String title;

  final String type;

  final String latestMessage;

  final DateTime? latestTime;

  final String? avatar;

  /// Unread messages in this conversation (from the API; not shown in the UI yet).
  final int unreadCount;

  ChatConversation({

    required this.id,

    required this.title,

    required this.type,

    required this.latestMessage,

    required this.latestTime,

    this.avatar,

    this.unreadCount = 0,
  });

  factory ChatConversation.fromMap(
      Map<String, dynamic> map,
      ) {

    return ChatConversation(

      id: map['id'] ?? '',

      title: map['title'] ?? '',

      type: map['type'] ?? '',

      latestMessage:
      map['latest_message'] ?? '',

      latestTime:
      map['latest_time'] != null
          ? DateTime.parse(
        map['latest_time'],
      )
          : null,

      avatar: map['avatar'],

      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}
