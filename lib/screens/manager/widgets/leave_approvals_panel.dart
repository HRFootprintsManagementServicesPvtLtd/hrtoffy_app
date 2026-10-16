import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';
import 'partitioned_approvals.dart';

/// Team leave applications split by what the caller may do: needs my action / waiting on others / history. The list comes
/// from the time service (`GET /leaves/team-applications`), the engine's row-meta says who may decide, and a decision is
/// `PUT /leaves/applications/:id` with `{status, manager_comments}` (the server hands it to the approval engine).
class LeaveApprovalsPanel extends StatefulWidget {
  const LeaveApprovalsPanel({super.key, this.approvalsRepository});

  final ApprovalsRepository? approvalsRepository;

  /// Number of leave requests the caller may decide now (the "Needs my action" tab). Throws when it cannot be known.
  static Future<int> countActionable({
    ApprovalsRepository? approvalsRepository,
  }) async {
    final repo = approvalsRepository ?? ApprovalsRepository();
    final p = await loadApprovalPartition(
      repo: repo,
      module: 'leaves',
      loadWaiting: () => repo.leaveApplications(history: false),
      throwOnMetaFailure: true,
    );
    return p.actionable.length;
  }

  @override
  State<LeaveApprovalsPanel> createState() => _LeaveApprovalsPanelState();
}

class _LeaveApprovalsPanelState extends State<LeaveApprovalsPanel> {
  late final ApprovalsRepository _repo =
      widget.approvalsRepository ?? ApprovalsRepository();

  @override
  Widget build(BuildContext context) {
    return PartitionedApprovalsView(
      heading: 'Leave requests',
      load: () => loadApprovalPartition(
        repo: _repo,
        module: 'leaves',
        loadWaiting: () => _repo.leaveApplications(history: false),
        loadHistory: () => _repo.leaveApplications(history: true),
      ),
      approve: (row, c) =>
          _repo.decideLeave(row['id'].toString(), approve: true, comments: c),
      reject: (row, c) =>
          _repo.decideLeave(row['id'].toString(), approve: false, comments: c),
      dialogSummary: (row) => _name(row),
      cardBody: (row, {required history}) => _body(row, history),
    );
  }

  static String? _name(Map<String, dynamic> row) {
    final e = row['employee_records'];
    final n = e is Map ? e['full_name']?.toString().trim() : null;
    return n == null || n.isEmpty ? null : n;
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
    final from = approvalDate(row['from_date']);
    final to = approvalDate(row['to_date']);
    final dates = from == null
        ? to
        : (to == null || to == from ? from : '$from - $to');
    final type = _title(row['leave_type']);
    final n = num.tryParse('${row['total_days'] ?? ''}');
    final days = n == null || n <= 0
        ? null
        : (n == n.roundToDouble() ? '${n.toInt()}' : '$n');
    final reason = row['reason']?.toString().trim();
    final comments = row['manager_comments']?.toString().trim();
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
            if (type != null) ApprovalDetail('Type', type),
            if (dates != null) ApprovalDetail('Dates', dates),
            if (days != null) ApprovalDetail('Days', days),
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

/// A readable word for a type value; null for an id or nothing.
String? _title(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-').hasMatch(s)) return null;
  final t = s.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}
