import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../core/api/json_case.dart';
import '../repositories/loans_repository.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

/// The request may have reached the server even when the answer was lost, so the employee is told to check the list.
const String kLoanRequestFailedMessage =
    "Couldn't submit your loan request. Check My Loans before trying again.";

/// The largest amount the `requested_amount` column (decimal 12,2) can hold.
const double kLoanMaxAmountColumn = 9999999999.99;

/// Form for a loan request: amount, reason and an optional repayment period. Nothing else is sent.
/// The grade limit and eligibility are not checked here; the server does not enforce them either.
class LoanApplicationSheet extends StatefulWidget {
  final Future<bool> Function({
    required double amount,
    required String reason,
    int? repaymentMonths,
  })
  onSubmit;
  const LoanApplicationSheet({super.key, required this.onSubmit});

  @override
  State<LoanApplicationSheet> createState() => _LoanApplicationSheetState();
}

class _LoanApplicationSheetState extends State<LoanApplicationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _months = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _months.dispose();
    super.dispose();
  }

  static final _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

  String? _validateAmount(String? v) {
    final t = (v ?? '').trim();
    if (!_amountPattern.hasMatch(t))
      return 'Enter a valid amount (up to 2 decimals)';
    final n = double.tryParse(t);
    if (n == null || n <= 0) return 'Amount must be greater than 0';
    if (n > kLoanMaxAmountColumn) return 'Amount is too large';
    return null;
  }

  String? _validateReason(String? v) =>
      (v ?? '').trim().isEmpty ? 'Reason is required' : null;

  String? _validateMonths(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1)
      return 'Enter a whole number of months, or leave blank';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final monthsText = _months.text.trim();
    final ok = await widget.onSubmit(
      amount: double.parse(_amount.text.trim()),
      reason: _reason.text.trim(),
      repaymentMonths: monthsText.isEmpty ? null : int.parse(monthsText),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Apply for a loan',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
                validator: _validateAmount,
              ),
              TextFormField(
                controller: _reason,
                enabled: !_submitting,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: _validateReason,
              ),
              TextFormField(
                controller: _months,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Repayment months (optional)',
                  helperText: 'If left blank, 12 months is used.',
                ),
                validator: _validateMonths,
              ),
              const SizedBox(height: 10),
              Text(
                'Your request is sent for review. Any limit or eligibility rule is applied by HR, not by this form. '
                'Documents cannot be attached from the app.',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Submitting...' : 'Submit request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoansAdvancesScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  /// Overridable for tests; default to the signed-in session.
  final LoansRepository? loansRepository;

  const LoansAdvancesScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.loansRepository,
  }) : super(key: key);

  @override
  State<LoansAdvancesScreen> createState() => _LoansAdvancesScreenState();
}

