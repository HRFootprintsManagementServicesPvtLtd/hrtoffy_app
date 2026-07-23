import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import '../../services/chat_service.dart';
import '../../models/chat_conversation.dart';
import '../chat_thread_screen.dart';
import '../../widgets/new_chat_dialog.dart';

class ManagerEngageScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerEngageScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerEngageScreen> createState() => _ManagerEngageScreenState();
}

class _ManagerEngageScreenState extends State<ManagerEngageScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _mainTabController;

  bool loading = true;
  String? organizationId;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 6, vsync: this);
    organizationId = widget.userData['organization_id']?.toString();
    setState(() => loading = false);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.engage,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Image.asset("assets/HR TOFFY.png", height: 35),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu, color: Colors.black),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _mainTabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF1E90FF),
              indicatorWeight: 3,
              labelColor: const Color(0xFF1E90FF),
              unselectedLabelColor: Colors.grey,
              labelStyle: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: "Internal Updates"),
                Tab(text: "Company Directory"),
                Tab(text: "Tasks & Checklists"),
                Tab(text: "Tickets"),
                Tab(text: "Letters & Documents"),
                Tab(text: "Internal Opportunities"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _InternalUpdatesHub(userData: widget.userData),
          _CompanyDirectorySection(userData: widget.userData),
          _TasksChecklistsSection(userData: widget.userData),
          _TicketsSection(userData: widget.userData),
          _LettersDocumentsSection(userData: widget.userData),
          _InternalOpportunitiesSection(userData: widget.userData),
        ],
      ),
    );
  }
}

// 🔵 1. INTERNAL UPDATES HUB
class _InternalUpdatesHub extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _InternalUpdatesHub({required this.userData});

  @override
  State<_InternalUpdatesHub> createState() => _InternalUpdatesHubState();
}

class _InternalUpdatesHubState extends State<_InternalUpdatesHub> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeroHeader(),
        _buildSubTabs(),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _MessagesTab(userData: widget.userData),
              _AnnouncementsTab(organizationId: widget.userData['organization_id']?.toString()),
              _EventsTab(organizationId: widget.userData['organization_id']?.toString()),
              _RecognitionTab(userData: widget.userData),
              _SurveysTab(organizationId: widget.userData['organization_id']?.toString()),
              _FAQsTab(organizationId: widget.userData['organization_id']?.toString()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blue.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Celebrate wins, share the news",
            style: GoogleFonts.playfairDisplay(color: const Color(0xFF1E90FF), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Announcements, recognition, surveys and milestones — keep the team in the loop.",
            style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabs() {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _subTabController,
        isScrollable: true,
        indicator: BoxDecoration(
          color: const Color(0xFF1E90FF),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: const Color(0xFF1E90FF).withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 20),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: "Messages"),
          Tab(text: "Announcements"),
          Tab(text: "Events & Calendar"),
          Tab(text: "Recognition"),
          Tab(text: "Surveys"),
          Tab(text: "FAQs"),
        ],
      ),
    );
  }
}

// 🔵 2. COMPANY DIRECTORY
class _CompanyDirectorySection extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _CompanyDirectorySection({required this.userData});

  @override
  State<_CompanyDirectorySection> createState() => _CompanyDirectorySectionState();
}

