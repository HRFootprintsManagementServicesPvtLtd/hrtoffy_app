import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';
import 'file_repository.dart';
import 'travel_repository.dart' show ReceiptFile;

/// One line of an expense claim as entered on the form.
class ExpenseLine {
  const ExpenseLine({
    required this.expenseDate,
    required this.description,
    required this.amount,
    this.receipt,
  });

  /// `yyyy-MM-dd`
  final String expenseDate;
  final String description;
  final double amount;
  final ReceiptFile? receipt;
}

/// The signed-in employee's own expense claims.
class ExpenseRepository extends BaseRepository {
  ExpenseRepository({super.auth});

  static const receiptBucket = 'expense-receipts';

  late final FileRepository _files = FileRepository(auth: auth);

  /// `GET /organizations/:orgId/expenses/categories` (active ones, by name).
  /// `monthly_limit` is a decimal string on the wire; the UI gets a number.
  Future<List<Map<String, dynamic>>> categories() async {
    final data = await api.get(orgPath('/expenses/categories'));
    return asMapList(data).map((c) {
      final m = Map<String, dynamic>.from(snakeKeys(c) as Map);
      if (m.containsKey('monthly_limit'))
        m['monthly_limit'] = asNum(m['monthly_limit']);
      return m;
    }).toList();
  }

  /// `GET /organizations/:orgId/expenses?employeeId=<own>`, newest first.
  ///
  /// `employeeId` is always sent: users who can view compensation would otherwise receive the whole
  /// organization's claims. Pass the loaded [categories] to get `category_name` on each claim.
  Future<List<Map<String, dynamic>>> claims({
    List<Map<String, dynamic>> categories = const [],
  }) async {
    final data = await api.get(
      orgPath('/expenses'),
      query: {'employeeId': employeeId},
    );
    final rows = asMapList(data).map(_normalizeClaim).toList();
    rows.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );
    return withCategoryNames(rows, categories);
  }

  /// Adds `category_name` to every claim from its `category_id` (the API returns the id only).
  static List<Map<String, dynamic>> withCategoryNames(
    List<Map<String, dynamic>> claims,
    List<Map<String, dynamic>> categories,
  ) {
    final names = {
      for (final c in categories) c['id'].toString(): c['name']?.toString(),
    };
    return [
      for (final c in claims)
        {
          ...c,
          if (c['category_id'] != null &&
              names[c['category_id'].toString()] != null)
            'category_name': names[c['category_id'].toString()],
        },
    ];
  }

  /// Uploads a receipt to the private `expense-receipts` bucket and returns its `bucket/path` reference.
  ///
  /// Any failure is a [ReceiptUploadException] so the caller can tell a receipt problem from a problem with the claim
  /// (a 404/405 means the receipt service itself is not on this server).
  Future<String> uploadReceipt(ReceiptFile file) async {
    try {
      final up = await _files.upload(
        bucket: receiptBucket,
        bytes: file.bytes,
        fileName: file.name,
        contentType: file.contentType,
      );
      return up.ref;
    } on ApiException catch (e) {
      throw ReceiptUploadException(e.statusCode);
    }
  }

  /// Uploads the receipts, then `POST /organizations/:orgId/expenses` with all lines in one request.
  ///
  /// Lines without a description or with a zero amount are skipped (as the web form does); at least
  /// one valid line is required. The server totals the lines and files the claim as pending.
  /// Returns the created claim row.
  Future<Map<String, dynamic>> createClaim({
    required String title,
    String? description,
    String? categoryId,
    required List<ExpenseLine> lines,
  }) async {
    final valid = lines
        .where((l) => l.description.trim().isNotEmpty && l.amount > 0)
        .toList();
    if (valid.isEmpty)
      throw StateError('At least one valid expense line item is required');

    final items = <Map<String, dynamic>>[];
    for (final l in valid) {
      final ref = l.receipt == null ? null : await uploadReceipt(l.receipt!);
      items.add({
        'expense_date': l.expenseDate,
        'description': l.description.trim(),
        'amount': l.amount,
        'receipt_url': ref,
      });
    }

    final data = await api.post(
      orgPath('/expenses'),
      body: {
        'employeeId': employeeId,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        'items': items,
      },
    );
    return data is Map
        ? _normalizeClaim(Map<String, dynamic>.from(data))
        : <String, dynamic>{};
  }

  static Map<String, dynamic> _normalizeClaim(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(snakeKeys(raw) as Map);
    for (final k in const ['amount', 'total_amount', 'approved_amount']) {
      if (m.containsKey(k)) m[k] = asNum(m[k]);
    }
    if (m['expense_date'] != null)
      m['expense_date'] = asDateOnly(m['expense_date']);
    return m;
  }
}

