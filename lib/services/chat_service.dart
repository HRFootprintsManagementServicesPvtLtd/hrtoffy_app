import 'package:flutter/foundation.dart';

import '../models/chat_conversation.dart';
import '../repositories/chat_repository.dart';

/// The conversation list for the Messages screens (employee and manager Engage tab).
/// All data comes from the HR Toffy API through [ChatRepository].
class ChatService {
  ChatService({ChatRepository? repository}) : _repository = repository;

  ChatRepository? _repository;
  ChatRepository get repository => _repository ??= ChatRepository();

  /// The signed-in user's conversations, newest first. A failed load gives an empty list (as before).
  Future<List<ChatConversation>> loadConversations() async {
    try {
      return await repository.channels();
    } catch (_) {
      debugPrint('[Messages] loading conversations failed');
      return [];
    }
  }
}
