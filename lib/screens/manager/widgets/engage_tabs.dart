import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/json_case.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/engagement_repository.dart';
import '../../../repositories/employee_repository.dart';
import '../../../repositories/helpdesk_repository.dart';
import '../../../repositories/manager_repository.dart';
import '../../../repositories/letters_repository.dart';
import '../../../repositories/recruitment_repository.dart';
import '../../../repositories/tasks_repository.dart';
import 'manager_state_views.dart';
import 'org_chart_view.dart';
import 'team_tasks_view.dart';

const Color _blue = Color(0xFF1E90FF);

/// Shown when giving recognition is refused (403) or the server cannot take it right now.
const String kRecognitionNotAllowedMessage =
    "You can't give recognition right now.";
const String kNoRecognitionBadgesMessage =
    'No recognition badges are set up for your organisation yet. Ask HR to add some.';
const String kRecognitionFailedMessage =
    "Couldn't send the recognition. Please try again.";

String _initial(Object? name) {
  final s = name?.toString().trim() ?? '';
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

Widget _hero(String title, String subtitle, {Color? tint}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(24),
  margin: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: tint ?? Colors.white,
    borderRadius: BorderRadius.circular(24),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: GoogleFonts.playfairDisplay(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 13),
      ),
    ],
  ),
);

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    text.toUpperCase(),
    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
  ),
);

String _dateText(dynamic v, [String pattern = 'dd MMM yyyy']) {
  final d = asDate(v);
  return d == null ? '' : DateFormat(pattern).format(d.toLocal());
}

// ---------------------------------------------------------------------------
// Company directory
// ---------------------------------------------------------------------------

/// The people the caller can reach: `GET /chat/employees` (active colleagues the organization's chat scope allows).
/// That is the only verified directory the caller's role may read; it is not guaranteed to be every employee.
class CompanyDirectoryTab extends StatefulWidget {
  const CompanyDirectoryTab({
    super.key,
    required this.chat,
    required this.manager,
    required this.employees,
  });

  final ChatRepository chat;
  final ManagerRepository manager;
  final EmployeeRepository employees;

  @override
  State<CompanyDirectoryTab> createState() => _CompanyDirectoryTabState();
}

class _CompanyDirectoryTabState extends State<CompanyDirectoryTab> {
  String query = '';
  bool showOrgChart = false;

  Widget _toggle(String label, bool active, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? Colors.white : Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? Colors.white : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _hero(
          'Company Directory',
          'Browse the colleagues you can reach in your organization',
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          height: 45,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _toggle(
                'Employee Directory',
                !showOrgChart,
                Icons.people_outline,
                () => setState(() => showOrgChart = false),
              ),
              _toggle(
                'Org Chart',
                showOrgChart,
                Icons.account_tree_outlined,
                () => setState(() => showOrgChart = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: showOrgChart
              ? OrgChartView(
                  manager: widget.manager,
                  employees: widget.employees,
                )
              : _directory(),
        ),
      ],
    );
  }

