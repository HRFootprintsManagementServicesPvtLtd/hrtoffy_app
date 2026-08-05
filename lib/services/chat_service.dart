import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_conversation.dart';

import '../models/chat_message.dart';

class ChatService {

  final supabase =
      Supabase.instance.client;

  Future<List<ChatConversation>> loadConversations() async {
    try {
      debugPrint("[Messages] Loading conversations for current user");
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Optimized query: Get channels where the user is a member, including members and the latest message
      final response = await supabase
          .from('chat_channels')
          .select('''
            *,
            members:chat_channel_members(user_id),
            latest_message:chat_messages(content, created_at)
          ''')
          .eq('chat_channel_members.user_id', userId)
          .order('created_at', referencedTable: 'chat_messages', ascending: false)
          .limit(1, referencedTable: 'chat_messages');

      // The above query might be tricky with the !inner and filtering. 
      // Alternative: Get member records first, then batch fetch channels.
      final memberships = await supabase
          .from('chat_channel_members')
          .select('channel_id')
          .eq('user_id', userId);

      if (memberships.isEmpty) return [];
      final channelIds = memberships.map((m) => m['channel_id']).toList();

      debugPrint("[Messages] Fetching details for ${channelIds.length} channels");
      final List<dynamic> channelsData = await supabase
          .from('chat_channels')
          .select('created_at, *, chat_channel_members(user_id)')
          .inFilter('id', channelIds);

      final List<ChatConversation> conversations = [];

      // Fetch latest messages and other user profiles for DMs in parallel
      final List<Future> detailFutures = [];

      for (var channel in channelsData) {
        detailFutures.add(_getChannelDetails(channel, userId));
      }

      final results = await Future.wait(detailFutures);
      for (var res in results) {
        if (res != null) conversations.add(res);
      }

      conversations.sort((a, b) {
        final aTime = a.latestTime ?? DateTime(2000);
        final bTime = b.latestTime ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      debugPrint("[Messages] Loaded ${conversations.length} conversations");
      return conversations;
    } catch (e) {
      if (e is PostgrestException) {
        debugPrint("[Messages] loadConversations PostgrestException:\nMessage: ${e.message}\nDetails: ${e.details}\nHint: ${e.hint}\nCode: ${e.code}");
      } else {
        debugPrint("[Messages] loadConversations error: $e");
      }
      return [];
    }
  }

  Future<ChatConversation?> _getChannelDetails(Map<String, dynamic> channel, String currentUserId) async {
    final channelId = channel['id'];
    
    // Fetch latest message
    final latestMsg = await supabase
        .from('chat_messages')
        .select('content, created_at')
        .eq('channel_id', channelId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    String title = channel['name'] ?? channel['title'] ?? 'Group Chat';
    
    if (channel['channel_type'] == 'dm') {
      final members = List.from(channel['chat_channel_members'] ?? []);
      final otherMember = members.firstWhere((m) => m['user_id'] != currentUserId, orElse: () => null);
      
      if (otherMember != null) {
        final employee = await supabase
            .from('employee_records')
            .select('full_name')
            .eq('user_id', otherMember['user_id'])
            .maybeSingle();
        
        if (employee != null) {
          title = employee['full_name'] ?? 'Direct Message';
        }
      }
    }

    return ChatConversation.fromMap({
      'id': channelId,
      'title': title,
      'type': channel['channel_type'],
      'latest_message': latestMsg?['content'] ?? 'No messages yet',
      'latest_time': latestMsg?['created_at'] ?? channel['created_at'],
    });
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
