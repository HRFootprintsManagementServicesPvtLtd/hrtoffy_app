import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/json_case.dart';

/// What the decision dialog asks for.
enum ApprovalDialogMode { approve, reject, review }

/// The manager's decision: [approve] and the typed note (required, trimmed, for a rejection).
class ApprovalDecisionResult {
  const ApprovalDecisionResult({required this.approve, required this.comments});
  final bool approve;
  final String comments;
}

/// Asks for the decision note and returns the decision, or null when cancelled. A rejection needs a reason; an approval
/// may carry a note. [ApprovalDialogMode.review] shows both buttons (as the original Review dialogs).
Future<ApprovalDecisionResult?> showApprovalDecisionDialog(
  BuildContext context, {
  required ApprovalDialogMode mode,
  required String title,
  String? summary,
}) {
  return showDialog<ApprovalDecisionResult>(
    context: context,
    builder: (_) => _DecisionDialog(mode: mode, title: title, summary: summary),
  );
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({
    required this.mode,
    required this.title,
    this.summary,
  });
  final ApprovalDialogMode mode;
  final String title;
  final String? summary;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _decide(bool approve) {
    final text = _controller.text.trim();
    if (!approve && text.isEmpty) {
      setState(() => _error = 'Please give a reason for rejecting.');
      return;
    }
    Navigator.pop(
      context,
      ApprovalDecisionResult(approve: approve, comments: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final rejecting = mode == ApprovalDialogMode.reject;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.title,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.summary != null && widget.summary!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.summary!,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              rejecting
                  ? 'Reason for rejecting'
                  : mode == ApprovalDialogMode.approve
                  ? 'Note (optional)'
                  : 'Decision Comments',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: rejecting
                    ? 'Tell the employee why...'
                    : 'Add your decision notes...',
                hintStyle: const TextStyle(fontSize: 12),
                errorText: _error,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (mode == ApprovalDialogMode.review) ...[
              const SizedBox(height: 6),
              Text(
                'A reason is needed to reject.',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            if (mode != ApprovalDialogMode.approve) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  key: const ValueKey('decision-reject'),
                  onPressed: () => _decide(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Reject'),
                ),
              ),
            ],
            if (mode != ApprovalDialogMode.reject) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  key: const ValueKey('decision-approve'),
                  onPressed: () => _decide(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// `dd MMM yyyy` for a date value, or null when there is none.
String? approvalDate(dynamic v, {String pattern = 'dd MMM yyyy'}) {
  final d = asDate(v);
  if (d == null) return null;
  return DateFormat(
    pattern,
  ).format(d.isUtc ? DateTime(d.year, d.month, d.day) : d);
}

/// `hh:mm a` for a punch time (ISO timestamp or `HH:mm:ss`), or null.
String? approvalTime(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  try {
    final dt = s.contains('T')
        ? DateTime.parse(s).toLocal()
        : DateFormat('HH:mm:ss').parse(s);
    return DateFormat('hh:mm a').format(dt);
  } catch (_) {
    return null;
  }
}

/// `₹ 12,500` for an amount the server gave, or null when it is missing or not above zero (an unknown amount is
/// never shown as 0).
String? approvalAmount(dynamic v) {
  final n = asNum(v);
  if (n == null || n <= 0) return null;
  return '₹ ${NumberFormat.decimalPattern('en_IN').format(n)}';
}

/// A small label above a value.
class ApprovalDetail extends StatelessWidget {
  const ApprovalDetail(
    this.label,
    this.value, {
    super.key,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 8,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.blue.shade700 : Colors.black87,
          ),
        ),
      ],
    );
  }
}

/// The applicant header of an approval card: initial, name, code and an optional trailing widget.
class ApprovalApplicantRow extends StatelessWidget {
  const ApprovalApplicantRow({
    super.key,
    required this.name,
    this.subtitle,
    this.trailing,
  });
  final String? name;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final n = (name ?? '').trim();
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.blue.shade50,
          child: Text(
            n.isEmpty ? '?' : n[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n.isEmpty ? 'Unknown' : n,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    color: Colors.black54,
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A small coloured status pill (`PENDING`, `APPROVED`, `REJECTED`).
class ApprovalStatusPill extends StatelessWidget {
  const ApprovalStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'approved'
        ? Colors.green
        : status == 'rejected'
        ? Colors.red
        : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: GoogleFonts.montserrat(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Card chrome shared by the approval panels.
BoxDecoration approvalCardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Colors.grey.shade100),
);

/// A centred friendly message with an optional Retry (loading failed) or plain note (empty).
class ApprovalMessage extends StatelessWidget {
  const ApprovalMessage({
    super.key,
    required this.text,
    this.icon,
    this.onRetry,
  });
  final String text;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 36, color: Colors.grey.shade500),
              const SizedBox(height: 10),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

void approvalSnack(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null),
  );
}
