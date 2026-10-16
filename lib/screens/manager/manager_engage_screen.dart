import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/engagement_repository.dart';
import '../../repositories/helpdesk_repository.dart';
import '../../repositories/letters_repository.dart';
import '../../repositories/recruitment_repository.dart';
import '../../repositories/tasks_repository.dart';
import 'widgets/engage_tabs.dart';
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import '../../services/chat_service.dart';
import '../survey_response_screen.dart';
import '../../models/chat_conversation.dart';
import '../chat_thread_screen.dart';
import '../../widgets/new_chat_dialog.dart';

/// Shown for every section that has no verified AWS route yet. Nothing is requested for them, and no
/// empty list, zero or placeholder data is shown in their place.
const String kEngageUnavailableMessage = "This isn't available yet";

/// Fixed text for any failed load: the server's or the exception's text is never shown.
const String kEngageLoadFailedMessage =
    "Couldn't load this right now. Please try again.";

/// Manager "Engage" hub (AWS migration phase 1).
///
/// Every tab reads real AWS data (see the repositories used by the tab bodies in widgets/engage_tabs.dart). A part the
/// server refuses for the caller's role shows "Not available for your role"; only the org chart and task management have
/// no route and say so.
class ManagerEngageScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final EngagementRepository? engagementRepository;
  final ChatService? chatService;
  final ChatRepository? chatRepository;
  final TasksRepository? tasksRepository;
  final HelpdeskRepository? helpdeskRepository;
  final LettersRepository? lettersRepository;
  final RecruitmentRepository? recruitmentRepository;

  const ManagerEngageScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.engagementRepository,
    this.chatService,
    this.chatRepository,
    this.tasksRepository,
    this.helpdeskRepository,
    this.lettersRepository,
    this.recruitmentRepository,
  });

  @override
  State<ManagerEngageScreen> createState() => _ManagerEngageScreenState();
}

class _ManagerEngageScreenState extends State<ManagerEngageScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _mainTabController;
  late final EngagementRepository _engagement =
      widget.engagementRepository ?? EngagementRepository();
  late final ChatService _chat = widget.chatService ?? ChatService();
  late final ChatRepository _chatRepo =
      widget.chatRepository ?? ChatRepository();
  late final TasksRepository _tasks =
      widget.tasksRepository ?? TasksRepository();
  late final HelpdeskRepository _helpdesk =
      widget.helpdeskRepository ?? HelpdeskRepository();
  late final LettersRepository _letters =
      widget.lettersRepository ?? LettersRepository();
  late final RecruitmentRepository _recruitment =
      widget.recruitmentRepository ?? RecruitmentRepository();

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 6, vsync: this);
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
              labelStyle: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
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
          _InternalUpdatesHub(
            engagement: _engagement,
            chat: _chat,
            chatRepo: _chatRepo,
          ),
          CompanyDirectoryTab(chat: _chatRepo),
          TasksChecklistsTab(tasks: _tasks),
          TicketsTab(helpdesk: _helpdesk),
          LettersDocumentsTab(letters: _letters),
          InternalOpportunitiesTab(recruitment: _recruitment),
        ],
      ),
    );
  }
}

/// A load that failed: a fixed message and a retry.
class _LoadFailed extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kEngageLoadFailedMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(fontSize: 13, color: Colors.red[700]),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// 🔵 1. INTERNAL UPDATES HUB
class _InternalUpdatesHub extends StatefulWidget {
  final EngagementRepository engagement;
  final ChatService chat;
  final ChatRepository chatRepo;
  const _InternalUpdatesHub({
    required this.engagement,
    required this.chat,
    required this.chatRepo,
  });

  @override
  State<_InternalUpdatesHub> createState() => _InternalUpdatesHubState();
}

class _InternalUpdatesHubState extends State<_InternalUpdatesHub>
    with SingleTickerProviderStateMixin {
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
              _MessagesTab(chatService: widget.chat),
              _AnnouncementsTab(engagement: widget.engagement),
              _EventsTab(engagement: widget.engagement),
              RecognitionTab(
                engagement: widget.engagement,
                chat: widget.chatRepo,
              ),
              _SurveysTab(engagement: widget.engagement),
              _FAQsTab(engagement: widget.engagement),
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
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Celebrate wins, share the news",
            style: GoogleFonts.playfairDisplay(
              color: const Color(0xFF1E90FF),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Announcements, recognition, surveys and milestones — keep the team in the loop.",
            style: GoogleFonts.montserrat(
              color: Colors.black54,
              fontSize: 13,
              height: 1.4,
            ),
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
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E90FF).withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 20),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
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

