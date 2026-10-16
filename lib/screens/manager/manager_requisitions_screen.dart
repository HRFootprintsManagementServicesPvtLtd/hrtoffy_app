import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json_case.dart';
import '../../repositories/requisitions_repository.dart';
import '../../widgets/drawer_route.dart';
import '../../widgets/manager_drawer.dart';
import 'manager_requisition_form_screen.dart';
import 'widgets/manager_state_views.dart';

/// 404: the server does not have the requisitions routes yet.
const String kRequisitionsNotAvailableYetMessage =
    "Requisitions aren't available yet";

/// 403: the module is off or the role is not allowed.
const String kRequisitionsUnavailableMessage =
    "Requisitions aren't available for your role";

const _statusLabels = {
  'draft': 'Draft',
  'pending_approval': 'Pending Approval',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'converted': 'Converted',
  'cancelled': 'Cancelled',
};

const _priorityLabels = {
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'urgent': 'Urgent',
};

/// A fixed, friendly message for a failed requisition action. The server's own text is never shown.
String requisitionActionError(Object e) {
  if (e is ApiException) {
    if (e.isNetworkError) return "Couldn't reach the server. Please try again.";
    switch (e.statusCode) {
      case 400:
        return 'Please check the details and try again.';
      case 403:
        return 'Only the requester can do this.';
      case 404:
        return kRequisitionsNotAvailableYetMessage;
      case 409:
        return "This requisition can't be changed in its current state. Refresh and try again.";
    }
  }
  return "Couldn't complete that. Please try again.";
}

String requisitionStatusLabel(dynamic s) => _label(_statusLabels, s);
String requisitionPriorityLabel(dynamic s) => _label(_priorityLabels, s);

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

String _text(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? '-' : s;
}

Color _statusColor(String? s) {
  switch (s) {
    case 'approved':
    case 'converted':
      return Colors.green.shade700;
    case 'pending_approval':
      return Colors.orange.shade800;
    case 'rejected':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade700;
  }
}

Color _priorityColor(String? s) {
  switch (s) {
    case 'urgent':
      return Colors.red.shade700;
    case 'high':
      return Colors.orange.shade800;
    case 'medium':
      return Colors.blue.shade700;
    default:
      return Colors.grey.shade700;
  }
}

const _filters = <String?, String>{
  null: 'All',
  'draft': 'Draft',
  'pending_approval': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'cancelled': 'Cancelled',
};

const _pageSize = 20;

/// The manager's job requisitions (own and the reporting tree's, as the server scopes them), with create / edit /
/// submit / cancel for the requester. Deciding is HR-only and is not offered.
class ManagerRequisitionsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final RequisitionsRepository? requisitionsRepository;

  const ManagerRequisitionsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.requisitionsRepository,
  });

  @override
  State<ManagerRequisitionsScreen> createState() =>
      _ManagerRequisitionsScreenState();
}

