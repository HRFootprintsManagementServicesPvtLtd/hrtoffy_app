import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api/json_case.dart';
import '../repositories/benefits_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/workflow_repository.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'payslip_screen.dart';
import 'attendance_screen.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

/// Claim submission stays OFF until the staging backend is verified to store a claim's payroll fields (payment mode,
/// claim month and year, manager). That fix (commit ba743e3) was merged into the backend's `claude/funny-allen-dt492e`
/// branch on 8 Oct, but the app cannot tell what staging actually runs. Before turning this on: submit one claim as a
/// dedicated test employee and check the stored row has `payment_mode = 'payroll'`, `claim_month`, `claim_year` and
/// `manager_id`, that an approval step exists for the manager (the app starts it with `POST /workflows/initialize`
/// after the claim), and that approving it makes payroll pick it up. Mind the month: the server sets it in UTC, so a
/// claim made in the first hours (IST) of the 1st lands in the previous month. Receipts are not sent: the Files API is
/// not on the deployed backend, so the form says attachments can't be added.
const bool kBenefitClaimSubmissionEnabled = false;

const String kBenefitSubmitFailedMessage =
    "Couldn't submit your claim. Please try again.";
const String kBenefitClaimLoadFailedMessage =
    "Couldn't load this claim. Please try again.";

class BenefitsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  /// Overridable for tests; default to the signed-in session.
  final BenefitsRepository? benefitsRepository;
  final EmployeeRepository? employeeRepository;

  /// Overridable for tests: starts the approval chain after a claim is stored.
  final WorkflowRepository? workflowRepository;

  /// Tests only: lets the submit flow be exercised while [kBenefitClaimSubmissionEnabled] is false. The app never sets it.
  final bool? claimSubmissionEnabled;

  const BenefitsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.benefitsRepository,
    this.employeeRepository,
    this.workflowRepository,
    this.claimSubmissionEnabled,
  });
  @override
  State<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends State<BenefitsScreen>
    with TickerProviderStateMixin, RefreshableScreen<BenefitsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0; // Benefits tab index
  String? employeeId, organizationId, grade, managerId;
  late final BenefitsRepository _benefits =
      widget.benefitsRepository ?? BenefitsRepository();
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();
  late final WorkflowRepository _workflows =
      widget.workflowRepository ?? WorkflowRepository();
  bool _loadFailed = false;
  List<Map<String, dynamic>> claims = [];
  List<Map<String, dynamic>> benefits = [];
  Map<String, dynamic>? gradeLimitData;
  double claimedTotal = 0.0;
  @override
  void initState() {
    super.initState();
    startLoad();
  }

  @override
  Future<void> loadData() async {
    await fetchAll();
  }

  /// Loads the employee, their claims, the catalog and the grade limit from the HR Toffy API.
  /// Only the claims list is shown for now; the catalog and the limit are kept for the claim form,
  /// which stays unavailable until claim submission is enabled.
  Future<void> fetchAll() async {
    try {
      final me = await _employees.getMe();
      employeeId = me['id']?.toString();
      organizationId = me['organization_id']?.toString();
      grade = me['grade_code']?.toString();
      managerId = me['manager_id']?.toString();
      _loadFailed = false;
    } catch (_) {
      debugPrint('[Benefits] loading the employee failed');
      if (mounted) setState(() => _loadFailed = true);
      return;
    }

    await Future.wait([fetchClaims(), fetchBenefits()]);
    if (mounted) setState(() {});
  }

  Future<void> fetchClaims() async {
    try {
      claims = await _benefits.claims();
      claimedTotal = BenefitsRepository.claimedTotalForYear(
        claims,
        DateTime.now().year,
      );
      _loadFailed = false;
    } catch (_) {
      debugPrint('[Benefits] loading claims failed');
      claims = [];
      claimedTotal = 0.0;
      _loadFailed = true;
    }
  }

  Future<void> fetchBenefits() async {
    try {
      benefits = await _benefits.catalog();
    } catch (_) {
      debugPrint('[Benefits] loading the catalog failed');
      benefits = [];
    }
    final code = grade;
    if (code != null && code.isNotEmpty) {
      try {
        gradeLimitData = await _benefits.gradeLimit(code);
      } catch (_) {
        debugPrint('[Benefits] loading the grade limit failed');
        gradeLimitData = null;
      }
    }
  }

  /// Claim submission is switched off in the app: the backend that stores the payroll fields of a
  /// claim is not confirmed deployed yet, and the old direct-to-database path of the previous backend is gone.
  void _claimSubmissionUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Submitting benefit claims from the app isn't available yet. Please contact HR.",
        ),
      ),
    );
  }

  void _onAddPressed() {
    if (!(widget.claimSubmissionEnabled ?? kBenefitClaimSubmissionEnabled)) {
      return _claimSubmissionUnavailable();
    }
    if (benefits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No benefits are available to claim right now.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmitClaimPage(
          benefits: benefits,
          gradeLimitData: gradeLimitData,
          claimedTotal: claimedTotal,
          onSubmit: _submitClaim,
        ),
      ),
    );
  }

  /// Sends the claim for the signed-in employee (the repository takes the employee from the session); the server
  /// decides everything else. True only on success; failures show a fixed message, never the server's text.
  Future<bool> _submitClaim({
    required String benefitId,
    required double claimAmount,
    required String description,
  }) async {
    String claimId;
    try {
      claimId = await _benefits.submitClaim(
        benefitId: benefitId,
        amount: claimAmount,
        description: description.trim(),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kBenefitSubmitFailedMessage)),
        );
      return false;
    }
    // The claim is stored. Start its approval chain as a separate step, like the website; a failure here is not a failed
    // claim (the call never throws), it only changes what the employee is told.
    final routed = await _workflows.initialize(
      WorkflowRepository.benefits,
      claimId,
    );
    await fetchClaims();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            routed
                ? 'Claim submitted.'
                : "Claim submitted. We couldn't confirm that approval routing started, so your manager may not be notified yet.",
          ),
        ),
      );
    }
    return true;
  }

  Future<void> _openClaim(Map<String, dynamic> claim) async {
    final id = claim['id']?.toString();
    if (id == null || id.isEmpty) return;
    final Map<String, dynamic> d;
    try {
      d = await _benefits.claim(id);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kBenefitClaimLoadFailedMessage)),
        );
      return;
    }
    if (!mounted) return;
    final catalog = d['benefits_catalog'] is Map
        ? Map<String, dynamic>.from(d['benefits_catalog'] as Map)
        : const <String, dynamic>{};
    String row(String k) => (d[k] ?? '-').toString();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (catalog['benefit_name'] ?? 'Benefit').toString(),
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text('Status: ${row('status').toUpperCase()}'),
              Text('Claimed: ₹${row('claimed_amount')}'),
              if (d['approved_amount'] != null)
                Text('Approved: ₹${row('approved_amount')}'),
              Text('Date: ${row('claim_date')}'),
              Text('Description: ${row('description')}'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildRefreshable(
      skeleton: const SkeletonBenefits(),
      childBuilder: () => Scaffold(
        key: _scaffoldKey,
        backgroundColor: EmployeeUi.pageBg,
        endDrawer: AppDrawer(
          userEmail: widget.userEmail,
          userData: widget.userData,
          fetchHrmsContext: widget.fetchHrmsContext,
          currentRoute: DrawerRoute.benefits,
          companyLogoUrl: widget.userData['company_logo_url'],
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
                  padding: const EdgeInsets.only(right: 6, top: 12),
                  child: GestureDetector(
                    onTap: _onAddPressed,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: EmployeeUi.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 12),
                  child: Container(
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
                        "assets/icons/menu.svg",
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          EmployeeUi.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      onPressed: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                  ),
                ),
                const SizedBox(width: 1),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFD7E8FF), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text("Benefits Hub", style: EmployeeUi.header(24)),
                      const SizedBox(height: 4),
                      Text(
                        "Manage your perks and claims",
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
            SliverFillRemaining(
              child: MyBenefitsTab(
                claims: claims,
                loadFailed: _loadFailed,
                onOpen: _openClaim,
              ),
            ),
          ],
        ),
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
              setState(() => _bottomTabIndex = 0);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    email: widget.userEmail,
                    employeeId: widget.userData['id'], // 👈 IMPORTANT
                  ),
                ),
              );
              return;
            }
            if (index == 1) {
              setState(() => _bottomTabIndex = 1);
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
              setState(() => _bottomTabIndex = 2);
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
              setState(() => _bottomTabIndex = 3);
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
            // 🤖 TOFFY ICON
          },
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/dashboard.svg",
                width: 22,
                color: _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/leaves.svg",
                width: 22,
                color: _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Leave',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/attendance.svg",
                width: 22,
                color: _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Attendance',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/payroll.svg",
                width: 22,
                color: _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Payslip',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/menu.svg",
                width: 22,
                color: Colors.grey,
              ),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

