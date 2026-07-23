import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';
import 'widgets/travel_approval_panel.dart';

class ManagerTravelScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerTravelScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerTravelScreen> createState() => _ManagerTravelScreenState();
}

class _ManagerTravelScreenState extends State<ManagerTravelScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  String activeAction = 'none'; // none, new_claim, request_advance, settlement, approvals
  Map<String, dynamic>? selectedAdvanceForSettlement;
  bool loading = true;
  
  List<Map<String, dynamic>> unifiedFeed = [];
  Map<String, dynamic> stats = {
    'total_claims': 0,
    'total_advances': 0,
    'outstanding': 0.0,
    'pending': 0,
  };

  String? employeeId, organizationId, empRole;

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

  Future<void> _initData() async {
    setState(() => loading = true);
    try {
      employeeId = widget.userData['id']?.toString();
      organizationId = widget.userData['organization_id']?.toString();
      empRole = widget.userData['emp_role']?.toString();

      await _fetchTravelData();
    } catch (e) {
      debugPrint("Error initializing manager travel: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchTravelData() async {
    final bool isHR = ['hr', 'hr_manager', 'hr_head', 'admin'].contains(empRole?.toLowerCase());
    
    try {
      // 1. Fetch Claims
      var claimsQuery = supabase
          .from('travel_claims')
          .select('*, employee_records!travel_claims_employee_id_fkey(full_name, employee_id)')
          .eq('organization_id', organizationId!);
      
      if (!isHR) {
        claimsQuery = claimsQuery.eq('employee_id', employeeId!);
      }
      
      final claimsRes = await claimsQuery.order('created_at', ascending: false);
      final List<Map<String, dynamic>> claims = (claimsRes as List).map((c) {
        final map = Map<String, dynamic>.from(c);
        map['feed_type'] = map['linked_advance_id'] != null ? 'Settlement' : 'Claim';
        map['sort_date'] = map['created_at'];
        return map;
      }).toList();

      // 2. Fetch Advances
      var advancesQuery = supabase
          .from('loans_advances')
          .select('*, employee_records!loans_advances_employee_id_fkey(full_name, employee_id)')
          .eq('organization_id', organizationId!)
          .eq('loan_category', 'travel_advance');

      if (!isHR) {
        advancesQuery = advancesQuery.eq('employee_id', employeeId!);
      }

      final advancesRes = await advancesQuery.order('application_date', ascending: false);
      var advancesData = List<Map<String, dynamic>>.from(advancesRes);

      // Decrypt advance amounts if any
      if (advancesData.isNotEmpty) {
        try {
          final ids = advancesData.map((a) => a['id']).toList();
          final decryptRes = await supabase.functions.invoke('salary-encryption', body: {
            'action': 'decrypt-batch',
            'table': 'loans_advances',
            'ids': ids,
          });
          if (decryptRes.data != null) {
            final decryptedMap = {for (var item in decryptRes.data) item['id']: item};
            for (var adv in advancesData) {
              if (decryptedMap.containsKey(adv['id'])) {
                final d = decryptedMap[adv['id']];
                adv['requested_amount'] = d['requested_amount'];
                adv['approved_amount'] = d['approved_amount'];
                adv['outstanding_principal'] = d['outstanding_principal'];
              }
            }
          }
        } catch (de) {
          debugPrint("Decryption error in travel: $de");
        }
      }

      final List<Map<String, dynamic>> advances = advancesData.map((a) {
        final map = Map<String, dynamic>.from(a);
        map['feed_type'] = 'Advance';
        map['sort_date'] = map['application_date'] ?? map['created_at'];
        map['display_amount'] = map['requested_amount'] ?? 0.0;
        return map;
      }).toList();

      // 3. Merge and Sort
      final uFeed = [...claims, ...advances];
      uFeed.sort((a, b) => DateTime.parse(b['sort_date']).compareTo(DateTime.parse(a['sort_date'])));

      // 4. Calculate Stats
      final tClaimsCount = claims.where((c) => c['feed_type'] == 'Claim').length;
      final tAdvancesCount = advances.length;
      final pendingCount = uFeed.where((f) => f['status'] == 'pending').length;
      
      double outstandingVal = 0.0;
      for (var adv in advances) {
        if (adv['status'] == 'disbursed' || adv['status'] == 'active') {
          outstandingVal += (adv['requested_amount'] ?? 0.0).toDouble();
        }
      }

      if (!mounted) return;
      setState(() {
        unifiedFeed = uFeed;
        stats['total_claims'] = tClaimsCount;
        stats['total_advances'] = tAdvancesCount;
        stats['pending'] = pendingCount;
        stats['outstanding'] = outstandingVal;
      });

    } catch (e) {
      debugPrint("Fetch Travel Data Error: $e");
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
        gradient: LinearGradient(
          colors: [const Color(0xFFD7E8FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blue.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Unified Travel Hub",
            style: GoogleFonts.playfairDisplay(color: const Color(0xFF444444), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Manage claims, cash advances, and settlements for your trips.",
            style: GoogleFonts.montserrat(color: const Color(0xFF666666), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildKPISection() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _kpiCard("Total Claims", stats['total_claims'].toString(), const Color(0xFFD7E8FF), Icons.receipt_long),
        _kpiCard("Total Advances", stats['total_advances'].toString(), const Color(0xFFD4F3F7), Icons.account_balance_wallet),
        _kpiCard("Outstanding", "₹${NumberFormat('#,##,###').format(stats['outstanding'])}", const Color(0xFFFFECE6), Icons.trending_up),
        _kpiCard("Pending", stats['pending'].toString(), const Color(0xFFEBDFF6), Icons.pending_actions),
      ],
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black54)),
              Icon(icon, size: 14, color: Colors.black26),
            ],
          ),
          Text(value, style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _actionBtn("New Claim", Icons.add_circle_outline, Colors.blue, () => setState(() => activeAction = 'new_claim')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionBtn("Request Advance", Icons.payments_outlined, Colors.teal, () => setState(() => activeAction = 'request_advance')),
        ),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
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
            Text(label, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 45,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicator: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(10), 
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: EdgeInsets.zero,
        labelColor: Colors.blue.shade700,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: "All"), 
          Tab(text: "Claims"), 
          Tab(text: "Advances"), 
          Tab(text: "Settlements")
        ],
      ),
    );
  }

  Widget _buildFeedList() {
    List<Map<String, dynamic>> filtered = [];
    if (_tabController.index == 0) filtered = unifiedFeed;
    if (_tabController.index == 1) filtered = unifiedFeed.where((f) => f['feed_type'] == 'Claim').toList();
    if (_tabController.index == 2) filtered = unifiedFeed.where((f) => f['feed_type'] == 'Advance').toList();
    if (_tabController.index == 3) filtered = unifiedFeed.where((f) => f['feed_type'] == 'Settlement').toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text("No travel records found", style: GoogleFonts.montserrat(color: Colors.grey)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final type = item['feed_type'];
        final status = (item['status'] ?? 'pending').toString().toLowerCase();

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
                  _typeChip(type),
                  _statusPill(status),
                ],
              ),
              const SizedBox(height: 12),
              Text(item['claim_number'] ?? item['loan_number'] ?? '-', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade700)),
              const SizedBox(height: 4),
              Text(item['trip_purpose'] ?? item['purpose'] ?? 'Travel', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14)),
              if (item['trip_destination'] != null || item['supporting_documents']?['destination'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(item['trip_destination'] ?? item['supporting_documents']?['destination'] ?? '', style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('dd MMM yyyy').format(DateTime.parse(item['sort_date'])), style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey)),
                  Row(
                    children: [
                      Text(
                        "₹${NumberFormat('#,##,###.00').format(item['total_amount'] ?? item['display_amount'] ?? 0.0)}",
                        style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (type == 'Advance' && (status == 'disbursed' || status == 'active'))
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: TextButton(
                            onPressed: () => setState(() {
                              selectedAdvanceForSettlement = item;
                              activeAction = 'settlement';
                            }),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              minimumSize: const Size(0, 30),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Settle", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _typeChip(String type) {
    Color color = Colors.blue;
    if (type == 'Advance') color = Colors.teal;
    if (type == 'Settlement') color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(type.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusPill(String status) {
    Color color = Colors.orange;
    if (status == 'approved' || status == 'paid' || status == 'settled' || status == 'disbursed') color = Colors.green;
    if (status == 'rejected') color = Colors.red;
    if (status == 'manager_approved' || status == 'active') color = Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase().replaceAll('_', ' '), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailView() {
    Widget child;
    String title;

    switch (activeAction) {
      case 'approvals':
        title = "Travel Approvals";
        child = TravelApprovalPanel(userData: widget.userData, onBack: () => setState(() => activeAction = 'none'));
        break;
      case 'new_claim':
        title = "New Travel Claim";
        child = TravelClaimForm(
          employeeId: employeeId!,
          organizationId: organizationId!,
          onSuccess: () {
            setState(() => activeAction = 'none');
            _initData();
          },
        );
        break;
      case 'request_advance':
        title = "Request Travel Advance";
        child = TravelAdvanceForm(
          employeeId: employeeId!,
          organizationId: organizationId!,
          onSuccess: () {
            setState(() => activeAction = 'none');
            _initData();
          },
        );
        break;
      case 'settlement':
        title = "Settle Advance";
        child = TravelClaimForm(
          employeeId: employeeId!,
          organizationId: organizationId!,
          linkedAdvanceId: selectedAdvanceForSettlement?['id'],
          preFillData: selectedAdvanceForSettlement,
          onSuccess: () {
            setState(() {
              activeAction = 'none';
              selectedAdvanceForSettlement = null;
            });
            _initData();
          },
        );
        break;
      default:
        title = activeAction.replaceAll('_', ' ').toUpperCase();
        child = Center(child: Text("$title Coming Soon"));
    }

    return Column(
      children: [
        if (activeAction != 'approvals') _buildDetailHeader(title),
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
}

// 🔵 Travel Claim Form (handles New Claim & Settlement)
class TravelClaimForm extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  final String? linkedAdvanceId;
  final Map<String, dynamic>? preFillData;
  final VoidCallback onSuccess;
  const TravelClaimForm({super.key, required this.employeeId, required this.organizationId, this.linkedAdvanceId, this.preFillData, required this.onSuccess});

  @override
  State<TravelClaimForm> createState() => _TravelClaimFormState();
}

class _TravelClaimFormState extends State<TravelClaimForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  String? purpose, destination, fromLoc;
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now().add(const Duration(days: 2));
  String travelType = 'domestic';
  
  List<Map<String, dynamic>> items = [];
  bool submitting = false;
  bool scanning = false;

  @override
  void initState() {
    super.initState();
    if (widget.preFillData != null) {
      purpose = widget.preFillData!['trip_purpose'] ?? widget.preFillData!['purpose'];
      destination = widget.preFillData!['trip_destination'] ?? widget.preFillData!['supporting_documents']?['destination'];
      if (widget.preFillData!['trip_from_date'] != null) fromDate = DateTime.parse(widget.preFillData!['trip_from_date']);
      if (widget.preFillData!['trip_to_date'] != null) toDate = DateTime.parse(widget.preFillData!['trip_to_date']);
      if (widget.preFillData!['supporting_documents']?['travel_from_date'] != null) fromDate = DateTime.parse(widget.preFillData!['supporting_documents']?['travel_from_date']);
      if (widget.preFillData!['supporting_documents']?['travel_to_date'] != null) toDate = DateTime.parse(widget.preFillData!['supporting_documents']?['travel_to_date']);
    }
    _addNewItem();
  }

  void _addNewItem() {
    items.add({
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'category': 'Transport',
      'description': '',
      'amount': 0.0,
      'receipt': null
    });
  }

  Future<void> _scanReceipt(int index) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'png']);
    if (res == null) return;
    
    setState(() => scanning = true);
    try {
      final file = res.files.first;
      setState(() => items[index]['receipt'] = file);

      // Call Gemini OCR Edge Function
      final ocrRes = await supabase.functions.invoke('scan-receipt', body: {
        'image': base64.encode(File(file.path!).readAsBytesSync()),
        'module': 'travel'
      });

      if (ocrRes.data != null) {
        final data = ocrRes.data;
        setState(() {
          if (data['amount'] != null) items[index]['amount'] = (data['amount'] as num).toDouble();
          if (data['description'] != null) items[index]['description'] = data['description'];
          if (data['date'] != null) items[index]['date'] = data['date'];
        });
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double total = items.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.linkedAdvanceId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade100)),
                child: Row(children: [const Icon(Icons.info_outline, color: Colors.orange, size: 18), const SizedBox(width: 8), Text("Settling Advance: ${widget.preFillData?['loan_number']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange))]),
              ),
            _fieldTitle("Trip Purpose *"),
            TextFormField(initialValue: purpose, decoration: _inputDecoration(hint: "e.g. Client Meeting"), onChanged: (v) => purpose = v, validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_fieldTitle("From *"), TextFormField(initialValue: fromLoc, decoration: _inputDecoration(hint: "Origin"), onChanged: (v) => fromLoc = v, validator: (v) => v!.isEmpty ? "Required" : null)])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_fieldTitle("To *"), TextFormField(initialValue: destination, decoration: _inputDecoration(hint: "Destination"), onChanged: (v) => destination = v, validator: (v) => v!.isEmpty ? "Required" : null)])),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _datePicker("Start Date", fromDate, (d) => setState(() => fromDate = d))),
                const SizedBox(width: 12),
                Expanded(child: _datePicker("End Date", toDate, (d) => setState(() => toDate = d))),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Expense Items", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(onPressed: () => setState(_addNewItem), icon: const Icon(Icons.add), label: const Text("Add Item")),
              ],
            ),
            ...items.asMap().entries.map((e) => _buildLineItem(e.key, e.value)),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total Amount", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                  Text("₹${NumberFormat('#,##,###.00').format(total)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blue.shade800)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: _btnStyle(const Color(0xFF1E90FF)),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : Text(widget.linkedAdvanceId != null ? "Submit Settlement" : "Submit Travel Claim", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime value, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldTitle(label),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2023), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) onPick(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Colors.grey), const SizedBox(width: 8), Text(DateFormat('dd MMM yyyy').format(value), style: const TextStyle(fontSize: 12))]),
          ),
        )
      ],
    );
  }

  Widget _buildLineItem(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: TextFormField(key: ValueKey('desc_$index'), initialValue: item['description'], decoration: _inputDecoration(hint: "Description"), onChanged: (v) => item['description'] = v)),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: TextFormField(key: ValueKey('amt_$index'), controller: TextEditingController(text: item['amount'].toString())..selection = TextSelection.fromPosition(TextPosition(offset: item['amount'].toString().length)), keyboardType: TextInputType.number, decoration: _inputDecoration(hint: "Amount"), onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0))),
              IconButton(onPressed: () => setState(() => items.removeAt(index)), icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'png', 'pdf']);
                    if (res != null) setState(() => item['receipt'] = res.files.first);

                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.upload_file, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item['receipt']?.name ?? "Upload Receipt", style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                        if (item['receipt'] != null) const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _scanReceipt(index),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: scanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.document_scanner_outlined, size: 18, color: Colors.blue),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final total = items.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));
      final res = await supabase.from('travel_claims').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'trip_purpose': purpose,
        'trip_destination': destination,
        'from_location': fromLoc,
        'trip_from_date': fromDate.toIso8601String().substring(0, 10),
        'trip_to_date': toDate.toIso8601String().substring(0, 10),
        'travel_type': travelType,
        'total_amount': total,
        'status': 'pending',
        'linked_advance_id': widget.linkedAdvanceId,
      }).select().single();

      final claimId = res['id'];

      // Upload receipts and items
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String? rUrl;
        if (item['receipt'] != null) {
          final file = item['receipt'] as PlatformFile;
          final path = '${widget.employeeId}/$claimId/${i}_${DateTime.now().millisecondsSinceEpoch}.${file.extension}';
          await supabase.storage.from('travel-receipts').upload(path, File(file.path!));
          rUrl = supabase.storage.from('travel-receipts').getPublicUrl(path);
        }
        await supabase.from('travel_claim_items').insert({
          'claim_id': claimId,
          'organization_id': widget.organizationId,
          'expense_date': item['date'],
          'category': item['category'],
          'description': item['description'],
          'amount': item['amount'],
          'receipt_url': rUrl,
        });
      }

      // If settlement, update advance status
      if (widget.linkedAdvanceId != null) {
        await supabase.from('loans_advances').update({
          'status': 'settled',
          'closure_date': DateTime.now().toIso8601String(),
          'closure_reason': 'Settled via Travel Claim $claimId'
        }).eq('id', widget.linkedAdvanceId!);
      }

      await supabase.rpc('initialize_workflow', params: {'p_module': 'travel_claims', 'p_target_id': claimId, 'p_org_id': widget.organizationId});
      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(hintText: hint, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
  Widget _fieldTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)));
  ButtonStyle _btnStyle(Color color) => ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
}

