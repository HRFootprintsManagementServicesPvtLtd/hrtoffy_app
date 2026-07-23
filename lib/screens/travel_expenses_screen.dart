import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

class TravelExpensesScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const TravelExpensesScreen({
    Key? key,
    required this.email,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<TravelExpensesScreen> createState() => _TravelExpensesScreenState();
}

class _TravelExpensesScreenState extends State<TravelExpensesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  bool showForm = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.travel,
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
                    final empId = (widget.userData['id'] ?? widget.userData['employee_id'])?.toString() ?? '';
                    if (empId.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 12),
                child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer()),
              ),
              const SizedBox(width: 1),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD4F3F7), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Travel & Expenses", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Manage your business trip and expense claims", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
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
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmployeeUi.border)),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                    unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'Travel Claims'), Tab(text: 'Expense Claims')],
                  ),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTravelTab(),
                _buildExpenseTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: showForm ? null : FloatingActionButton(
        onPressed: () => setState(() => showForm = true),
        backgroundColor: EmployeeUi.primary,
        child: const Icon(Icons.add, color: Colors.white)
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
        onTap: (index) {
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.email, employeeId: widget.userData['id'].toString()))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildTravelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: showForm && _tabController.index == 0
          ? TravelClaimForm(userData: widget.userData, onCancel: () => setState(() => showForm = false))
          : TravelClaimsList(email: widget.email),
    );
  }

  Widget _buildExpenseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: showForm && _tabController.index == 1
          ? ExpenseClaimForm(userData: widget.userData, onCancel: () => setState(() => showForm = false))
          : ExpenseClaimsList(email: widget.email),
    );
  }
}

class TravelClaimsList extends StatelessWidget {
  final String email;
  final supabase = Supabase.instance.client;
  TravelClaimsList({required this.email, Key? key}) : super(key: key);

  Future<List<dynamic>> fetchClaims() async {
    final emp = await supabase.from('employee_records').select('id').eq('email', email).maybeSingle();
    if (emp == null) return [];
    return await supabase.from('travel_claims').select().eq('employee_id', emp['id']).order('created_at', ascending: false) ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchClaims(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const SkeletonTravelClaimsList();
        final claims = snapshot.data ?? [];
        if (claims.isEmpty) return Center(child: Column(children: [const SizedBox(height: 60), SvgPicture.asset("assets/icons/travel.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)), const SizedBox(height: 20), Text("No travel claims found", style: GoogleFonts.montserrat(color: Colors.black54))]));
        return Column(children: claims.map((cl) => _buildClaimCard(context, cl)).toList());
      },
    );
  }

  Widget _buildClaimCard(BuildContext context, dynamic cl) {
    final status = (cl['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.grey;
    if (status == 'approved' || status == 'paid') statusColor = Colors.green;
    else if (status == 'pending') statusColor = Colors.orange;
    else if (status == 'rejected') statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(cl['claim_number'] ?? 'TRV-REF', style: EmployeeUi.title(15)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
          ]),
          const SizedBox(height: 12),
          Text(cl['trip_purpose'] ?? '', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text("Destination: ${cl['trip_destination'] ?? '-'}", style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("₹${NumberFormat('#,##,###').format(cl['total_amount'] ?? 0)}", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
            Text("${cl['trip_from_date']} - ${cl['trip_to_date']}", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black38)),
          ]),
        ],
      ),
    );
  }
}

class TravelClaimForm extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onCancel;
  const TravelClaimForm({required this.userData, required this.onCancel, Key? key}) : super(key: key);
  @override State<TravelClaimForm> createState() => _TravelClaimFormState();
}