// MY BENEFITS TAB (unchanged UI)
class MyBenefitsTab extends StatelessWidget {
  final List<Map<String, dynamic>> claims;
  final bool loadFailed;
  final void Function(Map<String, dynamic> claim)? onOpen;
  const MyBenefitsTab({
    required this.claims,
    this.loadFailed = false,
    this.onOpen,
  });

  /// "08 Oct 2026", or "-" when a claim has no usable date (one bad row must not break the list).
  String _claimDateText(dynamic value) {
    final d = DateTime.tryParse(asDateOnly(value) ?? '');
    return d == null ? '-' : DateFormat('dd MMM yyyy').format(d);
  }

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'paid':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) {
      return Center(
        child: Text(
          loadFailed
              ? "Couldn't load your claims. Pull down to try again."
              : "No claims found.",
          style: GoogleFonts.montserrat(),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: const EmployeeSectionHeader(
            title: "My Benefits",
            subtitle: "Track claim status and approved amounts",
          ),
        ),
        ListView.separated(
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          itemBuilder: (c, i) {
            final claim = claims[i];
            final benefit = claim['benefits_catalog'] ?? {};
            final pastelColors = [
              const Color(0xFFEAF4FF), // Soft Blue
              const Color(0xFFFFF3E6), // Soft Peach
              const Color(0xFFEAFBF2), // Soft Mint
              const Color(0xFFFFEEF5), // Soft Pink
              const Color(0xFFF2EEFF), // Soft Lavender
              const Color(0xFFFFF9E8), // Soft Yellow
            ];

            final cardColor = pastelColors[i % pastelColors.length];
            return GestureDetector(
              onTap: onOpen == null ? null : () => onOpen!(claim),
              child: Container(
                decoration: EmployeeUi.cardDecoration().copyWith(
                  color: cardColor,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.book_outlined,
                            size: 21,
                            color: Colors.indigo,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              benefit['benefit_name'] ?? 'Benefit',
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        claim['description'] ?? '-',
                        style: GoogleFonts.montserrat(fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event_note, size: 17),
                          const SizedBox(width: 3),
                          Text(
                            _claimDateText(claim['claim_date']),
                            style: GoogleFonts.montserrat(fontSize: 13),
                          ),
                          Spacer(),
                          Text(
                            "₹${claim['claimed_amount'] ?? '-'}",
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (claim['approved_amount'] != null)
                            Text(
                              "Approved: ₹${claim['approved_amount']}",
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w500,
                                color: Colors.green,
                              ),
                            ),
                          Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor(
                                claim['status'],
                              ).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              (claim['status'] ?? '').toString().toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: statusColor(claim['status']),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          separatorBuilder: (c, i) => const SizedBox(height: 14),
          itemCount: claims.length,
        ),
      ],
    );
  }
}

// SUBMIT CLAIM PAGE (full screen)
class SubmitClaimPage extends StatefulWidget {
  final List<Map<String, dynamic>> benefits;
  final Map<String, dynamic>? gradeLimitData;
  final double claimedTotal;
  final Future<bool> Function({
    required String benefitId,
    required double claimAmount,
    required String description,
  })
  onSubmit;
  const SubmitClaimPage({
    required this.benefits,
    required this.gradeLimitData,
    required this.claimedTotal,
    required this.onSubmit,
  });
  @override
  State<SubmitClaimPage> createState() => _SubmitClaimPageState();
}

class _SubmitClaimPageState extends State<SubmitClaimPage> {
  String? selectedBenefitId;
  double? claimAmount;
  String? description;
  bool _submitting = false;
  final _formKey = GlobalKey<FormState>();
  String? warning;
  @override
  Widget build(BuildContext context) {
    // The grade's yearly benefit limit, or null when the server gave none: then nothing is invented (no default
    // limit) and the app does not block a claim. The server does not enforce this limit either, so HR decides.
    final limitRaw = widget.gradeLimitData?['benefit_annual_limit'];
    final double? totalLimit = limitRaw is num ? limitRaw.toDouble() : null;
    final alreadyUsed = widget.claimedTotal;
    final double? remaining = totalLimit == null
        ? null
        : totalLimit - alreadyUsed;

    final usagePercent = totalLimit != null && totalLimit > 0
        ? (alreadyUsed / totalLimit).clamp(0.0, 1.0)
        : 0.0;

    Color progressColor;
    if (usagePercent < 0.5) {
      progressColor = Colors.green;
    } else if (usagePercent < 0.8) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.red;
    }

    final claimExceeds = remaining != null && (claimAmount ?? 0) > remaining;

    warning = claimExceeds && claimAmount != null
        ? "Not eligible. Your grade allows maximum ₹${totalLimit!.toStringAsFixed(0)} per year. "
              "You've already claimed ₹${alreadyUsed.toStringAsFixed(2)}."
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text("Submit Claim")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Limits box
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 32,
                ),

                child: Column(
                  children: [
                    Text(
                      "Benefit Claim Limits",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _limitBox(
                            "Total Limit",
                            totalLimit == null
                                ? "Not available"
                                : "₹${totalLimit.toStringAsFixed(0)}",
                            Colors.black,
                          ),
                        ),
                        Expanded(
                          child: _limitBox(
                            "Already Used",
                            "₹${alreadyUsed.toStringAsFixed(0)}",
                            Colors.red,
                          ),
                        ),
                        Expanded(
                          child: _limitBox(
                            "Remaining",
                            remaining == null
                                ? "-"
                                : "₹${remaining.toStringAsFixed(0)}",
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: usagePercent,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation(progressColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (warning != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  warning!,
                  style: GoogleFonts.montserrat(color: Colors.red),
                ),
              ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedBenefitId,
                    decoration: const InputDecoration(
                      labelText: "Select Benefit",
                    ),
                    items: widget.benefits
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'],
                            child: Text(b['benefit_name'] ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selectedBenefitId = v),
                    validator: (v) =>
                        v == null ? "Please select a benefit" : null,
                  ),
                  const SizedBox(height: 16), // 👈 GAP
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Claim Amount (₹)",
                    ),
                    onChanged: (v) =>
                        setState(() => claimAmount = double.tryParse(v)),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val <= 0) {
                        return "Enter a valid amount";
                      }
                      if (remaining != null && val > remaining) {
                        return "Claim exceeds limit";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8), // 👈 GAP
                  TextFormField(
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: "Description"),
                    onChanged: (v) => description = v,
                    // Same rule as the website's claim form (5 to 1000 characters, after trimming).
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return "Description required";
                      if (t.length < 5) return "Enter at least 5 characters";
                      if (t.length > 1000) {
                        return "Description is too long (max 1000 characters)";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Attachments can't be added from the app yet.",
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    onPressed: _submitting
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _submitting = true);
                            final ok = await widget.onSubmit(
                              benefitId: selectedBenefitId!,
                              claimAmount: claimAmount!,
                              description: description ?? '',
                            );
                            if (!mounted) return;
                            if (ok) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() => _submitting = false);
                            }
                          },
                    child: Text(_submitting ? "Submitting..." : "Submit Claim"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }
}
