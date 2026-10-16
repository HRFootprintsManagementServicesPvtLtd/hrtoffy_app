import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../repositories/approvals_repository.dart';
import '../../repositories/benefits_repository.dart';
import '../../repositories/loans_repository.dart';
import '../../repositories/travel_repository.dart';
import 'widgets/benefit_claims_approvals.dart';
import 'widgets/leave_approvals_panel.dart';
import 'widgets/loan_approvals_panel.dart';
import 'widgets/overtime_approvals_panel.dart';
import 'widgets/regularization_approvals_panel.dart';
import 'widgets/travel_approvals_panel.dart';

/// Shown for a category that has no manager approval route (General Requests) and, until the lead plugs the panels in,
/// for Loans, Travel and Benefits.
const String kApprovalsUnavailableMessage = "This isn't available yet";

/// What a pending count shows while it is unknown (never 0, which would read as "all clear").
const String kApprovalsCountUnknown = '-';

/// Dashboard count keys the server fills for a manager (`GET /dashboard/approval-counts`).
const String kApprovalsLeavesCountKey = 'approvals-requests-leaves';
const String kApprovalsRegularizationCountKey = 'approvals-regularization';

/// Keys the server adds for a manager's team loans, benefits and travel claims (only when above zero; an older server
/// omits them entirely, so a missing key stays "-", never a made-up 0).
const String kApprovalsLoansCountKey = 'approvals-loans';
const String kApprovalsBenefitsCountKey = 'approvals-benefits';
const String kApprovalsTravelCountKey = 'approvals-travel';

