class ChatMessage {

  final String id;

  final String channelId;

  final String senderId;

  final String content;

  final String messageType;

  final String? attachmentUrl;

  final DateTime createdAt;

  ChatMessage({

    required this.id,

    required this.channelId,

    required this.senderId,

    required this.content,

    required this.messageType,

    this.attachmentUrl,

    required this.createdAt,
  });

  factory ChatMessage.fromMap(
      Map<String, dynamic> map,
      ) {

    return ChatMessage(

      id: map['id'] ?? '',

      channelId: map['channel_id'] ?? '',

      senderId:
      map['sender_user_id'] ?? '',

      content: map['content'] ?? '',

      messageType:
      map['message_type'] ?? 'text',

      attachmentUrl:
      map['attachment_url'],

      createdAt: DateTime.parse(
        map['created_at'],
      ),
    );
  }
}
