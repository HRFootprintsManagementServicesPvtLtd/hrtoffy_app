import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/disciplinary_repository.dart';
import '../../widgets/drawer_route.dart';
import '../../widgets/manager_drawer.dart';
import 'widgets/manager_state_views.dart';

/// Shown when the server refuses disciplinary cases (403: module off or role not allowed).
const String kDisciplinaryUnavailableMessage =
    "Disciplinary cases aren't available for your role";

const _closedStatuses = {'closed', 'withdrawn'};

const _statusLabels = {
  'draft': 'Draft',
  'pending_hr_approval': 'Pending HR Approval',
  'issued': 'Issued',
  'response_received': 'Response Received',
  'under_review': 'Under Review',
  'action_taken': 'Action Taken',
  'closed': 'Closed',
  'withdrawn': 'Withdrawn',
};

const _severityLabels = {
  'minor': 'Minor',
  'moderate': 'Moderate',
  'major': 'Major',
  'gross': 'Gross Misconduct',
};

const _actionLabels = {
  'verbal_warning': 'Verbal Warning',
  'written_warning': 'Written Warning',
  'final_warning': 'Final Written Warning',
  'fine': 'Fine',
  'suspension': 'Suspension',
  'demotion': 'Demotion',
  'termination': 'Termination',
  'case_dropped': 'Case Dropped (No Action)',
};

String _label(Map<String, String> labels, dynamic v) {
  final s = v?.toString() ?? '';
  if (s.isEmpty) return '-';
  return labels[s] ??
      s
          .split('_')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
}

String _date(dynamic v) {
  final d = asDate(v);
  return d == null ? '-' : DateFormat('d MMM yyyy').format(d.toLocal());
}

Color _statusColor(String? s) {
  switch (s) {
    case 'closed':
      return Colors.green.shade700;
    case 'issued':
      return Colors.blue.shade700;
    case 'response_received':
      return Colors.deepPurple;
    case 'under_review':
      return Colors.lightBlue.shade700;
    case 'action_taken':
    case 'pending_hr_approval':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade700;
  }
}

enum _Filter { all, open, closed }

/// Read-only list of the disciplinary cases the server shows the signed-in manager (their reporting tree).
/// Opening, acting on and closing cases are HR-only and not offered here; every call is a GET.
class ManagerDisciplinaryScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final DisciplinaryRepository? disciplinaryRepository;

  const ManagerDisciplinaryScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.disciplinaryRepository,
  });

  @override
  State<ManagerDisciplinaryScreen> createState() =>
      _ManagerDisciplinaryScreenState();
}

class _ManagerDisciplinaryScreenState extends State<ManagerDisciplinaryScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final DisciplinaryRepository _repo =
      widget.disciplinaryRepository ?? DisciplinaryRepository();

  _Filter _filter = _Filter.all;
  Key _loaderKey = UniqueKey();
  Map<String, String> _names = const {};

  Future<List<Map<String, dynamic>>> _load() async {
    final results = await Future.wait<Object>([
      _repo.cases(),
      _repo.employeeNames().catchError((_) => <String, String>{}),
    ]);
    _names = results[1] as Map<String, String>;
    return results[0] as List<Map<String, dynamic>>;
  }

  Future<void> _refresh() async {
    setState(() => _loaderKey = UniqueKey());
  }

  bool _matches(Map<String, dynamic> c) {
    final closed = _closedStatuses.contains(c['status']?.toString());
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.open:
        return !closed;
      case _Filter.closed:
        return closed;
    }
  }

  String _nameOf(Map<String, dynamic> c) =>
      _names[c['employee_id']?.toString()] ?? 'Employee';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.disciplinary,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Disciplinary Cases',
          style: GoogleFonts.montserrat(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu, color: Colors.black),
          ),
        ],
      ),
      body: ManagerLoader<List<Map<String, dynamic>>>(
        key: _loaderKey,
        load: _load,
        forbiddenMessage: kDisciplinaryUnavailableMessage,
        isEmpty: (rows) => rows.isEmpty,
        emptyText: 'No disciplinary cases',
        builder: (context, rows) {
          final shown = rows.where(_matches).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            const {
                              _Filter.all: 'All',
                              _Filter.open: 'Open',
                              _Filter.closed: 'Closed',
                            }[f]!,
                          ),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: shown.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No cases match this filter')),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: shown.length,
                          itemBuilder: (context, i) => _CaseCard(
                            row: shown[i],
                            name: _nameOf(shown[i]),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DisciplinaryCaseDetailScreen(
                                  summary: shown[i],
                                  employeeName: _nameOf(shown[i]),
                                  repository: _repo,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.row, required this.name, required this.onTap});

  final Map<String, dynamic> row;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString();
    final color = _statusColor(status);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row['case_number']?.toString() ?? 'Case',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _label(_statusLabels, status),
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${row['category'] ?? '-'}  |  ${_label(_severityLabels, row['severity'])}  |  ${_date(row['incident_date'])}',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseDetail {
  _CaseDetail(this.caseRow, this.actions, this.responses);
  final Map<String, dynamic> caseRow;
  final List<Map<String, dynamic>> actions;
  final List<Map<String, dynamic>> responses;
}

