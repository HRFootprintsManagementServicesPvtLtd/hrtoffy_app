import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_review.dart';

/// Statuses in which a request is still being decided somewhere along its approval chain.
const Set<String> kApprovalWaitingStatuses = {
  'pending',
  'manager_approved',
  'reviewer_approved',
};

bool approvalIsWaiting(Map<String, dynamic> row) => kApprovalWaitingStatuses
    .contains((row['status'] ?? '').toString().toLowerCase());

/// Who a request waits for, in words, from the engine's `required_role`. Unknown or missing: "someone else".
String approvalWaitingText(ApprovalMeta? meta) {
  final role = (meta?.requiredRole ?? '').trim().toLowerCase();
  const names = {
    'hr_manager': 'HR manager',
    'hr_head': 'HR head',
    'hr': 'HR',
    'manager': 'manager',
    'reviewer': 'reviewer',
    'finance': 'finance',
    'finance_manager': 'finance manager',
    'finance_head': 'finance head',
    'admin': 'admin',
    'owner': 'owner',
  };
  final name = names[role];
  return name == null ? 'Waiting on someone else' : 'Waiting on $name';
}

/// A module list split for the caller: what they may decide now, what waits for others, what is decided.
class ApprovalSplit {
  const ApprovalSplit({
    required this.needsMe,
    required this.waiting,
    required this.history,
    required this.meta,
    required this.metaFailed,
  });

  final List<Map<String, dynamic>> needsMe;
  final List<Map<String, dynamic>> waiting;
  final List<Map<String, dynamic>> history;
  final Map<String, ApprovalMeta> meta;

  /// True when the engine could not be asked: the waiting rows are then all in [waiting], without decision buttons.
  final bool metaFailed;
}

/// Splits [rows] with the engine's per-row answer (`POST .../workflows/module/<module>/row-meta`). The caller's own rows
/// are dropped (a person never decides their own request). A failing row-meta call does not throw: see [ApprovalSplit.metaFailed].
Future<ApprovalSplit> splitApprovalRows({
  required List<Map<String, dynamic>> rows,
  required String module,
  required ApprovalsRepository approvals,
}) async {
  String? me;
  try {
    me = approvals.employeeId;
  } catch (_) {
    me = null;
  }
  final others = [
    for (final r in rows)
      if (me == null || r['employee_id']?.toString() != me) r,
  ];
  final waiting = others.where(approvalIsWaiting).toList();
  final history = others.where((r) => !approvalIsWaiting(r)).toList();
  final ids = [
    for (final r in waiting)
      if ((r['id']?.toString() ?? '').isNotEmpty) r['id'].toString(),
  ];
  Map<String, ApprovalMeta> meta;
  try {
    meta = await approvals.rowMeta(module, ids);
  } catch (_) {
    return ApprovalSplit(
      needsMe: const [],
      waiting: waiting,
      history: history,
      meta: const {},
      metaFailed: true,
    );
  }
  bool mine(Map<String, dynamic> r) =>
      meta[r['id']?.toString()]?.canApprove == true;
  return ApprovalSplit(
    needsMe: waiting.where(mine).toList(),
    waiting: waiting.where((r) => !mine(r)).toList(),
    history: history,
    meta: meta,
    metaFailed: false,
  );
}

/// The number of rows still waiting in the caller's scope (decidable now or not). 
Future<int> countActionableRows({
  required List<Map<String, dynamic>> rows,
  required String module,
  required ApprovalsRepository approvals,
}) async {
  final split = await splitApprovalRows(
    rows: rows,
    module: module,
    approvals: approvals,
  );
  return split.needsMe.length + split.waiting.length;
}

const String kApprovalMetaFailed = "Couldn't check what you can decide.";

void approvalToast(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null),
  );
}

