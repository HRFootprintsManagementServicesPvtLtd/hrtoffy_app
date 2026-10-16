import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../repositories/chat_repository.dart';
import 'employee_ui.dart';

class CreateChannelDialog extends StatefulWidget {
  final Function() onCreated;

  /// Overridable for tests; defaults to the signed-in session.
  final ChatRepository? repository;

  const CreateChannelDialog({
    super.key,
    required this.onCreated,
    this.repository,
  });

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  late final ChatRepository _chat = widget.repository ?? ChatRepository();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allEmployees = [];
  List<Map<String, dynamic>> filteredEmployees = [];
  List<Map<String, dynamic>> selectedEmployees = [];
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
    debugPrint("[Messages] Searching employees: $query");
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

  Future<void> _createChannel() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Channel name is required")));
      return;
    }
    if (selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Add at least one member")));
      return;
    }

    setState(() => loading = true);
    try {
      // The API takes each member as {employeeId, userId}; people without a user id cannot be added.
      final members = <({String employeeId, String userId})>[
        for (final emp in selectedEmployees)
          if (emp['user_id'] != null && emp['id'] != null)
            (
              employeeId: emp['id'].toString(),
              userId: emp['user_id'].toString(),
            ),
      ];
      if (members.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add at least one member")),
        );
        return;
      }

      await _chat.createGroup(
        name: name,
        description: descriptionController.text.trim(),
        members: members,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Group channel created successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _handleError("Could not create the channel", e);
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
        height: MediaQuery.of(context).size.height * 0.8,
        width: MediaQuery.of(context).size.width * 0.9,
        child: loading && allEmployees.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Create Group Channel",
                        style: EmployeeUi.header(20),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: _inputDecoration(
                      hint: "Channel name (required)",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      hint: "Description (optional)",
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Add Members (${selectedEmployees.length})",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedEmployees.isNotEmpty)
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedEmployees.length,
                        itemBuilder: (context, index) {
                          final emp = selectedEmployees[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                emp['full_name'] ?? '',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () {
                                setState(
                                  () => selectedEmployees.removeAt(index),
                                );
                              },
                              deleteIcon: const Icon(Icons.close, size: 14),
                              backgroundColor: const Color(0xFFD7E8FF),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    onChanged: _filterEmployees,
                    decoration: _inputDecoration(
                      hint: "Search employees...",
                    ).copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredEmployees.isEmpty
                        ? Center(
                            child: Text(
                              "No employees found",
                              style: GoogleFonts.montserrat(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredEmployees.length,
                            itemBuilder: (context, index) {
                              final emp = filteredEmployees[index];
                              final isSelected = selectedEmployees.any(
                                (s) => s['user_id'] == emp['user_id'],
                              );

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: EmployeeUi.primary,
                                checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                contentPadding: EdgeInsets.zero,
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
                                secondary: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: null,
                                  child: emp['avatar_url'] == null
                                      ? Text(
                                          emp['full_name']?[0] ?? '?',
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      if (!isSelected)
                                        selectedEmployees.add(emp);
                                    } else {
                                      selectedEmployees.removeWhere(
                                        (s) => s['user_id'] == emp['user_id'],
                                      );
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : _createChannel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EmployeeUi.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Create Channel",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
