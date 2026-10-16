import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/approvals_repository.dart';
import '../../repositories/benefits_repository.dart';
import '../../repositories/employee_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import 'widgets/benefit_approvals_panel.dart';
import 'widgets/benefit_claims_approvals.dart';
import 'widgets/benefit_general_approvals_panel.dart';

/// Shown for every action that has no verified AWS route yet (claim submission, ESI claims and eligibility).
/// Nothing is requested for them and nothing is written.
const String kBenefitsUnavailableMessage = "This isn't available yet";

/// Fixed text for any failed load: the server's or the exception's text is never shown.
const String kBenefitsLoadFailedMessage =
    "Couldn't load this right now. Please try again.";

/// Manager benefits hub.
///
/// Live: the signed-in user's own claims, the benefits catalog, the grade limit with the year-to-date total,
/// their own insurance policies, and the team's ESI claim approvals ([BenefitApprovalsPanel]; the ESI Approvals badge is the
/// real count, "-" while unknown; the general Approvals badge is the other claims the caller may decide, "-" while unknown).
/// Unavailable: Submit Claim, LTA Claim, ESI Claims and eligibility.
class ManagerBenefitsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final BenefitsRepository? benefitsRepository;
  final EmployeeRepository? employeeRepository;
  final ProfileRepository? profileRepository;
  final ApprovalsRepository? approvalsRepository;

  const ManagerBenefitsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.benefitsRepository,
    this.employeeRepository,
    this.profileRepository,
    this.approvalsRepository,
  });

  @override
  State<ManagerBenefitsScreen> createState() => _ManagerBenefitsScreenState();
}

class _ManagerBenefitsScreenState extends State<ManagerBenefitsScreen> {
  late final BenefitsRepository _benefits =
      widget.benefitsRepository ?? BenefitsRepository();
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();
  late final ProfileRepository _profile =
      widget.profileRepository ?? ProfileRepository();
  late final ApprovalsRepository _approvals =
      widget.approvalsRepository ?? ApprovalsRepository();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String activeAction =
      'none'; // none, my_benefits, submit, lta, esi, esi_guide, approvals, esi_approvals, insurance
  bool loading = true;

  // Each part is null until loaded; a *Failed flag means it could not be loaded (never shown as empty or 0).
  List<Map<String, dynamic>>? myClaims;
  bool claimsFailed = false;
  List<Map<String, dynamic>>? catalog;
  bool catalogFailed = false;
  Map<String, dynamic>? gradeLimitData;
  bool gradeLimitFailed = false;
  List<Map<String, dynamic>>? myInsurance;
  bool insuranceFailed = false;

  /// Approved/claimed total for this year, from [BenefitsRepository.claimedTotalForYear]; null while claims are unknown.
  double? claimedTotalYTD;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (mounted) setState(() => loading = true);

    String? grade;
    try {
      final me = await _employees.getMe();
      grade = me['grade_code']?.toString();
    } catch (_) {
      grade = null; // the grade limit then stays "not available"
    }

