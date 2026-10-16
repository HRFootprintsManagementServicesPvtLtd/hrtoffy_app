import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../repositories/approvals_repository.dart';
import '../../../repositories/coff_repository.dart';
import 'approval_common.dart';
import 'partitioned_approvals.dart';

/// Shown when the server has no C-Off list route yet (an older server).
const String kCoffUnavailableMessage = "C-Off approvals aren't available yet";

/// Splits C-Off rows as the server already classified them (`can_decide`, `required_role`): no row-meta call is needed.
/// Rows that can be decided come first.
ApprovalPartitionResult partitionCoffRows({
  required List<Map<String, dynamic>> pending,
  required List<Map<String, dynamic>> decided,
}) {
  bool waits(Map<String, dynamic> r) => kApprovalWaitingStatuses.contains(
    (r['status'] ?? '').toString().trim().toLowerCase(),
  );
  final waitingRows = pending.where(waits).toList();
  final actionable = [
    for (final r in waitingRows)
      if (r['can_decide'] == true) r,
  ];
  final others = [
    for (final r in waitingRows)
      if (r['can_decide'] != true) r,
  ];
  final history = [
    for (final r in decided)
      if (!waits(r) && '${r['status'] ?? ''}'.trim().isNotEmpty) r,
  ].take(kPartitionHistoryCap).toList();
  return ApprovalPartitionResult(
    actionable: actionable,
    waiting: others,
    history: history,
    metaFailed: false,
    metaById: {
      for (final r in others)
        r['id'].toString(): ApprovalMeta(
          canApprove: false,
          requiredRole: r['required_role']?.toString(),
        ),
    },
  );
}

/// Team C-Off (compensatory off) requests: Pending (decidable first) / History. List and decision both come from the
/// time service (`GET /leaves/coff-requests?scope=team`, `POST /leaves/coff-requests/:id/decide`).
class CoffApprovalsPanel extends StatefulWidget {
  const CoffApprovalsPanel({super.key, this.repository});

  final CoffRepository? repository;

  @override
  State<CoffApprovalsPanel> createState() => _CoffApprovalsPanelState();
}

class _CoffApprovalsPanelState extends State<CoffApprovalsPanel> {
  late final CoffRepository _repo = widget.repository ?? CoffRepository();
  bool _unavailable = false;
  int _attempt = 0;

  Future<ApprovalPartitionResult> _load() async {
    try {
      final pending = await _repo.teamRequests(history: false);
      final decided = await _repo.teamRequests(history: true);
      return partitionCoffRows(pending: pending, decided: decided);
    } catch (e) {
      if (e is ApiException && e.isNotFound && mounted && !_unavailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _unavailable = true);
        });
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) {
      return ApprovalMessage(
        text: kCoffUnavailableMessage,
        icon: Icons.info_outline,
        onRetry: () => setState(() {
          _unavailable = false;
          _attempt++;
        }),
      );
    }
    return PartitionedApprovalsView(
      key: ValueKey('coff-$_attempt'),
      heading: 'C-Off requests',
      load: _load,
      approve: (row, c) =>
          _repo.decide(row['id'].toString(), approve: true, comments: c),
      reject: (row, c) =>
          _repo.decide(row['id'].toString(), approve: false, comments: c),
      dialogSummary: (row) => _name(row),
      cardBody: (row, {required history}) => _body(row, history),
    );
  }

  static String? _name(Map<String, dynamic> row) {
    final e = row['employee_records'];
    final n = e is Map ? e['full_name']?.toString().trim() : null;
    return n == null || n.isEmpty ? null : n;
  }

  static String? _workType(Map<String, dynamic> row) {
    final t = (row['work_type'] ?? '').toString().trim();
    final holiday = (row['holiday_name'] ?? '').toString().trim();
    final label = t.isEmpty
        ? null
        : (t == 'weekly_off'
              ? 'Weekly off'
              : t == 'holiday'
              ? 'Holiday'
              : t[0].toUpperCase() + t.substring(1).replaceAll('_', ' '));
    if (label == null) return holiday.isEmpty ? null : holiday;
    return holiday.isEmpty ? label : '$label ($holiday)';
  }

  Widget _body(Map<String, dynamic> row, bool history) {
    final emp = row['employee_records'] is Map
        ? Map<String, dynamic>.from(row['employee_records'] as Map)
        : const <String, dynamic>{};
    final status = (row['status'] ?? 'pending').toString();
    final sub = [
      emp['employee_id'],
      emp['department'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final date = approvalDate(row['work_date']);
    final type = _workType(row);
    final h = num.tryParse('${row['hours_worked'] ?? ''}');
    final hours = h == null || h <= 0
        ? null
        : (h == h.roundToDouble() ? '${h.toInt()}' : h.toStringAsFixed(2));
    final reason = row['reason']?.toString().trim();
    final comments = row['review_comments']?.toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ApprovalApplicantRow(
          name: emp['full_name']?.toString(),
          subtitle: sub,
          trailing: ApprovalStatusPill(status),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            if (date != null) ApprovalDetail('Worked on', date),
            if (type != null) ApprovalDetail('Type', type),
            if (hours != null) ApprovalDetail('Hours', hours),
          ],
        ),
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            reason,
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87),
          ),
        ],
        if (history && comments != null && comments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Comments: $comments',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ],
    );
  }
}
