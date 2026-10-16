import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/expense_repository.dart';
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import '../../repositories/approvals_repository.dart';
import 'widgets/expense_approvals_panel.dart';

/// Shown for every action that has no verified AWS route yet (submitting a claim, team approvals, the
/// organization-wide list, claim line items and receipts). Nothing is requested for them and nothing is written.
const String kExpensesUnavailableMessage = "This isn't available yet";

/// Fixed text for any failed load: the server's or the exception's text is never shown.
const String kExpensesLoadFailedMessage =
    "Couldn't load your expenses right now. Please try again.";

/// Manager expenses hub (AWS migration phase A, read-only).
///
/// Live: the signed-in user's OWN expense claims and category names, through [ExpenseRepository]. The
/// repository always sends the caller's own employee id; if it cannot be established no request is made.
/// Unavailable: Submit Claim, Approvals (badge "-"), All Claims, claim line items and receipts.
class ManagerExpensesScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final ExpenseRepository? expenseRepository;
  final ApprovalsRepository? approvalsRepository;

  const ManagerExpensesScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.expenseRepository,
    this.approvalsRepository,
  });

  @override
  State<ManagerExpensesScreen> createState() => _ManagerExpensesScreenState();
}

class _ManagerExpensesScreenState extends State<ManagerExpensesScreen> {
  late final ExpenseRepository _expenses =
      widget.expenseRepository ?? ExpenseRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Claims the caller may decide; null while unknown or when it could not be read (the badge then shows "-").
  int? approvalsCount;

  String activeAction =
      'none'; // none, my_expenses, submit, approvals, all_claims
  bool loading = true;

  /// Null until loaded, or when loading failed ([claimsFailed]).
  List<Map<String, dynamic>>? claims;
  bool claimsFailed = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (mounted) setState(() => loading = true);

    // Claims carry category_id only: the names come from the category list (best effort).
    List<Map<String, dynamic>> categories = const [];
    try {
      categories = await _expenses.categories();
    } catch (_) {}

