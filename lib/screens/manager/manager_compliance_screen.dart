import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/compliance_repository.dart';
import '../../widgets/drawer_route.dart';
import '../../widgets/manager_drawer.dart';
import 'widgets/manager_state_views.dart';

/// Shown for the destinations that have no route at all (Pay Equity, Auditor Pack, gratuity payouts).
const String kComplianceUnavailableMessage = "This isn't available yet";

/// The one state shown when the server refuses compliance to the caller (403): the owner's decision is that compliance
/// is for HR managers and above.
const String kComplianceHrOnlyMessage =
    'Compliance is available to HR managers and above';

/// Manager compliance hub. Every tab and quick link reads the real AWS route (see [ComplianceRepository]); all calls are
/// reads. A plain manager is refused by the server (403) on all of them, which turns the whole screen into
/// [kComplianceHrOnlyMessage]; nothing is faked or hidden.
class ManagerComplianceScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final ComplianceRepository? complianceRepository;

  const ManagerComplianceScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.complianceRepository,
  });

  @override
  State<ManagerComplianceScreen> createState() =>
      _ManagerComplianceScreenState();
}

class _ManagerComplianceScreenState extends State<ManagerComplianceScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  late final ComplianceRepository _repo =
      widget.complianceRepository ?? ComplianceRepository();

  String activeQuickLink =
      'none'; // none, posh, maternity, clra, pay_equity, apprentices, auditor

  bool healthLoading = true;
  int? healthScore;
  LoadIssue? healthIssue;

  Future<Map<String, String>>? _namesFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadHealth();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHealth() async {
    setState(() => healthLoading = true);
    try {
      final s = await _repo.healthScore();
      if (!mounted) return;
      setState(() {
        healthScore = s;
        healthIssue = null;
        healthLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        healthIssue = classifyLoadIssue(e);
        healthLoading = false;
      });
    }
  }

  bool get _blocked => healthIssue == LoadIssue.forbidden;

  /// Employee names for the registers, fetched once; a failure means "names unknown" (shown as "Employee").
  Future<Map<String, String>> _names() {
    return _namesFuture ??= _repo.employeeNames().catchError(
      (_) => <String, String>{},
    );
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
        currentRoute: DrawerRoute.compliance,
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
        bottom: activeQuickLink == 'none' && !_blocked
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: const Color(0xFF1E90FF),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFF1E90FF),
                    unselectedLabelColor: Colors.grey,
                    labelStyle: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(text: "Wage Registers"),
                      Tab(text: "Statutory Returns"),
                      Tab(text: "Factories Act"),
                      Tab(text: "Shops & Estb."),
                      Tab(text: "Statutory Bonus"),
                      Tab(text: "Gratuity"),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    // Nothing else is requested until the server has said whether the caller may see compliance at all.
    if (healthLoading) return const Center(child: CircularProgressIndicator());
    if (_blocked) {
      return const ManagerInfoState(
        kComplianceHrOnlyMessage,
        icon: Icons.lock_outline_rounded,
      );
    }
    if (activeQuickLink != 'none') {
      return _buildQuickLinkView();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildHealthScoreWidget(),
          _buildQuickLinks(),
          const SizedBox(height: 20),
          SizedBox(
            height: 600,
            child: TabBarView(
              controller: _tabController,
              children: [
                _WageRegistersTab(repo: _repo, names: _names),
                _StatutoryReturnsTab(repo: _repo),
                _FactoriesActTab(repo: _repo),
                _ShopsTab(repo: _repo),
                _BonusTab(repo: _repo),
                _GratuityTab(repo: _repo, names: _names),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The score is shown only when the server has one: otherwise "-" with no ring, no colour judgement and no verdict.
  Widget _buildHealthScoreWidget() {
    final score = healthScore;
    final known = score != null;
    Color color = Colors.red;
    if (known && score >= 80) {
      color = Colors.green;
    } else if (known && score >= 50) {
      color = Colors.orange;
    }
    final String headline;
    if (healthLoading) {
      headline = 'Loading...';
    } else if (healthIssue != null) {
      headline = 'Not available right now';
    } else if (!known) {
      headline = 'No score recorded yet';
    } else if (score >= 80) {
      headline = 'Your organization is well-guarded';
    } else {
      headline = 'Action required to improve score';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Compliance Health Score",
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  headline,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (known)
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: (score / 100).clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Text(
                  "$score%",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            )
          else
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade100,
              ),
              child: Text(
                "-",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _quickLinkCard("POSH", Icons.gavel, const Color(0xFFFFECE6), 'posh'),
          _quickLinkCard(
            "Maternity",
            Icons.child_care,
            const Color(0xFFD7E8FF),
            'maternity',
          ),
          _quickLinkCard(
            "CLRA",
            Icons.engineering,
            const Color(0xFFDFF6E5),
            'clra',
          ),
          _quickLinkCard(
            "Pay Equity",
            Icons.balance,
            const Color(0xFFEBDFF6),
            'pay_equity',
          ),
          _quickLinkCard(
            "Apprentices",
            Icons.school,
            const Color(0xFFD4F3F7),
            'apprentices',
          ),
          _quickLinkCard(
            "Auditor Pack",
            Icons.archive,
            const Color(0xFFF5F5F5),
            'auditor',
          ),
        ],
      ),
    );
  }

  Widget _quickLinkCard(
    String label,
    IconData icon,
    Color color,
    String action,
  ) {
    return InkWell(
      onTap: () => setState(() => activeQuickLink = action),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: Colors.black54),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickLinkBody() {
    switch (activeQuickLink) {
      case 'posh':
        return _SimpleList(
          load: _repo.poshComplaints,
          emptyText: 'No records found',
          title: (r) => r['case_number']?.toString() ?? 'Complaint',
          subtitle: (r) => _text(r['status']),
        );
      case 'maternity':
        return _SimpleList(
          load: _repo.maternityCases,
          emptyText: 'No records found',
          title: (r) {
            final name = _text(r['employee_name']);
            final type = _text(r['leave_type']);
            return [name, type].where((s) => s.isNotEmpty).join(' - ');
          },
          subtitle: (r) => _dateOrEmpty(r['expected_delivery_date']),
        );
      case 'clra':
        return _SimpleList(
          load: _repo.contractors,
          emptyText: 'No records found',
          title: (r) => _text(r['name']),
          subtitle: (r) => _text(r['license_number']),
        );
      case 'apprentices':
        return _SimpleList(
          load: _repo.apprentices,
          emptyText: 'No records found',
          title: (r) => _text(r['apprentice_name']),
          subtitle: (r) => _text(r['trade']),
        );
      default: // pay_equity, auditor: no route
        return const ManagerInfoState(kComplianceUnavailableMessage);
    }
  }

  Widget _buildQuickLinkView() {
    final title = activeQuickLink.replaceAll('_', ' ').toUpperCase();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => activeQuickLink = 'none'),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      "Back",
                      style: GoogleFonts.montserrat(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(child: _quickLinkBody()),
      ],
    );
  }
}

