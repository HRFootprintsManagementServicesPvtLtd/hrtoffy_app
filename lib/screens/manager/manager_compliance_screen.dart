import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

class ManagerComplianceScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerComplianceScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerComplianceScreen> createState() => _ManagerComplianceScreenState();
}

class _ManagerComplianceScreenState extends State<ManagerComplianceScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  bool loading = true;
  Map<String, dynamic>? healthSnapshot;
  String activeQuickLink = 'none'; // none, posh, maternity, clra, pay_equity, apprentices, auditor

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _fetchComplianceData();
  }

  Future<void> _fetchComplianceData() async {
    try {
      final orgId = widget.userData['organization_id'];
      
      dynamic snapshot;
      // Try org_id first
      try {
        snapshot = await supabase
            .from('compliance_health_snapshots')
            .select()
            .eq('org_id', orgId)
            .order('snapshot_date', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (e1) {
        // Try organization_id
        try {
          snapshot = await supabase
              .from('compliance_health_snapshots')
              .select()
              .eq('organization_id', orgId)
              .order('snapshot_date', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (e2) {
          debugPrint("Compliance snapshot both failed: $e1 / $e2");
        }
      }

      if (mounted) {
        setState(() {
          healthSnapshot = snapshot;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Compliance health snapshot critical error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        bottom: activeQuickLink == 'none' ? PreferredSize(
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
              labelStyle: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold),
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
        ) : null,
      ),
      body: loading 
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (activeQuickLink != 'none') {
      return _buildQuickLinkView();
    }

    return RefreshIndicator(
      onRefresh: _fetchComplianceData,
      child: SingleChildScrollView(
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
                  _WageRegistersTab(userData: widget.userData),
                  _StatutoryReturnsTab(userData: widget.userData),
                  _FactoriesActTab(userData: widget.userData),
                  _ShopsEstablishmentTab(userData: widget.userData),
                  _StatutoryBonusTab(userData: widget.userData),
                  _GratuityTab(userData: widget.userData),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthScoreWidget() {
    final score = healthSnapshot?['overall_score'] ?? 0;
    Color color = Colors.red;
    if (score >= 80) color = Colors.green;
    else if (score >= 50) color = Colors.orange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Compliance Health Score", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  score >= 80 ? "Your organization is well-guarded" : "Action required to improve score",
                  style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text("$score%", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          )
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
          _quickLinkCard("Maternity", Icons.child_care, const Color(0xFFD7E8FF), 'maternity'),
          _quickLinkCard("CLRA", Icons.engineering, const Color(0xFFDFF6E5), 'clra'),
          _quickLinkCard("Pay Equity", Icons.balance, const Color(0xFFEBDFF6), 'pay_equity'),
          _quickLinkCard("Apprentices", Icons.school, const Color(0xFFD4F3F7), 'apprentices'),
          _quickLinkCard("Auditor Pack", Icons.archive, const Color(0xFFF5F5F5), 'auditor'),
        ],
      ),
    );
  }

  Widget _quickLinkCard(String label, IconData icon, Color color, String action) {
    return InkWell(
      onTap: () => setState(() => activeQuickLink = action),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: Colors.black54),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickLinkView() {
    Widget content;
    String title = activeQuickLink.replaceAll('_', ' ').toUpperCase();

    switch (activeQuickLink) {
      case 'posh': content = _PoshComplianceView(userData: widget.userData); break;
      case 'maternity': content = _MaternityComplianceView(userData: widget.userData); break;
      case 'clra': content = _CLRAComplianceView(userData: widget.userData); break;
      case 'pay_equity': content = _PayEquityView(userData: widget.userData); break;
      case 'apprentices': content = _ApprenticesView(userData: widget.userData); break;
      case 'auditor': content = _AuditorPackView(userData: widget.userData); break;
      default: content = const Center(child: Text("Coming Soon"));
    }

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
                child: Row(children: [const Icon(Icons.arrow_back, size: 18, color: Colors.blue), const SizedBox(width: 8), Text("Back", style: GoogleFonts.montserrat(color: Colors.blue, fontWeight: FontWeight.bold))]),
              ),
              const Spacer(),
              Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 1. WAGE REGISTERS
// -----------------------------------------------------------------------------
class _WageRegistersTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _WageRegistersTab({required this.userData});

  @override
  State<_WageRegistersTab> createState() => _WageRegistersTabState();
}

class _WageRegistersTabState extends State<_WageRegistersTab> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _subTabController;
  List<dynamic> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _subTabController.addListener(() {
       if (!_subTabController.indexIsChanging) {
         _fetchItems();
       }
    });
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      String table = 'wage_register_fines';
      if (_subTabController.index == 1) table = 'wage_register_deductions';
      if (_subTabController.index == 2) table = 'wage_register_advances';

      final orgId = widget.userData['organization_id'];
      
      // Step 1: Fetch core records without join to avoid relationship errors
      dynamic res;
      try {
        res = await supabase.from(table).select().eq('org_id', orgId).order('created_at', ascending: false);
      } catch (_) {
        res = await supabase.from(table).select().eq('organization_id', orgId).order('created_at', ascending: false);
      }

      final List<Map<String, dynamic>> rawItems = List<Map<String, dynamic>>.from(res ?? []);
      
      // Step 2: Manually map employee names to avoid join issues
      if (rawItems.isNotEmpty) {
        final empIds = rawItems.map((i) => i['employee_id']).where((id) => id != null).toSet().toList();
        if (empIds.isNotEmpty) {
          final emps = await supabase.from('employee_records').select('id, full_name, employee_id').inFilter('id', empIds);
          final empMap = {for (var e in emps) e['id']: e};
          for (var item in rawItems) {
            if (item['employee_id'] != null && empMap.containsKey(item['employee_id'])) {
              item['employee_records'] = empMap[item['employee_id']];
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          items = rawItems;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Wage Register robust fetch error: $e");
      if (mounted) {
        setState(() {
          items = [];
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          labelColor: const Color(0xFF1E90FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1E90FF),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          tabs: const [Tab(text: "Fines"), Tab(text: "Deductions"), Tab(text: "Advances")],
        ),
        Expanded(
          child: loading 
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty 
                  ? const Center(child: Text("No records found"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final emp = item['employee_records'];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(emp?['full_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(item['offense_description'] ?? item['damage_description'] ?? item['purpose'] ?? '', style: const TextStyle(fontSize: 11)),
                            trailing: Text("₹${item['fine_amount'] ?? item['deduction_amount'] ?? item['advance_amount'] ?? 0}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. STATUTORY RETURNS
// -----------------------------------------------------------------------------
class _StatutoryReturnsTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _StatutoryReturnsTab({required this.userData});

  @override
  State<_StatutoryReturnsTab> createState() => _StatutoryReturnsTabState();
}

class _StatutoryReturnsTabState extends State<_StatutoryReturnsTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> filings = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchFilings();
  }

  Future<void> _fetchFilings() async {
    try {
      final orgId = widget.userData['organization_id'];
      dynamic res;
      try {
        res = await supabase
            .from('statutory_return_filings')
            .select()
            .eq('org_id', orgId)
            .order('due_date', ascending: false);
      } catch (e) {
        res = await supabase
            .from('statutory_return_filings')
            .select()
            .eq('organization_id', orgId)
            .order('due_date', ascending: false);
      }
      
      if (mounted) setState(() {
        filings = res ?? [];
        loading = false;
      });
    } catch (e) {
      debugPrint("Statutory filings error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (filings.isEmpty) return const Center(child: Text("No filings found"));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filings.length,
      itemBuilder: (context, index) {
        final f = filings[index];
        final status = (f['status'] ?? 'pending').toString().toLowerCase();
        Color statusColor = status == 'filed' ? Colors.green : (status == 'overdue' ? Colors.red : Colors.orange);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(f['return_type'] ?? '', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text("Period: ${f['period_month']} ${f['period_year']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text("Due Date: ${DateFormat('dd MMM yyyy').format(DateTime.parse(f['due_date']))}", style: const TextStyle(fontSize: 12)),
                if (f['challan_amount'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text("Amount: ₹${f['challan_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 3. FACTORIES ACT
// -----------------------------------------------------------------------------
class _FactoriesActTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _FactoriesActTab({required this.userData});

  @override
  State<_FactoriesActTab> createState() => _FactoriesActTabState();
}

class _FactoriesActTabState extends State<_FactoriesActTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> logs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    try {
      final orgId = widget.userData['organization_id'];
      dynamic res;
      try {
        res = await supabase.from('factory_accident_log').select().eq('org_id', orgId).order('accident_datetime', ascending: false);
      } catch (e) {
        res = await supabase.from('factory_accident_log').select().eq('organization_id', orgId).order('accident_datetime', ascending: false);
      }
      
      final List<Map<String, dynamic>> rawLogs = List<Map<String, dynamic>>.from(res ?? []);

      if (rawLogs.isNotEmpty) {
        final empIds = rawLogs.map((i) => i['employee_id']).where((id) => id != null).toSet().toList();
        if (empIds.isNotEmpty) {
          final emps = await supabase.from('employee_records').select('id, full_name').inFilter('id', empIds);
          final empMap = {for (var e in emps) e['id']: e};
          for (var log in rawLogs) {
            if (log['employee_id'] != null && empMap.containsKey(log['employee_id'])) {
              log['employee_records'] = empMap[log['employee_id']];
            }
          }
        }
      }

      if (mounted) setState(() {
        logs = rawLogs;
        loading = false;
      });
    } catch (e) {
      debugPrint("Factories Act robust fetch error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (logs.isEmpty) return const Center(child: Text("No accident logs recorded"));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(log['injury_type'] ?? 'Accident', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Location: ${log['accident_location']} • Reported: ${log['status']}"),
            trailing: const Icon(Icons.warning_amber_rounded, color: Colors.red),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 4. SHOPS & ESTABLISHMENTS
// -----------------------------------------------------------------------------
class _ShopsEstablishmentTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _ShopsEstablishmentTab({required this.userData});

  @override
  State<_ShopsEstablishmentTab> createState() => _ShopsEstablishmentTabState();
}

class _ShopsEstablishmentTabState extends State<_ShopsEstablishmentTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> certs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCerts();
  }

  Future<void> _fetchCerts() async {
    try {
      final orgId = widget.userData['organization_id'];
      dynamic res;
      try {
        res = await supabase
            .from('shops_establishment_certs')
            .select()
            .eq('org_id', orgId);
      } catch (e) {
        res = await supabase
            .from('shops_establishment_certs')
            .select()
            .eq('organization_id', orgId);
      }
      
      if (mounted) setState(() {
        certs = res ?? [];
        loading = false;
      });
    } catch (e) {
      debugPrint("Shops Certs error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (certs.isEmpty) return const Center(child: Text("No certificates found"));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: certs.length,
      itemBuilder: (context, index) {
        final c = certs[index];
        final validUntil = c['valid_until'];
        DateTime? expiry;
        if (validUntil != null) expiry = DateTime.tryParse(validUntil.toString());
        
        final isExpired = expiry != null && expiry.isBefore(DateTime.now());
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.verified, color: Colors.blue),
            title: Text(c['establishment_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(expiry != null ? "Valid until: ${DateFormat('dd MMM yyyy').format(expiry)}" : "Validity not set"),
            trailing: Icon(Icons.circle, size: 12, color: isExpired ? Colors.red : Colors.green),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 5. STATUTORY BONUS
// -----------------------------------------------------------------------------
class _StatutoryBonusTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _StatutoryBonusTab({required this.userData});

  @override
  State<_StatutoryBonusTab> createState() => _StatutoryBonusTabState();
}

class _StatutoryBonusTabState extends State<_StatutoryBonusTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> bonusRuns = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchBonusRuns();
  }
  Future<void> _fetchBonusRuns() async {
    try {
      final orgId = widget.userData['organization_id'];
      dynamic res;
      try {
        res = await supabase
            .from('bonus_runs')
            .select()
            .eq('organization_id', orgId)
            .order('accounting_year', ascending: false);
      } catch (e) {
        res = await supabase
            .from('bonus_runs')
            .select()
            .eq('org_id', orgId)
            .order('accounting_year', ascending: false);
      }
      
      if (mounted) setState(() {
        bonusRuns = res ?? [];
        loading = false;
      });
    } catch (e) {
      debugPrint("Bonus runs error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (bonusRuns.isEmpty) return const Center(child: Text("No bonus runs found"));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: bonusRuns.length,
      itemBuilder: (context, index) {
        final run = bonusRuns[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Bonus Year: ${run['accounting_year']}", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 15)),
                    _statusChip(run['status']),
                  ],
                ),
                const Divider(height: 24),
                _row("Eligible Employees", run['total_eligible_employees']?.toString() ?? '0'),
                _row("Total Payout", "₹${NumberFormat('#,##,###').format(run['total_payout_amount'] ?? 0)}"),
                _row("Applied %", "${run['bonus_pct_applied']}%"),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(String? status) {
    Color color = status == 'posted' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text((status ?? 'draft').toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _row(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. GRATUITY
// -----------------------------------------------------------------------------
class _GratuityTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  const _GratuityTab({required this.userData});

  @override
  State<_GratuityTab> createState() => _GratuityTabState();
}

class _GratuityTabState extends State<_GratuityTab> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _subTabController;
  List<dynamic> provisions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    _fetchProvisions();
  }

  Future<void> _fetchProvisions() async {
    try {
      final orgId = widget.userData['organization_id'];
      dynamic res;
      try {
        res = await supabase.from('gratuity_provisions').select().eq('organization_id', orgId).order('period_month', ascending: false);
      } catch (e) {
        res = await supabase.from('gratuity_provisions').select().eq('org_id', orgId).order('period_month', ascending: false);
      }
      
      final List<Map<String, dynamic>> rawProvisions = List<Map<String, dynamic>>.from(res ?? []);

      if (rawProvisions.isNotEmpty) {
        final empIds = rawProvisions.map((i) => i['employee_id']).where((id) => id != null).toSet().toList();
        if (empIds.isNotEmpty) {
          final emps = await supabase.from('employee_records').select('id, full_name, employee_id').inFilter('id', empIds);
          final empMap = {for (var e in emps) e['id']: e};
          for (var p in rawProvisions) {
            if (p['employee_id'] != null && empMap.containsKey(p['employee_id'])) {
              p['employee_records'] = empMap[p['employee_id']];
            }
          }
        }
      }

      if (mounted) setState(() {
        provisions = rawProvisions;
        loading = false;
      });
    } catch (e) {
      debugPrint("Gratuity robust fetch error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          labelColor: const Color(0xFF1E90FF),
          tabs: const [Tab(text: "Provisions Ledger"), Tab(text: "Payouts")],
        ),
        Expanded(
          child: loading 
              ? const Center(child: CircularProgressIndicator())
              : provisions.isEmpty 
                  ? const Center(child: Text("No provisions found"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: provisions.length,
                      itemBuilder: (context, index) {
                        final p = provisions[index];
                        final emp = p['employee_records'];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(emp?['full_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text("Eligible Years: ${p['eligible_service_years']}"),
                            trailing: Text("₹${NumberFormat('#,##,###').format(p['provision_amount'] ?? 0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// QUICK LINK VIEWS
// -----------------------------------------------------------------------------

class _PoshComplianceView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _PoshComplianceView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return _simpleListView('posh_cases', 'case_number', 'status', userData['organization_id']);
  }
}

class _MaternityComplianceView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _MaternityComplianceView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return _simpleListView('maternity_cases', 'leave_type', 'expected_delivery_date', userData['organization_id'], joinTable: 'employee_records');
  }
}

class _CLRAComplianceView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _CLRAComplianceView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return _simpleListView('contractors', 'name', 'license_number', userData['organization_id']);
  }
}

class _PayEquityView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _PayEquityView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Pay Equity Analysis - Dashboard coming soon"));
  }
}

class _ApprenticesView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _ApprenticesView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return _simpleListView('apprentice_records', 'apprentice_name', 'trade', userData['organization_id']);
  }
}

class _AuditorPackView extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _AuditorPackView({required this.userData});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Auditor Export Pack - Request a manifest from web console"));
  }
}

Widget _simpleListView(String table, String titleCol, String subTitleCol, String orgId, {String? joinTable}) {
  final supabase = Supabase.instance.client;
  String select = '*';
  if (joinTable != null) select = '*, $joinTable(full_name)';

  return FutureBuilder(
    future: () async {
      try {
        // Try all schema variations
        try {
          return await supabase.from(table).select(select).eq('org_id', orgId);
        } catch (_) {
          return await supabase.from(table).select(select).eq('organization_id', orgId);
        }
      } catch (e) {
        // Final fallback without join if join failed
        if (select != '*') {
           try {
            return await supabase.from(table).select('*').eq('org_id', orgId);
          } catch (_) {
            return await supabase.from(table).select('*').eq('organization_id', orgId);
          }
        }
        rethrow;
      }
    }(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text("Data fetch error: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.red)));
      
      final List data = (snapshot.data as List?) ?? [];
      if (data.isEmpty) return const Center(child: Text("No records found"));

      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final item = data[i];
          String title = item[titleCol]?.toString() ?? '';
          if (joinTable != null && item[joinTable] != null) {
            title = "${item[joinTable]['full_name']} - $title";
          }
          return Card(
            child: ListTile(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item[subTitleCol]?.toString() ?? ''),
            ),
          );
        },
      );
    },
  );
}
