import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';

/// Texts of [InboxApprovalsPanel].
const String kInboxEmptyMessage = 'No pending requests';
const String kInboxLoadFailedMessage =
    "Couldn't load requests. Please try again.";

/// Pending requests of ONE module (`leaves`, `expenses`, `benefits`, `travel_claims`, `loans`, ...) that the signed-in
/// approver may decide now, from the approvals inbox (`GET /approvals`, plus `/reviewer-queue` for reviewers and HR).
/// The server lists only requests the caller can decide at their current step; Approve and Reject go through the
/// approval engine's decision routes, never a direct status write.
///
/// Works both inside a scroll view (it shrink-wraps) and in a bounded box (its list scrolls and pulls to refresh).
class InboxApprovalsPanel extends StatefulWidget {
  const InboxApprovalsPanel({
    super.key,
    required this.module,
    this.title,
    this.repository,
  });

  final String module;
  final String? title;
  final ApprovalsRepository? repository;

  @override
  State<InboxApprovalsPanel> createState() => _InboxApprovalsPanelState();
}

class _InboxApprovalsPanelState extends State<InboxApprovalsPanel> {
  late final ApprovalsRepository _repo =
      widget.repository ?? ApprovalsRepository();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _failed = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant InboxApprovalsPanel old) {
    super.didUpdateWidget(old);
    if (old.module != widget.module) _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final items = await _repo.inbox(module: widget.module);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _items.isEmpty) _failed = true;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> item, bool approve) async {
    final id = item['id'].toString();
    final who = _record(item)['employee_full_name']?.toString();
    final result = await showApprovalDecisionDialog(
      context,
      mode: approve ? ApprovalDialogMode.approve : ApprovalDialogMode.reject,
      title: approve ? 'Approve request' : 'Reject request',
      summary: who,
    );
    if (result == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      if (approve) {
        await _repo.approveInbox(id, comments: result.comments);
      } else {
        await _repo.rejectInbox(id, reason: result.comments);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        _items = _items.where((e) => e['id'].toString() != id).toList();
      });
      approvalSnack(context, approve ? 'Request approved' : 'Request rejected');
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final header = _header();
        if (_loading) {
          final spinner = const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
          return bounded
              ? Column(
                  children: [
                    header,
                    Expanded(child: spinner),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [header, spinner],
                );
        }
        if (_failed) {
          final msg = ApprovalMessage(
            text: kInboxLoadFailedMessage,
            icon: Icons.cloud_off_rounded,
            onRetry: _load,
          );
          return bounded
              ? Column(
                  children: [
                    header,
                    Expanded(child: msg),
                  ],
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [header, msg]);
        }
        if (_items.isEmpty) {
          final msg = const ApprovalMessage(
            text: kInboxEmptyMessage,
            icon: Icons.inbox_outlined,
          );
          return bounded
              ? Column(
                  children: [
                    header,
                    Expanded(child: msg),
                  ],
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [header, msg]);
        }
        final cards = [for (final it in _items) _card(it)];
        if (bounded) {
          return Column(
            children: [
              header,
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: cards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => cards[i],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    final count = _loading || _failed ? null : _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [
                if (widget.title != null) widget.title!,
                if (count != null) '$count pending',
              ].join(' · '),
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
            onPressed: _loading ? null : () => _load(silent: true),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _record(Map<String, dynamic> item) {
    final r = item['record'];
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  Widget _card(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final rec = _record(item);
    final code = rec['employee_code']?.toString();
    final busy = _busy.contains(id);
    final details = inboxDetails(canonicalApprovalModule(widget.module), rec);
    final reason = _reasonOf(rec);
    return Container(
      key: ValueKey('inbox-$id'),
      padding: const EdgeInsets.all(16),
      decoration: approvalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApprovalApplicantRow(
            name: rec['employee_full_name']?.toString(),
            subtitle: code,
            trailing: const ApprovalStatusPill('pending'),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [for (final d in details) ApprovalDetail(d.$1, d.$2)],
            ),
          ],
          if (reason != null) ...[
            const SizedBox(height: 12),
            Text(
              reason,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.black87,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('reject-$id'),
                  onPressed: busy ? null : () => _decide(item, false),
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
                  onPressed: busy ? null : () => _decide(item, true),
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
        ],
      ),
    );
  }

  String? _reasonOf(Map<String, dynamic> rec) {
    for (final k in ['reason', 'description', 'purpose', 'trip_purpose']) {
      final v = rec[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }
}

/// The key facts of a request the server sent in `record`, as (label, value) pairs. Only what the server provided is
/// listed: a missing field is left out, an amount that is missing or zero is never shown as 0.
List<(String, String)> inboxDetails(String module, Map<String, dynamic> r) {
  final out = <(String, String)>[];
  void add(String label, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      out.add((label, value.trim()));
    }
  }

  String? range(dynamic from, dynamic to) {
    final a = approvalDate(from);
    final b = approvalDate(to);
    if (a == null) return b;
    return b == null || a == b ? a : '$a - $b';
  }

  switch (module) {
    case 'leaves':
      add('Type', _title(r['leave_type']));
      add('Dates', range(r['from_date'], r['to_date']));
      final days = r['total_days'];
      if (days != null && '$days'.isNotEmpty) {
        final n = num.tryParse('$days');
        add(
          'Days',
          n == null ? null : (n == n.roundToDouble() ? '${n.toInt()}' : '$n'),
        );
      }
      add('Session', _title(r['half_day_session']));
    case 'expenses':
      add('Title', r['title']?.toString());
      add('Date', approvalDate(r['expense_date'] ?? r['claim_date']));
      add('Merchant', r['merchant_name']?.toString());
      add('Amount', approvalAmount(r['total_amount'] ?? r['amount']));
    case 'benefits':
      add('Date', approvalDate(r['claim_date']));
      add('Amount', approvalAmount(r['claimed_amount']));
    case 'loans':
      add('Category', _title(r['loan_category']));
      add('Amount', approvalAmount(r['requested_amount']));
      final t = r['tenure_months'];
      if (t != null && '$t'.isNotEmpty) add('Tenure', '$t months');
    case 'travel_claims':
      add('Destination', r['trip_destination']?.toString());
      add('Dates', range(r['trip_from_date'], r['trip_to_date']));
      add('Total', approvalAmount(r['total_amount']));
    case 'overtime':
      add('Date', approvalDate(r['ot_date']));
      final h = r['total_hours'];
      if (h != null && '$h'.isNotEmpty) add('Hours', '$h hrs');
      add('Type', _title(r['ot_type']));
    default:
      add('Date', approvalDate(r['created_at']));
  }
  return out;
}

String? _title(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  if (RegExp(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-").hasMatch(s)) {
    return null; // an id is never shown
  }
  final t = s.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}
