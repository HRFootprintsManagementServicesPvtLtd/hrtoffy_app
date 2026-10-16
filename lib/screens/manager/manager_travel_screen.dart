import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/loans_repository.dart';
import '../../repositories/travel_repository.dart';
import '../loans_advances_screens.dart'
    show LoanApplicationSheet, kLoanRequestFailedMessage;
import '../travel_expenses_screen.dart' show TravelClaimForm;
import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

/// Shown for what has no verified AWS route yet (the Settlements tab and settling an advance). Nothing is requested for it.
const String kTravelUnavailableMessage = "This isn't available yet";

/// Fixed text for a failed load: the server's or the exception's text is never shown.
const String kTravelLoadFailedMessage =
    "Couldn't load your travel claims right now. Please try again.";

/// Fixed text for a failed advances load.
const String kTravelAdvancesLoadFailedMessage =
    "Couldn't load your travel advances right now. Please try again.";

/// Unknown figures (advances, outstanding, or anything while the claims are not loaded) show this, never 0.
const String kTravelUnknown = '-';

/// Manager travel hub.
///
/// Live: the signed-in user's OWN travel claims ([TravelRepository.claims]) and travel advances ([TravelRepository.advances],
/// loans in the travel_advance category), New Claim ([TravelClaimForm]) and Request Advance (POST /loans/request).
/// Both reads always send the caller's own employee id. Unavailable: the Settlements tab. Approvals of the team's claims are
/// [TravelApprovalsPanel] (embedded by the Pending Approvals hub).
class ManagerTravelScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final TravelRepository? travelRepository;

  const ManagerTravelScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.travelRepository,
  });

  @override
  State<ManagerTravelScreen> createState() => _ManagerTravelScreenState();
}

