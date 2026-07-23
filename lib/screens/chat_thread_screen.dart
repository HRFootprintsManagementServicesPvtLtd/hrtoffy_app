import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/employee_ui.dart';

class ChatThreadScreen extends StatefulWidget {
  final String channelId;
  final String title;
  const ChatThreadScreen({super.key, required this.channelId, required this.title});
  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController messageController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadMessages();
    Supabase.instance.client.channel('public:chat_messages').onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'chat_messages', callback: (payload) { if (payload.newRecord['channel_id'] == widget.channelId) loadMessages(); }).subscribe();
  }

  void scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); }); }

  Future<void> loadMessages() async {
    try {
      final supabase = Supabase.instance.client;
      final result = await supabase.from('chat_messages').select('*, chat_attachments(file_url, file_type)').eq('channel_id', widget.channelId).order('created_at', ascending: true);
      setState(() { messages = List<Map<String, dynamic>>.from(result); loading = false; });
      scrollToBottom();
    } catch (e) { setState(() { loading = false; }); }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      await supabase.from('chat_messages').insert({'channel_id': widget.channelId, 'sender_user_id': userId, 'content': text, 'message_type': 'text'});
      messageController.clear();
      loadMessages();
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: EmployeeUi.appBar(title: widget.title),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: messages.length,
              itemBuilder: (context, i) {
                final m = messages[i];
                final isMine = m['sender_user_id']?.toString() == Supabase.instance.client.auth.currentUser?.id;
                return ChatMessageBubble(message: m, isMine: isMine);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))]),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.attach_file, color: Colors.grey)),
                  Expanded(child: TextField(controller: messageController, decoration: InputDecoration(hintText: "Type a message...", hintStyle: GoogleFonts.montserrat(fontSize: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), filled: true, fillColor: const Color(0xFFF3F4F6), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)))),
                  const SizedBox(width: 8),
                  CircleAvatar(backgroundColor: EmployeeUi.primary, child: IconButton(onPressed: sendMessage, icon: const Icon(Icons.send, color: Colors.white, size: 18))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