    try {
      // Scoped to the signed-in employee by the repository; it throws (no request) without an employee id.
      claims = await _expenses.claims(categories: categories);
      claimsFailed = false;
    } catch (_) {
      claims = null;
      claimsFailed = true;
    }
    if (mounted) setState(() => loading = false);
    _loadApprovalsCount();
  }

  Future<void> _loadApprovalsCount() async {
    if (!_isApprover) return;
    try {
      final n = await ExpenseApprovalsPanel.countActionable(
        approvalsRepository: _approvals,
        expenseRepository: _expenses,
      );
      if (mounted) setState(() => approvalsCount = n);
    } catch (_) {
      if (mounted) setState(() => approvalsCount = null);
    }
  }

  bool get _isApprover => const [
    'manager',
    'reviewer',
    'hr',
    'hr_manager',
    'hr_head',
    'admin',
  ].contains(widget.userData['emp_role']?.toString().toLowerCase());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.expenses,
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Image.asset("assets/HR TOFFY.png", height: 35),
        actions: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.menu, color: Colors.black),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (activeAction != 'none') return _buildDetailView();

    return RefreshIndicator(
      onRefresh: _initData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroBanner(),
            const SizedBox(height: 32),
            _buildGrid(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD7E8FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Rewards that feel personal",
            style: GoogleFonts.playfairDisplay(
              color: const Color(0xFF444444),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Track reimbursements, submit business expenses, and manage team claims in one place.",
            style: GoogleFonts.montserrat(
              color: const Color(0xFF666666),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // Which cards appear still depends on the role, exactly as before.
    final empRole = widget.userData['emp_role']?.toString().toLowerCase();
    final bool isApprover = [
      'manager',
      'reviewer',
      'hr',
      'hr_manager',
      'hr_head',
      'admin',
    ].contains(empRole);
    final bool isAdmin = ['admin', 'hr_head'].contains(empRole);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.9,
      children: [
        _actionCard(
          "My Expenses",
          "View your reimbursement history.",
          Icons.receipt_long,
          const Color(0xFFDFF6E5),
          'my_expenses',
        ),
        _actionCard(
          "Submit Claim",
          "Raise a new expense claim.",
          Icons.add_circle_outline,
          const Color(0xFFD4F3F7),
          'submit',
        ),
        if (isApprover)
          _actionCard(
            "Approvals",
            "Review pending team expenses.",
            Icons.fact_check_outlined,
            const Color(0xFFFFECE6),
            'approvals',
            unknownBadge: true,
            badgeText: approvalsCount == null ? '-' : '$approvalsCount',
          ),
        if (isAdmin)
          _actionCard(
            "All Claims",
            "Organization-wide expense view.",
            Icons.analytics_outlined,
            const Color(0xFFF5F5F5),
            'all_claims',
          ),
      ],
    );
  }

  /// [unknownBadge]: the team count is not available, so a neutral "-" is shown (never 0).
  Widget _actionCard(
    String label,
    String desc,
    IconData icon,
    Color color,
    String action, {
    bool unknownBadge = false,
    String badgeText = '-',
  }) {
    return InkWell(
      onTap: () => setState(() => activeAction = action),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.black87, size: 24),
                ),
                if (unknownBadge)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade500,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                desc,
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  color: Colors.black54,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailableState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 40,
              color: Colors.orange[700],
            ),
            const SizedBox(height: 12),
            Text(
              kExpensesUnavailableMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    Widget child;
    String title;

    switch (activeAction) {
      case 'my_expenses':
        title = "My Expenses";
        child = MyExpensesPanel(
          claims: claims,
          failed: claimsFailed,
          onRetry: _initData,
        );
        break;
      case 'submit':
        title = "Submit Expense Claim";
        child = _unavailableState();
        break;
      case 'approvals':
        title = "Expense Approvals";
        child = ExpenseApprovalsPanel(
          approvalsRepository: _approvals,
          expenseRepository: _expenses,
        );
        break;
      case 'all_claims':
        title = "All Claims";
        child = _unavailableState();
        break;
      default:
        title = activeAction.replaceAll('_', ' ').toUpperCase();
        child = _unavailableState();
    }

    return Column(
      children: [
        _buildDetailHeader(title),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildDetailHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white),
      child: InkWell(
        onTap: () {
          final wasApprovals = activeAction == 'approvals';
          setState(() => activeAction = 'none');
          if (wasApprovals)
            _loadApprovalsCount(); // a decision changed the queue
        },
        child: Row(
          children: [
            const Icon(Icons.arrow_back, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              "Back to overview",
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "₹1,250.50" for a number; "-" when the amount is unknown (never a made-up 0).
String _money(num? v) => v == null
    ? '-'
    : NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(v);

// 🔵 My Expenses Panel: the user's own claims. Line items and receipts have no verified route yet.
class MyExpensesPanel extends StatelessWidget {
  final List<Map<String, dynamic>>? claims;
  final bool failed;
  final VoidCallback onRetry;
  const MyExpensesPanel({
    super.key,
    required this.claims,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kExpensesLoadFailedMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    final list = claims ?? const <Map<String, dynamic>>[];
    if (list.isEmpty)
      return Center(
        child: Text(
          "No expense claims found",
          style: GoogleFonts.montserrat(color: Colors.grey),
        ),
      );

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final claim = list[index];
        final status = (claim['status'] ?? 'pending').toString().toLowerCase();
        // The repository normalises both fields to numbers; whichever the server sends is shown.
        final total = asNum(claim['total_amount']) ?? asNum(claim['amount']);

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade100),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade100),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  claim['claim_number']?.toString() ?? 'Expense claim',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue.shade700,
                  ),
                ),
                _statusBadge(status),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  claim['title']?.toString() ?? 'Expense',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  claim['category_name']?.toString() ?? '-',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 16,
                      color: Colors.grey.shade400,
                    ), // receipts: no action, no request
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Line items and receipts aren't available yet",
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _money(total),
                      style: GoogleFonts.playfairDisplay(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'draft':
        color = Colors.grey;
        break;
      case 'pending':
        color = const Color(0xFFF2994A);
        break;
      case 'manager_approved':
        color = const Color(0xFF2F80ED);
        break;
      case 'approved':
      case 'paid':
        color = const Color(0xFF219653);
        break;
      case 'rejected':
        color = const Color(0xFFEB5757);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
