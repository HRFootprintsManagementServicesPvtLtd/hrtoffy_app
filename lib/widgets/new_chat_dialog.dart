import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../repositories/chat_repository.dart';
import '../screens/chat_thread_screen.dart';
import 'employee_ui.dart';

class NewChatDialog extends StatefulWidget {
  final Function() onCreated;

  /// Overridable for tests; defaults to the signed-in session.
  final ChatRepository? repository;

  const NewChatDialog({super.key, required this.onCreated, this.repository});

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  late final ChatRepository _chat = widget.repository ?? ChatRepository();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allEmployees = [];
  List<Map<String, dynamic>> filteredEmployees = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // The API decides who may be listed (the organization's chat scope); the caller is excluded.
      allEmployees = await _chat.directory();
      filteredEmployees = allEmployees;
    } catch (e) {
      _handleError("Could not load employees", e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _filterEmployees(String query) {
    debugPrint("[Messages] Searching direct message users: $query");
    setState(() {
      if (query.isEmpty) {
        filteredEmployees = allEmployees;
      } else {
        final lowercaseQuery = query.toLowerCase();
        filteredEmployees = allEmployees.where((e) {
          final fullName = (e['full_name'] ?? '').toString().toLowerCase();
          final empId = '';
          final dept = (e['department'] ?? '').toString().toLowerCase();
          final desig = (e['designation'] ?? '').toString().toLowerCase();
          return fullName.contains(lowercaseQuery) ||
              empId.contains(lowercaseQuery) ||
              dept.contains(lowercaseQuery) ||
              desig.contains(lowercaseQuery);
        }).toList();
      }
    });
  }

  void _handleError(String title, dynamic e) {
    debugPrint("[Messages] $title");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chatErrorText(
              e,
              "$title. Please try again.",
              // Only the create/start calls: a 404 there is the server refusing to find the colleague, not a missing screen.
              notFound: title.startsWith("Could not load") ? kChatDirectoryNotFoundMessage : kChatStartNotFoundMessage,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startChat(Map<String, dynamic> employee) async {
    final selectedUserId = employee['user_id']?.toString();
    final selectedEmployeeId = employee['id']?.toString();
    if (selectedUserId == null || selectedEmployeeId == null) return;

    setState(() => loading = true);
    try {
      // The server finds the existing conversation or creates it.
      final channelId = await _chat.openDirectMessage(
        otherUserId: selectedUserId,
        otherEmployeeId: selectedEmployeeId,
      );

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
              channelId: channelId,
              title: (employee['full_name'] ?? 'Direct Message').toString(),
            ),
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      _handleError("Could not start the chat", e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.montserrat(fontSize: 13, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: EmployeeUi.primary, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.7,
        width: MediaQuery.of(context).size.width * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("New Direct Message", style: EmployeeUi.header(20)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: searchController,
              onChanged: _filterEmployees,
              decoration: _inputDecoration(
                hint: "Search employees...",
              ).copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: loading && allEmployees.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filteredEmployees.isEmpty
                  ? Center(
                      child: Text(
                        "No employees found",
                        style: GoogleFonts.montserrat(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredEmployees.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final emp = filteredEmployees[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          onTap: () => _startChat(emp),
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage: null,
                            child: emp['avatar_url'] == null
                                ? Text(
                                    emp['full_name']?[0] ?? '?',
                                    style: const TextStyle(fontSize: 14),
                                  )
                                : null,
                          ),
                          title: Text(
                            emp['full_name'] ?? '',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            "${emp['designation'] ?? ''} • ${emp['department'] ?? ''}",
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