/// Manager approvals hub: category tiles with the server's pending counts where it gives them, and one panel per
/// category. Every decision goes through the approval engine's routes; nothing is written to a status column.
class PendingApprovalsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final ApprovalsRepository? repository;
  final LoansRepository? loansRepository;
  final TravelRepository? travelRepository;
  final BenefitsRepository? benefitsRepository;

  const PendingApprovalsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    this.repository,
    this.loansRepository,
    this.travelRepository,
    this.benefitsRepository,
  });

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  String? activeTab; // null means Inbox
  late final ApprovalsRepository _repo =
      widget.repository ?? ApprovalsRepository();
  Map<String, int>?
  _counts; // null until the server answered (and when it could not)

  /// Rows the caller may decide now, per tab (leaves, loans, travel, benefits); a missing key is unknown or failed.
  final Map<String, int> _actionable = {};
  int _countsGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final gen = ++_countsGeneration;
    Future<void> one(String tab, Future<int> Function() count) async {
      try {
        final n = await count();
        if (mounted && gen == _countsGeneration) {
          setState(() => _actionable[tab] = n);
        }
      } catch (_) {
        if (mounted && gen == _countsGeneration) {
          setState(() => _actionable.remove(tab));
        }
      }
    }

    await Future.wait([
      () async {
        try {
          final c = await _repo.counts();
          if (mounted && gen == _countsGeneration) {
            setState(() => _counts = c);
          }
        } catch (_) {
          if (mounted && gen == _countsGeneration) {
            setState(() => _counts = null);
          }
        }
      }(),
      one(
        'leaves',
        () => LeaveApprovalsPanel.countActionable(approvalsRepository: _repo),
      ),
      one(
        'loans',
        () => LoanApprovalsPanel.countActionable(
          loansRepository: widget.loansRepository,
          approvalsRepository: _repo,
        ),
      ),
      one(
        'travel',
        () => TravelApprovalsPanel.countActionable(
          travelRepository: widget.travelRepository,
          approvalsRepository: _repo,
        ),
      ),
      one(
        'benefits',
        () => BenefitClaimsApprovals.countActionable(
          benefitsRepository: widget.benefitsRepository,
          approvalsRepository: _repo,
        ),
      ),
    ]);
  }

  void _open(String? tab) {
    setState(() => activeTab = tab);
    if (tab == null) _loadCounts(); // a decision may have changed the queues
  }

  /// The badge text of a tile: for leaves, loans, travel and benefits the number of rows the caller may decide now (the
  /// panel's own count; "-" when it could not be read), for regularization the server's count (a missing key is a real 0
  /// once the server has answered), "-" for everything else. Never a made-up 0.
  String _badge(String tab) {
    switch (tab) {
      case 'leaves':
      case 'loans':
      case 'travel':
      case 'benefits':
        final n = _actionable[tab];
        return n == null ? kApprovalsCountUnknown : '$n';
      case 'regularization':
        final c = _counts;
        if (c == null) return kApprovalsCountUnknown;
        return '${c[kApprovalsRegularizationCountKey] ?? 0}';
      default:
        return kApprovalsCountUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          activeTab == null ? "Approvals" : _getTabTitle(activeTab!),
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: activeTab != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _open(null),
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: activeTab == null
          ? RefreshIndicator(onRefresh: _loadCounts, child: _buildInbox())
          : _detail(activeTab!),
    );
  }

  /// The panel behind a tile.
  Widget _detail(String tab) {
    switch (tab) {
      case 'leaves':
        return LeaveApprovalsPanel(approvalsRepository: _repo);
      case 'regularization':
        return RegularizationApprovalsPanel(
          repository: _repo,
          onBack: () => _open(null),
        );
      case 'overtime':
        return OvertimeApprovalsPanel(
          repository: _repo,
          onBack: () => _open(null),
        );
      case 'loans':
        return LoanApprovalsPanel(
          loansRepository: widget.loansRepository,
          approvalsRepository: _repo,
        );
      case 'travel':
        return TravelApprovalsPanel(
          travelRepository: widget.travelRepository,
          approvalsRepository: _repo,
        );
      case 'benefits':
        return BenefitClaimsApprovals(
          benefitsRepository: widget.benefitsRepository,
          approvalsRepository: _repo,
        );
      default:
        return _buildUnavailable(); // general requests: no approval route exists
    }
  }

  Widget _buildInbox() {
    final first = widget.userData['full_name']
        ?.toString()
        .trim()
        .split(' ')
        .first
        .toUpperCase();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE3F2FD).withValues(alpha: 0.5),
                  Colors.white,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "HELLO, ${(first == null || first.isEmpty) ? 'USER' : first}",
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.montserrat(
                      fontSize: 28,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      const TextSpan(text: "Decisions "),
                      TextSpan(
                        text: "waiting on you",
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Tap a category to review what's waiting for you.",
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          Text(
            "CATEGORIES",
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Tiles Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildTile(
                "Leave Requests",
                "leaves",
                const Color(0xFFE8F5E9),
                Icons.calendar_month,
              ),
              _buildTile(
                "Regularization",
                "regularization",
                const Color(0xFFF1F8E9),
                Icons.access_time,
              ),
              _buildTile(
                "Overtime",
                "overtime",
                const Color(0xFFFFF8E1),
                Icons.more_time,
              ),
              _buildTile(
                "Loan Requests",
                "loans",
                const Color(0xFFE0F7FA),
                Icons.account_balance_wallet,
              ),
              _buildTile(
                "Travel Claims",
                "travel",
                const Color(0xFFE3F2FD),
                Icons.flight_takeoff,
              ),
              _buildTile(
                "General Requests",
                "general",
                const Color(0xFFFAFAFA),
                Icons.chat_bubble_outline,
              ),
            ],
          ),

          const SizedBox(height: 30),
          Text(
            "MORE",
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _buildTile(
            "Benefits Claims",
            "benefits",
            const Color(0xFFF5F5F5),
            Icons.card_giftcard,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  String _getSubtitle(String tab) {
    switch (tab) {
      case 'leaves':
        return "Time-off applications from your team awaiting approval.";
      case 'regularization':
        return "Missed punches and attendance corrections to review.";
      case 'overtime':
        return "Overtime hours your team has claimed.";
      case 'loans':
        return "Salary advances and employee loan applications.";
      case 'travel':
        return "Travel expense claims with bills and approvals.";
      case 'general':
        return "Miscellaneous requests routed to you.";
      case 'benefits':
        return "Reimbursement claims under benefit policies.";
      default:
        return "";
    }
  }

  String _getTabTitle(String tab) {
    switch (tab) {
      case 'leaves':
        return "Leave Requests";
      case 'regularization':
        return "Regularization";
      case 'overtime':
        return "Overtime";
      case 'loans':
        return "Loan Requests";
      case 'travel':
        return "Travel Claims";
      case 'general':
        return "General Requests";
      case 'benefits':
        return "Benefits Claims";
      default:
        return "Approvals";
    }
  }

  Widget _buildTile(
    String title,
    String tab,
    Color color,
    IconData icon, {
    bool isFullWidth = false,
  }) {
    return GestureDetector(
      onTap: () => _open(tab),
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: Colors.black54),
                Container(
                  key: ValueKey('badge-$tab'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _badge(tab) == kApprovalsCountUnknown
                        ? Colors.grey.shade500
                        : Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _badge(tab),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getSubtitle(tab),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// General Requests: no approval route exists. A message only: no list, no actions, no request.
  Widget _buildUnavailable() {
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
              kApprovalsUnavailableMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _open(null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    "Back to inbox",
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