class _CompanyDirectorySectionState extends State<_CompanyDirectorySection> {
  final supabase = Supabase.instance.client;
  List<dynamic> allEmployees = [];
  List<dynamic> filteredEmployees = [];
  bool loading = true;
  String searchQuery = "";
  bool showOrgChart = false;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final res = await supabase
          .from('employee_records')
          .select()
          .eq('organization_id', widget.userData['organization_id'])
          .eq('status', 'active')
          .order('full_name');
      if (mounted) {
        setState(() {
          allEmployees = res;
          filteredEmployees = res;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Directory fetch error: $e");
    }
  }

  void _filter(String query) {
    setState(() {
      searchQuery = query;
      filteredEmployees = allEmployees.where((e) {
        final name = (e['full_name'] ?? '').toString().toLowerCase();
        final id = (e['employee_id'] ?? '').toString().toLowerCase();
        final dept = (e['department'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase()) || id.contains(query.toLowerCase()) || dept.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHeroHeader(),
        _buildToggle(),
        if (!showOrgChart) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: "Search by name, designation, or ID...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, 
                childAspectRatio: 0.75, 
                crossAxisSpacing: 12, 
                mainAxisSpacing: 12
              ),
              itemCount: filteredEmployees.length,
              itemBuilder: (context, index) {
                final emp = filteredEmployees[index];
                return _buildEmployeeCard(emp);
              },
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text("Org Chart Interactive View"))),
      ],
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Company Directory",
            style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Browse employees and explore the organization structure",
            style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      height: 45,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _toggleBtn("Employee Directory", !showOrgChart, Icons.people_outline, () => setState(() => showOrgChart = false))),
          Expanded(child: _toggleBtn("Org Chart", showOrgChart, Icons.account_tree_outlined, () => setState(() => showOrgChart = true))),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: active ? Colors.blue : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.w500, color: active ? Colors.white : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
     return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30, 
            backgroundColor: Colors.blue.shade50, 
            backgroundImage: emp['avatar_url'] != null ? NetworkImage(emp['avatar_url']) : null,
            child: emp['avatar_url'] == null ? Text(emp['full_name']?[0] ?? '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)) : null,
          ),
          const SizedBox(height: 12),
          Text(emp['full_name'] ?? '', textAlign: TextAlign.center, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(emp['designation'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(emp['employee_id'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionIcon(Icons.email_outlined),
              _actionIcon(Icons.phone_outlined),
              _actionIcon(Icons.location_on_outlined),
            ],
          )
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: Colors.grey.shade600),
    );
  }
}

// 🔵 3. TASKS & CHECKLISTS
class _TasksChecklistsSection extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _TasksChecklistsSection({required this.userData});

  @override
  State<_TasksChecklistsSection> createState() => _TasksChecklistsSectionState();
}

class _TasksChecklistsSectionState extends State<_TasksChecklistsSection> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  List<dynamic> myTasks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    try {
      final res = await supabase
          .from('task_assignments')
          .select('*, tasks(*)')
          .eq('employee_id', widget.userData['id'])
          .order('created_at', ascending: false);
      if (mounted) setState(() {
        myTasks = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Tasks fetch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHero(),
        Container(
          height: 45,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            labelStyle: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: const [Tab(text: "My Tasks"), Tab(text: "Manage Tasks")],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMyTasksList(),
              const Center(child: Text("Task Management (HR/Manager View)")),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyTasksList() {
    if (myTasks.isEmpty) return const Center(child: Text("No tasks assigned"));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: myTasks.length,
      itemBuilder: (context, index) {
        final assignment = myTasks[index];
        final task = assignment['tasks'];
        final status = assignment['status'] ?? 'pending';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            title: Text(task['task_title'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("${task['task_type']} • $status", style: const TextStyle(fontSize: 11)),
            trailing: _statusPill(status),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task['task_description'] ?? 'No description provided', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    if (task['checklist_items'] != null) ...[
                      const Text("Checklist:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ...(task['checklist_items'] as List).map((item) => CheckboxListTile(
                        value: false,
                        onChanged: (v) {},
                        title: Text(item.toString(), style: const TextStyle(fontSize: 12)),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      )),
                    ],
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _statusPill(String status) {
    Color color = Colors.orange;
    if (status == 'completed') color = Colors.green;
    if (status == 'in_progress') color = Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.white]),
        borderRadius: BorderRadius.circular(24)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's focus, made simple", style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text("Onboarding checklists, follow-ups and reminders — see what needs attention now.", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// 🔵 4. TICKETS
class _TicketsSection extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _TicketsSection({required this.userData});

  @override
  State<_TicketsSection> createState() => _TicketsSectionState();
}

class _TicketsSectionState extends State<_TicketsSection> {
  final supabase = Supabase.instance.client;
  List<dynamic> tickets = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    try {
      final res = await supabase
          .from('support_requests')
          .select()
          .eq('employee_id', widget.userData['id'])
          .order('created_at', ascending: false);
      if (mounted) setState(() {
        tickets = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Tickets fetch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildHero(),
          Container(
            height: 40,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () {}, 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("My Tickets")
                ),
              ],
            ),
          ),
          Expanded(
            child: loading 
              ? const Center(child: CircularProgressIndicator())
              : tickets.isEmpty 
                ? const Center(child: Text("No tickets raised"))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      final t = tickets[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          title: Text(t['subject'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text("Created ${DateFormat('dd MMM').format(DateTime.parse(t['created_at']))} • ${t['category']}"),
                          trailing: _statusChip(t['status']),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: const Color(0xFF1E90FF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Raise Ticket", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _statusChip(String? status) {
    Color color = Colors.orange;
    if (status == 'resolved' || status == 'closed') color = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text((status ?? 'PENDING').toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Tickets", style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text("Raise issues and track resolutions", style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}

// 🔵 5. LETTERS & DOCUMENTS
class _LettersDocumentsSection extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _LettersDocumentsSection({required this.userData});

  @override
  State<_LettersDocumentsSection> createState() => _LettersDocumentsSectionState();
}

class _LettersDocumentsSectionState extends State<_LettersDocumentsSection> {
  final supabase = Supabase.instance.client;
  List<dynamic> letters = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLetters();
  }

  Future<void> _fetchLetters() async {
    try {
      final res = await supabase
          .from('generated_letters')
          .select()
          .eq('employee_id', widget.userData['id'])
          .order('created_at', ascending: false);
      if (mounted) setState(() {
        letters = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Letters fetch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHero(),
        Container(
          height: 40,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {}, 
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text("My Letters"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ),
        Expanded(
          child: letters.isEmpty 
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: letters.length,
                itemBuilder: (context, index) {
                  final letter = letters[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                      title: Text(letter['letter_category'] ?? 'Letter', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text("Issued: ${DateFormat('dd MMM yyyy').format(DateTime.parse(letter['created_at']))}"),
                      trailing: const Icon(Icons.download_outlined),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text("No Letters Yet", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text("You don't have any letters generated yet. Letters will appear here once HR generates them for you.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFF7F0FF), Colors.white]),
        borderRadius: BorderRadius.circular(24)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Your digital vault", style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text("Generate offer letters, certificates and payslips — store, share and download in seconds.", style: TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }
}

// 🔵 6. INTERNAL OPPORTUNITIES
class _InternalOpportunitiesSection extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _InternalOpportunitiesSection({required this.userData});

  @override
  State<_InternalOpportunitiesSection> createState() => _InternalOpportunitiesSectionState();
}

class _InternalOpportunitiesSectionState extends State<_InternalOpportunitiesSection> {
  final supabase = Supabase.instance.client;
  List<dynamic> jobs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    try {
      final res = await supabase
          .from('job_openings')
          .select()
          .eq('organization_id', widget.userData['organization_id'])
          .eq('is_internal_posting', true)
          .eq('status', 'open')
          .order('created_at', ascending: false);
      if (mounted) setState(() {
        jobs = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Jobs fetch error: $e");
    }
  }

  Future<void> _apply(dynamic job) async {
     try {
      final employee = await supabase.from('employee_records').select().eq('id', widget.userData['id']).single();
      var candidate = await supabase.from('candidates').select().eq('email', employee['email']).maybeSingle();
      
      if (candidate == null) {
        candidate = await supabase.from('candidates').insert({
          'organization_id': widget.userData['organization_id'],
          'first_name': employee['full_name'].split(' ').first,
          'last_name': employee['full_name'].split(' ').last,
          'email': employee['email'],
          'source': 'Internal Opportunity', // ✅ Fixed: Try more descriptive source if 'Internal' fails
        }).select().single();
      }

      await supabase.from('job_applications').insert({
        'organization_id': widget.userData['organization_id'],
        'job_id': job['id'],
        'candidate_id': candidate['id'],
        'applicant_employee_id': widget.userData['id'],
        'is_internal_applicant': true,
        'status': 'active',
        'current_stage': 'screening',
        'applied_date': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Applied successfully!")));
        _fetchJobs();
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHeroHeader(),
        Expanded(
          child: jobs.isEmpty 
            ? const Center(child: Text("No internal opportunities available at the moment"))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: jobs.length,
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  return _buildJobCard(job);
                },
              ),
        ),
      ],
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Internal Opportunities",
            style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Explore career growth opportunities within the organization",
            style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final postedDate = DateTime.parse(job['created_at']);
    final diff = DateTime.now().difference(postedDate);
    final timeAgo = diff.inDays > 30 ? "${(diff.inDays/30).floor()} months ago" : "${diff.inDays} days ago";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(job['job_title'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text("Internal", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
            ],
          ),
          Text(job['department'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          _jobInfoRow(Icons.location_on_outlined, job['location'] ?? 'Mumbai'),
          _jobInfoRow(Icons.access_time_outlined, job['employment_type'] ?? 'full time'),
          _jobInfoRow(Icons.currency_rupee, "INR ${job['salary_min']} - ${job['salary_max']}"),
          _jobInfoRow(Icons.people_outline, "${job['number_of_positions']} positions"),
          _jobInfoRow(Icons.calendar_today_outlined, "Deadline: ${job['internal_deadline'] ?? '18/12/2025'}"),
          const SizedBox(height: 12),
          Text(job['job_description'] ?? 'test', style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Posted $timeAgo", style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ElevatedButton.icon(
                onPressed: () => _apply(job),
                icon: const Icon(Icons.send, size: 14),
                label: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _jobInfoRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

// --- SUB-TAB IMPLEMENTATIONS FROM PREVIOUS VERSION ---

class _MessagesTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _MessagesTab({required this.userData});

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  final chatService = ChatService();
  List<ChatConversation> conversations = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final res = await chatService.loadConversations();
      if (mounted) setState(() {
        conversations = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Load conversations error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.blue.shade100),
            const SizedBox(height: 16),
            Text("No conversations yet", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text("Start a conversation with a colleague.", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showNewChatDialog(),
              icon: const Icon(Icons.add),
              label: const Text("Start New Chat"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E90FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: conversations.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final conv = conversations[index];
            return ListTile(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(channelId: conv.id, title: conv.title)));
              },
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Text(conv.title[0], style: const TextStyle(color: Color(0xFF1E90FF), fontWeight: FontWeight.bold)),
              ),
              title: Text(conv.title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(conv.latestMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: conv.latestTime != null 
                  ? Text(DateFormat('HH:mm').format(conv.latestTime!), style: const TextStyle(fontSize: 10, color: Colors.grey))
                  : null,
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(),
        backgroundColor: const Color(0xFF1E90FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showNewChatDialog() {
    showDialog(context: context, builder: (context) => NewChatDialog(onCreated: _loadConversations));
  }
}

class _AnnouncementsTab extends StatefulWidget {
  final String? organizationId;
  const _AnnouncementsTab({this.organizationId});

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> announcements = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    if (widget.organizationId == null) return;
    try {
      final res = await supabase
          .from('announcements')
          .select()
          .eq('organization_id', widget.organizationId!)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          announcements = res;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Announcements error: $e");
    }
  }

  Widget _priorityChip(String? priority) {
    Color color = Colors.blue;
    if (priority?.toLowerCase() == 'high') color = Colors.red;
    if (priority?.toLowerCase() == 'medium') color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text("${priority ?? 'Normal'} Priority".toLowerCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _audienceChip(String? audience) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF1E90FF), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.book, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text((audience ?? 'All').toLowerCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _categoryChip(String? category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade100)),
      child: Text((category ?? 'General').toLowerCase(), style: TextStyle(color: Colors.blue.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (announcements.isEmpty) return const Center(child: Text("No announcements yet"));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: announcements.length,
      itemBuilder: (context, index) {
        final ann = announcements[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _priorityChip(ann['priority']),
                    const SizedBox(width: 8),
                    _audienceChip(ann['audience_type']),
                    const SizedBox(width: 8),
                    _categoryChip(ann['category']),
                    const Spacer(),
                    Text(DateFormat('dd MMM').format(DateTime.parse(ann['created_at'])), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(ann['title'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(ann['body'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87, height: 1.4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EventsTab extends StatefulWidget {
  final String? organizationId;
  const _EventsTab({this.organizationId});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    if (widget.organizationId == null) return;
    try {
      final res = await supabase
          .from('events')
          .select()
          .eq('organization_id', widget.organizationId!)
          .order('event_date', ascending: true);
      if (mounted) setState(() {
        events = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Events error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) return const Center(child: Text("No upcoming events"));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final ev = events[index];
        final start = _parseEventDate(ev['event_date']);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
          child: Row(
            children: [
              Container(
                width: 50,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(DateFormat('MMM').format(start), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E90FF))),
                    Text(DateFormat('dd').format(start), style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E90FF))),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ev['title'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text("${DateFormat('hh:mm a').format(start)} • ${ev['location'] ?? 'Online'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  DateTime _parseEventDate(dynamic date) {
    if (date == null) return DateTime.now();
    try {
      return DateTime.parse(date.toString());
    } catch (_) {
      return DateTime.now();
    }
  }
}

class _RecognitionTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _RecognitionTab({required this.userData});

  @override
  State<_RecognitionTab> createState() => _RecognitionTabState();
}

class _RecognitionTabState extends State<_RecognitionTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> recognitions = [];
  List<dynamic> milestones = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final orgId = widget.userData['organization_id'];
      final monthDay = DateFormat('MM-dd').format(DateTime.now());
      
      final results = await Future.wait([
        supabase
          .from('recognitions')
          .select('*, giver:employee_records!giver_employee_id(full_name), recipient:employee_records!recipient_employee_id(full_name), recognition_badges(name, icon, color)')
          .eq('organization_id', orgId)
          .order('created_at', ascending: false),
        supabase
          .from('employee_records')
          .select('full_name, date_of_birth, joining_date')
          .eq('organization_id', orgId),
      ]);

      List<dynamic> recs = results[0];
      List<dynamic> allEmps = results[1];
      
      // Filter milestones in memory to avoid LIKE error on DATE columns
      final mList = allEmps.where((e) {
        final dob = e['date_of_birth']?.toString() ?? '';
        final join = e['joining_date']?.toString() ?? '';
        return dob.contains(monthDay) || join.contains(monthDay);
      }).toList();

      if (!mounted) return;
      setState(() {
        recognitions = recs;
        milestones = mList;
        loading = false;
      });
    } catch (e) {
      debugPrint("Recognition data error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (milestones.isNotEmpty) _buildMilestonesSection(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text("Recent Recognition", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: recognitions.length,
                itemBuilder: (context, index) {
                  final rec = recognitions[index];
                  final badge = rec['recognition_badges'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(radius: 18, backgroundColor: Colors.blue.shade50, child: Text((rec['recipient']?['full_name'] ?? '?')[0])),
                            const SizedBox(width: 12),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
                                  children: [
                                    TextSpan(text: rec['giver']?['full_name'] ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const TextSpan(text: ' recognized '),
                                    TextSpan(text: rec['recipient']?['full_name'] ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.stars, color: Colors.amber, size: 16),
                            const SizedBox(width: 8),
                            Text(badge?['name'] ?? 'Appreciation', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(rec['message'] ?? '', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, height: 1.4)),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGiveRecognitionDialog(),
        backgroundColor: const Color(0xFF1E90FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildMilestonesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text("Celebrations Today!", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange.shade900)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: milestones.length,
              itemBuilder: (context, index) {
                final m = milestones[index];
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 14, child: Text(m['full_name'][0])),
                      const SizedBox(width: 8),
                      Text(m['full_name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showGiveRecognitionDialog() {
    showDialog(context: context, builder: (context) => _GiveRecognitionDialog(userData: widget.userData, onCreated: _fetchData));
  }
}

class _GiveRecognitionDialog extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onCreated;
  const _GiveRecognitionDialog({required this.userData, required this.onCreated});

  @override
  State<_GiveRecognitionDialog> createState() => _GiveRecognitionDialogState();
}

class _GiveRecognitionDialogState extends State<_GiveRecognitionDialog> {
  final supabase = Supabase.instance.client;
  List<dynamic> employees = [];
  List<dynamic> badges = [];
  String? selectedEmployeeId;
  String? selectedBadgeId;
  final messageController = TextEditingController();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final res = await Future.wait([
        supabase.from('employee_records').select('id, full_name').eq('organization_id', widget.userData['organization_id']),
        supabase.from('recognition_badges').select().eq('organization_id', widget.userData['organization_id']).eq('is_active', true),
      ]);
      if (mounted) setState(() {
        employees = (res[0] as List).where((e) => e['id'].toString() != widget.userData['id'].toString()).toList();
        badges = res[1];
        loading = false;
      });
    } catch (e) {
      debugPrint("Fetch data error: $e");
    }
  }

  Future<void> _submit() async {
    if (selectedEmployeeId == null || selectedBadgeId == null || messageController.text.isEmpty) return;
    try {
      await supabase.from('recognitions').insert({
        'organization_id': widget.userData['organization_id'],
        'giver_employee_id': widget.userData['id'],
        'recipient_employee_id': selectedEmployeeId,
        'badge_id': selectedBadgeId,
        'message': messageController.text,
        'visibility': 'public',
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Submit recognition error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Give Recognition", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: "Recipient", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: employees.map((e) => DropdownMenuItem<String>(value: e['id'].toString(), child: Text(e['full_name']))).toList(),
                onChanged: (v) => setState(() => selectedEmployeeId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: "Badge", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: badges.map((b) => DropdownMenuItem<String>(value: b['id'].toString(), child: Text(b['name']))).toList(),
                onChanged: (v) => setState(() => selectedBadgeId = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: messageController,
                maxLines: 3,
                decoration: InputDecoration(labelText: "Message", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E90FF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("Send Recognition"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _SurveysTab extends StatefulWidget {
  final String? organizationId;
  const _SurveysTab({this.organizationId});

  @override
  State<_SurveysTab> createState() => _SurveysTabState();
}

class _SurveysTabState extends State<_SurveysTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> surveys = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSurveys();
  }

  Future<void> _fetchSurveys() async {
    if (widget.organizationId == null) return;
    try {
      final res = await supabase
          .from('surveys')
          .select()
          .eq('organization_id', widget.organizationId!)
          .eq('status', 'active');
      if (mounted) setState(() {
        surveys = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("Surveys error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (surveys.isEmpty) return const Center(child: Text("No active surveys"));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: surveys.length,
      itemBuilder: (context, index) {
        final survey = surveys[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(survey['title'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Text(survey['description'] ?? '', maxLines: 2, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: const Color(0xFF1E90FF), elevation: 0),
                  child: const Text("Take Survey", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FAQsTab extends StatefulWidget {
  final String? organizationId;
  const _FAQsTab({this.organizationId});

  @override
  State<_FAQsTab> createState() => _FAQsTabState();
}

class _FAQsTabState extends State<_FAQsTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> allFaqs = [];
  List<dynamic> filteredFaqs = [];
  bool loading = true;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchFAQs();
  }

  Future<void> _fetchFAQs() async {
    if (widget.organizationId == null) return;
    try {
      final res = await supabase
          .from('faqs')
          .select()
          .eq('organization_id', widget.organizationId!)
          .eq('is_active', true);
      if (mounted) setState(() {
        allFaqs = res;
        filteredFaqs = res;
        loading = false;
      });
    } catch (e) {
      debugPrint("FAQs error: $e");
    }
  }

  void _filterFaqs(String query) {
    setState(() {
      searchQuery = query;
      filteredFaqs = allFaqs.where((f) {
        final q = (f['question'] ?? '').toString().toLowerCase();
        final a = (f['answer'] ?? '').toString().toLowerCase();
        return q.contains(query.toLowerCase()) || a.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            onChanged: _filterFaqs,
            decoration: InputDecoration(
              hintText: "Search FAQs...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filteredFaqs.isEmpty 
            ? const Center(child: Text("No FAQs found"))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: filteredFaqs.length,
                itemBuilder: (context, index) {
                  final faq = filteredFaqs[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(faq['question'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(faq['answer'] ?? '', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54, height: 1.5)),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }
}
