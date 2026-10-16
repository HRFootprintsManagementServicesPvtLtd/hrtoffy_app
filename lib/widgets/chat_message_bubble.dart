import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Turns a stored private file reference into a short-lived link (the Files API signed URL).
typedef AttachmentUrlResolver = Future<String> Function(String ref);

class ChatMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;

  /// Opens private attachments. Without it an attachment is shown by name only and cannot be opened.
  final AttachmentUrlResolver? resolveUrl;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.resolveUrl,
  });

  /// The message's file, from the API's `attachments[]` (first entry), or null for a plain text message.
  /// `ref` is the private `bucket/path` reference: it is never shown or opened directly.
  static ({String ref, String name, String? type})? attachmentOf(
    Map<String, dynamic> message,
  ) {
    final list = message['attachments'];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    final a = Map<String, dynamic>.from(list.first as Map);
    final ref = a['file_url']?.toString();
    if (ref == null || ref.isEmpty) return null;
    final name = (a['file_name'] ?? message['content'] ?? 'Attachment')
        .toString();
    return (ref: ref, name: name, type: a['file_type']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final String content = (message['content'] ?? '').toString();
    final attachment = attachmentOf(message);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFFD9EBFF) : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              AttachmentTile(
                key: ValueKey(attachment.ref),
                reference: attachment.ref,
                name: attachment.name,
                fileType: attachment.type,
                resolveUrl: resolveUrl,
              ),

            // TEXT MESSAGE
            if (content.isNotEmpty && attachment == null)
              Text(content, style: const TextStyle(fontSize: 16)),

            const SizedBox(height: 6),

            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                formatTime(message['created_at']),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatTime(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';

    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $ampm';
  }
}

/// A file in a chat message. Images preview through a signed link; other files show their name.
/// Tapping asks the Files API for a fresh signed link and opens it; the raw reference is never exposed.
class AttachmentTile extends StatefulWidget {
  const AttachmentTile({
    super.key,
    required this.reference,
    required this.name,
    required this.fileType,
    required this.resolveUrl,
  });

  final String reference;
  final String name;
  final String? fileType;
  final AttachmentUrlResolver? resolveUrl;

  bool get isImage => fileType != null && fileType!.startsWith('image');

  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  /// Resolved once per tile, so the list rebuilding on every poll does not ask for the link again.
  Future<String>? _preview;

  @override
  void initState() {
    super.initState();
    final resolve = widget.resolveUrl;
    if (widget.isImage && resolve != null) _preview = resolve(widget.reference);
  }

  Future<void> _open() async {
    final resolve = widget.resolveUrl;
    if (resolve == null) return;
    try {
      final url = await resolve(widget.reference);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the file.')));
    }
  }

  Widget _fileRow() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.isImage ? Icons.image_outlined : Icons.attach_file),
          const SizedBox(width: 8),
          Flexible(child: Text(widget.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return GestureDetector(
      onTap: _open,
      child: preview == null
          ? _fileRow()
          : FutureBuilder<String>(
              future: preview,
              builder: (context, snap) {
                if (snap.hasError) return _fileRow();
                if (!snap.hasData) {
                  return const SizedBox(
                    height: 180,
                    width: 180,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    snap.data!,
                    height: 180,
                    width: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fileRow(),
                  ),
                );
              },
            ),
    );
  }
}