// 🔵 MESSAGES (existing AWS chat; the chat implementation itself is unchanged)
class _MessagesTab extends StatefulWidget {
  final ChatService chatService;
  const _MessagesTab({required this.chatService});

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  List<ChatConversation> conversations = [];
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final res = await widget.chatService.loadConversations();
      if (mounted) {
        setState(() {
          conversations = res;
          loading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (failed) return _LoadFailed(onRetry: _loadConversations);

    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.blue.shade100,
            ),
            const SizedBox(height: 16),
            Text(
              "No conversations yet",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Start a conversation with a colleague.",
              style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showNewChatDialog(),
              icon: const Icon(Icons.add),
              label: const Text("Start New Chat"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E90FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatThreadScreen(channelId: conv.id, title: conv.title),
                  ),
                );
              },
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Text(
                  conv.title[0],
                  style: const TextStyle(
                    color: Color(0xFF1E90FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                conv.title,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                conv.latestMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: conv.latestTime != null
                  ? Text(
                      DateFormat('HH:mm').format(conv.latestTime!),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    )
                  : null,
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
    showDialog(
      context: context,
      builder: (context) => NewChatDialog(onCreated: _loadConversations),
    );
  }
}

/// Loads one list through an [EngagementRepository] method (the one the employee screens use) and renders
/// it with [builder]. A failure is a fixed message with Retry.
class _RepoList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final String emptyText;
  final Widget Function(BuildContext context, List<Map<String, dynamic>> rows)
  builder;
  const _RepoList({
    required this.load,
    required this.emptyText,
    required this.builder,
  });

  @override
  State<_RepoList> createState() => _RepoListState();
}

class _RepoListState extends State<_RepoList> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (mounted) setState(() => loading = true);
    try {
      final res = await widget.load();
      if (mounted) {
        setState(() {
          rows = res;
          failed = false;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (failed) return _LoadFailed(onRetry: _fetch);
    if (rows.isEmpty) return Center(child: Text(widget.emptyText));
    return widget.builder(context, rows);
  }
}

// 🔵 ANNOUNCEMENTS: EngagementRepository.announcements() (drafts and inactive items stay filtered out there)
class _AnnouncementsTab extends StatelessWidget {
  final EngagementRepository engagement;
  const _AnnouncementsTab({required this.engagement});

  Widget _priorityChip(String? priority) {
    Color color = Colors.blue;
    if (priority?.toLowerCase() == 'high') color = Colors.red;
    if (priority?.toLowerCase() == 'medium') color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        "${priority ?? 'Normal'} Priority".toLowerCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _audienceChip(String? audience) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E90FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.book, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            (audience ?? 'All').toLowerCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String? category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(
        (category ?? 'General').toLowerCase(),
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RepoList(
      load: engagement.announcements,
      emptyText: "No announcements yet",
      builder: (context, announcements) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: announcements.length,
        itemBuilder: (context, index) {
          final ann = announcements[index];
          final created = asDate(ann['created_at']);
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _priorityChip(ann['priority']?.toString()),
                      const SizedBox(width: 8),
                      _audienceChip(ann['audience_type']?.toString()),
                      const SizedBox(width: 8),
                      _categoryChip(ann['category']?.toString()),
                      const Spacer(),
                      if (created != null)
                        Text(
                          DateFormat('dd MMM').format(created.toLocal()),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ann['title']?.toString() ?? '',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ann['body']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// 🔵 EVENTS: EngagementRepository.events()
class _EventsTab extends StatelessWidget {
  final EngagementRepository engagement;
  const _EventsTab({required this.engagement});

  DateTime _parseEventDate(dynamic date) =>
      asDate(date)?.toLocal() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    return _RepoList(
      load: engagement.events,
      emptyText: "No upcoming events",
      builder: (context, events) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final ev = events[index];
          final start = _parseEventDate(ev['event_date']);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMM').format(start),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF),
                        ),
                      ),
                      Text(
                        DateFormat('dd').format(start),
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E90FF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ev['title']?.toString() ?? '',
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${DateFormat('hh:mm a').format(start)} • ${ev['location'] ?? 'Online'}",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 🔵 SURVEYS: EngagementRepository.activeSurveys()
class _SurveysTab extends StatelessWidget {
  final EngagementRepository engagement;
  const _SurveysTab({required this.engagement});

  @override
  Widget build(BuildContext context) {
    return _RepoList(
      load: engagement.activeSurveys,
      emptyText: "No active surveys",
      builder: (context, surveys) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: surveys.length,
        itemBuilder: (context, index) {
          final survey = surveys[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  survey['title']?.toString() ?? '',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  survey['description']?.toString() ?? '',
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SurveyResponseScreen(
                          survey: survey,
                          employeeId: engagement.user.employeeId ?? '',
                          organizationId: engagement.organizationId,
                          userEmail: engagement.user.email,
                          repository: engagement,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: const Color(0xFF1E90FF),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Take Survey",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 🔵 FAQs: EngagementRepository.faqs()
class _FAQsTab extends StatefulWidget {
  final EngagementRepository engagement;
  const _FAQsTab({required this.engagement});

  @override
  State<_FAQsTab> createState() => _FAQsTabState();
}

class _FAQsTabState extends State<_FAQsTab> {
  String searchQuery = "";

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> all) {
    final query = searchQuery.toLowerCase();
    return all.where((f) {
      final q = (f['question'] ?? '').toString().toLowerCase();
      final a = (f['answer'] ?? '').toString().toLowerCase();
      return q.contains(query) || a.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _RepoList(
      load: widget.engagement.faqs,
      emptyText: "No FAQs found",
      builder: (context, allFaqs) {
        final filteredFaqs = _filter(allFaqs);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                onChanged: (v) => setState(() => searchQuery = v),
                decoration: InputDecoration(
                  hintText: "Search FAQs...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              faq['question']?.toString() ?? '',
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Text(
                                  faq['answer']?.toString() ?? '',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    color: Colors.black54,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
