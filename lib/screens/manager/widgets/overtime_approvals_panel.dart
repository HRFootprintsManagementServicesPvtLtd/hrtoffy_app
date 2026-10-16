import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import 'approval_common.dart';
import 'decision_list_panel.dart';

/// Overtime requests of the caller's team, Pending and History. Approve and Reject go to
/// `POST /attendance/overtime/records/:id/approve|reject`; the overtime approve route takes no note, so only a rejection
/// carries the typed reason.
class OvertimeApprovalsPanel extends StatefulWidget {
  const OvertimeApprovalsPanel({super.key, this.repository, this.onBack});

  final ApprovalsRepository? repository;
  final VoidCallback? onBack;

  @override
  State<OvertimeApprovalsPanel> createState() => _OvertimeApprovalsPanelState();
}

class _OvertimeApprovalsPanelState extends State<OvertimeApprovalsPanel> {
  late final ApprovalsRepository _repo =
      widget.repository ?? ApprovalsRepository();

  @override
  Widget build(BuildContext context) {
    return DecisionListPanel(
      eyebrow: 'OVERTIME',
      heading: 'Review Requests',
      metaModule: 'overtime',
      repository: _repo,
      onBack: widget.onBack,
      load: (history) => _repo.overtime(history: history),
      approve: (row, _) => _repo.approveOvertime(row['id'].toString()),
      reject: (row, c) =>
          _repo.rejectOvertime(row['id'].toString(), comments: c),
      dialogTitle: 'Review Overtime',
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
    final sub = [
      emp['employee_id'],
      emp['department'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final hours = row['total_hours'];
    final type = row['ot_type']?.toString();
    final amount = approvalAmount(row['ot_amount']);
    final reason = row['reason']?.toString().trim();
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
            ApprovalDetail('Date', approvalDate(row['ot_date']) ?? '-'),
            if (hours != null && '$hours'.isNotEmpty)
              ApprovalDetail('Hours', '$hours hrs'),
            if (type != null && type.isNotEmpty)
              ApprovalDetail('Type', type.replaceAll('_', ' ')),
            if (amount != null) ApprovalDetail('Amount', amount),
          ],
        ),
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Reason: $reason',
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87),
          ),
        ],
      ],
    );
  }
}
