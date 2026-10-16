import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/approvals_repository.dart';
import '../../../repositories/travel_repository.dart';
import 'approval_review.dart';
import 'approval_split_panel.dart';

/// Fixed text for a failed load: the server's or the exception's text is never shown.
const String kTravelApprovalsLoadFailed =
    "Couldn't load travel claims right now. Please try again.";

/// "₹5,400.50" for a number; "-" when missing or not numeric (never a made-up 0).
String _money(dynamic v) {
  final n = asNum(v);
  return n == null
      ? '-'
      : NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: 2,
        ).format(n);
}

String _date(dynamic v) {
  final d = asDate(v);
  return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
}

/// Travel claims of the manager's team, decided through the approval API.
///
/// * "Needs my action": waiting claims the server says the caller may decide now (row-meta, module `travel_claims`).
/// * "Waiting on others": waiting claims at someone else's step, without buttons.
/// * "History": decided claims. The caller's own claims are never listed here.
///
/// Approving approves the claimed total (no amount or comment is sent); Reject needs a reason.
class TravelApprovalsPanel extends StatefulWidget {
  const TravelApprovalsPanel({
    super.key,
    this.travelRepository,
    this.approvalsRepository,
  });

  final TravelRepository? travelRepository;
  final ApprovalsRepository? approvalsRepository;

  /// How many claims the caller may decide now. Throws when the list or the engine's answer is not available.
  static Future<int> countActionable({
    TravelRepository? travelRepository,
    ApprovalsRepository? approvalsRepository,
  }) async {
    final rows = await (travelRepository ?? TravelRepository())
        .approvalClaims();
    return countActionableRows(
      rows: rows,
      module: 'travel_claims',
      approvals: approvalsRepository ?? ApprovalsRepository(),
    );
  }

  @override
  State<TravelApprovalsPanel> createState() => _TravelApprovalsPanelState();
}

class _TravelApprovalsPanelState extends State<TravelApprovalsPanel> {
  late final TravelRepository _repo =
      widget.travelRepository ?? TravelRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();

  Future<ApprovalDecision?> _review(
    BuildContext context,
    Map<String, dynamic> claim,
    bool canDecide,
  ) {
    final emp = (claim['employee'] as Map?) ?? const {};
    final expenses = (claim['expenses'] as List?) ?? const [];
    return showApprovalReviewDialog(
      context,
      title: canDecide ? 'Review Travel Claim' : 'Travel Claim',
      canDecide: canDecide,
      details: [
        approvalDetailRow('Employee', emp['full_name']?.toString()),
        approvalDetailRow('Claim', claim['claim_number']?.toString()),
        approvalDetailRow('Destination', claim['trip_destination']?.toString()),
        approvalDetailRow(
          'Travel dates',
          '${_date(claim['trip_from_date'])} - ${_date(claim['trip_to_date'])}',
        ),
        approvalDetailRow('Purpose', claim['trip_purpose']?.toString()),
        approvalDetailRow('Total claimed', _money(claim['total_amount'])),
        if (!canDecide && claim['approved_amount'] != null)
          approvalDetailRow(
            'Approved amount',
            _money(claim['approved_amount']),
          ),
        approvalDetailRow(
          'Status',
          (claim['status'] ?? '').toString().replaceAll('_', ' '),
        ),
        if (expenses.isNotEmpty) ...[
          Text(
            'Expense breakdown',
            style: GoogleFonts.montserrat(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          for (final e in expenses.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${e['expense_type'] ?? 'Expense'} • ${_date(e['expense_date'])}',
                      style: GoogleFonts.montserrat(fontSize: 11),
                    ),
                  ),
                  Text(
                    _money(e['amount']),
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (canDecide)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Approving approves the claimed total.',
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _decide(Map<String, dynamic> claim, ApprovalDecision d) async {
    final id = claim['id'].toString();
    if (d.approve) {
      await _repo.approveClaim(id);
    } else {
      await _repo.rejectClaim(id, reason: d.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ApprovalSplitPanel(
      module: 'travel_claims',
      loadRows: _repo.approvalClaims,
      approvalsRepository: _approvals,
      loadFailedText: kTravelApprovalsLoadFailed,
      emptyActionText: 'No claims require your action at this time.',
      emptyHistoryText: 'No decided travel claims yet.',
      cardDetails: _details,
      review: _review,
      decide: _decide,
      approvedText: 'Claim approved',
      rejectedText: 'Claim rejected',
      errorText: TravelRepository.decisionErrorText,
    );
  }

  List<Widget> _details(Map<String, dynamic> claim) {
    final emp = (claim['employee'] as Map?) ?? const {};
    final status = (claim['status'] ?? 'pending').toString().toLowerCase();
    final designation = emp['designation']?.toString() ?? '';
    final destination = claim['trip_destination']?.toString() ?? '-';
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              claim['claim_number']?.toString() ?? 'Travel claim',
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
      const SizedBox(height: 8),
      Text(
        designation.isEmpty
            ? (emp['full_name']?.toString() ?? 'Unknown')
            : '${emp['full_name'] ?? 'Unknown'} • $designation',
        style: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '$destination  |  ${_date(claim['trip_from_date'])} - ${_date(claim['trip_to_date'])}',
        style: GoogleFonts.montserrat(
          fontSize: 11,
          color: Colors.grey.shade600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        claim['trip_purpose']?.toString() ?? '-',
        style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 8),
      Text(
        _money(claim['total_amount']),
        style: GoogleFonts.playfairDisplay(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ];
  }
}
