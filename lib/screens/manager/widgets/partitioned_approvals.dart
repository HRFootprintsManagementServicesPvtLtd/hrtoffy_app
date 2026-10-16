import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';

/// Statuses of a request that still waits for a decision.
const Set<String> kApprovalWaitingStatuses = {
  'pending',
  'manager_approved',
  'reviewer_approved',
};

const String kPartitionMetaFailedNote = "Couldn't check what you can decide.";
const String kPartitionLoadFailedMessage =
    "Couldn't load requests. Please try again.";
const String kPartitionWaitingUnknown = 'Waiting on someone else';
const int kPartitionHistoryCap = 50;

/// "Waiting on HR manager" from the engine's `requiredRole`; a generic text when the role is unknown (a raw role name or id
/// is never shown).
String approvalWaitingOnText(ApprovalMeta? meta) {
  switch ((meta?.requiredRole ?? '').trim().toLowerCase()) {
    case 'hr_manager':
      return 'Waiting on HR manager';
    case 'hr_head':
      return 'Waiting on HR head';
    case 'hr':
      return 'Waiting on HR';
    case 'manager':
      return 'Waiting on manager';
    case 'reviewer':
      return 'Waiting on reviewer';
    case 'admin':
      return 'Waiting on admin';
    case 'finance':
      return 'Waiting on finance';
    default:
      return kPartitionWaitingUnknown;
  }
}

/// The three lists of an approvals panel.
class ApprovalPartitionResult {
  const ApprovalPartitionResult({
    required this.actionable,
    required this.waiting,
    required this.history,
    required this.metaFailed,
    required this.metaById,
  });
  final List<Map<String, dynamic>> actionable;
  final List<Map<String, dynamic>> waiting;
  final List<Map<String, dynamic>> history;
  final bool metaFailed;
  final Map<String, ApprovalMeta> metaById;
}

bool _isOwn(Map<String, dynamic> row, String own) =>
    row['employee_id']?.toString() == own;

String _status(Map<String, dynamic> r) =>
    (r['status'] ?? '').toString().trim().toLowerCase();

/// Loads the rows, drops the caller's own, asks the engine (row-meta) which waiting rows the caller may decide and splits
/// them. [loadWaiting] gives the module's rows (waiting ones are picked by status); [loadHistory] (optional) the decided
/// ones. When row-meta fails the waiting rows are returned as `waiting` with [ApprovalPartitionResult.metaFailed] set (never a guess).
/// With [throwOnMetaFailure] a row-meta failure is thrown instead (for counts).
Future<ApprovalPartitionResult> loadApprovalPartition({
  required ApprovalsRepository repo,
  required String module,
  required Future<List<Map<String, dynamic>>> Function() loadWaiting,
  Future<List<Map<String, dynamic>>> Function()? loadHistory,
  bool throwOnMetaFailure = false,
}) async {
  final own = repo.employeeId;
  final all = await loadWaiting();
  final histRows = loadHistory == null ? all : await loadHistory();
  final waitingRows = [
    for (final r in all)
      if (!_isOwn(r, own) && kApprovalWaitingStatuses.contains(_status(r))) r,
  ];
  final history = [
    for (final r in histRows)
      if (!_isOwn(r, own) &&
          !kApprovalWaitingStatuses.contains(_status(r)) &&
          _status(r).isNotEmpty &&
          _status(r) != 'draft')
        r,
  ].take(kPartitionHistoryCap).toList();

  var meta = <String, ApprovalMeta>{};
  var failed = false;
  if (waitingRows.isNotEmpty) {
    try {
      meta = await repo.rowMeta(module, [
        for (final r in waitingRows) r['id'].toString(),
      ]);
    } catch (_) {
      if (throwOnMetaFailure) rethrow;
      failed = true;
    }
  }
  final actionable = <Map<String, dynamic>>[];
  final others = <Map<String, dynamic>>[];
  for (final r in waitingRows) {
    if (!failed && meta[r['id'].toString()]?.canApprove == true) {
      actionable.add(r);
    } else {
      others.add(r);
    }
  }
  return ApprovalPartitionResult(
    actionable: actionable,
    waiting: others,
    history: history,
    metaFailed: failed,
    metaById: meta,
  );
}

