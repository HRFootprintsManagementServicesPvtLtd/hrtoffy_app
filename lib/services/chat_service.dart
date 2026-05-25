import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_conversation.dart';

import '../models/chat_message.dart';

class ChatService {

  final supabase =
      Supabase.instance.client;

  Future<List<ChatConversation>>
  loadConversations() async {

    final userId =
        supabase.auth.currentUser!.id;

    final memberships = await supabase
        .from('chat_channel_members')
        .select()
        .eq('user_id', userId);

    final List<ChatConversation>
    conversations = [];

    for (final member in memberships) {

      final channelId =
      member['channel_id'];

      final channel = await supabase
          .from('chat_channels')
          .select()
          .eq('id', channelId)
          .single();

      final latestMessage =
      await supabase
          .from('chat_messages')
          .select()
          .eq(
        'channel_id',
        channelId,
      )
          .order(
        'created_at',
        ascending: false,
      )
          .limit(1)
          .maybeSingle();

      String title =
          channel['name'] ?? '';

      if (channel['channel_type']
          == 'dm') {

        final members =
        await supabase
            .from(
          'chat_channel_members',
        )
            .select()
            .eq(
          'channel_id',
          channelId,
        );

        final otherUsers = members.where(
              (m) => m['user_id'] != userId,
        ).toList();

        if (otherUsers.isEmpty) {
          continue;
        }

        final otherUser = otherUsers.first;

        final employee =
        await supabase
            .from(
          'employee_records',
        )
            .select()
            .eq(
          'user_id',
          otherUser['user_id'],
        )
            .maybeSingle();

        if (employee != null) {

          title =
              employee['full_name']
                  ?? 'Conversation';
        }
      }

      conversations.add(

        ChatConversation.fromMap({

          'id': channel['id'],

          'title': title,

          'type':
          channel['channel_type'],

          'latest_message':
          latestMessage?['content']
              ?? '',

          'latest_time':
          latestMessage?[
          'created_at'],
        }),
      );
    }

    conversations.sort((a, b) {

      final aTime =
          a.latestTime ??
              DateTime(2000);

      final bTime =
          b.latestTime ??
              DateTime(2000);

      return bTime.compareTo(aTime);
    });

    return conversations;
  }

  Future<List<ChatMessage>>
  loadMessages(
      String channelId,
      ) async {

    final result = await supabase
        .from('chat_messages')
        .select()
        .eq('channel_id', channelId)
        .order(
      'created_at',
      ascending: true,
    );

    return result
        .map<ChatMessage>(
          (e) =>
          ChatMessage.fromMap(e),
    )
        .toList();
  }
}
