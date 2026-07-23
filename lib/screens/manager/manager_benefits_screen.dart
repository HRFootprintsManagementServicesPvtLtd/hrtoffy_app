import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import 'widgets/benefit_approval_panel.dart';

class ManagerBenefitsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerBenefitsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerBenefitsScreen> createState() => _ManagerBenefitsScreenState();
}

class _ManagerBenefitsScreenState extends State<ManagerBenefitsScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  String activeAction = 'none'; // none, my_benefits, submit, lta, esi, esi_guide, approvals, esi_approvals, insurance
  bool loading = true;
  
  int pendingCount = 0;
  int esiPendingCount = 0;

  String? employeeId, organizationId, grade;
  List<Map<String, dynamic>> myClaims = [];
  List<Map<String, dynamic>> catalog = [];
  List<Map<String, dynamic>> myInsurance = [];
  Map<String, dynamic>? gradeLimitData;
  Map<String, dynamic>? esiEligibility;
  double claimedTotalYTD = 0.0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => loading = true);
    try {
      final myId = widget.userData['id'];
      employeeId = myId.toString();
      organizationId = widget.userData['organization_id']?.toString();
      grade = widget.userData['grade_code']?.toString();

      await Future.wait([
        _fetchCounts(),
        _fetchMyClaims(),
        _fetchCatalog(),
        _fetchGradeLimits(),
        _fetchESIEligibility(),
        _fetchMyInsurance(),
      ]);
    } catch (e) {
      debugPrint("Error initializing manager benefits: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchCounts() async {
    try {
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': employeeId});
      List<String> teamIds = [];
      if (hierarchy is List) {
        teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      }

      if (teamIds.isNotEmpty) {
        final res = await supabase
            .from('benefit_claims')
            .select('id, is_esi_claim')
            .inFilter('employee_id', teamIds)
            .eq('status', 'pending');
        
        final list = res as List;
        pendingCount = list.length;
        esiPendingCount = list.where((c) => c['is_esi_claim'] == true).length;
      }
    } catch (e) {
      debugPrint("Error fetching benefit counts: $e");
    }
  }

  Future<void> _fetchMyClaims() async {
    final res = await supabase
        .from('benefit_claims')
        .select('*, benefits_catalog(benefit_name)')
        .eq('employee_id', employeeId!)
        .order('created_at', ascending: false);
    myClaims = List<Map<String, dynamic>>.from(res);
    
    final currentYear = DateTime.now().year;
    claimedTotalYTD = 0.0;
    for (var claim in myClaims) {
      if ((claim['claim_year'] ?? 0) == currentYear && claim['status'] == 'approved') {
        claimedTotalYTD += (claim['approved_amount'] ?? claim['claimed_amount'] ?? 0).toDouble();
      }
    }
  }

  Future<void> _fetchCatalog() async {
    if (organizationId == null) return;
    final res = await supabase
        .from('benefits_catalog')
        .select()
        .eq('organization_id', organizationId!)
        .eq('is_active', true);
    catalog = List<Map<String, dynamic>>.from(res);
  }

  Future<void> _fetchGradeLimits() async {
    if (organizationId == null) return;
    // ✅ Improved: Attempt to fetch grade from userData if not directly available
    final gCode = grade ?? widget.userData['grade_code'] ?? widget.userData['grade'];
    if (gCode == null) return;
    
    final res = await supabase
        .from('grade_structure')
        .select()
        .eq('organization_id', organizationId!)
        .eq('grade_code', gCode)
        .maybeSingle();
    
    if (mounted) setState(() => gradeLimitData = res);
  }

  Future<void> _fetchESIEligibility() async {
    final res = await supabase
        .from('employee_eligibility')
        .select()
        .eq('employee_id', employeeId!)
        .maybeSingle();
    esiEligibility = res;
  }

  Future<void> _fetchMyInsurance() async {
    try {
      final res = await supabase
          .from('employee_insurance_policies')
          .select()
          .eq('organization_id', organizationId!);
      myInsurance = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint("Insurance fetch error: $e");
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
          BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Rewards that feel personal",
            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Manage your benefits, submit claims, and approve team requests all in one place.",
            style: GoogleFonts.montserrat(color: Colors.white.withOpacity(0.9), fontSize: 13, height: 1.4),
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
        _actionCard("My Benefits", "View benefits available to you.", Icons.card_giftcard, Colors.purple, 'my_benefits'),
        _actionCard("Submit Claim", "Raise a reimbursement claim.", Icons.add_circle_outline, Colors.green, 'submit'),
        _actionCard("LTA Claim", "Leave Travel Allowance claim.", Icons.flight_takeoff, Colors.blue, 'lta'),
        _actionCard("ESI Claims", "Statutory medical benefit claims.", Icons.verified_user_outlined, Colors.lightBlue, 'esi'),
        _actionCard("ESI Guide", "Explainer for ESI eligibility.", Icons.menu_book, Colors.grey, 'esi_guide'),
        _actionCard("Approvals", "Pending team benefit claims.", Icons.fact_check_outlined, Colors.deepOrange, 'approvals', badge: pendingCount),
        _actionCard("ESI Approvals", "Pending team ESI claims.", Icons.assignment_turned_in_outlined, Colors.deepOrange, 'esi_approvals', badge: esiPendingCount),
        _actionCard("My Insurance", "Group policies linked to you.", Icons.favorite_border, Colors.redAccent, 'insurance'),
      ],
    );
  }

  Widget _actionCard(String label, String desc, IconData icon, Color color, String action, {int? badge}) {
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
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
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
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text(badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(label, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Expanded(
              child: Text(desc, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey.shade600, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
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
        child = BenefitApprovalPanel(userData: widget.userData, onBack: () => setState(() => activeAction = 'none'));
        break;
      case 'esi_approvals':
        title = "ESI Approvals";
        child = BenefitApprovalPanel(
          userData: widget.userData, 
          onBack: () => setState(() => activeAction = 'none'),
          filterCategory: 'esi',
        );
        break;
      case 'esi_guide':
        title = "ESI Guide";
        child = _buildESIGuide();
        break;
      case 'my_benefits':
        title = "My Benefits";
        child = MyBenefitsPanel(claims: myClaims);
        break;
      case 'submit':
        title = "Submit Claim";
        child = SubmitClaimPanel(
          catalog: catalog, 
          gradeLimitData: gradeLimitData, 
          claimedTotalYTD: claimedTotalYTD,
          onSuccess: () {
            setState(() => activeAction = 'none');
            _fetchMyClaims();
          },
        );
        break;
      case 'lta':
        title = "LTA Claim";
        child = LTAClaimPanel(
          employeeId: employeeId!, 
          organizationId: organizationId!,
          onSuccess: () => setState(() => activeAction = 'none'),
        );
        break;
      case 'esi':
        title = "ESI Claims";
        child = ESIClaimsPanel(
          eligibility: esiEligibility, 
          employeeId: employeeId!,
          organizationId: organizationId!,
          onSuccess: () => setState(() => activeAction = 'none'),
        );
        break;
      case 'insurance':
        title = "My Insurance";
        child = MyInsurancePanel(policies: myInsurance);
        break;
      default:
        title = activeAction.replaceAll('_', ' ').toUpperCase();
        child = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text("$title View Coming Soon", style: GoogleFonts.montserrat(color: Colors.grey)),
            ],
          ),
        );
    }

    return Column(
      children: [
        if (activeAction != 'approvals' && activeAction != 'esi_approvals')
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
        onTap: () => setState(() => activeAction = 'none'),
        child: Row(
          children: [
            const Icon(Icons.arrow_back, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Text("Back to overview", style: GoogleFonts.montserrat(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(title, style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87));
  }

  Widget _buildESIGuide() {
    final bool isEligible = esiEligibility?['esi_applicable'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEligible ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isEligible ? Colors.green.shade100 : Colors.red.shade100),
            ),
            child: Row(
              children: [
                Icon(isEligible ? Icons.check_circle : Icons.error_outline, color: isEligible ? Colors.green : Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEligible ? "You are Eligible for ESI" : "Not Eligible for ESI",
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: isEligible ? Colors.green.shade900 : Colors.red.shade900),
                      ),
                      Text(
                        isEligible ? "Your ESI contributions are active." : "Monthly gross exceeds wage ceiling or not enabled.",
                        style: GoogleFonts.montserrat(fontSize: 11, color: isEligible ? Colors.green.shade700 : Colors.red.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
          _stepItem("1", "Visit ESI Dispensary", "Get examined by a medical officer at your registered dispensary."),
          _stepItem("2", "Get Medical Certificate", "Obtain Form 7/8/9 from the officer after diagnosis."),
          _stepItem("3", "Submit Claim on App", "Open ESI Claims, fill details and upload your certificate."),
          _stepItem("4", "Approval Review", "Manager and HR will review your statutory claim."),
          _stepItem("5", "ESIC Disbursement", "Once approved, benefits are settled directly by ESIC."),
          const SizedBox(height: 24),
          _sectionTitle("Frequently Asked Questions"),
          const SizedBox(height: 12),
          _faqItem("Who is eligible for ESI?", "Employees earning gross salary up to ₹21,000 per month."),
          _faqItem("Will I get salary during ESI period?", "No, salary is usually skipped as ESIC pays the benefit directly."),
          _faqItem("What documents are needed?", "ESI IP Card and a Medical Certificate from a Dispensary."),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
          const SizedBox(height: 6),
          Text(a, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
        ],
      ),
    );
  }

  Widget _esiTypeCard(String title, String benefit) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade800)),
          const SizedBox(height: 4),
          Text(benefit, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey.shade600)),
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
          CircleAvatar(radius: 12, backgroundColor: Colors.blue, child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 🟣 My Benefits Panel
class MyBenefitsPanel extends StatefulWidget {
  final List<Map<String, dynamic>> claims;
  const MyBenefitsPanel({super.key, required this.claims});

  @override
  State<MyBenefitsPanel> createState() => _MyBenefitsPanelState();
}

class _MyBenefitsPanelState extends State<MyBenefitsPanel> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final filtered = widget.claims.where((c) {
      final name = c['benefits_catalog']?['benefit_name']?.toString().toLowerCase() ?? "";
      return name.contains(searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            onChanged: (v) => setState(() => searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search your benefit claims...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
            ? Center(child: Text("No benefit claims yet", style: GoogleFonts.montserrat(color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final claim = filtered[index];
                  final status = (claim['status'] ?? 'pending').toString().toLowerCase();
                  Color statusColor = Colors.orange;
                  if (status == 'approved') statusColor = Colors.green;
                  if (status == 'rejected') statusColor = Colors.red;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(claim['benefits_catalog']?['benefit_name'] ?? 'Benefit', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(claim['description'] ?? '-', style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMM yyyy').format(DateTime.parse(claim['created_at'])), style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54)),
                            Text("₹${NumberFormat('#,##,###').format(claim['claimed_amount'] ?? 0)}", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
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

// 🟢 Submit Claim Panel
class SubmitClaimPanel extends StatefulWidget {
  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic>? gradeLimitData;
  final double claimedTotalYTD;
  final VoidCallback onSuccess;

  const SubmitClaimPanel({super.key, required this.catalog, required this.gradeLimitData, required this.claimedTotalYTD, required this.onSuccess});

  @override
  State<SubmitClaimPanel> createState() => _SubmitClaimPanelState();
}

class _SubmitClaimPanelState extends State<SubmitClaimPanel> {
  final _formKey = GlobalKey<FormState>();
  String? selectedBenefitId;
  double? amount;
  String? description;
  PlatformFile? attachment;
  bool submitting = false;

  @override
  Widget build(BuildContext context) {
    final annualLimit = (widget.gradeLimitData?['benefit_annual_limit'] ?? 0.0).toDouble();
    final remaining = annualLimit - widget.claimedTotalYTD;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _limitStat("Annual Limit", "₹${NumberFormat('#,##,###').format(annualLimit)}"),
                      _limitStat("Remaining", "₹${NumberFormat('#,##,###').format(remaining)}", color: Colors.blue.shade700),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: annualLimit > 0 ? (widget.claimedTotalYTD / annualLimit).clamp(0, 1) : 0,
                    backgroundColor: Colors.white,
                    valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _fieldTitle("Select Benefit"),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: selectedBenefitId,
              decoration: _inputDecoration(),
              items: widget.catalog.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['benefit_name'] ?? ''))).toList(),
              onChanged: (v) => setState(() => selectedBenefitId = v),
              validator: (v) => v == null ? "Required" : null,
            ),
            const SizedBox(height: 20),
            _fieldTitle("Claim Amount (₹)"),
            TextFormField(
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(hint: "Enter amount"),
              onChanged: (v) => amount = double.tryParse(v),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return "Invalid amount";
                if (n > remaining) return "Exceeds remaining limit";
                return null;
              },
            ),
            const SizedBox(height: 20),
            _fieldTitle("Description"),
            TextFormField(
              maxLines: 3,
              decoration: _inputDecoration(hint: "Add details about this claim..."),
              onChanged: (v) => description = v,
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
            const SizedBox(height: 20),
            _fieldTitle("Upload Receipt"),
            InkWell(
              onTap: () async {
                final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
                if (res != null) setState(() => attachment = res.files.first);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(attachment?.name ?? "Click to upload receipt image", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: _buttonStyle(),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit Claim"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitStat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black54)),
        Text(value, style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  Widget _fieldTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
  );

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade700,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontWeight: FontWeight.bold),
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      String? fileUrl;
      if (attachment != null) {
        final path = 'claims/${user!.id}/${DateTime.now().millisecondsSinceEpoch}_${attachment!.name}';
        await Supabase.instance.client.storage.from('claim-documents').upload(path, File(attachment!.path!));
        fileUrl = Supabase.instance.client.storage.from('claim-documents').getPublicUrl(path);
      }

      final now = DateTime.now();
      await Supabase.instance.client.from('benefit_claims').insert({
        'employee_id': user!.id,
        'organization_id': widget.catalog.first['organization_id'],
        'benefit_catalog_id': selectedBenefitId,
        'claimed_amount': amount,
        'claim_date': now.toIso8601String(),
        'description': description,
        'status': 'pending',
        'document_urls': fileUrl != null ? [fileUrl] : [],
        'claim_year': now.year,
        'claim_month': now.month,
      });
      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

// 🔵 LTA Claim Panel
class LTAClaimPanel extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  final VoidCallback onSuccess;
  const LTAClaimPanel({super.key, required this.employeeId, required this.organizationId, required this.onSuccess});

  @override
  State<LTAClaimPanel> createState() => _LTAClaimPanelState();
}

class _LTAClaimPanelState extends State<LTAClaimPanel> {
  final _formKey = GlobalKey<FormState>();
  int journeysUsed = 0;
  String blockPeriod = "2026-2029";
  bool submitting = false;

  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final dateCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  String mode = "Air";
  List<String> familyMembers = [];

  @override
  void initState() {
    super.initState();
    _fetchLTAStats();
  }

  Future<void> _fetchLTAStats() async {
    // Basic logic: current year 2026-2029 block
    try {
      final res = await Supabase.instance.client
          .from('lta_journey_claims')
          .select('id')
          .eq('employee_id', widget.employeeId);
      if (mounted) setState(() => journeysUsed = (res as List).length);
    } catch (e) {
      debugPrint("LTA Stats Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50, 
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("LTA Block Period: $blockPeriod", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text("Journeys Used: $journeysUsed/2  Remaining: ${2 - journeysUsed}", style: GoogleFonts.montserrat(fontSize: 12, color: Colors.blue.shade700)),
                        const SizedBox(height: 4),
                        const Text("2 journeys available in block 2026-2029", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _fieldTitle("Travel From *"),
            TextFormField(controller: fromCtrl, decoration: _inputDecoration(hint: "Origin city/location"), validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            _fieldTitle("Travel To *"),
            TextFormField(controller: toCtrl, decoration: _inputDecoration(hint: "Destination city/location"), validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            _fieldTitle("Travel Date *"),
            TextFormField(controller: dateCtrl, readOnly: true, decoration: _inputDecoration(hint: "dd-mm-yyyy"), onTap: _pickDate, validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            _fieldTitle("Mode of Travel *"),
            DropdownButtonFormField<String>(
              value: mode,
              items: ["Air", "Train", "Bus", "Taxi"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => mode = v!),
              decoration: _inputDecoration(hint: "Select travel mode"),
            ),
            const SizedBox(height: 16),
            _fieldTitle("Claim Amount (₹) *"),
            TextFormField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration(hint: "Total travel expense"), validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            _fieldTitle("Family Members"),
            DropdownButtonFormField<String>(
              value: "Self only",
              items: ["Self only", "Self & Spouse", "Self & Children", "Entire Family"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {},
              decoration: _inputDecoration(hint: "Family details"),
            ),
            const SizedBox(height: 16),
            _fieldTitle("Additional Notes"),
            TextFormField(controller: notesCtrl, maxLines: 3, decoration: _inputDecoration(hint: "Any additional details about your travel...")),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: _buttonStyle(),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit LTA Claim"),
            ),
          ],
        ),
      ),
    );
  }

  void _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2026), lastDate: DateTime(2029, 12, 31));
    if (d != null) setState(() => dateCtrl.text = DateFormat('yyyy-MM-dd').format(d));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      await Supabase.instance.client.from('lta_journey_claims').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'journey_from': fromCtrl.text,
        'journey_to': toCtrl.text,
        'trip_date': dateCtrl.text, // ✅ Fixed: Use 'trip_date' instead of 'journey_date'
        'status': 'pending',
      });
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submission Error: $e")));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget _fieldTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
  );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade700,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 0,
  );
}

// 🩵 ESI Claims Panel
class ESIClaimsPanel extends StatefulWidget {
  final Map<String, dynamic>? eligibility;
  final String employeeId;
  final String organizationId;
  final VoidCallback onSuccess;
  const ESIClaimsPanel({super.key, required this.eligibility, required this.employeeId, required this.organizationId, required this.onSuccess});

  @override
  State<ESIClaimsPanel> createState() => _ESIClaimsPanelState();
}

class _ESIClaimsPanelState extends State<ESIClaimsPanel> {
  final _formKey = GlobalKey<FormState>();
  bool submitting = false;
  String benefitType = "Sickness";
  final startCtrl = TextEditingController();
  final endCtrl = TextEditingController();
  final ipCtrl = TextEditingController();
  final hospitalCtrl = TextEditingController();
  final diagnosisCtrl = TextEditingController();
  PlatformFile? certificate;

  @override
  Widget build(BuildContext context) {
    final bool isEligible = widget.eligibility?['esi_applicable'] == true;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isEligible) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Text("Not Eligible for ESI", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("Monthly gross exceeds ESI wage ceiling (₹21,000) or ESI is not enabled for your profile.", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.red.shade700)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Center(child: Text("You cannot raise ESI claims.", style: GoogleFonts.montserrat(color: Colors.grey))),
          ] else ...[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldTitle("ESI Benefit Type"),
                  DropdownButtonFormField<String>(
                    value: benefitType,
                    items: ["Sickness", "Maternity", "Disablement", "Medical", "Funeral"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => benefitType = v!),
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _fieldTitle("Start Date"),
                        TextFormField(controller: startCtrl, readOnly: true, decoration: _inputDecoration(hint: "yyyy-mm-dd"), onTap: () => _pickDate(startCtrl), validator: (v) => v!.isEmpty ? "Required" : null),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _fieldTitle("End Date"),
                        TextFormField(controller: endCtrl, readOnly: true, decoration: _inputDecoration(hint: "yyyy-mm-dd"), onTap: () => _pickDate(endCtrl), validator: (v) => v!.isEmpty ? "Required" : null),
                      ])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _fieldTitle("IP Number"),
                  TextFormField(controller: ipCtrl, decoration: _inputDecoration(hint: "ESI Identity Card No."), validator: (v) => v!.isEmpty ? "Required" : null),
                  const SizedBox(height: 16),
                  _fieldTitle("Hospital / Dispensary"),
                  TextFormField(controller: hospitalCtrl, decoration: _inputDecoration(hint: "Name & Location"), validator: (v) => v!.isEmpty ? "Required" : null),
                  const SizedBox(height: 16),
                  _fieldTitle("Diagnosis"),
                  TextFormField(controller: diagnosisCtrl, maxLines: 2, decoration: _inputDecoration(hint: "Brief medical reason")),
                  const SizedBox(height: 16),
                  _fieldTitle("Medical Certificate"),
                  InkWell(
                    onTap: () async {
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
                      if (res != null) setState(() => certificate = res.files.first);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Text(certificate?.name ?? "Upload Certificate", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: submitting ? null : _submit,
                    style: _buttonStyle(),
                    child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit ESI Claim"),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _pickDate(TextEditingController ctrl) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 30)));
    if (d != null) setState(() => ctrl.text = DateFormat('yyyy-MM-dd').format(d));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      String? fileUrl;
      if (certificate != null) {
        final path = 'esi-certs/${widget.employeeId}/${DateTime.now().millisecondsSinceEpoch}_${certificate!.name}';
        await Supabase.instance.client.storage.from('documents').upload(path, File(certificate!.path!));
        fileUrl = Supabase.instance.client.storage.from('documents').getPublicUrl(path);
      }

      await Supabase.instance.client.from('benefit_claims').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'is_esi_claim': true,
        'amount': 0.0, // ESIC pays directly usually
        'claim_date': DateTime.now().toIso8601String(),
        'description': "ESI $benefitType Claim: ${diagnosisCtrl.text}",
        'status': 'pending',
        'document_urls': fileUrl != null ? [fileUrl] : [],
        'esi_benefit_type': benefitType,
        'esi_start_date': startCtrl.text,
        'esi_end_date': endCtrl.text,
        'esi_ip_number': ipCtrl.text,
        'esi_hospital_name': hospitalCtrl.text,
      });
      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget _fieldTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
  );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade700,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 0,
  );
}

// ❤️ My Insurance Panel
class MyInsurancePanel extends StatelessWidget {
  final List<Map<String, dynamic>> policies;
  const MyInsurancePanel({super.key, required this.policies});

  @override
  Widget build(BuildContext context) {
    return policies.isEmpty
      ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("No Active Policies", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text("Your insurance policies will appear here once assigned by HR.", textAlign: TextAlign.center, style: GoogleFonts.montserrat(color: Colors.grey, fontSize: 12)),
          ],
        )
      : ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: policies.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final p = policies[index];
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['policy_type'] ?? 'Insurance', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue.shade800)),
                      const Icon(Icons.security, color: Colors.blue, size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _row("Insurer", p['insurer']),
                  _row("Sum Insured", "₹${NumberFormat('#,##,###').format(p['sum_insured'] ?? 0)}"),
                  _row("Validity", "${p['start_date']} to ${p['end_date']}"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton.icon(onPressed: () {}, icon: const Icon(Icons.people_outline, size: 16), label: const Text("View Nominees", style: TextStyle(fontSize: 12))),
                      const Spacer(),
                      TextButton.icon(onPressed: () {}, icon: const Icon(Icons.local_hospital_outlined, size: 16), label: const Text("Hospitals", style: TextStyle(fontSize: 12))),
                    ],
                  ),
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
          Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade600)),
          Text(val ?? '-', style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
