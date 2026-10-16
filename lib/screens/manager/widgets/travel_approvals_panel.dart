import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/travel_repository.dart';
import 'approval_review.dart';

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
/// * "Needs My Action": claims still open (`pending` or `manager_approved`), newest first.
/// * "History": every other claim the server lets this manager see.
///
/// Who may decide a claim is the server's call (reporting line, never your own claim); a refusal is shown as a short message
/// and the list is reloaded. Approving approves the claimed total (no amount or comment is sent); a reason can be given on Reject.
class TravelApprovalsPanel extends StatefulWidget {
  const TravelApprovalsPanel({super.key, this.travelRepository});

  final TravelRepository? travelRepository;

  @override
  State<TravelApprovalsPanel> createState() => _TravelApprovalsPanelState();
}

class _TravelApprovalsPanelState extends State<TravelApprovalsPanel> {
  late final TravelRepository _repo =
      widget.travelRepository ?? TravelRepository();

  List<Map<String, dynamic>>? _claims;
  bool _loading = true;
  bool _failed = false;
  String? _busyId;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _claims == null);
    try {
      final rows = await _repo.approvalClaims();
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
    final open = TravelRepository.isOpen(claim);
    final emp = (claim['employee'] as Map?) ?? const {};
    final expenses = (claim['expenses'] as List?) ?? const [];
    final decision = await showApprovalReviewDialog(
      context,
      title: open ? 'Review Travel Claim' : 'Travel Claim',
      canDecide: open,
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
        if (!open && claim['approved_amount'] != null)
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
        if (open)
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
    if (decision == null || !mounted) return;
    await _decide(claim, decision);
  }

  Future<void> _decide(Map<String, dynamic> claim, ApprovalDecision d) async {
    final id = claim['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      if (d.approve) {
        await _repo.approveClaim(id);
      } else {
        await _repo.rejectClaim(id, reason: d.reason);
      }
      if (mounted) _toast(d.approve ? 'Claim approved' : 'Claim rejected');
    } catch (e) {
      if (mounted) _toast(TravelRepository.decisionErrorText(e), error: true);
    }
    if (mounted) setState(() => _busyId = null);
    await _load(); // the list is the server's answer, also after a refusal
  }

  @override
  Widget build(BuildContext context) {
    final claims = _claims;
    final open = claims?.where(TravelRepository.isOpen).toList();
    final history = claims?.where((c) => !TravelRepository.isOpen(c)).toList();
    final shown = _tab == 0 ? open : history;

    return Column(
      children: [
        ApprovalSegments(
          labels: const ['Needs My Action', 'History'],
          counts: [open?.length, history?.length],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        Expanded(child: _body(shown)),
      ],
    );
  }

  Widget _body(List<Map<String, dynamic>>? shown) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed || shown == null) {
      return ApprovalMessage(
        kTravelApprovalsLoadFailed,
        onRetry: _load,
        isError: true,
      );
    }
    if (shown.isEmpty) {
      return ApprovalMessage(
        _tab == 0
            ? 'No claims require your action at this time.'
            : 'No decided travel claims yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(shown[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> claim) {
    final emp = (claim['employee'] as Map?) ?? const {};
    final status = (claim['status'] ?? 'pending').toString().toLowerCase();
    final open = TravelRepository.isOpen(claim);
    final designation = emp['designation']?.toString() ?? '';
    final destination = claim['trip_destination']?.toString() ?? '-';
    return approvalCardShell(
      children: [
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
        approvalReviewButton(
          open: open,
          busy: _busyId == claim['id']?.toString(),
          onPressed: () => _review(claim),
        ),
      ],
    );
  }
}
