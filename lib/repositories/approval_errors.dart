import '../core/api/api_client.dart';

/// A short message that is safe to show when a manager's approve/reject call or an approvals list failed.
///
/// Decisions are made by the server's approval engine as the signed-in manager, which refuses with the codes in the backend's
/// `docs/MOBILE_APPROVAL_CONTRACT.md` (`SELF_APPROVAL`, `NOT_ALLOWED`, `NOT_PENDING`, `FORBIDDEN`, `AMOUNT_ABOVE_CLAIM`...).
/// The server's own text, URLs, ids and exception text are never shown: only these fixed sentences.
/// [fallback] is used for server errors and anything unknown.
String approvalErrorText(Object e, {required String fallback}) {
  if (e is! ApiException) return fallback;
  if (e.isNetworkError) {
    return 'No connection. Please check your internet and try again.';
  }
  if (e.isUnauthorized) {
    return 'Your session has expired. Please sign in again.';
  }
  if (e.isServerError) return fallback;

  final code = (e.code ?? '').toUpperCase();
  final text = e.message.toLowerCase();
  if (code == 'SELF_APPROVAL' ||
      text.contains('your own') ||
      text.contains('you submitted')) {
    return "You can't approve or reject your own request.";
  }
  if (code == 'NOT_PENDING' ||
      text.contains('cannot approve') ||
      text.contains('cannot reject') ||
      text.contains('already')) {
    return 'This request has already been decided.';
  }
  if (code == 'AMOUNT_ABOVE_CLAIM' || code == 'BAD_AMOUNT') {
    return "That amount can't be approved for this request.";
  }
  if (code == 'OVERRIDE_REASON_REQUIRED') {
    return 'A reason is required to decide this request.';
  }
  if (e.isNotFound || code == 'NOT_FOUND') {
    return 'This request is no longer available to you.';
  }
  if (e.isForbidden || code == 'FORBIDDEN' || code == 'NOT_ALLOWED') {
    return "You can't decide this request right now. It may be waiting for someone else.";
  }
  return fallback;
}
