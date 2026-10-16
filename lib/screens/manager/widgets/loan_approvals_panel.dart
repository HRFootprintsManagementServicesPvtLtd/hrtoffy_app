import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';
import '../../../repositories/loans_repository.dart';
import 'approval_review.dart';

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
/// * "Needs My Action": loans still open (`pending` or `manager_approved`), newest first.
/// * "History": every other loan the server lets this manager see.
///
/// Who may decide a loan is the server's call (the approval engine); a refusal is shown as a short message and the list is
/// reloaded. Approving sanctions the requested amount (the route takes no amount or comment); a reason can be given on Reject.
class LoanApprovalsPanel extends StatefulWidget {
  const LoanApprovalsPanel({super.key, this.loansRepository});

  final LoansRepository? loansRepository;

  @override
  State<LoanApprovalsPanel> createState() => _LoanApprovalsPanelState();
}

class _LoanApprovalsPanelState extends State<LoanApprovalsPanel> {
  late final LoansRepository _repo =
      widget.loansRepository ?? LoansRepository();

  List<Map<String, dynamic>>? _loans;
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
    if (mounted) setState(() => _loading = _loans == null);
    try {
      final rows = await _repo.approvalLoans();
      if (!mounted) return;
      setState(() {
        _loans = rows;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loans = null;
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

  Future<void> _review(Map<String, dynamic> loan) async {
    final open = LoansRepository.isOpen(loan);
    final emp = (loan['employee'] as Map?) ?? const {};
    final tenure = asNum(loan['tenure_months'])?.toInt();
    final decision = await showApprovalReviewDialog(
      context,
      title: open ? 'Review Loan Request' : 'Loan Request',
      canDecide: open,
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
        if (!open &&
            (loan['manager_comments'] ?? '').toString().trim().isNotEmpty)
          approvalDetailRow(
            'Manager comments',
            loan['manager_comments']?.toString(),
          ),
        if (open)
          Text(
            'Approving sanctions the requested amount.',
            style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54),
          ),
      ],
    );
    if (decision == null || !mounted) return;
    await _decide(loan, decision);
  }

  Future<void> _decide(Map<String, dynamic> loan, ApprovalDecision d) async {
    final id = loan['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      if (d.approve) {
        await _repo.approveLoan(id);
      } else {
        await _repo.rejectLoan(id, reason: d.reason);
      }
      if (mounted) _toast(d.approve ? 'Loan approved' : 'Loan rejected');
    } catch (e) {
      if (mounted) _toast(LoansRepository.decisionErrorText(e), error: true);
    }
    if (mounted) setState(() => _busyId = null);
    await _load(); // the list is the server's answer, also after a refusal
  }

  @override
  Widget build(BuildContext context) {
    final loans = _loans;
    final open = loans?.where(LoansRepository.isOpen).toList();
    final history = loans?.where((l) => !LoansRepository.isOpen(l)).toList();
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
        kLoanApprovalsLoadFailed,
        onRetry: _load,
        isError: true,
      );
    }
    if (shown.isEmpty) {
      return ApprovalMessage(
        _tab == 0
            ? 'No loan requests need your action.'
            : 'No decided loan requests yet.',
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

  Widget _card(Map<String, dynamic> loan) {
    final emp = (loan['employee'] as Map?) ?? const {};
    final status = (loan['status'] ?? 'pending').toString().toLowerCase();
    final open = LoansRepository.isOpen(loan);
    final tenure = asNum(loan['tenure_months'])?.toInt();
    final applied = asDate(loan['application_date'] ?? loan['created_at']);
    final code = emp['employee_id']?.toString() ?? '';
    return approvalCardShell(
      children: [
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
          loan['loan_category']
                  ?.toString()
                  .replaceAll('_', ' ')
                  .toUpperCase() ??
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
        approvalReviewButton(
          open: open,
          busy: _busyId == loan['id']?.toString(),
          onPressed: () => _review(loan),
        ),
      ],
    );
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
