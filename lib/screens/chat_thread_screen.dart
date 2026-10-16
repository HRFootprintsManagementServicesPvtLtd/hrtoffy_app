import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

import '../core/polling.dart';
import '../repositories/chat_repository.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/employee_ui.dart';

class ChatThreadScreen extends StatefulWidget {
  final String channelId;
  final String title;

  /// Overridable for tests; default to the signed-in session and a 5 second poll.
  final ChatRepository? repository;
  final Duration pollInterval;

  const ChatThreadScreen({
    super.key,
    required this.channelId,
    required this.title,
    this.repository,
    this.pollInterval = const Duration(seconds: 5),
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  static const int _clientMaxFileMb = 10;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController messageController = TextEditingController();
  late final ChatRepository _chat = widget.repository ?? ChatRepository();
  Poller? _poller;
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool _sending = false;
  ChatSettings _settings = const ChatSettings();
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    try {
      _myUserId = _chat.currentUserId;
    } catch (_) {
      _myUserId = null;
    }
    loadMessages(initial: true);
    _loadSettings();
    // New messages arrive by polling (there is no push channel). One poller per screen, stopped in dispose.
    _poller = Poller(widget.pollInterval, _poll)..start();
  }

  @override
  void dispose() {
    _poller?.stop();
    _poller = null;
    _scrollController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _chat.settings();
      if (mounted) setState(() => _settings = s);
    } catch (_) {
      // the defaults (file sharing on, 10 MB) apply
    }
  }

  /// The same message list again (same ids in the same order, nothing deleted): nothing to redraw.
  bool _sameMessages(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['id'] != b[i]['id']) return false;
      if ((a[i]['attachments'] as List?)?.length !=
          (b[i]['attachments'] as List?)?.length)
        return false;
    }
    return true;
  }

  Future<void> loadMessages({bool initial = false}) async {
    try {
      final fresh = await _chat.messages(widget.channelId);
      if (!mounted) return;
      final grew = fresh.length > messages.length;
      if (_sameMessages(messages, fresh)) {
        if (loading) setState(() => loading = false);
        return;
      }
      setState(() {
        messages = fresh;
        loading = false;
      });
      if (initial || grew) scrollToBottom();
    } catch (_) {
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> _poll() => loadMessages();

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _chat.sendText(widget.channelId, text);
      messageController.clear();
      await loadMessages();
    } catch (e) {
      _snack(chatErrorText(e, 'Could not send the message. Please try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> pickFile() async {
    if (!_settings.allowFileSharing) {
      _snack('File sharing is turned off for your organization.');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (result == null) return;
      final picked = result.files.single;
      if (picked.path == null) return;

      final limitMb = _settings.maxFileSizeMb < _clientMaxFileMb
          ? _settings.maxFileSizeMb
          : _clientMaxFileMb;
      if (picked.size > limitMb * 1024 * 1024) {
        _snack(
          'Maximum file size is ${limitMb == limitMb.truncate() ? limitMb.truncate() : limitMb} MB',
        );
        return;
      }

      await sendAttachment(File(picked.path!));
    } catch (_) {
      debugPrint('[Chat] picking a file failed');
    }
  }

  Future<void> sendAttachment(File file) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final name = path.basename(file.path);
      await _chat.sendFile(
        widget.channelId,
        bytes: await file.readAsBytes(),
        fileName: name,
        contentType: lookupMimeType(file.path),
      );
      await loadMessages();
    } catch (e) {
      debugPrint('[Chat] sending the attachment failed');
      _snack(chatErrorText(e, 'Could not send the file. Please try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final m = messages[i];
                final isMine =
                    _myUserId != null &&
                    m['sender_user_id']?.toString() == _myUserId;
                return ChatMessageBubble(
                  key: ValueKey(m['id']),
                  message: m,
                  isMine: isMine,
                  resolveUrl: _chat.attachmentUrl,
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    onPressed: pickFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: GoogleFonts.montserrat(fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: EmployeeUi.primary,
                    child: IconButton(
                      onPressed: sendMessage,
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