/// A panel with two lists, as on the website (Pending: everything waiting, decidable rows first with the review button,
/// the others marked "Waiting on ..."; History) for one module. Decisions are sent through
/// `decide`; the list is reloaded after every decision, also a refused one.
class ApprovalSplitPanel extends StatefulWidget {
  const ApprovalSplitPanel({
    super.key,
    required this.module,
    required this.loadRows,
    required this.approvalsRepository,
    required this.loadFailedText,
    required this.emptyActionText,
    required this.emptyHistoryText,
    required this.cardDetails,
    required this.review,
    required this.decide,
    required this.approvedText,
    required this.rejectedText,
    required this.errorText,
  });

  final String module;
  final Future<List<Map<String, dynamic>>> Function() loadRows;
  final ApprovalsRepository approvalsRepository;
  final String loadFailedText;
  final String emptyActionText;
  final String emptyHistoryText;

  /// The card's content above the footer.
  final List<Widget> Function(Map<String, dynamic> row) cardDetails;

  /// Shows the review dialog; canDecide false means a read-only view. Returns null when dismissed.
  final Future<ApprovalDecision?> Function(
    BuildContext context,
    Map<String, dynamic> row,
    bool canDecide,
  )
  review;

  /// Sends the decision. May throw; the panel shows `errorText` of it and reloads.
  final Future<void> Function(Map<String, dynamic> row, ApprovalDecision d)
  decide;
  final String approvedText;
  final String rejectedText;
  final String Function(Object e) errorText;

  @override
  State<ApprovalSplitPanel> createState() => _ApprovalSplitPanelState();
}

class _ApprovalSplitPanelState extends State<ApprovalSplitPanel> {
  ApprovalSplit? _split;
  bool _loading = true;
  bool _failed = false;
  String? _busyId;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _split == null);
    try {
      final rows = await widget.loadRows();
      final split = await splitApprovalRows(
        rows: rows,
        module: widget.module,
        approvals: widget.approvalsRepository,
      );
      if (!mounted) return;
      setState(() {
        _split = split;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _split = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> row, bool canDecide) async {
    final d = await widget.review(context, row, canDecide);
    if (d == null || !mounted || !canDecide) return;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      await widget.decide(row, d);
      if (mounted) {
        approvalToast(
          context,
          d.approve ? widget.approvedText : widget.rejectedText,
        );
      }
    } catch (e) {
      if (mounted) approvalToast(context, widget.errorText(e), error: true);
    }
    if (mounted) setState(() => _busyId = null);
    await _load(); // the list is the server's answer, also after a refusal
  }

  @override
  Widget build(BuildContext context) {
    final s = _split;
    return Column(
      children: [
        ApprovalSegments(
          labels: const ['Pending', 'History'],
          counts: [
            s == null ? null : s.needsMe.length + s.waiting.length,
            s?.history.length,
          ],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        Expanded(child: _body(s)),
      ],
    );
  }

  Widget _body(ApprovalSplit? s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed || s == null) {
      return ApprovalMessage(
        widget.loadFailedText,
        onRetry: _load,
        isError: true,
      );
    }
    final shown = _tab == 0 ? [...s.needsMe, ...s.waiting] : s.history;
    if (shown.isEmpty) {
      return ApprovalMessage(
        _tab == 0 ? widget.emptyActionText : widget.emptyHistoryText,
      );
    }
    final note = _tab == 0 && s.metaFailed;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: shown.length + (note ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (note && i == 0) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    kApprovalMetaFailed,
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.red[700],
                    ),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            );
          }
          final row = shown[i - (note ? 1 : 0)];
          return _card(row, _tab, s.needsMe.contains(row));
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> row, int tab, bool canDecide) {
    final id = row['id']?.toString();
    final s = _split!;
    return KeyedSubtree(
      key: ValueKey('approval-card-$id'),
      child: approvalCardShell(
        children: [
          ...widget.cardDetails(row),
          if (tab == 0 && !canDecide && !s.metaFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                approvalWaitingText(s.meta[id]),
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
          approvalReviewButton(
            open: canDecide,
            busy: _busyId == id,
            onPressed: () => _open(row, canDecide),
          ),
        ],
      ),
    );
  }
}
