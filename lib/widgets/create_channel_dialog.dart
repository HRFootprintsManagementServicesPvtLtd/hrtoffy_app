import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'employee_ui.dart';

class CreateChannelDialog extends StatefulWidget {
  final Function() onCreated;

  const CreateChannelDialog({
    super.key,
    required this.onCreated,
  });

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final supabase = Supabase.instance.client;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allEmployees = [];
  List<Map<String, dynamic>> filteredEmployees = [];
  List<Map<String, dynamic>> selectedEmployees = [];
  bool loading = true;
  String? organizationId;
  String? currentUserId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final authUser = supabase.auth.currentUser;
      debugPrint("[Messages] Current auth.uid(): ${authUser?.id}");
      if (authUser == null) throw Exception("User not authenticated");
      currentUserId = authUser.id;

      debugPrint("[Messages] Resolving employee record for user_id: $currentUserId");
      // Use exact resolution logic as Leave/Travel
      final currentEmp = await supabase
          .from('employee_records')
          .select('id, organization_id, status')
          .eq('user_id', currentUserId!)
          .maybeSingle();

      debugPrint("[Messages] Resolved employee record: $currentEmp");
      if (currentEmp == null) {
        debugPrint("[Messages] ERROR: Active employee record not found for user_id: $currentUserId");
        throw Exception("Active employee record not found");
      }
      
      final empId = currentEmp['id'];
      organizationId = currentEmp['organization_id']?.toString();
      
      debugPrint("[Messages] Resolved employee id: $empId");
      debugPrint("[Messages] Resolved organization id: $organizationId");

      if (organizationId != null) {
        await _loadOrganizationMembers();
      } else {
        debugPrint("[Messages] ERROR: Organization ID is null for employee: $empId");
      }
    } catch (e) {
      _handleError("Initialization Error", e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadOrganizationMembers() async {
    try {
      debugPrint("[Messages] Loading organization members. Query: organization_id=$organizationId, status=active, exclude current user");
      // Fetch ONLY permitted columns
      final result = await supabase.rpc(
        'get_chat_directory',
        params: {
          'p_org_id': organizationId!,
        },
      );
      debugPrint("=== EMPLOYEE RESULT START ===");
      debugPrint(result.toString());
      debugPrint("Employee Count: ${result.length}");
      debugPrint("=== EMPLOYEE RESULT END ===");
      allEmployees = List<Map<String, dynamic>>.from(result);
      debugPrint("[Messages] Number of employees returned: ${allEmployees.length}");
      debugPrint("[Messages] Employee IDs: ${allEmployees.map((e) => e['id']).toList()}");
      debugPrint("[Messages] Employee names: ${allEmployees.map((e) => e['full_name']).toList()}");
      
      filteredEmployees = allEmployees;
    } on PostgrestException catch (e) {
      debugPrint("[Messages] Load Members - PostgrestException:\nMessage: ${e.message}\nDetails: ${e.details}\nHint: ${e.hint}\nCode: ${e.code}");
      rethrow;
    } catch (e) {
      debugPrint("[Messages] Load Members Error: $e");
      rethrow;
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
    if (e is PostgrestException) {
      debugPrint("[Messages] $title - PostgrestException:\nMessage: ${e.message}\nDetails: ${e.details}\nHint: ${e.hint}\nCode: ${e.code}");
    } else {
      debugPrint("[Messages] $title: $e");
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$title: ${e.toString()}"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createChannel() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Channel name is required")));
      return;
    }
    if (selectedEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add at least one member")));
      return;
    }

    setState(() => loading = true);
    try {
      debugPrint("[Messages] Creating channel: $name");
      debugPrint("========== CREATE GROUP ==========");
      debugPrint("organizationId = $organizationId");
      debugPrint("currentUserId = $currentUserId");
      debugPrint("name = ${nameController.text}");
      debugPrint("==================================");

      // Build arrays required by the RPC
      final memberUserIds = selectedEmployees
          .map((e) => e['user_id'])
          .where((e) => e != null)
          .toList();

      final memberEmployeeIds = selectedEmployees
          .map((e) => e['id'])
          .where((e) => e != null)
          .toList();

      debugPrint("RPC USER IDS: $memberUserIds");
      debugPrint("RPC EMP IDS : $memberEmployeeIds");

      final channelId = await supabase.rpc(
        'create_chat_channel',
        params: {
          'p_org_id': organizationId,
          'p_channel_type': 'group',
          'p_name': name,
          'p_description': descriptionController.text.trim(),
          'p_member_user_ids': memberUserIds,
          'p_member_employee_ids': memberEmployeeIds,
        },
      );

      debugPrint("Created Channel ID => $channelId");
      
      debugPrint("[Messages] Channel and members successfully created");
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Group channel created successfully"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _handleError("Create Channel Error", e);
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
                      Text("Create Group Channel", style: EmployeeUi.header(20)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: _inputDecoration(hint: "Channel name (required)"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: _inputDecoration(hint: "Description (optional)"),
                  ),
                  const SizedBox(height: 20),
                  Text("Add Members (${selectedEmployees.length})",
                      style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
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
                              label: Text(emp['full_name'] ?? '', style: const TextStyle(fontSize: 12)),
                              onDeleted: () {
                                setState(() => selectedEmployees.removeAt(index));
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
                    decoration: _inputDecoration(hint: "Search employees...").copyWith(
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredEmployees.isEmpty
                        ? Center(child: Text("No employees found", style: GoogleFonts.montserrat(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: filteredEmployees.length,
                            itemBuilder: (context, index) {
                              final emp = filteredEmployees[index];
                              final isSelected = selectedEmployees.any((s) => s['user_id'] == emp['user_id']);

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: EmployeeUi.primary,
                                checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                contentPadding: EdgeInsets.zero,
                                title: Text(emp['full_name'] ?? '', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
                                subtitle: Text("${emp['designation'] ?? ''} • ${emp['department'] ?? ''}",
                                    style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey)),
                                secondary: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: null,
                                  child: emp['avatar_url'] == null ? Text(emp['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 12)) : null,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      if (!isSelected) selectedEmployees.add(emp);
                                    } else {
                                      selectedEmployees.removeWhere((s) => s['user_id'] == emp['user_id']);
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Create Channel", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