String _text(dynamic v) => v?.toString() ?? '';

String _dateOrEmpty(dynamic v, [String pattern = 'dd MMM yyyy']) {
  final d = asDate(v);
  return d == null ? '' : DateFormat(pattern).format(d);
}

/// An amount, or "-" when the server did not give one (never a made-up 0).
String _money(dynamic v) {
  final n = asNum(v);
  if (n == null) return '-';
  return '₹${NumberFormat.decimalPattern('en_IN').format(n)}';
}

Widget _statusChip(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    text.toUpperCase(),
    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
  ),
);

/// A plain list of cards: title and subtitle from the row.
class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.load,
    required this.emptyText,
    required this.title,
    required this.subtitle,
  });

  final Future<List<Map<String, dynamic>>> Function() load;
  final String emptyText;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) subtitle;

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: load,
      isEmpty: (r) => r.isEmpty,
      emptyText: emptyText,
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, rows) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final sub = subtitle(rows[i]);
          return Card(
            child: ListTile(
              title: Text(
                title(rows[i]),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: sub.isEmpty ? null : Text(sub),
            ),
          );
        },
      ),
    );
  }
}

class _Named {
  const _Named(this.rows, this.names);
  final List<Map<String, dynamic>> rows;
  final Map<String, String> names;
  String nameOf(Map<String, dynamic> r) =>
      names[r['employee_id']?.toString()] ?? 'Employee';
}