class _TravelClaimFormState extends State<TravelClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _purposeController = TextEditingController();
  final _destController = TextEditingController();
  final _fromLocController = TextEditingController();
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now().add(const Duration(days: 3));
  String travelType = 'domestic';
  bool submitting = false;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    items = [{'date': DateFormat('yyyy-MM-dd').format(DateTime.now()), 'category': 'Hotel', 'description': '', 'amount': 0.0, 'receipt': null}];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final empId = widget.userData['id'] ?? widget.userData['employee_id'];
      final orgId = widget.userData['organization_id'];
      final total = items.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));
      
      final res = await supabase.from('travel_claims').insert({
        'employee_id': empId,
        'organization_id': orgId,
        'trip_purpose': _purposeController.text,
        'trip_destination': _destController.text,
        'from_location': _fromLocController.text,
        'trip_from_date': fromDate.toIso8601String().substring(0, 10),
        'trip_to_date': toDate.toIso8601String().substring(0, 10),
        'travel_type': travelType,
        'total_amount': total,
        'status': 'pending',
        'claim_number': 'TRV-${DateTime.now().millisecondsSinceEpoch}',
      }).select().single();

      final claimId = res['id'];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String? rUrl;
        if (item['receipt'] != null) {
          final file = item['receipt'] as PlatformFile;
          final path = 'travel-claims/$empId/$claimId/${i}_${DateTime.now().millisecondsSinceEpoch}.${file.extension}';
          await supabase.storage.from('claim-documents').upload(path, File(file.path!));
          rUrl = supabase.storage.from('claim-documents').getPublicUrl(path);
        }
        await supabase.from('travel_claim_items').insert({
          'claim_id': claimId,
          'organization_id': orgId,
          'expense_date': item['date'],
          'category': item['category'],
          'description': item['description'],
          'amount': item['amount'],
          'receipt_url': rUrl,
        });
      }

      await supabase.rpc('initialize_workflow', params: {'p_module': 'travel', 'p_target_id': claimId, 'p_org_id': orgId});
      widget.onCancel();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: EmployeeUi.cardDecoration(),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text("New Travel Claim", style: EmployeeUi.title(18)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel)]),
          const SizedBox(height: 20),
          TextFormField(controller: _purposeController, decoration: const InputDecoration(labelText: "Trip Purpose", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Purpose required" : null),
          const SizedBox(height: 16),
          TextFormField(controller: _destController, decoration: const InputDecoration(labelText: "Destination", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Destination required" : null),
          const SizedBox(height: 16),
          TextFormField(controller: _fromLocController, decoration: const InputDecoration(labelText: "From Location", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "From Location required" : null),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: fromDate, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => fromDate = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: "From Date", border: OutlineInputBorder()), child: Text(DateFormat('yyyy-MM-dd').format(fromDate))),
            )),
            const SizedBox(width: 12),
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: toDate, firstDate: fromDate, lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => toDate = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: "To Date", border: OutlineInputBorder()), child: Text(DateFormat('yyyy-MM-dd').format(toDate))),
            )),
          ]),
          const SizedBox(height: 24),
          Text("Expense Items", style: EmployeeUi.title(16)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => _buildItemRow(entry.key, entry.value)),
          TextButton.icon(onPressed: () => setState(() => items.add({'date': DateFormat('yyyy-MM-dd').format(fromDate), 'category': 'Hotel', 'description': '', 'amount': 0.0, 'receipt': null})), icon: const Icon(Icons.add), label: const Text("Add Item")),
          const SizedBox(height: 24),
          submitting ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  Widget _buildItemRow(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextFormField(initialValue: item['description'], decoration: const InputDecoration(hintText: "Description"), onChanged: (v) => item['description'] = v)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextFormField(initialValue: item['amount'].toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Amount"), onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0))),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => setState(() => items.removeAt(index))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: InkWell(
            onTap: () async {
              final res = await FilePicker.platform.pickFiles();
              if (res != null) setState(() => item['receipt'] = res.files.first);
            },
            child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4)), child: Row(children: [Icon(Icons.attach_file, size: 14, color: EmployeeUi.primary), const SizedBox(width: 8), Expanded(child: Text(item['receipt']?.name ?? "Upload Receipt", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))])),
          )),
        ]),
      ]),
    );
  }
}

class ExpenseClaimsList extends StatelessWidget {
  final String email;
  final supabase = Supabase.instance.client;
  ExpenseClaimsList({required this.email, Key? key}) : super(key: key);

  Future<List<dynamic>> fetchClaims() async {
    final emp = await supabase.from('employee_records').select('id').eq('email', email).maybeSingle();
    if (emp == null) return [];
    return await supabase.from('expense_claims').select('*, expense_categories!category_id(category_name)').eq('employee_id', emp['id']).order('created_at', ascending: false) ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchClaims(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const SkeletonTravelClaimsList();
        final claims = snapshot.data ?? [];
        if (claims.isEmpty) return Center(child: Column(children: [const SizedBox(height: 60), SvgPicture.asset("assets/icons/payroll.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)), const SizedBox(height: 20), Text("No expense claims found", style: GoogleFonts.montserrat(color: Colors.black54))]));
        return Column(children: claims.map((cl) => _buildClaimCard(context, cl)).toList());
      },
    );
  }

  Widget _buildClaimCard(BuildContext context, dynamic cl) {
    final status = (cl['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.grey;
    if (status == 'approved' || status == 'paid') statusColor = Colors.green;
    else if (status == 'pending') statusColor = Colors.orange;
    else if (status == 'rejected') statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(cl['title'] ?? 'EXP-REF', style: EmployeeUi.title(15)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
          ]),
          const SizedBox(height: 12),
          Text("Category: ${cl['expense_categories']?['category_name'] ?? '-'}", style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("₹${NumberFormat('#,##,###').format(cl['total_amount'] ?? 0)}", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
            Text(DateFormat('yyyy-MM-dd').format(DateTime.parse(cl['expense_date'])), style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black38)),
          ]),
        ],
      ),
    );
  }
}