    await Future.wait([
      _fetchMyClaims(),
      _fetchCatalog(),
      _fetchGradeLimit(grade),
      _fetchMyInsurance(),
      _fetchEsiPending(),
      _fetchApprovalCount(),
    ]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchMyClaims() async {
    try {
      final claims = await _benefits.claims();
      myClaims = claims;
      claimsFailed = false;
      claimedTotalYTD = BenefitsRepository.claimedTotalForYear(
        claims,
        DateTime.now().year,
      );
    } catch (_) {
      myClaims = null;
      claimsFailed = true;
      claimedTotalYTD = null;
    }
  }

  Future<void> _fetchCatalog() async {
    try {
      catalog = await _benefits.catalog();
      catalogFailed = false;
    } catch (_) {
      catalog = null;
      catalogFailed = true;
    }
  }

  Future<void> _fetchGradeLimit(String? gradeCode) async {
    gradeLimitData = null;
    gradeLimitFailed = false;
    if (gradeCode == null || gradeCode.isEmpty) return;
    try {
      gradeLimitData = await _benefits.gradeLimit(gradeCode);
    } catch (_) {
      gradeLimitFailed = true;
    }
  }

  /// ESI claims waiting for this manager (`GET /benefits/esi/claims`); null while unknown or when the list could not be loaded.
  int? esiPending;

  Future<void> _fetchEsiPending() async {
    try {
      esiPending = (await _benefits.esiApprovalClaims()).length;
    } catch (_) {
      esiPending = null;
    }
  }

  /// Other (non-ESI) claims the caller may decide now; null while unknown or when it could not be determined.
  int? approvalsPending;

  Future<void> _fetchApprovalCount() async {
    try {
      approvalsPending = await BenefitGeneralApprovalsPanel.countActionable(
        benefitsRepository: _benefits,
        approvalsRepository: _approvals,
      );
    } catch (_) {
      approvalsPending = null;
    }
  }

  Future<void> _backToOverview() async {
    setState(() => activeAction = 'none');
    await Future.wait([_fetchEsiPending(), _fetchApprovalCount()]); // a decision may have changed them
    if (mounted) setState(() {});
  }

  Future<void> _fetchMyInsurance() async {
    try {
      myInsurance = await _profile.insurancePolicies();
      insuranceFailed = false;
    } catch (_) {
      myInsurance = null;
      insuranceFailed = true;
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
        currentRoute: DrawerRoute.benefits,
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
        gradient: LinearGradient(
          colors: [Colors.indigo.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.2),
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
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Manage your benefits, submit claims, and approve team requests all in one place.",
            style: GoogleFonts.montserrat(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.9,
      children: [
        _actionCard(
          "My Benefits",
          "View benefits available to you.",
          Icons.card_giftcard,
          Colors.purple,
          'my_benefits',
        ),
        _actionCard(
          "Submit Claim",
          "Raise a reimbursement claim.",
          Icons.add_circle_outline,
          Colors.green,
          'submit',
        ),
        _actionCard(
          "LTA Claim",
          "Leave Travel Allowance claim.",
          Icons.flight_takeoff,
          Colors.blue,
          'lta',
        ),
        _actionCard(
          "ESI Claims",
          "Statutory medical benefit claims.",
          Icons.verified_user_outlined,
          Colors.lightBlue,
          'esi',
        ),
        _actionCard(
          "ESI Guide",
          "Explainer for ESI eligibility.",
          Icons.menu_book,
          Colors.grey,
          'esi_guide',
        ),
        _actionCard(
          "Approvals",
          "Pending team benefit claims.",
          Icons.fact_check_outlined,
          Colors.deepOrange,
          'approvals',
          badge: approvalsPending,
          unknownBadge: approvalsPending == null,
        ),
        _actionCard(
          "ESI Approvals",
          "Pending team ESI claims.",
          Icons.assignment_turned_in_outlined,
          Colors.deepOrange,
          'esi_approvals',
          badge: esiPending,
          unknownBadge: esiPending == null,
        ),
        _actionCard(
          "My Insurance",
          "Group policies linked to you.",
          Icons.favorite_border,
          Colors.redAccent,
          'insurance',
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
      onTap: () => setState(() => activeAction = action),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
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
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
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
                        color: Colors.grey.shade400,
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
                  color: Colors.grey.shade600,
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
              kBenefitsUnavailableMessage,
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
      case 'approvals':
        title = "Benefit Approvals";
        child = BenefitClaimsApprovals(
          benefitsRepository: _benefits,
          approvalsRepository: _approvals,
          initialTab: 1,
        );
        break;
      case 'esi_approvals':
        title = "ESI Approvals";
        child = BenefitClaimsApprovals(
          benefitsRepository: _benefits,
          approvalsRepository: _approvals,
        );
        break;
      case 'esi_guide':
        title = "ESI Guide";
        child = _buildESIGuide();
        break;
      case 'my_benefits':
        title = "My Benefits";
        child = MyBenefitsPanel(
          claims: myClaims,
          claimsFailed: claimsFailed,
          catalog: catalog,
          catalogFailed: catalogFailed,
          gradeLimit: gradeLimitData,
          gradeLimitFailed: gradeLimitFailed,
          claimedTotalYTD: claimedTotalYTD,
          onRetry: _initData,
        );
        break;
      case 'submit':
        title = "Submit Claim";
        child = _unavailableState();
        break;
      case 'lta':
        title = "LTA Claim";
        child = _unavailableState();
        break;
      case 'esi':
        title = "ESI Claims";
        child = _unavailableState();
        break;
      case 'insurance':
        title = "My Insurance";
        child = MyInsurancePanel(
          policies: myInsurance,
          failed: insuranceFailed,
          onRetry: _initData,
        );
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

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  /// Static explainer. The "are you eligible" banner is gone: ESI eligibility has no verified AWS source yet.
  Widget _buildESIGuide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Types of ESI Benefits"),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _esiTypeCard("Sickness", "70% of wages"),
              _esiTypeCard("Ext. Sickness", "Up to 2 years"),
              _esiTypeCard("Enh. Sickness", "Full wages"),
              _esiTypeCard("Maternity", "100% of wages"),
              _esiTypeCard("Disablement", "90% of wages"),
              _esiTypeCard("Medical", "Full medical care"),
              _esiTypeCard("Dependents", "90% for family"),
            ],
          ),
          const SizedBox(height: 32),
          _sectionTitle("How to Claim ESI Benefits"),
          const SizedBox(height: 20),
          _stepItem(
            "1",
            "Visit ESI Dispensary",
            "Get examined by a medical officer at your registered dispensary.",
          ),
          _stepItem(
            "2",
            "Get Medical Certificate",
            "Obtain Form 7/8/9 from the officer after diagnosis.",
          ),
          _stepItem(
            "3",
            "Submit Your Claim",
            "Submitting ESI claims from the app isn't available yet. Please contact HR.",
          ),
          _stepItem(
            "4",
            "Approval Review",
            "Manager and HR will review your statutory claim.",
          ),
          _stepItem(
            "5",
            "ESIC Disbursement",
            "Once approved, benefits are settled directly by ESIC.",
          ),
          const SizedBox(height: 24),
          _sectionTitle("Frequently Asked Questions"),
          const SizedBox(height: 12),
          _faqItem(
            "Who is eligible for ESI?",
            "Employees earning gross salary up to ₹21,000 per month.",
          ),
          _faqItem(
            "Will I get salary during ESI period?",
            "No, salary is usually skipped as ESIC pays the benefit directly.",
          ),
          _faqItem(
            "What documents are needed?",
            "ESI IP Card and a Medical Certificate from a Dispensary.",
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _esiTypeCard(String title, String benefit) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            benefit,
            style: GoogleFonts.montserrat(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepItem(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue,
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
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
                  title,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "₹1,250" for a number; "-" when the amount is unknown (never a made-up 0).
String _money(num? v) =>
    v == null ? '-' : '₹${NumberFormat.decimalPattern('en_IN').format(v)}';

class _LoadFailed extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kBenefitsLoadFailedMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(fontSize: 13, color: Colors.red[700]),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// 🟣 My Benefits Panel: the user's own limit and year-to-date total, the catalog, and their own claims.
class MyBenefitsPanel extends StatefulWidget {
  final List<Map<String, dynamic>>? claims;
  final bool claimsFailed;
  final List<Map<String, dynamic>>? catalog;
  final bool catalogFailed;
  final Map<String, dynamic>? gradeLimit;
  final bool gradeLimitFailed;
  final double? claimedTotalYTD;
  final VoidCallback onRetry;

  const MyBenefitsPanel({
    super.key,
    required this.claims,
    required this.claimsFailed,
    required this.catalog,
    required this.catalogFailed,
    required this.gradeLimit,
    required this.gradeLimitFailed,
    required this.claimedTotalYTD,
    required this.onRetry,
  });

  @override
  State<MyBenefitsPanel> createState() => _MyBenefitsPanelState();
}

class _MyBenefitsPanelState extends State<MyBenefitsPanel> {
  String searchQuery = "";

  Widget _summaryCard() {
    final limit = widget.gradeLimitFailed
        ? null
        : asNum(widget.gradeLimit?['benefit_annual_limit']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _stat("Annual limit", _money(limit))),
          Expanded(
            child: _stat("Claimed this year", _money(widget.claimedTotalYTD)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 11,
          color: Colors.grey.shade600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _catalogSection() {
    if (widget.catalogFailed) {
      return Text(
        "Available benefits: $kBenefitsLoadFailedMessage",
        style: GoogleFonts.montserrat(fontSize: 12, color: Colors.red[700]),
      );
    }
    final catalog = widget.catalog ?? const [];
    if (catalog.isEmpty) {
      return Text(
        "No benefits are available to you yet.",
        style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in catalog)
          Chip(
            label: Text(
              b['benefit_name']?.toString() ?? 'Benefit',
              style: GoogleFonts.montserrat(fontSize: 11),
            ),
            backgroundColor: Colors.purple.shade50,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.claimsFailed) return _LoadFailed(onRetry: widget.onRetry);
    final all = widget.claims ?? const <Map<String, dynamic>>[];
    final filtered = all.where((c) {
      final name =
          c['benefits_catalog']?['benefit_name']?.toString().toLowerCase() ??
          "";
      return name.contains(searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryCard(),
              const SizedBox(height: 16),
              Text(
                "Available benefits",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              _catalogSection(),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => searchQuery = v),
                decoration: InputDecoration(
                  hintText: "Search your benefit claims...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    "No benefit claims yet",
                    style: GoogleFonts.montserrat(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final claim = filtered[index];
                    final status = (claim['status'] ?? 'pending')
                        .toString()
                        .toLowerCase();
                    Color statusColor = Colors.orange;
                    if (status == 'approved') statusColor = Colors.green;
                    if (status == 'rejected') statusColor = Colors.red;
                    final date = asDate(
                      claim['created_at'] ?? claim['claim_date'],
                    );

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                claim['benefits_catalog']?['benefit_name']
                                        ?.toString() ??
                                    'Benefit',
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            claim['description']?.toString() ?? '-',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                date == null
                                    ? '-'
                                    : DateFormat(
                                        'dd MMM yyyy',
                                      ).format(date.toLocal()),
                                style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                _money(asNum(claim['claimed_amount'])),
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// 🔴 My Insurance Panel: the signed-in user's own policies (ProfileRepository.insurancePolicies).
// Only the fields the profile screen already reads are shown.
class MyInsurancePanel extends StatelessWidget {
  final List<Map<String, dynamic>>? policies;
  final bool failed;
  final VoidCallback onRetry;
  const MyInsurancePanel({
    super.key,
    required this.policies,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (failed) return _LoadFailed(onRetry: onRetry);
    final list = policies ?? const <Map<String, dynamic>>[];
    if (list.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            "No Active Policies",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your insurance policies will appear here once assigned by HR.",
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(color: Colors.grey, fontSize: 12),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final p = list[index];
        return Container(
          padding: const EdgeInsets.all(20),
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
                    p['insurance_type']?.toString() ?? 'Insurance',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const Icon(Icons.security, color: Colors.blue, size: 20),
                ],
              ),
              const SizedBox(height: 16),
              _row("Provider", p['provider_name']?.toString()),
              _row("Policy #", p['policy_number']?.toString()),
              _row("Sum Insured", _money(asNum(p['sum_insured']))),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String? val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            val ?? '-',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
