import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';

const String kDecisionEmptyMessage = 'No requests found';
const String kDecisionLoadFailedMessage =
    "Couldn't load requests. Please try again.";
const String kDecisionWaitingMessage = 'Waiting for another approver';

/// Pending / History list of requests that have a dedicated list route (regularization, overtime). The panel asks the
/// approval engine (row-meta) which pending rows the caller may decide and enables the Review button for those only; when
/// that answer is unavailable the button stays enabled and the server's refusal is shown in friendly words.
class DecisionListPanel extends StatefulWidget {
  const DecisionListPanel({
    super.key,
    required this.eyebrow,
    required this.heading,
    required this.metaModule,
    required this.repository,
    required this.load,
    required this.cardBody,
    required this.approve,
    required this.reject,
    required this.dialogTitle,
    this.dialogSummary,
    this.onBack,
  });

  final String eyebrow;
  final String heading;

  /// Engine module name for the row-meta question.
  final String metaModule;
  final ApprovalsRepository repository;
  final Future<List<Map<String, dynamic>>> Function(bool history) load;
  final Widget Function(Map<String, dynamic> row, bool history) cardBody;
  final Future<void> Function(Map<String, dynamic> row, String comments)
  approve;
  final Future<void> Function(Map<String, dynamic> row, String comments) reject;
  final String dialogTitle;
  final String? Function(Map<String, dynamic> row)? dialogSummary;
  final VoidCallback? onBack;

  @override
  State<DecisionListPanel> createState() => _DecisionListPanelState();
}

class _DecisionListPanelState extends State<DecisionListPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _rows = [];
  Map<String, ApprovalMeta> _meta = {};
  bool _loading = true;
  bool _failed = false;
  final Set<String> _busy = {};
  int _generation = 0;

  bool get _history => _tabs.index == 1;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_generation;
    final history = _history;
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
        _rows = [];
      });
    }
    try {
      final rows = await widget.load(history);
      var meta = <String, ApprovalMeta>{};
      if (!history && rows.isNotEmpty) {
        try {
          meta = await widget.repository.rowMeta(widget.metaModule, [
            for (final r in rows) r['id'].toString(),
          ]);
        } catch (_) {
          // no answer: buttons stay enabled and the server decides on click
        }
      }
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = rows;
        _meta = meta;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _failed = true;
      });
    }
  }

  Future<void> _review(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final result = await showApprovalDecisionDialog(
      context,
      mode: ApprovalDialogMode.review,
      title: widget.dialogTitle,
      summary: widget.dialogSummary?.call(row),
    );
    if (result == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (result.approve) {
        await widget.approve(row, result.comments);
      } else {
        await widget.reject(row, result.comments);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        _rows = _rows.where((r) => r['id'].toString() != id).toList();
      });
      approvalSnack(
        context,
        'Request ${result.approve ? 'approved' : 'rejected'}',
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      approvalSnack(context, approvalsErrorText(e), error: true);
      if (approvalIsStale(e)) await _load(silent: true);
    }
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

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.eyebrow,
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.heading,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.onBack != null) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: widget.onBack,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Back to inbox',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabs,
        indicator: BoxDecoration(
          color: Colors.blue.shade600,
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        tabs: const [
          Tab(text: 'Pending'),
          Tab(text: 'History'),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return ApprovalMessage(
        text: kDecisionLoadFailedMessage,
        icon: Icons.cloud_off_rounded,
        onRetry: _load,
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          kDecisionEmptyMessage,
          style: GoogleFonts.montserrat(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(_rows[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = row['id'].toString();
    final history = _history;
    final meta = _meta[id];
    final allowed = meta == null || meta.canApprove;
    final busy = _busy.contains(id);
    return Container(
      key: ValueKey('row-$id'),
      padding: const EdgeInsets.all(16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.cardBody(row, history),
          if (!history) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: ValueKey('review-$id'),
                onPressed: allowed && !busy ? () => _review(row) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                    : const Text('Review Request'),
              ),
            ),
            if (!allowed) ...[
              const SizedBox(height: 6),
              Text(
                kDecisionWaitingMessage,
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),
            ],
          ] else if ((row['manager_comments']?.toString() ?? '')
              .isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Comments: ${row['manager_comments']}',
              style: GoogleFonts.montserrat(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
