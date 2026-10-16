import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import '../../../repositories/expense_repository.dart';
import 'approval_common.dart';
import 'partitioned_approvals.dart';

/// Expense claims of the caller's team split by what the caller may do: needs my action / waiting on others / history.
/// The list is `GET /expenses`, the engine's row-meta (module `expenses`) says who may decide, and a decision is
/// `POST /expenses/:id/approve` or `/reject {reason}`. The caller's own claims are never listed.
class ExpenseApprovalsPanel extends StatefulWidget {
  const ExpenseApprovalsPanel({
    super.key,
    this.approvalsRepository,
    this.expenseRepository,
  });

  final ApprovalsRepository? approvalsRepository;
  final ExpenseRepository? expenseRepository;

  /// Number of claims the caller may decide now. Throws when it cannot be known.
  static Future<int> countActionable({
    ApprovalsRepository? approvalsRepository,
    ExpenseRepository? expenseRepository,
  }) async {
    final repo = approvalsRepository ?? ApprovalsRepository();
    final p = await loadApprovalPartition(
      repo: repo,
      module: 'expenses',
      loadWaiting: repo.teamExpenseClaims,
      throwOnMetaFailure: true,
    );
    return p.actionable.length;
  }

  @override
  State<ExpenseApprovalsPanel> createState() => _ExpenseApprovalsPanelState();
}

class _ExpenseApprovalsPanelState extends State<ExpenseApprovalsPanel> {
  late final ApprovalsRepository _repo =
      widget.approvalsRepository ?? ApprovalsRepository();
  late final ExpenseRepository _expenses =
      widget.expenseRepository ?? ExpenseRepository();

  Future<ApprovalPartitionResult> _load() async {
    // Claims carry the category id only: names come from the category list (best effort).
    var categories = const <Map<String, dynamic>>[];
    try {
      categories = await _expenses.categories();
    } catch (_) {}
    return loadApprovalPartition(
      repo: _repo,
      module: 'expenses',
      loadWaiting: () async => ExpenseRepository.withCategoryNames(
        await _repo.teamExpenseClaims(),
        categories,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PartitionedApprovalsView(
      heading: 'Expense claims',
      load: _load,
      approve: (row, c) => _repo.approveExpense(row['id'].toString()),
      reject: (row, c) => _repo.rejectExpense(row['id'].toString(), reason: c),
      dialogSummary: (row) => _name(row),
      cardBody: (row, {required history}) => _body(row),
    );
  }

  static String? _name(Map<String, dynamic> row) {
    final e = row['employee_records'];
    final n = e is Map ? e['full_name']?.toString().trim() : null;
    return n == null || n.isEmpty ? null : n;
  }

  Widget _body(Map<String, dynamic> row) {
    final emp = row['employee_records'] is Map
        ? Map<String, dynamic>.from(row['employee_records'] as Map)
        : const <String, dynamic>{};
    final status = (row['status'] ?? 'pending').toString();
    final sub = [
      emp['employee_id'],
      emp['department'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final title = row['title']?.toString().trim();
    final amount = approvalAmount(row['amount'] ?? row['total_amount']);
    final date = approvalDate(row['expense_date']);
    final category = row['category_name']?.toString().trim();
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
            if (amount != null) ApprovalDetail('Amount', amount),
            if (date != null) ApprovalDetail('Date', date),
            if (category != null && category.isNotEmpty)
              ApprovalDetail('Category', category),
          ],
        ),
        if (title != null && title.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black87),
          ),
        ],
      ],
    );
  }
}