// -----------------------------------------------------------------------------
// 1. WAGE REGISTERS
// -----------------------------------------------------------------------------
class _WageRegistersTab extends StatefulWidget {
  const _WageRegistersTab({required this.repo, required this.names});
  final ComplianceRepository repo;
  final Future<Map<String, String>> Function() names;

  @override
  State<_WageRegistersTab> createState() => _WageRegistersTabState();
}

class _WageRegistersTabState extends State<_WageRegistersTab>
    with SingleTickerProviderStateMixin {
  late final TabController _sub = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  Widget _register(
    String kind,
    String descKey,
    String amountKey,
    String altDesc,
  ) {
    return ManagerLoader<_Named>(
      load: () async {
        final rows = await widget.repo.wageRegister(kind);
        final names = rows.isEmpty ? <String, String>{} : await widget.names();
        return _Named(rows, names);
      },
      isEmpty: (d) => d.rows.isEmpty,
      emptyText: 'No records found',
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, d) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: d.rows.length,
        itemBuilder: (context, i) {
          final item = d.rows[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                d.nameOf(item),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                _text(item[descKey]).isNotEmpty
                    ? _text(item[descKey])
                    : _text(item[altDesc]),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                _money(item[amountKey]),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _sub,
          labelColor: const Color(0xFF1E90FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1E90FF),
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          tabs: const [
            Tab(text: "Fines"),
            Tab(text: "Deductions"),
            Tab(text: "Advances"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _sub,
            children: [
              _register('fines', 'offense_description', 'fine_amount', 'notes'),
              _register(
                'deductions',
                'damage_description',
                'deduction_amount',
                'notes',
              ),
              _register('advances', 'purpose', 'advance_amount', 'notes'),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. STATUTORY RETURNS
// -----------------------------------------------------------------------------
class _StatutoryReturnsTab extends StatelessWidget {
  const _StatutoryReturnsTab({required this.repo});
  final ComplianceRepository repo;

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: repo.returns,
      isEmpty: (r) => r.isEmpty,
      emptyText: 'No filings found',
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, filings) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: filings.length,
        itemBuilder: (context, i) {
          final f = filings[i];
          final status = (f['status'] ?? 'pending').toString().toLowerCase();
          final statusColor = status == 'filed'
              ? Colors.green
              : (status == 'overdue' ? Colors.red : Colors.orange);
          final label = _text(f['period_label']).isNotEmpty
              ? _text(f['period_label'])
              : [
                  if (asInt(f['period_month'], 0) > 0)
                    DateFormat.MMM().format(
                      DateTime(2000, asInt(f['period_month'])),
                    ),
                  _text(f['period_year']),
                ].where((s) => s.isNotEmpty).join(' ');
          final due = _dateOrEmpty(f['due_date']);
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _text(f['return_type']),
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      _statusChip(status, statusColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (label.isNotEmpty)
                    Text(
                      "Period: $label",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (due.isNotEmpty)
                    Text(
                      "Due Date: $due",
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (asNum(f['challan_amount']) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        "Amount: ${_money(f['challan_amount'])}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. FACTORIES ACT
// -----------------------------------------------------------------------------
class _FactoriesActTab extends StatelessWidget {
  const _FactoriesActTab({required this.repo});
  final ComplianceRepository repo;

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: repo.factoryAccidents,
      isEmpty: (r) => r.isEmpty,
      emptyText: 'No accident logs recorded',
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, logs) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: logs.length,
        itemBuilder: (context, i) {
          final log = logs[i];
          final parts = [
            if (_text(log['accident_location']).isNotEmpty)
              "Location: ${_text(log['accident_location'])}",
            if (_text(log['status']).isNotEmpty)
              "Status: ${_text(log['status'])}",
          ];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                _text(log['injury_type']).isEmpty
                    ? 'Accident'
                    : _text(log['injury_type']),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: parts.isEmpty ? null : Text(parts.join(' • ')),
              trailing: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
              ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. SHOPS & ESTABLISHMENTS
// -----------------------------------------------------------------------------
class _ShopsTab extends StatelessWidget {
  const _ShopsTab({required this.repo});
  final ComplianceRepository repo;

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: repo.shopsCerts,
      isEmpty: (r) => r.isEmpty,
      emptyText: 'No certificates found',
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, certs) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: certs.length,
        itemBuilder: (context, i) {
          final c = certs[i];
          final expiry = asDate(c['valid_until']);
          final isExpired = expiry != null && expiry.isBefore(DateTime.now());
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.verified, color: Colors.blue),
              title: Text(
                _text(c['establishment_name']),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                expiry != null
                    ? "Valid until: ${DateFormat('dd MMM yyyy').format(expiry)}"
                    : "Validity not set",
              ),
              trailing: expiry == null
                  ? null
                  : Icon(
                      Icons.circle,
                      size: 12,
                      color: isExpired ? Colors.red : Colors.green,
                    ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 5. STATUTORY BONUS
// -----------------------------------------------------------------------------
class _BonusTab extends StatelessWidget {
  const _BonusTab({required this.repo});
  final ComplianceRepository repo;

  Widget _row(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          val,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ManagerLoader<List<Map<String, dynamic>>>(
      load: repo.bonusRuns,
      isEmpty: (r) => r.isEmpty,
      emptyText: 'No bonus runs found',
      forbiddenMessage: kComplianceHrOnlyMessage,
      builder: (context, runs) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: runs.length,
        itemBuilder: (context, i) {
          final run = runs[i];
          final status = _text(run['status']).isEmpty
              ? 'draft'
              : _text(run['status']);
          final pct = asNum(run['bonus_pct_applied']);
          final eligible = asNum(run['total_eligible_employees']);
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Bonus Year: ${_text(run['accounting_year'])}",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      _statusChip(
                        status,
                        status == 'posted' ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _row(
                    "Eligible Employees",
                    eligible == null ? '-' : eligible.toInt().toString(),
                  ),
                  _row("Total Payout", _money(run['total_payout_amount'])),
                  _row("Applied %", pct == null ? '-' : "$pct%"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. GRATUITY
// -----------------------------------------------------------------------------
class _GratuityTab extends StatefulWidget {
  const _GratuityTab({required this.repo, required this.names});
  final ComplianceRepository repo;
  final Future<Map<String, String>> Function() names;

  @override
  State<_GratuityTab> createState() => _GratuityTabState();
}

class _GratuityTabState extends State<_GratuityTab>
    with SingleTickerProviderStateMixin {
  late final TabController _sub = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _sub,
          labelColor: const Color(0xFF1E90FF),
          tabs: const [
            Tab(text: "Provisions Ledger"),
            Tab(text: "Payouts"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _sub,
            children: [
              ManagerLoader<_Named>(
                load: () async {
                  final rows = await widget.repo.gratuityProvisions();
                  final names = rows.isEmpty
                      ? <String, String>{}
                      : await widget.names();
                  return _Named(rows, names);
                },
                isEmpty: (d) => d.rows.isEmpty,
                emptyText: 'No provisions found',
                forbiddenMessage: kComplianceHrOnlyMessage,
                builder: (context, d) => ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: d.rows.length,
                  itemBuilder: (context, i) {
                    final p = d.rows[i];
                    final years = asNum(p['eligible_service_years']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          d.nameOf(p),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "Eligible Years: ${years == null ? '-' : years.toString()}",
                        ),
                        trailing: Text(
                          _money(p['provision_amount']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const ManagerInfoState(kComplianceUnavailableMessage),
            ],
          ),
        ),
      ],
    );
  }
}
