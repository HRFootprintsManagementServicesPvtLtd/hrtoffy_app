import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../widgets/chat_message_bubble.dart';

class ChatThreadScreen extends StatefulWidget {

  final String channelId;
  final String title;

  const ChatThreadScreen({
    super.key,
    required this.channelId,
    required this.title,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {

  final ScrollController _scrollController =
  ScrollController();

  void scrollToBottom() {

    WidgetsBinding.instance
        .addPostFrameCallback((_) {

      if (_scrollController.hasClients) {

        _scrollController.animateTo(

          _scrollController.position.maxScrollExtent,

          duration: const Duration(
            milliseconds: 300,
          ),

          curve: Curves.easeOut,
        );
      }
    });
  }

  final TextEditingController messageController =
  TextEditingController();

  List<Map<String, dynamic>> messages = [];

  bool loading = true;

  @override
  void initState() {

    super.initState();

    loadMessages();
    Supabase.instance.client
        .channel('public:chat_messages')

        .onPostgresChanges(
      event: PostgresChangeEvent.insert,

      schema: 'public',

      table: 'chat_messages',

      callback: (payload) {

        if (payload.newRecord['channel_id']
            == widget.channelId) {

          loadMessages();
        }
      },
    )
        .subscribe();
  }

  Future<void> loadMessages() async {

    try {

      final supabase = Supabase.instance.client;

      final result = await supabase
          .from('chat_messages')
          .select('''
*,
chat_attachments (
  file_url,
  file_type
)
''')
          .eq('channel_id', widget.channelId)
          .order(
        'created_at',
        ascending: true,
      );

      setState(() {

        messages =
        List<Map<String, dynamic>>
            .from(result);

        for (var message in messages) {

          final attachments =
          message['chat_attachments'];

          if (attachments != null &&
              attachments is List &&
              attachments.isNotEmpty) {

            final attachment =
                attachments.first;

            message['file_url'] =
            attachment['file_url'];

            message['file_type'] =
            attachment['file_type'];
          }
        }

        loading = false;
      });
      scrollToBottom();

    } catch (e) {

      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> sendMessage() async {

    final text = messageController.text.trim();

    if (text.isEmpty) return;

    try {

      final supabase = Supabase.instance.client;

      final userId = supabase.auth.currentUser!.id;

      await supabase
          .from('chat_messages')
          .insert({
        'channel_id': widget.channelId,
        'sender_user_id': userId,
        'content': text,
        'message_type': 'text',
      });

      messageController.clear();
      scrollToBottom();

      loadMessages();

    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> uploadFile() async {

    try {

      final result =
      await FilePicker.platform.pickFiles();

      if (result == null) return;

      final file =
      File(result.files.single.path!);

      final fileName =
          result.files.single.name;

      final supabase =
          Supabase.instance.client;

      final path =
          'chat-files/$fileName';

      await supabase.storage
          .from('chat-attachments')
          .upload(path, file);

      final publicUrl = supabase.storage
          .from('chat-attachments')
          .getPublicUrl(path);

      final userId =
          supabase.auth.currentUser!.id;

      await supabase
          .from('chat_messages')
          .insert({

        'channel_id': widget.channelId,

        'sender_user_id':
        Supabase.instance.client
            .auth.currentUser!
            .id,

        'content': fileName,

        'attachment_url': publicUrl,

        'message_type': 'file',
      });

      loadMessages();

    } catch (e) {

      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
          title: Text(widget.title)
      ),

      body: Column(

        children: [

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {

                final message = messages[index];

                final isMine =
                    message['sender_user_id']?.toString() ==
                        Supabase.instance.client.auth.currentUser?.id;

                return ChatMessageBubble(
                  message: message,
                  isMine: isMine,
                );
              },
            ),
          ),

          Container(

            padding: const EdgeInsets.all(10),

            child: Row(

              children: [

                IconButton(
                  onPressed: uploadFile,
                  icon: const Icon(
                    Icons.attach_file,
                  ),
                ),

                Expanded(
                  child: TextField(
                    controller: messageController,

                    decoration: InputDecoration(
                      hintText: "Type message...",
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                CircleAvatar(

                  radius: 26,

                  child: IconButton(
                    onPressed: sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