class ExpenseClaimForm extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onCancel;
  const ExpenseClaimForm({required this.userData, required this.onCancel, Key? key}) : super(key: key);
  @override State<ExpenseClaimForm> createState() => _ExpenseClaimFormState();
}

class _ExpenseClaimFormState extends State<ExpenseClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  DateTime expenseDate = DateTime.now();
  String? selectedCategoryId;
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> items = [];
  bool submitting = false;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    items = [{'description': '', 'amount': 0.0, 'receipt': null}];
  }

  Future<void> _fetchCategories() async {
    final orgId = widget.userData['organization_id'];
    final res = await supabase.from('expense_categories').select().eq('organization_id', orgId).eq('is_active', true);
    setState(() => categories = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a category")));
      return;
    }
    setState(() => submitting = true);
    try {
      final empId = widget.userData['id'] ?? widget.userData['employee_id'];
      final orgId = widget.userData['organization_id'];
      final total = items.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));
      
      final res = await supabase.from('expense_claims').insert({
        'employee_id': empId,
        'organization_id': orgId,
        'category_id': selectedCategoryId,
        'title': _titleController.text,
        'total_amount': total,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
        'status': 'pending',
        'submitted_at': DateTime.now().toIso8601String(),
      }).select().single();

      final claimId = res['id'];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String? rUrl;
        if (item['receipt'] != null) {
          final file = item['receipt'] as PlatformFile;
          final path = 'expense-claims/$empId/$claimId/${i}_${DateTime.now().millisecondsSinceEpoch}.${file.extension}';
          await supabase.storage.from('claim-documents').upload(path, File(file.path!));
          rUrl = supabase.storage.from('claim-documents').getPublicUrl(path);
        }
        await supabase.from('expense_claim_items').insert({
          'claim_id': claimId,
          'organization_id': orgId,
          'description': item['description'],
          'amount': item['amount'],
          'receipt_url': rUrl,
          'expense_date': expenseDate.toIso8601String().substring(0, 10),
        });
      }

      await supabase.rpc('initialize_workflow', params: {'p_module': 'expenses', 'p_target_id': claimId, 'p_org_id': orgId});
      widget.onCancel();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: EmployeeUi.cardDecoration(),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text("New Expense Claim", style: EmployeeUi.title(18)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel)]),
          const SizedBox(height: 20),
          TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: "Claim Title", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Title required" : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
            value: selectedCategoryId,
            items: categories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['category_name'] ?? ''))).toList(),
            onChanged: (v) => setState(() => selectedCategoryId = v),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: expenseDate, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
              if (d != null) setState(() => expenseDate = d);
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: "Expense Date", border: OutlineInputBorder()), child: Text(DateFormat('yyyy-MM-dd').format(expenseDate))),
          ),
          const SizedBox(height: 24),
          Text("Expense Items", style: EmployeeUi.title(16)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => _buildItemRow(entry.key, entry.value)),
          TextButton.icon(onPressed: () => setState(() => items.add({'description': '', 'amount': 0.0, 'receipt': null})), icon: const Icon(Icons.add), label: const Text("Add Item")),
          const SizedBox(height: 24),
          submitting ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  Widget _buildItemRow(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextFormField(initialValue: item['description'], decoration: const InputDecoration(hintText: "Description"), onChanged: (v) => item['description'] = v)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextFormField(initialValue: item['amount'].toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Amount"), onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0))),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => setState(() => items.removeAt(index))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: InkWell(
            onTap: () async {
              final res = await FilePicker.platform.pickFiles();
              if (res != null) setState(() => item['receipt'] = res.files.first);
            },
            child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4)), child: Row(children: [Icon(Icons.attach_file, size: 14, color: EmployeeUi.primary), const SizedBox(width: 8), Expanded(child: Text(item['receipt']?.name ?? "Upload Receipt", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))])),
          )),
        ]),
      ]),
    );
  }
}