// 🟢 Travel Advance Form
class TravelAdvanceForm extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  final VoidCallback onSuccess;
  const TravelAdvanceForm({super.key, required this.employeeId, required this.organizationId, required this.onSuccess});

  @override
  State<TravelAdvanceForm> createState() => _TravelAdvanceFormState();
}

class _TravelAdvanceFormState extends State<TravelAdvanceForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  double? amount;
  String? purpose, destination;
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now().add(const Duration(days: 3));
  bool submitting = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldTitle("Trip Purpose *"),
            TextFormField(decoration: _inputDecoration(hint: "Purpose of travel"), onChanged: (v) => purpose = v, validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            _fieldTitle("Destination *"),
            TextFormField(decoration: _inputDecoration(hint: "Target city/location"), onChanged: (v) => destination = v, validator: (v) => v!.isEmpty ? "Required" : null),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _datePicker("Start Date", fromDate, (d) => setState(() => fromDate = d))),
                const SizedBox(width: 12),
                Expanded(child: _datePicker("End Date", toDate, (d) => setState(() => toDate = d))),
              ],
            ),
            const SizedBox(height: 16),
            _fieldTitle("Requested Amount (₹) *"),
            TextFormField(keyboardType: TextInputType.number, decoration: _inputDecoration(hint: "Estimated cash required"), onChanged: (v) => amount = double.tryParse(v), validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? "Invalid amount" : null),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              style: _btnStyle(Colors.teal),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Request Advance", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime value, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldTitle(label),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) onPick(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Colors.grey), const SizedBox(width: 8), Text(DateFormat('dd MMM yyyy').format(value), style: const TextStyle(fontSize: 12))]),
          ),
        )
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final res = await supabase.from('loans_advances').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'loan_category': 'travel_advance',
        'requested_amount': amount,
        'tenure_months': 1, // ✅ Fixed: Set default tenure to 1 to satisfy not-null constraint
        'purpose': purpose,
        'status': 'pending',
        'application_date': DateTime.now().toIso8601String(),
        'supporting_documents': {
          'destination': destination,
          'travel_from_date': fromDate.toIso8601String().substring(0, 10),
          'travel_to_date': toDate.toIso8601String().substring(0, 10),
        }
      }).select().single();

      await supabase.rpc('initialize_workflow', params: {'p_module': 'travel_advances', 'p_target_id': res['id'], 'p_org_id': widget.organizationId});
      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(hintText: hint, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
  Widget _fieldTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)));
  ButtonStyle _btnStyle(Color color) => ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
}
