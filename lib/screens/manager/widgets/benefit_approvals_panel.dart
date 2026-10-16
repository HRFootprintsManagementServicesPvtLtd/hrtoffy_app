import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/benefits_repository.dart';
import 'approval_review.dart';

/// Fixed text for a failed load: the server's or the exception's text is never shown.
const String kBenefitApprovalsLoadFailed =
    "Couldn't load ESI claims right now. Please try again.";

String _date(dynamic v) {
  final d = asDate(v);
  return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
}

String _kind(dynamic v) {
  final s = (v ?? '').toString().replaceAll('_', ' ').trim();
  return s.isEmpty ? 'ESI claim' : s[0].toUpperCase() + s.substring(1);
}

/// ESI claims waiting for the manager's decision, through the approval API.
///
/// The server lists only the claims waiting for this caller (a manager's reporting tree, `pending`); decided ESI claims are
/// not returned, so there is no history here. ESI claims carry no claimed amount (the server stores 0), so none is shown.
/// Approving or rejecting sends a JSON body (the route requires one); a reason goes with a rejection only.
///
/// General (non-ESI) benefit claims have no manager route: they are decided from the approval inbox, which the lead
/// integrates in [_GeneralBenefitApprovalsSlot].
class BenefitApprovalsPanel extends StatefulWidget {
  const BenefitApprovalsPanel({
    super.key,
    this.benefitsRepository,
    this.showGeneralSlot = true,
  });

  final BenefitsRepository? benefitsRepository;

  /// The note about general (non-ESI) claims under the ESI list; off where a screen lists those claims itself.
  final bool showGeneralSlot;

  @override
  State<BenefitApprovalsPanel> createState() => _BenefitApprovalsPanelState();
}

class _BenefitApprovalsPanelState extends State<BenefitApprovalsPanel> {
  late final BenefitsRepository _repo =
      widget.benefitsRepository ?? BenefitsRepository();

  List<Map<String, dynamic>>? _claims;
  bool _loading = true;
  bool _failed = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _claims == null);
    try {
      final rows = await _repo.esiApprovalClaims();
      if (!mounted) return;
      setState(() {
        _claims = rows;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _claims = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _review(Map<String, dynamic> claim) async {
    final days = claim['esi_days_claimed'];
    final decision = await showApprovalReviewDialog(
      context,
      title: 'Review ESI Claim',
      canDecide: true,
      details: [
        approvalDetailRow('Employee', claim['employee_name']?.toString()),
        approvalDetailRow('Department', claim['department']?.toString()),
        approvalDetailRow('Claim type', _kind(claim['esi_benefit_type'])),
        approvalDetailRow(
          'Period',
          '${_date(claim['esi_start_date'])} - ${_date(claim['esi_end_date'])}',
        ),
        approvalDetailRow('Days claimed', days == null ? null : '$days'),
        approvalDetailRow('Notes', claim['description']?.toString()),
        approvalDetailRow(
          'Status',
          (claim['status'] ?? '').toString().replaceAll('_', ' '),
        ),
      ],
    );
    if (decision == null || !mounted) return;
    await _decide(claim, decision);
  }

  Future<void> _decide(Map<String, dynamic> claim, ApprovalDecision d) async {
    final id = claim['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      if (d.approve) {
        await _repo.approveEsiClaim(id);
      } else {
        await _repo.rejectEsiClaim(id, comments: d.reason);
      }
      if (mounted) {
        _toast(d.approve ? 'ESI claim approved' : 'ESI claim rejected');
      }
    } catch (e) {
      if (mounted) _toast(BenefitsRepository.decisionErrorText(e), error: true);
    }
    if (mounted) setState(() => _busyId = null);
    await _load(); // the list is the server's answer, also after a refusal
  }

  @override
  Widget build(BuildContext context) {
    final claims = _claims;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              claims == null
                  ? 'ESI claims waiting for your decision.'
                  : 'ESI claims waiting for your decision (${claims.length}). Decided claims are not listed here.',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ),
        Expanded(child: _body(claims)),
        if (widget.showGeneralSlot) const _GeneralBenefitApprovalsSlot(),
      ],
    );
  }

  Widget _body(List<Map<String, dynamic>>? claims) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed || claims == null) {
      return ApprovalMessage(
        kBenefitApprovalsLoadFailed,
        onRetry: _load,
        isError: true,
      );
    }
    if (claims.isEmpty) {
      return const ApprovalMessage('No ESI claims need your action.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: claims.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(claims[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? 'pending').toString().toLowerCase();
    final code = claim['employee_code']?.toString() ?? '';
    final days = claim['esi_days_claimed'];
    return approvalCardShell(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                claim['employee_name']?.toString() ?? 'Unknown',
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
          _kind(claim['esi_benefit_type']),
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_date(claim['esi_start_date'])} - ${_date(claim['esi_end_date'])}'
          '${days == null ? '' : '  |  $days days'}',
          style: GoogleFonts.montserrat(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        approvalReviewButton(
          open: true,
          busy: _busyId == claim['id']?.toString(),
          onPressed: () => _review(claim),
        ),
      ],
    );
  }
}

/// LEAD-INTEGRATES: general (non-ESI) benefit claims have no manager route (they need COMPENSATION_MANAGE), so they are
/// decided from the approval inbox. Replace this widget with the inbox-based panel; until then it says so.
class _GeneralBenefitApprovalsSlot extends StatelessWidget {
  const _GeneralBenefitApprovalsSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('general-benefit-approvals-slot'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "General benefit claims aren't available here yet.",
        style: GoogleFonts.montserrat(
          fontSize: 12,
          color: Colors.orange.shade900,
        ),
      ),
    );
  }
}
