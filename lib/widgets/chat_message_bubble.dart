import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final String content =
        message['content'] ?? '';

    final String? fileUrl =
    message['file_url'];

    final String? fileType =
    message['file_type'];

    final bool isImage =
        fileType != null &&
            fileType.startsWith('image');

    return Align(
      alignment: isMine
          ? Alignment.centerRight
          : Alignment.centerLeft,

      child: Container(
        margin: const EdgeInsets.only(
          bottom: 12,
        ),

        padding: const EdgeInsets.all(12),

        constraints: BoxConstraints(
          maxWidth:
          MediaQuery.of(context)
              .size
              .width *
              0.75,
        ),

        decoration: BoxDecoration(
          color: isMine
              ? const Color(0xFFD9EBFF)
              : const Color(0xFFF1F1F1),

          borderRadius:
          BorderRadius.circular(18),
        ),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            // IMAGE PREVIEW
            if (isImage &&
                fileUrl != null)
              GestureDetector(
                onTap: () async {
                  final uri =
                  Uri.parse(fileUrl);

                  await launchUrl(
                    uri,
                    mode: LaunchMode
                        .externalApplication,
                  );
                },

                child: ClipRRect(
                  borderRadius:
                  BorderRadius.circular(
                      12),

                  child: Image.network(
                    fileUrl,
                    height: 180,
                    width: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // NORMAL FILE
            if (!isImage &&
                fileUrl != null)
              GestureDetector(
                onTap: () async {
                  final uri =
                  Uri.parse(fileUrl);

                  await launchUrl(
                    uri,
                    mode: LaunchMode
                        .externalApplication,
                  );
                },

                child: Container(
                  padding:
                  const EdgeInsets.all(
                      10),

                  decoration:
                  BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(
                        12),
                  ),

                  child: Row(
                    mainAxisSize:
                    MainAxisSize.min,

                    children: [
                      const Icon(
                        Icons.attach_file,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Flexible(
                        child: Text(
                          content,
                          overflow:
                          TextOverflow
                              .ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // TEXT MESSAGE
            if (content.isNotEmpty &&
                fileUrl == null)
              Text(
                content,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),

            const SizedBox(height: 6),

            Align(
              alignment:
              Alignment.bottomRight,

              child: Text(
                formatTime(
                  message['created_at'],
                ),

                style: TextStyle(
                  fontSize: 11,
                  color:
                  Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatTime(String? value) {
    if (value == null) return '';

    final dt =
    DateTime.parse(value).toLocal();

    final hour =
    dt.hour > 12
        ? dt.hour - 12
        : dt.hour;

    final minute = dt.minute
        .toString()
        .padLeft(2, '0');

    final ampm =
    dt.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $ampm';
  }
}
