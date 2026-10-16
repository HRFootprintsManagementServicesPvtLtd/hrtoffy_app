import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/approvals_repository.dart';
import '../../../repositories/loans_repository.dart';
import 'approval_review.dart';
import 'approval_split_panel.dart';

/// Fixed text for a failed load: the server's or the exception's text is never shown.
const String kLoanApprovalsLoadFailed =
    "Couldn't load loan requests right now. Please try again.";

/// A usable amount as "₹50,000"; "Not available" for a missing, zero or unreadable one (never "₹0").
String _amount(dynamic v) {
  final n = asNum(v);
  if (!LoansRepository.isUsableAmount(n)) return 'Not available';
  return '₹${NumberFormat('#,##,###.##').format(n)}';
}

/// Loan requests of the manager's team, decided through the approval API.
///
/// * "Needs my action": waiting loans the server says the caller may decide now (row-meta).
/// * "Waiting on others": waiting loans that are at someone else's step, without buttons.
/// * "History": decided loans. The caller's own loans are never listed here.
///
/// Approving sanctions the requested amount (the route takes no amount or comment); Reject needs a reason.
class LoanApprovalsPanel extends StatefulWidget {
  const LoanApprovalsPanel({
    super.key,
    this.loansRepository,
    this.approvalsRepository,
  });

  final LoansRepository? loansRepository;
  final ApprovalsRepository? approvalsRepository;

  /// How many loans the caller may decide now. Throws when the list or the engine's answer is not available.
  static Future<int> countActionable({
    LoansRepository? loansRepository,
    ApprovalsRepository? approvalsRepository,
  }) async {
    final rows = await (loansRepository ?? LoansRepository()).approvalLoans();
    return countActionableRows(
      rows: rows,
      module: 'loans',
      approvals: approvalsRepository ?? ApprovalsRepository(),
    );
  }

  @override
  State<LoanApprovalsPanel> createState() => _LoanApprovalsPanelState();
}

class _LoanApprovalsPanelState extends State<LoanApprovalsPanel> {
  late final LoansRepository _repo =
      widget.loansRepository ?? LoansRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();

  Future<ApprovalDecision?> _review(
    BuildContext context,
    Map<String, dynamic> loan,
    bool canDecide,
  ) {
    final emp = (loan['employee'] as Map?) ?? const {};
    final tenure = asNum(loan['tenure_months'])?.toInt();
    return showApprovalReviewDialog(
      context,
      title: canDecide ? 'Review Loan Request' : 'Loan Request',
      canDecide: canDecide,
      details: [
        approvalDetailRow('Employee', emp['full_name']?.toString()),
        approvalDetailRow('Loan number', loan['loan_number']?.toString()),
        approvalDetailRow(
          'Category',
          loan['loan_category']?.toString().replaceAll('_', ' '),
        ),
        approvalDetailRow('Reason', loan['purpose']?.toString()),
        approvalDetailRow(
          'Requested amount',
          _amount(loan['requested_amount']),
        ),
        approvalDetailRow('Tenure', tenure == null ? null : '$tenure months'),
        approvalDetailRow(
          'Status',
          (loan['status'] ?? '').toString().replaceAll('_', ' '),
        ),
        if (!canDecide &&
            (loan['manager_comments'] ?? '').toString().trim().isNotEmpty)
          approvalDetailRow(
            'Manager comments',
            loan['manager_comments']?.toString(),
          ),
        if (canDecide)
          Text(
            'Approving sanctions the requested amount.',
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54),
          ),
      ],
    );
  }

  Future<void> _decide(Map<String, dynamic> loan, ApprovalDecision d) async {
    final id = loan['id'].toString();
    if (d.approve) {
      await _repo.approveLoan(id);
    } else {
      await _repo.rejectLoan(id, reason: d.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ApprovalSplitPanel(
      module: 'loans',
      loadRows: _repo.approvalLoans,
      approvalsRepository: _approvals,
      loadFailedText: kLoanApprovalsLoadFailed,
      emptyActionText: 'No loan requests need your action.',
      emptyHistoryText: 'No decided loan requests yet.',
      cardDetails: _details,
      review: _review,
      decide: _decide,
      approvedText: 'Loan approved',
      rejectedText: 'Loan rejected',
      errorText: LoansRepository.decisionErrorText,
    );
  }

  List<Widget> _details(Map<String, dynamic> loan) {
    final emp = (loan['employee'] as Map?) ?? const {};
    final status = (loan['status'] ?? 'pending').toString().toLowerCase();
    final tenure = asNum(loan['tenure_months'])?.toInt();
    final applied = asDate(loan['application_date'] ?? loan['created_at']);
    final code = emp['employee_id']?.toString() ?? '';
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              loan['loan_number']?.toString() ?? 'Loan',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          approvalStatusPill(status),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        emp['full_name']?.toString() ?? 'Unknown',
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      if (code.isNotEmpty)
        Text(
          code,
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
        ),
      const SizedBox(height: 4),
      Text(
        loan['loan_category']?.toString().replaceAll('_', ' ').toUpperCase() ??
            'LOAN',
        style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat('Requested', _amount(loan['requested_amount'])),
          _stat('Tenure', tenure == null ? '-' : '$tenure months'),
          _stat(
            'Applied',
            applied == null
                ? '-'
                : DateFormat('dd MMM yyyy').format(applied.toLocal()),
          ),
        ],
      ),
    ];
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
        ),
        Text(
          value,
          style: GoogleFonts.playfairDisplay(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