class _LoansAdvancesScreenState extends State<LoansAdvancesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  late final LoansRepository _loansRepo =
      widget.loansRepository ?? LoansRepository();
  bool _loansLoading = true;
  bool _loansFailed = false;
  List<Map<String, dynamic>> _loans = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The employee's own loans from the HR Toffy API (read-only). The employee comes from the signed-in
  /// session; the grade's loan limit is not loaded because nothing on this screen shows it.
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loansLoading = true);
    try {
      _loans = await _loansRepo.loans();
      _loansFailed = false;
    } catch (_) {
      debugPrint('[Loans] loading loans failed');
      _loans = [];
      _loansFailed = true;
    }
    if (mounted) setState(() => _loansLoading = false);
  }

  bool _applying = false;

  /// Opens the loan request form. The request goes to `POST /loans/request` for the signed-in employee (taken from the
  /// session by the repository). The backend creates a pending request only: no documents, no manager, and no
  /// server-side check of the grade's loan limit.
  Future<void> _openApplication() async {
    if (_applying) return;
    _applying = true;
    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => LoanApplicationSheet(onSubmit: _submitRequest),
      );
      if (submitted == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loan request submitted. It is pending review.'),
          ),
        );
        await _load();
      }
    } finally {
      _applying = false;
    }
  }

  /// True when the server accepted the request. A fixed message is shown otherwise, never the server's text.
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kLoanRequestFailedMessage)),
        );
      return false;
    }
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: SvgPicture.asset(
          icon,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(
            EmployeeUi.primary,
            BlendMode.srcIn,
          ),
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.loans,
        companyLogoUrl: null,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 12),
                child: _circleIconBtn(
                  icon: "assets/icons/notification.svg",
                  onTap: () {
                    final empId =
                        (widget.userData['id'] ??
                                widget.userData['employee_id'])
                            ?.toString() ??
                        '';
                    if (empId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationsScreen(
                            employeeId: empId,
                            userEmail: widget.userEmail,
                            userData: widget.userData,
                            fetchHrmsContext: widget.fetchHrmsContext,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: _circleIconBtn(
                  icon: "assets/icons/menu.svg",
                  onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ),
              const SizedBox(width: 1),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEBDFF6), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Loans & Advances", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text(
                      "Manage your financial requests",
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: EmployeeUi.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EmployeeUi.border),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: EmployeeUi.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'My Loans'),
                      Tab(text: 'EMI Schedule'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                MyLoansTab(
                  loans: _loans,
                  loading: _loansLoading,
                  loadFailed: _loansFailed,
                ),
                EMIScheduleTab(repository: _loansRepo),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _openApplication,
              backgroundColor: EmployeeUi.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) async {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardScreen(
                  email: widget.userEmail,
                  employeeId: widget.userData['id'].toString(),
                ),
              ),
            );
            return;
          }
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LeavesScreen(
                  email: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext: widget.fetchHrmsContext,
                ),
              ),
            );
            return;
          }
          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TimeAttendanceScreen(
                  userEmail: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext: widget.fetchHrmsContext,
                ),
              ),
            );
            return;
          }
          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayslipScreen(
                  userEmail: widget.userEmail,
                  userData: widget.userData,
                  fetchHrmsContext: widget.fetchHrmsContext,
                ),
              ),
            );
            return;
          }
          if (index == 4) {
            _scaffoldKey.currentState?.openEndDrawer();
            return;
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/dashboard.svg",
              width: 22,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/leaves.svg",
              width: 22,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
            label: 'Leave',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/attendance.svg",
              width: 22,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/payroll.svg",
              width: 22,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
            label: 'Payslip',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              "assets/icons/menu.svg",
              width: 22,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

/// The employee's loans (already loaded by the screen). Amounts the server could not give a usable value
/// for are shown as "Not available" rather than "₹0".
class MyLoansTab extends StatelessWidget {
  final List<Map<String, dynamic>> loans;
  final bool loading;
  final bool loadFailed;
  const MyLoansTab({
    Key? key,
    required this.loans,
    this.loading = false,
    this.loadFailed = false,
  }) : super(key: key);

  static const List<Color> _pastelPalette = [
    Color(0xFFD7E8FF), // Soft Blue
    Color(0xFFFFECE6), // Soft Peach
    Color(0xFFDFF6E5), // Soft Mint
    Color(0xFFFCE4EC), // Soft Pink
    Color(0xFFEBDFF6), // Soft Lavender
    Color(0xFFFFF7D6), // Soft Yellow
  ];

  String formatCurrency(dynamic value) {
    final n = asNum(value);
    if (!LoansRepository.isUsableAmount(n)) return 'Not available';
    return '₹${NumberFormat('#,##,###').format(n)}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonLoansMyLoans();
    if (loans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              "assets/icons/loans.svg",
              height: 80,
              colorFilter: const ColorFilter.mode(
                Colors.blueGrey,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              loadFailed
                  ? "Couldn't load your loans. Please try again later."
                  : "No loans found",
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: loans.length,
      itemBuilder: (context, i) {
        final loan = loans[i];
        final status = (loan['status'] ?? "").toString().toLowerCase();
        Color statusColor = Colors.grey;
        if (status == 'approved' || status == 'active') {
          statusColor = Colors.green;
        } else if (status == 'pending') {
          statusColor = Colors.orange;
        } else if (status == 'rejected') {
          statusColor = Colors.red;
        }

        final pastel = _pastelPalette[i % _pastelPalette.length];
        final baseDeco = EmployeeUi.cardDecoration();
        final tenure = asNum(loan['tenure_months'])?.toInt();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: (baseDeco is BoxDecoration)
              ? baseDeco.copyWith(color: pastel)
              : BoxDecoration(
                  color: pastel,
                  borderRadius: BorderRadius.circular(12),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (loan['loan_number'] ?? "LOAN-ID").toString(),
                    style: EmployeeUi.title(15),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _rowInfo("Category", loan['loan_category']),
              _rowInfo("Amount", formatCurrency(loan['requested_amount'])),
              _rowInfo("Tenure", tenure == null ? '-' : "$tenure months"),
            ],
          ),
        );
      },
    );
  }

  Widget _rowInfo(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value?.toString() ?? '-',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The instalment schedule of the employee's loans. An instalment whose EMI amount is missing or 0 shows
/// "Not available" (and hides the outstanding balance) instead of presenting zeros as real figures.
class EMIScheduleTab extends StatefulWidget {
  final LoansRepository repository;
  const EMIScheduleTab({Key? key, required this.repository}) : super(key: key);

  @override
  State<EMIScheduleTab> createState() => _EMIScheduleTabState();
}

class _EMIScheduleTabState extends State<EMIScheduleTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.emiSchedule();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Couldn't load your EMI schedule. Please try again later.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const SkeletonLoansEMISchedule();
        final emis = snapshot.data!;
        if (emis.isEmpty)
          return const Center(child: Text("No EMI schedules found."));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: emis.length,
          itemBuilder: (context, i) {
            final emi = emis[i];
            final status = (emi['status'] ?? 'pending')
                .toString()
                .toLowerCase();
            final emiAmount = asNum(emi['emi_amount']);
            final emiUsable = LoansRepository.isUsableAmount(emiAmount);
            final outstanding = asNum(emi['outstanding_principal']);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: EmployeeUi.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Loan: ${emi['loans_advances']?['loan_number'] ?? '-'}",
                        style: EmployeeUi.title(14),
                      ),
                      Text(
                        status.toUpperCase(),
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: status == 'paid'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Due Date: ${asDateOnly(emi['due_date']) ?? '-'}",
                    style: GoogleFonts.montserrat(fontSize: 13),
                  ),
                  if (emiUsable && outstanding != null)
                    Text(
                      "Outstanding: ₹${NumberFormat('#,##,###').format(outstanding)}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  Text(
                    emiUsable
                        ? "EMI Amount: ₹${NumberFormat('#,##,###').format(emiAmount)}"
                        : "EMI Amount: Not available",
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: EmployeeUi.primary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