/// One case, read-only: its fields, the actions taken (oldest first) and the employee's responses.
class DisciplinaryCaseDetailScreen extends StatelessWidget {
  const DisciplinaryCaseDetailScreen({
    super.key,
    required this.summary,
    required this.employeeName,
    required this.repository,
  });

  final Map<String, dynamic> summary;
  final String employeeName;
  final DisciplinaryRepository repository;

  Future<_CaseDetail> _load() async {
    final id = summary['id'].toString();
    final c = await repository.caseById(id);
    List<Map<String, dynamic>> embedded(String key) => asMapList(
      c[key],
    ).map((m) => Map<String, dynamic>.from(snakeKeys(m) as Map)).toList();
    // The case already embeds both lists; the dedicated routes are asked too and the embedded rows are the fallback.
    final actions = await repository
        .actions(id)
        .catchError((_) => embedded('disciplinary_actions'));
    final responses = await repository
        .responses(id)
        .catchError((_) => embedded('disciplinary_responses'));
    return _CaseDetail(c.isEmpty ? summary : c, actions, responses);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          summary['case_number']?.toString() ?? 'Disciplinary case',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: ManagerLoader<_CaseDetail>(
        load: _load,
        forbiddenMessage: kDisciplinaryUnavailableMessage,
        builder: (context, d) {
          final c = d.caseRow;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Case', [
                _field('Employee', employeeName),
                _field('Status', _label(_statusLabels, c['status'])),
                _field('Category', c['category']?.toString() ?? '-'),
                _field('Severity', _label(_severityLabels, c['severity'])),
                _field('Incident date', _date(c['incident_date'])),
                _field('Issued', _date(c['issued_at'])),
                _field('Response due', _date(c['response_due_at'])),
                if (c['closed_at'] != null)
                  _field('Closed', _date(c['closed_at'])),
                if ((c['final_action'] ?? '').toString().isNotEmpty)
                  _field(
                    'Final action',
                    _label(_actionLabels, c['final_action']),
                  ),
                if ((c['final_remarks'] ?? '').toString().isNotEmpty)
                  _field('Final remarks', c['final_remarks'].toString()),
                _field(
                  'Description',
                  (c['incident_description'] ?? '-').toString(),
                ),
              ]),
              _section('Actions', [
                if (d.actions.isEmpty)
                  const Text('No actions yet')
                else
                  for (final a in d.actions)
                    _entry(
                      _label(_actionLabels, a['action_type']),
                      [
                        _date(a['action_date'] ?? a['created_at']),
                        if (a['suspension_days'] != null)
                          '${a['suspension_days']} day(s) suspension',
                        if (a['fine_amount'] != null &&
                            asDouble(a['fine_amount']) > 0)
                          'Fine ${asDouble(a['fine_amount']).toStringAsFixed(2)}',
                      ].join('  |  '),
                      a['remarks']?.toString(),
                    ),
              ]),
              _section('Employee responses', [
                if (d.responses.isEmpty)
                  const Text('No responses yet')
                else
                  for (final r in d.responses)
                    _entry(
                      _date(r['submitted_at'] ?? r['created_at']),
                      (r['attachment_name'] ?? '').toString().isEmpty
                          ? ''
                          : 'Attachment: ${r['attachment_name']}',
                      r['response_text']?.toString(),
                    ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  Widget _field(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _entry(String title, String sub, String? body) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        if (body != null && body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(body, style: GoogleFonts.montserrat(fontSize: 12)),
          ),
      ],
    ),
  );
}
