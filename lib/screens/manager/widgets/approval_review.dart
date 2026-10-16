import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// What the manager chose in [showApprovalReviewDialog]. [reason] is only ever filled for a rejection (the approve
/// routes take no comment, so none is collected for an approval).
class ApprovalDecision {
  const ApprovalDecision.approve() : approve = true, reason = '';
  const ApprovalDecision.reject(this.reason) : approve = false;

  final bool approve;
  final String reason;
}

/// One "label / value" line of a review dialog. A missing value shows "-", never a made-up one.
Widget approvalDetailRow(String label, String? value) {
  final v = (value == null || value.trim().isEmpty) ? '-' : value.trim();
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        Text(
          v,
          style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black87),
        ),
      ],
    ),
  );
}

/// Review dialog shared by the loan, travel and ESI approval panels.
///
/// An open request shows Approve and Reject; Reject first asks for an optional reason and then confirms. A decided request
/// shows only a Close button. Returns null when the dialog is dismissed.
Future<ApprovalDecision?> showApprovalReviewDialog(
  BuildContext context, {
  required String title,
  required List<Widget> details,
  required bool canDecide,
}) {
  return showDialog<ApprovalDecision>(
    context: context,
    builder: (ctx) => _ApprovalReviewDialog(
      title: title,
      details: details,
      canDecide: canDecide,
    ),
  );
}

class _ApprovalReviewDialog extends StatefulWidget {
  const _ApprovalReviewDialog({
    required this.title,
    required this.details,
    required this.canDecide,
  });

  final String title;
  final List<Widget> details;
  final bool canDecide;

  @override
  State<_ApprovalReviewDialog> createState() => _ApprovalReviewDialogState();
}

class _ApprovalReviewDialogState extends State<_ApprovalReviewDialog> {
  final _reason = TextEditingController();
  bool _rejecting = false;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...widget.details,
            if (widget.canDecide && _rejecting) ...[
              const SizedBox(height: 6),
              TextField(
                key: const Key('reject-reason'),
                controller: _reason,
                maxLines: 3,
                onChanged: (_) {
                  if (_reasonError != null) setState(() => _reasonError = null);
                },
                decoration: InputDecoration(
                  errorText: _reasonError,
                  hintText: 'Reason for rejecting',
                  hintStyle: GoogleFonts.montserrat(fontSize: 12),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.canDecide)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        else if (!_rejecting)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _rejecting = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, const ApprovalDecision.approve()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Approve',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _rejecting = false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final reason = _reason.text.trim();
                    if (reason.isEmpty) {
                      setState(
                        () => _reasonError =
                            'Please give a reason for rejecting.',
                      );
                      return;
                    }
                    Navigator.pop(context, ApprovalDecision.reject(reason));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirm reject',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Two-way switch (e.g. "Needs My Action" / "History") with a count on each side. A count of null shows nothing.
class ApprovalSegments extends StatelessWidget {
  const ApprovalSegments({
    super.key,
    required this.labels,
    required this.counts,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final List<int?> counts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(i),
                child: Container(
                  height: labels.length > 2 ? 44 : 36,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? Colors.blue.shade600
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    counts[i] == null
                        ? labels[i]
                        : '${labels[i]} (${counts[i]})',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: labels.length > 2 ? 10 : 11,
                      fontWeight: FontWeight.bold,
                      color: i == index ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A centred message, with an optional Retry button (used for failures).
class ApprovalMessage extends StatelessWidget {
  const ApprovalMessage(
    this.text, {
    super.key,
    this.onRetry,
    this.isError = false,
  });

  final String text;
  final VoidCallback? onRetry;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: isError ? Colors.red[700] : Colors.grey.shade500,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// A coloured status word for a request row ("PENDING", "MANAGER APPROVED"...).
Widget approvalStatusPill(String status) {
  Color color = Colors.orange;
  if (status == 'approved' || status == 'paid' || status == 'disbursed') {
    color = Colors.green;
  } else if (status == 'rejected') {
    color = Colors.red;
  } else if (status == 'manager_approved' || status == 'active') {
    color = Colors.blue;
  } else if (status == 'closed' || status == 'cancelled') {
    color = Colors.grey;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      status.toUpperCase().replaceAll('_', ' '),
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );
}

/// The shell every approval card shares.
Widget approvalCardShell({required List<Widget> children}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// "Review" for an open request, "View" for a decided one.
Widget approvalReviewButton({
  required bool open,
  required VoidCallback onPressed,
  bool busy = false,
}) {
  return Align(
    alignment: Alignment.centerRight,
    child: busy
        ? const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : TextButton(
            onPressed: onPressed,
            child: Text(
              open ? 'Review' : 'View',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
  );
}
