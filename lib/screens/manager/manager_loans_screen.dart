import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/approvals_repository.dart';
import '../../repositories/employee_repository.dart';
import '../../repositories/loans_repository.dart';
import '../loans_advances_screens.dart'
    show LoanApplicationSheet, kLoanRequestFailedMessage;
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import 'widgets/loan_approvals_panel.dart';

/// Shown for every action that has no verified AWS route yet (the organization-wide list and HR submission).
/// Nothing is requested for them and nothing is written.
const String kLoansUnavailableMessage = "This isn't available yet";

/// Fixed text for any failed load: the server's or the exception's text is never shown.
const String kLoansLoadFailedMessage =
    "Couldn't load your loans right now. Please try again.";

/// What an amount that is missing, zero or otherwise unusable (possibly an unreadable encrypted value) shows.
const String kLoanAmountUnavailable = 'Not available';

/// "₹50,000" for a usable amount; [kLoanAmountUnavailable] for null, zero or non-numeric values (never "₹0").
String loanMoney(dynamic v) {
  final n = asNum(v);
  if (!LoansRepository.isUsableAmount(n)) return kLoanAmountUnavailable;
  return '₹${NumberFormat('#,##,###.##').format(n)}';
}

/// Manager loans hub.
///
/// Live: the signed-in user's OWN loans, EMI schedule, grade loan limit and the utilization against it, Apply for Loan
/// (`POST /loans/request`), and Approvals ([LoanApprovalsPanel]; its badge counts the requests the caller may decide now, "-" while unknown).
/// Unavailable: All Loans and HR Submit (HR-only, no verified route for managers).
class ManagerLoansScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final LoansRepository? loansRepository;
  final EmployeeRepository? employeeRepository;
  final ApprovalsRepository? approvalsRepository;

  const ManagerLoansScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.loansRepository,
    this.employeeRepository,
    this.approvalsRepository,
  });

  @override
  State<ManagerLoansScreen> createState() => _ManagerLoansScreenState();
}

class _ManagerLoansScreenState extends State<ManagerLoansScreen> {
  late final LoansRepository _loansRepo =
      widget.loansRepository ?? LoansRepository();
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String activeAction =
      'none'; // none, my_loans, apply, emi_schedule, approvals, all_loans, hr_submit
  bool loading = true;

  /// Null until loaded or when loading failed ([loansFailed]).
  List<Map<String, dynamic>>? loans;
  bool loansFailed = false;

  /// The grade's loan limit; null when unknown (no grade, no limit row, not readable, or a failed lookup).
  double? loanLimit;

  /// Loan requests the caller may decide now (row-meta); null while unknown or when it could not be determined.
  int? pendingApprovals;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (mounted) setState(() => loading = true);

    String? grade;
    try {
      grade = (await _employees.getMe())['grade_code']?.toString();
    } catch (_) {
      grade = null;
    }

