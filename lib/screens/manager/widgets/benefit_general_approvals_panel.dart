import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/approvals_repository.dart';
import '../../../repositories/benefits_repository.dart';
import 'approval_review.dart';
import 'approval_split_panel.dart';

/// Fixed text for a failed load: the server's or the exception's text is never shown.
const String kBenefitGeneralApprovalsLoadFailed =
    "Couldn't load benefit claims right now. Please try again.";

/// "₹1,250" for a usable amount; "Not available" for a missing, zero or unreadable one (never "₹0").
String _amount(dynamic v) {
  final n = asNum(v);
  if (n == null || n <= 0) return 'Not available';
  return '₹${NumberFormat('#,##,###.##').format(n)}';
}

String _date(dynamic v) {
  final d = asDate(v);
  return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
}

/// General (non-ESI) benefit claims of the manager's team, decided through
/// `POST /benefits/claims/:id/approve|reject`, with the same three lists as the loan and travel panels (row-meta, module
/// `benefits`). Approving approves the claimed amount (`approvedAmount` is sent); Reject needs a reason.
class BenefitGeneralApprovalsPanel extends StatefulWidget {
  const BenefitGeneralApprovalsPanel({
    super.key,
    this.benefitsRepository,
    this.approvalsRepository,
  });

  final BenefitsRepository? benefitsRepository;
  final ApprovalsRepository? approvalsRepository;

  /// How many general claims the caller may decide now. Throws when the list or the engine's answer is not available.
  static Future<int> countActionable({
    BenefitsRepository? benefitsRepository,
    ApprovalsRepository? approvalsRepository,
  }) async {
    final rows = await (benefitsRepository ?? BenefitsRepository())
        .generalApprovalClaims();
    return countActionableRows(
      rows: rows,
      module: 'benefits',
      approvals: approvalsRepository ?? ApprovalsRepository(),
    );
  }

  @override
  State<BenefitGeneralApprovalsPanel> createState() =>
      _BenefitGeneralApprovalsPanelState();
}

class _BenefitGeneralApprovalsPanelState
    extends State<BenefitGeneralApprovalsPanel> {
  late final BenefitsRepository _repo =
      widget.benefitsRepository ?? BenefitsRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();

  static bool _hasAmount(Map<String, dynamic> c) {
    final n = asNum(c['claimed_amount']);
    return n != null && n > 0;
  }

  Future<ApprovalDecision?> _review(
    BuildContext context,
    Map<String, dynamic> claim,
    bool canDecide,
  ) {
    final emp = (claim['employee'] as Map?) ?? const {};
    // Approving sends the claimed amount: without a usable one a claim can only be viewed here.
    final decidable = canDecide && _hasAmount(claim);
    return showApprovalReviewDialog(
      context,
      title: canDecide ? 'Review Benefit Claim' : 'Benefit Claim',
      canDecide: decidable,
      details: [
        approvalDetailRow('Employee', emp['full_name']?.toString()),
        approvalDetailRow('Benefit', claim['benefit_name']?.toString()),
        approvalDetailRow('Claim date', _date(claim['claim_date'])),
        approvalDetailRow('Claimed amount', _amount(claim['claimed_amount'])),
        if (!canDecide && claim['approved_amount'] != null)
          approvalDetailRow(
            'Approved amount',
            _amount(claim['approved_amount']),
          ),
        approvalDetailRow('Notes', claim['description']?.toString()),
        approvalDetailRow(
          'Status',
          (claim['status'] ?? '').toString().replaceAll('_', ' '),
        ),
        if (decidable)
          Text(
            'Approving approves the claimed amount.',
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54),
          )
        else if (canDecide)
          Text(
            "The claimed amount isn't available, so this claim can't be decided here.",
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54),
          ),
      ],
    );
  }

  Future<void> _decide(Map<String, dynamic> claim, ApprovalDecision d) async {
    final id = claim['id'].toString();
    if (d.approve) {
      await _repo.approveClaim(
        id,
        approvedAmount: asNum(claim['claimed_amount']) ?? 0,
      );
    } else {
      await _repo.rejectClaim(id, comments: d.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ApprovalSplitPanel(
      module: 'benefits',
      loadRows: _repo.generalApprovalClaims,
      approvalsRepository: _approvals,
      loadFailedText: kBenefitGeneralApprovalsLoadFailed,
      emptyActionText: 'No benefit claims need your action.',
      emptyHistoryText: 'No decided benefit claims yet.',
      cardDetails: _details,
      review: _review,
      decide: _decide,
      approvedText: 'Claim approved',
      rejectedText: 'Claim rejected',
      errorText: BenefitsRepository.decisionErrorText,
    );
  }

  List<Widget> _details(Map<String, dynamic> claim) {
    final emp = (claim['employee'] as Map?) ?? const {};
    final status = (claim['status'] ?? 'pending').toString().toLowerCase();
    final code = emp['employee_id']?.toString() ?? '';
    final benefit = claim['benefit_name']?.toString() ?? 'Benefit claim';
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              emp['full_name']?.toString() ?? 'Unknown',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          approvalStatusPill(status),
        ],
      ),
      if (code.isNotEmpty)
        Text(
          code,
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
        ),
      const SizedBox(height: 8),
      Text(
        benefit,
        style: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _date(claim['claim_date']),
        style: GoogleFonts.montserrat(
          fontSize: 11,
          color: Colors.grey.shade600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _amount(claim['claimed_amount']),
        style: GoogleFonts.playfairDisplay(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ];
  }
}
