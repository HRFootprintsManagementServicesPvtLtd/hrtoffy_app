import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/chat_thread_screen.dart';
import 'employee_ui.dart';

class NewChatDialog extends StatefulWidget {
  final Function() onCreated;

  const NewChatDialog({
    super.key,
    required this.onCreated,
  });

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  final supabase = Supabase.instance.client;
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allEmployees = [];
  List<Map<String, dynamic>> filteredEmployees = [];
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
      debugPrint("[Messages] Loading direct message users. Query: organization_id=$organizationId, status=active, exclude current user");
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

  Future<void> _startChat(Map<String, dynamic> employee) async {
    final selectedUserId = employee['user_id'];
    if (selectedUserId == null) return;

    setState(() => loading = true);
    try {
      debugPrint("[Messages] Creating/Opening conversation with: ${employee['full_name']}");
      
      final existingDms = await supabase
          .from('chat_channels')
          .select('id')
          .eq('channel_type', 'dm')
          .eq('organization_id', organizationId!);

      String? channelId;

      for (final dm in existingDms) {
        final members = await supabase
            .from('chat_channel_members')
            .select('user_id')
            .eq('channel_id', dm['id']);
        
        final memberIds = members.map((m) => m['user_id']).toList();
        if (memberIds.length == 2 && 
            memberIds.contains(currentUserId) && 
            memberIds.contains(selectedUserId)) {
          channelId = dm['id'];
          debugPrint("[Messages] Found existing conversation: $channelId");
          break;
        }
      }

      if (channelId == null) {
        debugPrint("[Messages] No existing DM found. Creating new conversation...");
        debugPrint("========== CREATE DM ==========");
        debugPrint("organizationId = $organizationId");
        debugPrint("currentUserId = $currentUserId");
        debugPrint("employee = $employee");
        debugPrint("===============================");
        final rpcResult = await supabase.rpc(
          'create_chat_channel',
          params: {
            'p_org_id': organizationId,
            'p_channel_type': 'dm',
            'p_name': null,
            'p_description': null,
            'p_member_user_ids': [
              selectedUserId,
            ],
            'p_member_employee_ids': [
              employee['id'],
            ],
          },
        );

        channelId = rpcResult.toString();

        debugPrint("DM Channel Created => $channelId");
        debugPrint("[Messages] New conversation created: $channelId");
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
              channelId: channelId!,
              title: employee['full_name'],
            ),
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      _handleError("Start Chat Error", e);
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
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: searchController,
              onChanged: _filterEmployees,
              decoration: _inputDecoration(hint: "Search employees...").copyWith(
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: loading && allEmployees.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filteredEmployees.isEmpty
                      ? Center(child: Text("No employees found", style: GoogleFonts.montserrat(color: Colors.grey)))
                      : ListView.separated(
                          itemCount: filteredEmployees.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final emp = filteredEmployees[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              onTap: () => _startChat(emp),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundImage: null,
                                child: emp['avatar_url'] == null ? Text(emp['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 14)) : null,
                              ),
                              title: Text(emp['full_name'] ?? '', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
                              subtitle: Text("${emp['designation'] ?? ''} • ${emp['department'] ?? ''}",
                                  style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey)),
                              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
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