    await Future.wait([
      _fetchLoans(),
      _fetchLimit(grade),
      _fetchApprovalCount(),
    ]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchLoans() async {
    try {
      // Scoped to the signed-in employee by the repository; it throws (no request) without an employee id.
      loans = await _loansRepo.loans();
      loansFailed = false;
    } catch (_) {
      loans = null;
      loansFailed = true;
    }
  }

  Future<void> _fetchApprovalCount() async {
    try {
      pendingApprovals = await LoanApprovalsPanel.countActionable(
        loansRepository: _loansRepo,
        approvalsRepository: _approvals,
      );
    } catch (_) {
      pendingApprovals = null;
    }
  }

  Future<void> _backToOverview() async {
    setState(() => activeAction = 'none');
    await _fetchApprovalCount(); // a decision may have changed it
    if (mounted) setState(() {});
  }

  bool _applying = false;

  /// Opens the loan request form: `POST /loans/request` for the signed-in employee. A fixed message is shown on failure.
  Future<void> _openApplication() async {
    if (_applying) return;
    _applying = true;
    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => LoanApplicationSheet(onSubmit: _submitRequest),
      );
      if (submitted == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loan request submitted. It is pending review.'),
          ),
        );
        await _initData();
      }
    } finally {
      _applying = false;
    }
  }

  Future<bool> _submitRequest({
    required double amount,
    required String reason,
    int? repaymentMonths,
  }) async {
    try {
      await _loansRepo.requestLoan(
        amount: amount,
        reason: reason,
        repaymentMonths: repaymentMonths,
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kLoanRequestFailedMessage)),
        );
      }
      return false;
    }
  }

  Future<void> _fetchLimit(String? grade) async {
    loanLimit = null;
    if (grade == null || grade.isEmpty) return;
    try {
      loanLimit = await _loansRepo.loanMaxAmount(grade);
    } catch (_) {
      loanLimit = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.loans,
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
            "Manage your loans, apply for advances, and track EMI schedules easily.",
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
    final bool isManager = [
      'manager',
      'reviewer',
      'hr',
      'hr_manager',
      'hr_head',
      'admin',
    ].contains(empRole);
    final bool isAdmin = ['admin', 'hr_head'].contains(empRole);
    final bool isHR = [
      'hr',
      'hr_manager',
      'hr_head',
      'admin',
    ].contains(empRole);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.9,
      children: [
        _actionCard(
          "My Loans",
          "Track your active loans.",
          Icons.credit_card,
          const Color(0xFFD4F3F7),
          'my_loans',
        ),
        _actionCard(
          "Apply for Loan",
          "Request a new advance.",
          Icons.add_circle_outline,
          const Color(0xFFDFF6E5),
          'apply',
        ),
        _actionCard(
          "EMI Schedule",
          "View upcoming deductions.",
          Icons.calendar_today,
          const Color(0xFFEBDFF6),
          'emi_schedule',
        ),
        if (isManager)
          _actionCard(
            "Approvals",
            "Review team loan requests.",
            Icons.check_box_outlined,
            const Color(0xFFFFECE6),
            'approvals',
            badge: pendingApprovals,
            unknownBadge: pendingApprovals == null,
          ),
        if (isAdmin)
          _actionCard(
            "All Loans",
            "View organization-wide loans.",
            Icons.list_alt_rounded,
            const Color(0xFFF5F5F5),
            'all_loans',
          ),
        if (isHR)
          _actionCard(
            "HR Submit",
            "Apply on behalf of employee.",
            Icons.add_to_photos_outlined,
            const Color(0xFFDFF6E5),
            'hr_submit',
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
    int? badge,
  }) {
    return InkWell(
      onTap: () {
        if (action == 'apply') {
          _openApplication();
        } else {
          setState(() => activeAction = action);
        }
      },
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
                      child: const Text(
                        "-",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (badge != null && badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$badge',
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
              kLoansUnavailableMessage,
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
      case 'my_loans':
        title = "My Loans";
        child = MyLoansPanel(
          loans: loans,
          failed: loansFailed,
          loanLimit: loanLimit,
          onRetry: _initData,
        );
        break;
      case 'emi_schedule':
        title = "EMI Schedule";
        child = EMISchedulePanel(repository: _loansRepo);
        break;
      case 'approvals':
        title = "Loan Approvals";
        child = LoanApprovalsPanel(
          loansRepository: _loansRepo,
          approvalsRepository: _approvals,
        );
        break;
      case 'all_loans':
        title = "All Loans";
        child = _unavailableState();
        break;
      case 'hr_submit':
        title = "HR Loan Submission";
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
        onTap: _backToOverview,
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

// 🔵 My Loans Panel: the user's own loans, with the loan limit and what is used against it.
class MyLoansPanel extends StatelessWidget {
  final List<Map<String, dynamic>>? loans;
  final bool failed;
  final double? loanLimit;
  final VoidCallback onRetry;
  const MyLoansPanel({
    super.key,
    required this.loans,
    required this.failed,
    required this.loanLimit,
    required this.onRetry,
  });

  Widget _limitCard(List<Map<String, dynamic>> list) {
    final used = LoansRepository.usedAgainstLimit(list);
    final limitUsable = LoansRepository.isUsableAmount(loanLimit);
    final percent = (limitUsable && !used.incomplete)
        ? (used.total / loanLimit!).clamp(0.0, 1.0)
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _stat("Loan limit", loanMoney(loanLimit))),
              Expanded(
                child: _stat(
                  used.incomplete ? "Used (at least)" : "Used",
                  used.total == 0 && used.incomplete
                      ? kLoanAmountUnavailable
                      : '₹${NumberFormat('#,##,###.##').format(used.total)}',
                ),
              ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: percent, minHeight: 6),
            const SizedBox(height: 4),
            Text(
              "${(percent * 100).round()}% of your limit",
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          if (used.incomplete) ...[
            const SizedBox(height: 8),
            Text(
              "Incomplete: some loan amounts aren't available, so this figure may be too low.",
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.orange.shade800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kLoansLoadFailedMessage,
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
    final list = loans ?? const <Map<String, dynamic>>[];
    if (list.isEmpty)
      return Center(
        child: Text(
          "No loans found",
          style: GoogleFonts.montserrat(color: Colors.grey),
        ),
      );

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == 0) return _limitCard(list);
        final loan = list[index - 1];
        final status = (loan['status'] ?? 'pending').toString().toLowerCase();
        final tenure = asNum(loan['tenure_months'])?.toInt();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loan['loan_number']?.toString() ?? 'Loan',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                loan['loan_category']
                        ?.toString()
                        .replaceAll('_', ' ')
                        .toUpperCase() ??
                    'LOAN',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                loan['purpose']?.toString() ?? '-',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat("Requested", loanMoney(loan['requested_amount'])),
                  _stat("Tenure", tenure == null ? '-' : "$tenure Months"),
                  _stat("EMI", loanMoney(loan['emi_amount'])),
                ],
              ),
              if (loan['is_hr_submission'] == true) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "HR SUBMITTED",
                    style: GoogleFonts.montserrat(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'pending':
        color = const Color(0xFFF2994A);
        break;
      case 'approved':
        color = const Color(0xFF219653);
        break;
      case 'rejected':
        color = const Color(0xFFEB5757);
        break;
      case 'active':
      case 'disbursed':
        color = const Color(0xFF2F80ED);
        break;
      case 'closed':
        color = const Color(0xFF888888);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _stat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
        ),
        Text(
          val,
          style: GoogleFonts.playfairDisplay(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// 🟣 EMI Schedule Panel: the user's own instalments, grouped by loan. An instalment whose EMI amount is
// missing or 0 shows "Not available" and hides the outstanding balance.
class EMISchedulePanel extends StatefulWidget {
  final LoansRepository repository;
  const EMISchedulePanel({super.key, required this.repository});

  @override
  State<EMISchedulePanel> createState() => _EMISchedulePanelState();
}

class _EMISchedulePanelState extends State<EMISchedulePanel> {
  bool loading = true;
  bool failed = false;
  Map<String, List<Map<String, dynamic>>> schedule = {};

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    if (mounted) setState(() => loading = true);
    try {
      final data = await widget.repository.emiSchedule();
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in data) {
        final ln =
            (row['loans_advances'] is Map
                    ? row['loans_advances']['loan_number']
                    : null)
                ?.toString() ??
            'Unknown';
        grouped.putIfAbsent(ln, () => []).add(row);
      }
      if (mounted) {
        setState(() {
          schedule = grouped;
          failed = false;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your EMI schedule right now. Please try again.",
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _fetchSchedule, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (schedule.isEmpty)
      return Center(
        child: Text(
          "No EMI schedules found",
          style: GoogleFonts.montserrat(color: Colors.grey),
        ),
      );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: schedule.entries.map((entry) {
        final category = entry.value.first['loans_advances'] is Map
            ? entry.value.first['loans_advances']['loan_category']
            : null;
        return ExpansionTile(
          title: Text(
            entry.key,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            category?.toString().toUpperCase() ?? '',
            style: const TextStyle(fontSize: 10),
          ),
          children: entry.value.map((emi) {
            final status = (emi['status'] ?? 'pending')
                .toString()
                .toLowerCase();
            final emiAmount = asNum(emi['emi_amount']);
            final emiUsable = LoansRepository.isUsableAmount(emiAmount);
            final outstanding = asNum(emi['outstanding_principal']);
            final due = asDate(emi['due_date']);
            return ListTile(
              dense: true,
              title: Text(
                "EMI #${emi['emi_number'] ?? '-'} - ${due == null ? '-' : DateFormat('MMM yyyy').format(due)}",
              ),
              subtitle: emiUsable && outstanding != null
                  ? Text(
                      "Outstanding: ${loanMoney(outstanding)}",
                      style: const TextStyle(fontSize: 11),
                    )
                  : null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    loanMoney(emiAmount),
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: status == 'paid' ? Colors.green : Colors.orange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