class _ManagerTravelScreenState extends State<ManagerTravelScreen>
    with SingleTickerProviderStateMixin {
  late final TravelRepository _travel =
      widget.travelRepository ?? TravelRepository();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  String activeAction = 'none'; // none, new_claim, request_advance
  bool loading = true;

  /// Null until loaded or when the load failed ([failed]); a failed load is never shown as an empty list.
  List<Map<String, dynamic>>? claims;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The caller's own travel advances (loans in the `travel_advance` category); null while unknown or failed.
  List<Map<String, dynamic>>? advances;
  bool advancesFailed = false;

  Future<void> _initData() async {
    if (mounted) setState(() => loading = true);
    await Future.wait([_fetchClaims(), _fetchAdvances()]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchClaims() async {
    try {
      // Scoped to the signed-in employee by the repository; it throws (no request) without an employee id.
      claims = await _travel.claims();
      failed = false;
    } catch (_) {
      claims = null;
      failed = true;
    }
  }

  Future<void> _fetchAdvances() async {
    try {
      advances = await _travel.advances();
      advancesFailed = false;
    } catch (_) {
      advances = null;
      advancesFailed = true;
    }
  }

  void _backToOverview() => setState(() => activeAction = 'none');

  bool _requesting = false;

  /// Travel advance request: `POST /loans/request` with the `travel_advance` category (a fixed message on failure).
  Future<void> _openAdvanceRequest() async {
    if (_requesting) return;
    _requesting = true;
    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => LoanApplicationSheet(onSubmit: _submitAdvance),
      );
      if (submitted == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Advance request submitted. It is pending review.'),
          ),
        );
        await _initData();
      }
    } finally {
      _requesting = false;
    }
  }

  Future<bool> _submitAdvance({
    required double amount,
    required String reason,
    int? repaymentMonths,
  }) async {
    try {
      await _travel.requestAdvance(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      endDrawer: ManagerDrawer(
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.travel,
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
            const SizedBox(height: 24),
            _buildKPISection(),
            const SizedBox(height: 32),
            _buildActionButtons(),
            const SizedBox(height: 32),
            _buildTabs(),
            const SizedBox(height: 16),
            _buildFeedList(),
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
            "Unified Travel Hub",
            style: GoogleFonts.playfairDisplay(
              color: const Color(0xFF444444),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Manage claims, cash advances, and settlements for your trips.",
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

  /// The requested amounts of the advances that are disbursed or active. "-" while unknown or when any such advance has no
  /// usable amount (the total would be a guess); "None" when there is no such advance (never "₹0").
  String _outstanding() {
    final list = advances;
    if (list == null) return kTravelUnknown;
    var total = 0.0;
    var any = false;
    for (final a in list) {
      final s = _status(a);
      if (s != 'disbursed' && s != 'active') continue;
      final amount = asNum(a['requested_amount']);
      if (!LoansRepository.isUsableAmount(amount)) return kTravelUnknown;
      total += amount!.toDouble();
      any = true;
    }
    return any ? _money(total) : 'None';
  }

  Widget _buildKPISection() {
    final list = claims;
    final total = list == null ? kTravelUnknown : list.length.toString();
    final pending = list == null
        ? kTravelUnknown
        : list.where((c) => _status(c) == 'pending').length.toString();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _kpiCard(
          "Total Claims",
          total,
          const Color(0xFFD7E8FF),
          Icons.receipt_long,
        ),
        _kpiCard(
          "Total Advances",
          advances == null ? kTravelUnknown : advances!.length.toString(),
          const Color(0xFFD4F3F7),
          Icons.account_balance_wallet,
        ),
        _kpiCard(
          "Outstanding",
          _outstanding(),
          const Color(0xFFFFECE6),
          Icons.trending_up,
        ),
        _kpiCard(
          "Pending",
          pending,
          const Color(0xFFEBDFF6),
          Icons.pending_actions,
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              Icon(icon, size: 14, color: Colors.black26),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _actionBtn(
            "New Claim",
            Icons.add_circle_outline,
            Colors.blue,
            () => setState(() => activeAction = 'new_claim'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionBtn(
            "Request Advance",
            Icons.payments_outlined,
            Colors.teal,
            _openAdvanceRequest,
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 45,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: EdgeInsets.zero,
        labelColor: Colors.blue.shade700,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        tabs: const [
          Tab(text: "All"),
          Tab(text: "Claims"),
          Tab(text: "Advances"),
          Tab(text: "Settlements"),
        ],
      ),
    );
  }

  String _status(Map<String, dynamic> c) =>
      (c['status'] ?? 'pending').toString().toLowerCase();

  /// "₹5,400.50" for a number; "-" when the amount is missing or not numeric (never a made-up 0).
  String _money(dynamic v) {
    final n = asNum(v);
    return n == null
        ? kTravelUnknown
        : NumberFormat.currency(
            locale: 'en_IN',
            symbol: '₹',
            decimalDigits: 2,
          ).format(n);
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
              kTravelUnavailableMessage,
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

  Widget _failedMessage(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _initData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedList() {
    final tab = _tabController.index;
    // Settlements have no verified source: they are unavailable, not empty.
    if (tab == 3) return _unavailableState();

    final showClaims = tab == 0 || tab == 1;
    final showAdvances = tab == 0 || tab == 2;
    final claimsOk = !showClaims || claims != null;
    final advancesOk = !showAdvances || advances != null;
    if (!claimsOk && !advancesOk) {
      return _failedMessage(kTravelLoadFailedMessage);
    }
    if (tab == 1 && failed) return _failedMessage(kTravelLoadFailedMessage);
    if (tab == 2 && advancesFailed) {
      return _failedMessage(kTravelAdvancesLoadFailedMessage);
    }

    final items = <Map<String, dynamic>>[
      if (showClaims && claims != null)
        for (final c in claims!) {...c, '_kind': 'claim'},
      if (showAdvances && advances != null)
        for (final a in advances!) {...a, '_kind': 'advance'},
    ];
    items.sort(
      (a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(
        asDate(a['created_at']) ?? DateTime(0),
      ),
    );

    // On the All tab one part may be missing: say so instead of pretending the list is complete.
    final partial = tab == 0 && (failed || advancesFailed);
    final note = partial
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              failed
                  ? "Your claims couldn't be loaded, so only advances are shown."
                  : "Your advances couldn't be loaded, so only claims are shown.",
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.red.shade700,
              ),
            ),
          )
        : const SizedBox.shrink();

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            "No travel records found",
            style: GoogleFonts.montserrat(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        note,
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => items[index]['_kind'] == 'advance'
              ? _advanceCard(items[index])
              : _claimCard(items[index]),
        ),
      ],
    );
  }

  /// A travel advance (a loan in the `travel_advance` category). An unusable amount shows "-", never ₹0.
  Widget _advanceCard(Map<String, dynamic> item) {
    final status = _status(item);
    final date = asDate(item['created_at']);
    final requested = asNum(item['requested_amount']);
    final tenure = asNum(item['tenure_months'])?.toInt();
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
            children: [_typeChip('Advance'), _statusPill(status)],
          ),
          const SizedBox(height: 12),
          Text(
            item['loan_number']?.toString() ?? '-',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item['purpose']?.toString() ?? 'Travel advance',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (tenure != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Repayment: $tenure months",
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date == null
                    ? '-'
                    : DateFormat('dd MMM yyyy').format(date.toLocal()),
                style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
              ),
              Text(
                LoansRepository.isUsableAmount(requested)
                    ? _money(requested)
                    : kTravelUnknown,
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _claimCard(Map<String, dynamic> item) {
    final status = _status(item);
    final date = asDate(item['created_at']);
    final from = item['trip_from_date']?.toString();
    final to = item['trip_to_date']?.toString();
    final destination = item['trip_destination']?.toString();

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
            children: [_typeChip('Claim'), _statusPill(status)],
          ),
          const SizedBox(height: 12),
          Text(
            item['claim_number']?.toString() ?? '-',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item['trip_purpose']?.toString() ?? 'Travel',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (destination != null && destination.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 12,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    destination,
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          if (from != null && to != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "$from to $to",
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date == null
                    ? '-'
                    : DateFormat('dd MMM yyyy').format(date.toLocal()),
                style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
              ),
              Text(
                _money(item['total_amount']),
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String type) {
    const color = Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    Color color = Colors.orange;
    if (status == 'approved' ||
        status == 'paid' ||
        status == 'settled' ||
        status == 'disbursed')
      color = Colors.green;
    if (status == 'rejected') color = Colors.red;
    if (status == 'manager_approved' || status == 'active') color = Colors.blue;

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

  Widget _buildDetailView() {
    final isClaim = activeAction == 'new_claim';
    final title = isClaim
        ? "New Travel Claim"
        : activeAction.replaceAll('_', ' ').toUpperCase();
    return Column(
      children: [
        _buildDetailHeader(title),
        Expanded(
          child: isClaim
              ? TravelClaimForm(
                  email: widget.userEmail,
                  userData: widget.userData,
                  repository: _travel,
                  onCancel: _backToOverview,
                  onSuccess: () {
                    _backToOverview();
                    _initData();
                  },
                )
              : _unavailableState(),
        ),
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
