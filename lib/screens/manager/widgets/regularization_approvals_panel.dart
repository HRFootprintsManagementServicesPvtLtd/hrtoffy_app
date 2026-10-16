import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';
import 'decision_list_panel.dart';

/// Attendance regularization requests of the caller's team, Pending and History. Approve and Reject go to
/// `POST /attendance/regularization-requests/:id/approve|reject`: the server applies the attendance correction on
/// approval, the app writes nothing to attendance.
class RegularizationApprovalsPanel extends StatefulWidget {
  const RegularizationApprovalsPanel({super.key, this.repository, this.onBack});

  final ApprovalsRepository? repository;
  final VoidCallback? onBack;

  @override
  State<RegularizationApprovalsPanel> createState() =>
      _RegularizationApprovalsPanelState();
}

class _RegularizationApprovalsPanelState
    extends State<RegularizationApprovalsPanel> {
  late final ApprovalsRepository _repo =
      widget.repository ?? ApprovalsRepository();

  @override
  Widget build(BuildContext context) {
    return DecisionListPanel(
      eyebrow: 'ATTENDANCE REGULARIZATION',
      heading: 'Review Requests',
      metaModule: 'attendance_regularization',
      repository: _repo,
      onBack: widget.onBack,
      load: (history) => _repo.regularizations(history: history),
      approve: (row, c) =>
          _repo.approveRegularization(row['id'].toString(), comments: c),
      reject: (row, c) =>
          _repo.rejectRegularization(row['id'].toString(), comments: c),
      dialogTitle: 'Review Regularization',
      dialogSummary: (row) {
        final r = row['reason']?.toString().trim();
        return r == null || r.isEmpty ? null : 'Reason: $r';
      },
      cardBody: _body,
    );
  }

  Widget _body(Map<String, dynamic> row, bool history) {
    final emp = row['employee_records'] is Map
        ? Map<String, dynamic>.from(row['employee_records'] as Map)
        : const <String, dynamic>{};
    final status = (row['status'] ?? 'pending').toString();
    String t(dynamic v) => approvalTime(v) ?? 'Not recorded';
    final sub = [
      emp['employee_id'],
      emp['department'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final reason = row['reason']?.toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ApprovalApplicantRow(
          name: emp['full_name']?.toString(),
          subtitle: sub,
          trailing: ApprovalStatusPill(status),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            ApprovalDetail(
              'Date',
              approvalDate(row['date'], pattern: 'dd MMM') ?? '-',
            ),
            ApprovalDetail('Original In', t(row['original_punch_in'])),
            ApprovalDetail('Original Out', t(row['original_punch_out'])),
            ApprovalDetail(
              'Requested In',
              t(row['requested_punch_in']),
              highlight: true,
            ),
            ApprovalDetail(
              'Requested Out',
              t(row['requested_punch_out']),
              highlight: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Reason: ${reason == null || reason.isEmpty ? 'No reason' : reason}',
          style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87),
        ),
      ],
    );
  }
}