class _ManagerRequisitionsScreenState extends State<ManagerRequisitionsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final RequisitionsRepository _repo =
      widget.requisitionsRepository ?? RequisitionsRepository();

  String? _status;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _moreError;
  LoadIssue? _issue;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    if (mounted) setState(() => _loading = true);
    try {
      final p = await _repo.list(status: _status, page: 1, limit: _pageSize);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = p.items;
        _total = p.total;
        _page = 1;
        _issue = null;
        _moreError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _issue = classifyLoadIssue(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final gen = _gen;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final p = await _repo.list(
        status: _status,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = [..._items, ...p.items];
        _total = p.total;
        _page += 1;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingMore = false;
        _moreError = kManagerLoadFailedMessage;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RequisitionDetailScreen(summary: row, repository: _repo),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RequisitionFormScreen(repository: _repo),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    switch (_issue) {
      case LoadIssue.forbidden:
        return const ManagerInfoState(kRequisitionsUnavailableMessage);
      case LoadIssue.notFound:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ManagerInfoState(kRequisitionsNotAvailableYetMessage),
              TextButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        );
      case LoadIssue.failed:
        return ManagerLoadFailed(onRetry: _reload);
      case null:
        break;
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No requisitions')),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _items.length + (_total > _items.length ? 1 : 0),
              itemBuilder: (context, i) {
                if (i < _items.length) {
                  return _RequisitionCard(
                    row: _items[i],
                    onTap: () => _open(_items[i]),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      if (_moreError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _moreError!,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: Colors.red[700],
                            ),
                          ),
                        ),
                      _loadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton(
                              onPressed: _loadMore,
                              child: const Text('Load more'),
                            ),
                    ],
                  ),
                );
              },
            ),
    );
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
        currentRoute: DrawerRoute.requisitions,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Requisitions',
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
      floatingActionButton: _issue == null && !_loading
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final f in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.value),
                      selected: _status == f.key,
                      onSelected: (_) {
                        if (_status == f.key) return;
                        setState(() => _status = f.key);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString();
    final priority = row['priority']?.toString();
    final small = GoogleFonts.montserrat(fontSize: 12, color: Colors.grey[700]);
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
                      _text(row['requisition_number']),
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _Badge(requisitionStatusLabel(status), _statusColor(status)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _text(row['position_title']),
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_text(row['department'])}  |  ${asInt(row['number_of_positions'], 1)} position(s)',
                style: small,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Badge(
                    requisitionPriorityLabel(priority),
                    _priorityColor(priority),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Requested by ${_text(row['requester_name'])}',
                style: small,
              ),
              Text(
                'Expected joining: ${_date(row['expected_joining_date'])}',
                style: small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One requisition with every field and, for the requester, Edit / Submit / Cancel.
class RequisitionDetailScreen extends StatefulWidget {
  const RequisitionDetailScreen({
    super.key,
    required this.summary,
    required this.repository,
  });

  final Map<String, dynamic> summary;
  final RequisitionsRepository repository;

  @override
  State<RequisitionDetailScreen> createState() =>
      _RequisitionDetailScreenState();
}

class _RequisitionDetailScreenState extends State<RequisitionDetailScreen> {
  Key _loaderKey = UniqueKey();
  bool _busy = false;

  Future<Map<String, dynamic>> _load() async {
    final r = await widget.repository.byId(widget.summary['id'].toString());
    return r.isEmpty ? widget.summary : r;
  }

  void _reload() => setState(() => _loaderKey = UniqueKey());

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body, String yes) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _act(
    String id,
    Future<Map<String, dynamic>> Function() call,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      _snack(done);
    } catch (e) {
      if (!mounted) return;
      _snack(requisitionActionError(e));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _submit(Map<String, dynamic> r) async {
    final ok = await _confirm(
      'Submit for approval?',
      'This sends ${_text(r['requisition_number'])} to be approved.',
      'Submit',
    );
    if (!ok || !mounted) return;
    final id = r['id'].toString();
    await _act(
      id,
      () => widget.repository.submit(id),
      'Submitted for approval',
    );
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final ok = await _confirm(
      'Cancel this requisition?',
      '${_text(r['requisition_number'])} will be cancelled.',
      'Cancel requisition',
    );
    if (!ok || !mounted) return;
    final id = r['id'].toString();
    await _act(id, () => widget.repository.cancel(id), 'Requisition cancelled');
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RequisitionFormScreen(repository: widget.repository, existing: r),
      ),
    );
    if (saved == true && mounted) _reload();
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
          widget.summary['requisition_number']?.toString() ?? 'Requisition',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: ManagerLoader<Map<String, dynamic>>(
        key: _loaderKey,
        load: _load,
        forbiddenMessage: kRequisitionsUnavailableMessage,
        builder: (context, r) {
          final status = r['status']?.toString();
          final mine = widget.repository.isMine(r['requested_by']);
          final canEdit = mine && (status == 'draft' || status == 'rejected');
          final canSubmit = mine && (status == 'draft' || status == 'rejected');
          final canCancel =
              mine &&
              (status == 'draft' ||
                  status == 'pending_approval' ||
                  status == 'rejected');
          final salary = r['salary_min'] == null && r['salary_max'] == null
              ? '-'
              : '${_text(r['currency'])} ${_text(r['salary_min'])} - ${_text(r['salary_max'])}';
          final exp = r['experience_min'] == null && r['experience_max'] == null
              ? '-'
              : '${_text(r['experience_min'])} - ${_text(r['experience_max'])} years';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Position', [
                _field('Title', _text(r['position_title'])),
                _field('Status', requisitionStatusLabel(status)),
                _field('Priority', requisitionPriorityLabel(r['priority'])),
                _field('Department', _text(r['department'])),
                _field('Location', _text(r['location'])),
                _field('Reports to', _text(r['reporting_to_name'])),
                _field(
                  'Employment type',
                  _label(const {}, r['employment_type']),
                ),
                _field('Positions', '${asInt(r['number_of_positions'], 1)}'),
                _field(
                  'Replacement',
                  r['is_replacement'] == true ? 'Yes' : 'No',
                ),
                _field('Experience', exp),
                _field('Salary', salary),
                _field('Key skills', _list(r['key_skills'])),
                _field('Qualifications', _list(r['qualifications'])),
                _field('Expected joining', _date(r['expected_joining_date'])),
              ]),
              _section('Description', [
                _field('Job description', _text(r['job_description'])),
                _field('Justification', _text(r['business_justification'])),
              ]),
              _section('Request', [
                _field('Requested by', _text(r['requester_name'])),
                _field('Created', _date(r['created_at'])),
                if (r['approved_at'] != null || r['approver_name'] != null)
                  _field('Approved by', _text(r['approver_name'])),
                if (r['approved_at'] != null)
                  _field('Approved on', _date(r['approved_at'])),
                if (r['rejected_at'] != null)
                  _field('Rejected on', _date(r['rejected_at'])),
                if ((r['rejection_reason'] ?? '').toString().isNotEmpty)
                  _field('Rejection reason', r['rejection_reason'].toString()),
              ]),
              if (canEdit || canSubmit || canCancel)
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (canEdit)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _edit(r),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    if (canSubmit)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _submit(r),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Submit'),
                      ),
                    if (canCancel)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _cancel(r),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  static String _list(dynamic v) {
    if (v is List && v.isNotEmpty) return v.map((e) => e.toString()).join(', ');
    return '-';
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
}