/// Three tabs: "Needs my action (n)" (Approve / Reject), "Waiting on others (n)" (who it waits for, no buttons) and
/// "History (n)". After every decision, also a refused one, the lists are loaded again.
class PartitionedApprovalsView extends StatefulWidget {
  const PartitionedApprovalsView({
    super.key,
    required this.heading,
    required this.load,
    required this.cardBody,
    required this.approve,
    required this.reject,
    this.dialogSummary,
  });

  final String heading;
  final Future<ApprovalPartitionResult> Function() load;
  final Widget Function(Map<String, dynamic> row, {required bool history})
  cardBody;
  final Future<void> Function(Map<String, dynamic> row, String comments)
  approve;
  final Future<void> Function(Map<String, dynamic> row, String reason) reject;
  final String? Function(Map<String, dynamic> row)? dialogSummary;

  @override
  State<PartitionedApprovalsView> createState() =>
      _PartitionedApprovalsViewState();
}

class _PartitionedApprovalsViewState extends State<PartitionedApprovalsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  ApprovalPartitionResult? _data;
  bool _loading = true;
  bool _failed = false;
  final Set<String> _busy = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    final gen = ++_generation;
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final d = await widget.load();
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = d;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        if (!silent || _data == null) _failed = true;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final id = row['id'].toString();
    final result = await showApprovalDecisionDialog(
      context,
      mode: approve ? ApprovalDialogMode.approve : ApprovalDialogMode.reject,
      title: approve ? 'Approve request' : 'Reject request',
      summary: widget.dialogSummary?.call(row),
    );
    if (result == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (approve) {
        await widget.approve(row, result.comments);
      } else {
        await widget.reject(row, result.comments);
      }
      if (!mounted) return;
      approvalSnack(context, approve ? 'Request approved' : 'Request rejected');
    } catch (e) {
      if (!mounted) return;
      approvalSnack(context, approvalsErrorText(e), error: true);
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    await _reload(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _tabBar(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.heading,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _loading ? null : () => _reload(silent: true),
        ),
      ],
    ),
  );

  Widget _tabBar() {
    final d = _data;
    String label(String t, int? n) => n == null || _failed ? t : '$t ($n)';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        tabs: [
          Tab(text: label('Needs my action', d?.actionable.length)),
          Tab(text: label('Waiting on others', d?.waiting.length)),
          Tab(text: label('History', d?.history.length)),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final d = _data;
    if (_failed || d == null) {
      return ApprovalMessage(
        text: kPartitionLoadFailedMessage,
        icon: Icons.cloud_off_rounded,
        onRetry: _reload,
      );
    }
    final index = _tabs.index;
    final rows = index == 0
        ? d.actionable
        : index == 1
        ? d.waiting
        : d.history;
    final note = d.metaFailed && index == 1;
    if (d.metaFailed && index == 0) {
      return const ApprovalMessage(
        text: kPartitionMetaFailedNote,
        icon: Icons.info_outline_rounded,
      );
    }
    if (rows.isEmpty) {
      return ApprovalMessage(
        text: index == 0
            ? 'Nothing needs your action'
            : index == 1
            ? 'Nothing is waiting on others'
            : 'No history yet',
        icon: Icons.inbox_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _reload(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: rows.length + (note ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (note && i == 0) {
            return Text(
              kPartitionMetaFailedNote,
              key: const ValueKey('meta-failed-note'),
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.orange.shade800,
              ),
            );
          }
          return _card(rows[i - (note ? 1 : 0)], index, d);
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> row, int tab, ApprovalPartitionResult d) {
    final id = row['id'].toString();
    final busy = _busy.contains(id);
    return Container(
      key: ValueKey('row-$id'),
      padding: const EdgeInsets.all(16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.cardBody(row, history: tab == 2),
          if (tab == 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: ValueKey('reject-$id'),
                    onPressed: busy ? null : () => _decide(row, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: ValueKey('approve-$id'),
                    onPressed: busy ? null : () => _decide(row, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ] else if (tab == 1 && !d.metaFailed) ...[
            const SizedBox(height: 10),
            Text(
              approvalWaitingOnText(d.metaById[row['id'].toString()]),
              key: ValueKey('waiting-$id'),
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