/// A receipt could not be uploaded. The claim was NOT created: receipts are uploaded before the claim is sent.
class ReceiptUploadException implements Exception {
  const ReceiptUploadException(this.statusCode);

  /// HTTP status of the failed upload, or 0 when no response arrived.
  final int statusCode;

  /// The server does not have the receipt service at all (route missing), not a problem with this file.
  bool get serviceUnavailable => statusCode == 404 || statusCode == 405;
}

/// The first problem the organization's expense policy would find with a claim, or null. This is the website's
/// `expensePolicyBlock` (it mirrors the database's `m2_expense_policy_guard`), run on the real category rows:
///  * a category is required when the organization has active categories, and it must be one of them;
///  * `monthly_limit` (> 0) caps the employee's total in the category for the month (`usedThisMonth` plus this claim);
///  * `requires_receipt` needs a receipt on at least one line.
/// The policy only rejects a claim when the organization runs expense reimbursement in `policy_enforced` mode, which the
/// app cannot read, so the caller treats the result as a warning the employee confirms, never as a hard block.
String? expensePolicyIssue({
  required List<Map<String, dynamic>> categories,
  required String? categoryId,
  required double total,
  required double usedThisMonth,
  required bool hasReceipt,
}) {
  final active = categories.where((c) => c['is_active'] != false).toList();
  if (categoryId == null || categoryId.isEmpty) {
    return active.isNotEmpty ? 'Select an expense category (your expense policy requires one).' : null;
  }
  Map<String, dynamic>? cat;
  for (final c in active) {
    if (c['id'].toString() == categoryId) cat = c;
  }
  if (cat == null) return 'The selected category is not active for your organization.';
  final name = cat['name']?.toString() ?? 'this category';
  final limit = (cat['monthly_limit'] as num?)?.toDouble() ?? 0;
  if (limit > 0 && usedThisMonth + total > limit) {
    return 'The monthly limit for "$name" is ${limit.toStringAsFixed(0)} (already ${usedThisMonth.toStringAsFixed(0)} this month), so this claim goes over it.';
  }
  if (cat['requires_receipt'] == true && !hasReceipt) {
    return 'A receipt is required for "$name".';
  }
  return null;
}

/// What the employee has already claimed in [categoryId] in the month of [date], from their own claims: the same sum the
/// database uses (approved amount, else the claimed amount; draft, rejected and cancelled claims do not count).
double expenseUsedThisMonth(
  List<Map<String, dynamic>> ownClaims, {
  required String categoryId,
  required DateTime date,
}) {
  var sum = 0.0;
  for (final c in ownClaims) {
    if (c['category_id']?.toString() != categoryId) continue;
    final status = (c['status'] ?? '').toString().toLowerCase();
    if (const {'draft', 'rejected', 'cancelled'}.contains(status)) continue;
    final when = DateTime.tryParse((c['expense_date'] ?? c['created_at'] ?? '').toString());
    if (when == null || when.year != date.year || when.month != date.month) continue;
    final amount = (c['approved_amount'] ?? c['amount'] ?? c['total_amount']) as num?;
    sum += amount?.toDouble() ?? 0;
  }
  return sum;
}