  Widget _directory() {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: widget.chat.directory,
      isEmpty: (rows) => rows.isEmpty,
      emptyText: 'No colleagues to show',
      builder: (context, all) {
        final q = query.toLowerCase();
        final rows = all.where((e) {
          return [
            e['full_name'],
            e['department'],
            e['designation'],
          ].any((v) => (v ?? '').toString().toLowerCase().contains(q));
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  hintText: 'Search by name, designation, or department...',
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
            const SizedBox(height: 16),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No colleagues found'))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.9,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _card(rows[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> emp) {
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
            child: Text(
              _initial(emp['full_name']),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            emp['full_name']?.toString() ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            emp['designation']?.toString() ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          Text(
            emp['department']?.toString() ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tasks & checklists
// ---------------------------------------------------------------------------

class TasksChecklistsTab extends StatefulWidget {
  const TasksChecklistsTab({
    super.key,
    required this.tasks,
    required this.manager,
  });

  final TasksRepository tasks;
  final ManagerRepository manager;

  @override
  State<TasksChecklistsTab> createState() => _TasksChecklistsTabState();
}

class _TasksChecklistsTabState extends State<TasksChecklistsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _hero(
          "Today's focus, made simple",
          'Onboarding checklists, follow-ups and reminders — see what needs attention now.',
          tint: Colors.blue.shade50,
        ),
        Container(
          height: 45,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabs,
            indicator: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            labelStyle: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            tabs: const [
              Tab(text: 'My Tasks'),
              Tab(text: 'Manage Tasks'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ManagerLoader<List<Map<String, dynamic>>>(
                load: widget.tasks.myTasks,
                isEmpty: (r) => r.isEmpty,
                emptyText: 'No tasks assigned',
                builder: (context, rows) => ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _taskCard(rows[i]),
                ),
              ),
              TeamTasksView(tasks: widget.tasks, manager: widget.manager),
            ],
          ),
        ),
      ],
    );
  }

  Widget _taskCard(Map<String, dynamic> a) {
    final task = a['task'] is Map
        ? Map<String, dynamic>.from(a['task'] as Map)
        : <String, dynamic>{};
    final status = (a['status'] ?? 'pending').toString();
    Color color = Colors.orange;
    if (status == 'completed') color = Colors.green;
    if (status == 'in_progress') color = Colors.blue;
    final raw = task['checklist_items'];
    final items = <String>[
      if (raw is List)
        for (final it in raw)
          if (it is Map)
            (it['title'] ?? it['text'] ?? it['label'] ?? '').toString()
          else
            it.toString(),
    ].where((s) => s.isNotEmpty).toList();
    final type = task['task_type']?.toString() ?? '';
    final desc = task['task_description']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: Text(
          task['task_title']?.toString() ?? '',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          [
            type,
            status.replaceAll('_', ' '),
          ].where((s) => s.isNotEmpty).join(' • '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: _pill(status.replaceAll('_', ' '), color),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.isEmpty ? 'No description provided' : desc,
                  style: const TextStyle(fontSize: 12),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Checklist:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $item',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tickets
// ---------------------------------------------------------------------------

class TicketsTab extends StatelessWidget {
  const TicketsTab({super.key, required this.helpdesk});

  final HelpdeskRepository helpdesk;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _hero('Tickets', 'Track the issues you have raised'),
        Container(
          height: 40,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'My Tickets',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: ManagerLoader<List<Map<String, dynamic>>>(
            load: helpdesk.myTickets,
            isEmpty: (r) => r.isEmpty,
            emptyText: 'No tickets raised',
            builder: (context, rows) => ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final t = rows[i];
                final status = (t['status'] ?? 'pending').toString();
                final done = status == 'resolved' || status == 'closed';
                final created = _dateText(t['created_at'], 'dd MMM');
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    title: Text(
                      t['subject']?.toString() ?? '',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (created.isNotEmpty) 'Created $created',
                        t['category']?.toString() ?? '',
                      ].where((s) => s.isNotEmpty).join(' • '),
                    ),
                    trailing: _pill(
                      status.replaceAll('_', ' '),
                      done ? Colors.green : Colors.orange,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Letters & documents
// ---------------------------------------------------------------------------

class LettersDocumentsTab extends StatelessWidget {
  const LettersDocumentsTab({super.key, required this.letters});

  final LettersRepository letters;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _hero(
          'Your digital vault',
          'The letters HR has issued to you.',
          tint: const Color(0xFFF7F0FF),
        ),
        Expanded(
          child: ManagerLoader<List<Map<String, dynamic>>>(
            load: letters.myLetters,
            isEmpty: (r) => r.isEmpty,
            emptyText:
                "No letters yet. Letters will appear here once HR has issued them to you.",
            builder: (context, rows) => ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final l = rows[i];
                final issued = _dateText(l['sent_at'] ?? l['created_at']);
                final subject = l['subject_line']?.toString() ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: Colors.redAccent,
                    ),
                    title: Text(
                      (l['letter_category']?.toString() ?? '').isEmpty
                          ? 'Letter'
                          : l['letter_category'].toString(),
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (subject.isNotEmpty) subject,
                        if (issued.isNotEmpty) 'Issued: $issued',
                      ].join('\n'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Internal opportunities
// ---------------------------------------------------------------------------

class _JobsData {
  _JobsData(this.jobs, this.applied, this.appliedKnown);
  final List<Map<String, dynamic>> jobs;
  final Set<String> applied;
  final bool appliedKnown;
}

class InternalOpportunitiesTab extends StatefulWidget {
  const InternalOpportunitiesTab({super.key, required this.recruitment});

  final RecruitmentRepository recruitment;

  @override
  State<InternalOpportunitiesTab> createState() =>
      _InternalOpportunitiesTabState();
}

class _InternalOpportunitiesTabState extends State<InternalOpportunitiesTab> {
  int _version = 0;
  final Set<String> _applying = {};

  Future<_JobsData> _load() async {
    final jobs = await widget.recruitment.internalJobs();
    var applied = <String>{};
    var known = true;
    try {
      applied = await widget.recruitment.appliedJobIds();
    } catch (_) {
      known = false;
    }
    return _JobsData(jobs, applied, known);
  }

  Future<void> _apply(String jobId) async {
    if (_applying.contains(jobId)) return;
    setState(() => _applying.add(jobId));
    String message;
    try {
      await widget.recruitment.applyInternal(jobId);
      message = 'Applied successfully!';
    } on ApiException catch (e) {
      message = e.message.toLowerCase().contains('already applied')
          ? 'You have already applied for this job.'
          : "Couldn't submit your application. Please try again.";
    } catch (_) {
      message = "Couldn't submit your application. Please try again.";
    }
    if (!mounted) return;
    setState(() {
      _applying.remove(jobId);
      _version++;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _hero(
          'Internal Opportunities',
          'Explore career growth opportunities within the organization',
        ),
        Expanded(
          child: ManagerLoader<_JobsData>(
            key: ValueKey(_version),
            load: _load,
            isEmpty: (d) => d.jobs.isEmpty,
            emptyText: 'No internal opportunities available at the moment',
            builder: (context, d) => ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: d.jobs.length,
              itemBuilder: (context, i) => _jobCard(d.jobs[i], d),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    ),
  );

  Widget _jobCard(Map<String, dynamic> job, _JobsData d) {
    final id = job['id']?.toString() ?? '';
    final posted = asDate(job['created_at']);
    String? timeAgo;
    if (posted != null) {
      final days = DateTime.now().difference(posted).inDays;
      timeAgo = days > 30
          ? '${(days / 30).floor()} months ago'
          : '$days days ago';
    }
    final min = asNum(job['salary_min']);
    final max = asNum(job['salary_max']);
    final fmt = NumberFormat.decimalPattern('en_IN');
    final deadline = _dateText(job['internal_deadline']);
    final positions = asInt(job['number_of_positions'], 0);
    final applied = d.applied.contains(id);
    final busy = _applying.contains(id);
    final dept = job['department']?.toString() ?? '';
    final loc = job['location']?.toString() ?? '';
    final type = job['employment_type']?.toString() ?? '';
    final desc = job['job_description']?.toString() ?? '';
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
              Expanded(
                child: Text(
                  job['job_title']?.toString() ?? '',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Internal',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          if (dept.isNotEmpty)
            Text(
              dept,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          const SizedBox(height: 16),
          if (loc.isNotEmpty) _row(Icons.location_on_outlined, loc),
          if (type.isNotEmpty) _row(Icons.access_time_outlined, type),
          if (min != null && max != null)
            _row(
              Icons.currency_rupee,
              'INR ${fmt.format(min)} - ${fmt.format(max)}',
            ),
          if (positions > 0) _row(Icons.people_outline, '$positions positions'),
          if (deadline.isNotEmpty)
            _row(Icons.calendar_today_outlined, 'Deadline: $deadline'),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                timeAgo == null ? '' : 'Posted $timeAgo',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              if (applied)
                _pill('Applied', Colors.green)
              else
                ElevatedButton.icon(
                  onPressed: busy || id.isEmpty ? null : () => _apply(id),
                  icon: const Icon(Icons.send, size: 14),
                  label: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recognition
// ---------------------------------------------------------------------------

class RecognitionTab extends StatefulWidget {
  const RecognitionTab({
    super.key,
    required this.engagement,
    required this.chat,
  });

  final EngagementRepository engagement;
  final ChatRepository chat;

  @override
  State<RecognitionTab> createState() => _RecognitionTabState();
}

class _RecognitionTabState extends State<RecognitionTab> {
  int _version = 0;

  Future<void> _give() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => GiveRecognitionDialog(
        engagement: widget.engagement,
        chat: widget.chat,
      ),
    );
    if (done == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CelebrationsStrip(
              key: ValueKey('cel$_version'),
              engagement: widget.engagement,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Recent Recognition',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            SizedBox(
              height: 480,
              child: ManagerLoader<List<Map<String, dynamic>>>(
                key: ValueKey('rec$_version'),
                load: widget.engagement.recognitions,
                isEmpty: (r) => r.isEmpty,
                emptyText: 'No recognition yet',
                builder: (context, rows) => ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _card(rows[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _give,
        tooltip: 'Give Recognition',
        backgroundColor: _blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _card(Map<String, dynamic> rec) {
    Map<String, dynamic> m(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    final from = m(rec['from_employee']);
    final to = m(rec['to_employee']);
    final badge = m(rec['recognition_badges']);
    final badgeName = badge['badge_name']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.shade50,
                child: Text(_initial(to['full_name'])),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                    children: [
                      TextSpan(
                        text: from['full_name']?.toString() ?? 'Someone',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' recognized '),
                      TextSpan(
                        text: to['full_name']?.toString() ?? 'Someone',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
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
              Text(
                badgeName.isEmpty ? 'Appreciation' : badgeName,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rec['recognition_message']?.toString() ?? '',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CelebrationsStrip extends StatefulWidget {
  const _CelebrationsStrip({super.key, required this.engagement});

  final EngagementRepository engagement;

  @override
  State<_CelebrationsStrip> createState() => _CelebrationsStripState();
}

class _CelebrationsStripState extends State<_CelebrationsStrip> {
  List<Map<String, dynamic>>? items;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.engagement.celebrations();
      if (mounted) setState(() => items = r);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return const ManagerInlineNote(
        "Today's celebrations aren't available right now",
      );
    }
    final list = items;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Celebrations Today!',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              itemBuilder: (context, i) {
                final m = list[i];
                final label = m['kind'] == 'anniversary'
                    ? 'Work anniversary'
                    : 'Birthday';
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text(_initial(m['full_name'])),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['full_name']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
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
}

class _GiveData {
  _GiveData(this.people, this.badges);
  final List<Map<String, dynamic>> people;
  final List<Map<String, dynamic>> badges;
}

/// "Give Recognition": recipient (from the directory), badge, message and visibility. A 403 shows
/// [kRecognitionNotAllowedMessage]; no server text is ever shown.
class GiveRecognitionDialog extends StatefulWidget {
  const GiveRecognitionDialog({
    super.key,
    required this.engagement,
    required this.chat,
  });

  final EngagementRepository engagement;
  final ChatRepository chat;

  @override
  State<GiveRecognitionDialog> createState() => _GiveRecognitionDialogState();
}

class _GiveRecognitionDialogState extends State<GiveRecognitionDialog> {
  final message = TextEditingController();
  _GiveData? data;
  bool loading = true;
  String? loadError;
  String? recipientId;
  String? badgeId;
  String visibility = 'public';
  bool sending = false;
  String? sendError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        widget.chat.directory(),
        widget.engagement.badges(),
      ]);
      final me = widget.engagement.user.employeeId;
      if (!mounted) return;
      setState(() {
        data = _GiveData(
          r[0].where((e) => e['id']?.toString() != me).toList(),
          r[1],
        );
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = classifyLoadIssue(e) == LoadIssue.forbidden
            ? kRecognitionNotAllowedMessage
            : kManagerLoadFailedMessage;
        loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (sending) return;
    final text = message.text.trim();
    if (recipientId == null || badgeId == null || text.isEmpty) {
      setState(
        () => sendError = 'Choose a colleague and a badge and write a message.',
      );
      return;
    }
    final badge = data!.badges.firstWhere(
      (b) => b['id'].toString() == badgeId,
      orElse: () => const {},
    );
    final pts = asNum(badge['points_value'])?.toInt();
    setState(() {
      sending = true;
      sendError = null;
    });
    try {
      await widget.engagement.giveRecognition(
        givenTo: recipientId!,
        badgeId: badgeId!,
        message: text,
        visibility: visibility,
        points: pts,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        sending = false;
        sendError = classifyLoadIssue(e) == LoadIssue.forbidden
            ? kRecognitionNotAllowedMessage
            : kRecognitionFailedMessage;
      });
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (loadError != null) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(loadError!, textAlign: TextAlign.center),
      );
    } else if (data!.badges.isEmpty) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(kNoRecognitionBadgesMessage, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    } else if (data!.people.isEmpty) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'There is nobody to recognise yet.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    } else {
      final d = data!;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: _dec('Recipient'),
            items: [
              for (final e in d.people)
                DropdownMenuItem(
                  value: e['id'].toString(),
                  child: Text(
                    e['full_name']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => recipientId = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: _dec('Badge'),
            items: [
              for (final b in d.badges)
                DropdownMenuItem(
                  value: b['id'].toString(),
                  child: Text(
                    b['badge_name']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => badgeId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: message,
            maxLines: 3,
            decoration: _dec('Message'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: visibility,
            decoration: _dec('Visibility'),
            items: const [
              DropdownMenuItem(value: 'public', child: Text('Public')),
              DropdownMenuItem(value: 'private', child: Text('Private')),
            ],
            onChanged: (v) => setState(() => visibility = v ?? 'public'),
          ),
          if (sendError != null) ...[
            const SizedBox(height: 12),
            Text(
              sendError!,
              style: TextStyle(color: Colors.red[700], fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Send Recognition'),
            ),
          ),
        ],
      );
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Give Recognition',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              body,
            ],
          ),
        ),
      ),
    );
  }
}
