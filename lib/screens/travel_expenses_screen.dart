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

// =============================================================================
// TRAVEL & EXPENSES — Flutter parity with website
// =============================================================================
// Source of truth: src/components/expenses/ExpenseClaimForm.tsx
//                  src/components/travel/TravelClaimForm.tsx
//                  src/components/expenses/ExpenseClaimsList.tsx
//                  src/components/travel/TravelClaimsList.tsx
//
// Key rules (do not diverge):
//   * expense_categories column = "name" (NOT category_name)
//   * travel line items table   = "travel_expenses" (NOT travel_claim_items)
//   * expense receipts bucket   = "expense-receipts" (private → SIGNED URL)
//   * travel  receipts bucket   = "travel-receipts"  (private, website uses public URL)
//   * expense receipt path      = {auth.uid()}/{claimId}/{index}_{ts}.{ext}
//   * travel  receipt path      = {employeeId}/{ts}_{index}.{ext}
//   * claim_number is filled by a DB trigger — send empty string ''
//   * DO NOT call initialize_workflow RPC (does not exist in DB)
//   * Employee lookup must scope by user_id + organization_id + status='active'
//   * List queries must scope by organization_id
// =============================================================================

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
  // Bumped whenever a claim is submitted → children refetch.
  int _travelRefresh = 0;
  int _expenseRefresh = 0;

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

  void _handleSubmitSuccess({required bool isTravel, required String label}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.green.shade600,
      content: Text('$label submitted successfully'),
      duration: const Duration(seconds: 2),
    ));
    setState(() {
      showForm = false;
      if (isTravel) {
        _travelRefresh++;
      } else {
        _expenseRefresh++;
      }
    });
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
        onPressed: () {
          // Ensure the form we open matches the visually selected tab,
          // even if the tab animation hasn't fully settled yet.
          final target = _tabController.animation?.value.round() ?? _tabController.index;
          if (_tabController.index != target) {
            _tabController.index = target;
          }
          setState(() => showForm = true);
        },
        backgroundColor: EmployeeUi.primary,
        child: const Icon(Icons.add, color: Colors.white),
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
      child: (showForm && _tabController.index == 0)
          ? TravelClaimForm(
        email: widget.email,
        userData: widget.userData,
        onCancel: () => setState(() => showForm = false),
        onSuccess: () => _handleSubmitSuccess(isTravel: true, label: 'Travel claim'),
      )
          : TravelClaimsList(email: widget.email, userData: widget.userData, refreshKey: _travelRefresh),
    );
  }


  Widget _buildExpenseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: (showForm && _tabController.index == 1)
          ? ExpenseClaimForm(

      email: widget.email,
        userData: widget.userData,
        onCancel: () => setState(() => showForm = false),
        onSuccess: () => _handleSubmitSuccess(isTravel: false, label: 'Expense claim'),
      )
          : ExpenseClaimsList(email: widget.email, userData: widget.userData, refreshKey: _expenseRefresh),
    );
  }
}

// =============================================================================
// Shared helpers
// =============================================================================

class _ClaimContext {
  final String employeeId;
  final String organizationId;
  final String? managerId;
  final String authUid;
  _ClaimContext({
    required this.employeeId,
    required this.organizationId,
    required this.managerId,
    required this.authUid,
  });
}

/// Resolves employee_id / organization_id / manager_id the same way the
/// website does: user_id + organization_id + status='active'.
Future<_ClaimContext?> _resolveClaimContext({
  required Map<String, dynamic> userData,
}) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  debugPrint("========== CLAIM CONTEXT ==========");
  debugPrint("AUTH USER = ${user?.id}");
  debugPrint("USER DATA = $userData");
  if (user == null) return null;

  final orgId = userData['organization_id']?.toString();
  debugPrint("ORG ID = $orgId");
  if (orgId == null || orgId.isEmpty) return null;

  // Website: .eq('user_id', user.id).eq('organization_id', orgId).eq('status', 'active')
  final emp = await supabase
      .from('employee_records')
      .select('id, manager_id')
      .eq('user_id', user.id)
      .eq('organization_id', orgId)
      .eq('status', 'active')
      .maybeSingle();
  debugPrint("EMPLOYEE RECORD = $emp");

  if (emp == null) {
    debugPrint("Employee lookup returned NULL");
    return null;
  }

  if (emp == null) return null;
  return _ClaimContext(
    employeeId: emp['id'].toString(),
    organizationId: orgId,
    managerId: emp['manager_id']?.toString(),
    authUid: user.id,
  );
}

// =============================================================================
// TRAVEL CLAIMS — LIST
// =============================================================================

class TravelClaimsList extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final int refreshKey;
  const TravelClaimsList({required this.email, required this.userData, this.refreshKey = 0, Key? key}) : super(key: key);

  @override
  State<TravelClaimsList> createState() => _TravelClaimsListState();
}

class _TravelClaimsListState extends State<TravelClaimsList> {
  final supabase = Supabase.instance.client;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant TravelClaimsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() => _future = _fetch());
    }
  }

  Future<List<dynamic>> _fetch() async {
    final ctx = await _resolveClaimContext(
      userData: widget.userData,
    );

    debugPrint("===== TRAVEL FETCH =====");
    debugPrint("ctx = $ctx");

    if (ctx == null) {
      debugPrint("Travel context is NULL");
      return [];
    }

    final rows = await supabase
        .from('travel_claims')
        .select('*')
        .eq('employee_id', ctx.employeeId)
        .eq('organization_id', ctx.organizationId)
        .order('created_at', ascending: false);

    debugPrint('Travel rows: $rows');
    return (rows as List?) ?? [];
  }



  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const SkeletonTravelClaimsList();
        final claims = snapshot.data ?? [];
        if (claims.isEmpty) {
          return Center(child: Column(children: [
            const SizedBox(height: 60),
            SvgPicture.asset("assets/icons/travel.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)),
            const SizedBox(height: 20),
            Text("No travel claims found", style: GoogleFonts.montserrat(color: Colors.black54)),
          ]));
        }
        return Column(children: claims.map((cl) => _buildClaimCard(context, cl)).toList());
      },
    );
  }

  Widget _buildClaimCard(BuildContext context, dynamic cl) {
    final status = (cl['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.grey;
    if (status == 'approved' || status == 'paid' || status == 'manager_approved') statusColor = Colors.green;
    else if (status == 'pending') statusColor = Colors.orange;
    else if (status == 'rejected') statusColor = Colors.red;

    // Pastel colors (same style as Loans & Benefits)
    const pastelPalette = [
      Color(0xFFD7E8FF), // Soft Blue
      Color(0xFFFFECE6), // Soft Peach
      Color(0xFFDFF6E5), // Soft Mint
      Color(0xFFFCE4EC), // Soft Pink
      Color(0xFFEBDFF6), // Soft Lavender
      Color(0xFFFFF7D6), // Soft Yellow
    ];

// Pick a color based on the claim number so colors stay stable
    final claimNo = (cl['claim_number'] ?? '').toString();
    final colorIndex = claimNo.hashCode.abs() % pastelPalette.length;

    final baseDecoration = EmployeeUi.cardDecoration();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: (baseDecoration is BoxDecoration)
          ? baseDecoration.copyWith(
        color: pastelPalette[colorIndex],
      )
          : BoxDecoration(
        color: pastelPalette[colorIndex],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text((cl['claim_number']?.toString().isNotEmpty ?? false) ? cl['claim_number'] : 'TRV-DRAFT', style: EmployeeUi.title(15)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(cl['trip_purpose']?.toString() ?? '', style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text("Destination: ${cl['trip_destination'] ?? '-'}", style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("₹${NumberFormat('#,##,###').format(cl['total_amount'] ?? 0)}", style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
            Text("${cl['trip_from_date'] ?? ''} - ${cl['trip_to_date'] ?? ''}", style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black38)),
          ]),
        ],
      ),
    );
  }
}

// =============================================================================
// TRAVEL CLAIM — FORM
// =============================================================================

class TravelClaimForm extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  const TravelClaimForm({
    required this.email,
    required this.userData,
    required this.onCancel,
    required this.onSuccess,
    Key? key,
  }) : super(key: key);
  @override
  State<TravelClaimForm> createState() => _TravelClaimFormState();
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

  // Website expense_type enum values — must match server-side validation.
  static const List<String> _expenseTypes = [
    'Airfare', 'Train Fare', 'Bus Fare', 'Taxi/Cab', 'Hotel',
    'Meals', 'Fuel', 'Toll', 'Parking', 'Other',
  ];

  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    items = [{
      'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'expense_type': 'Meals',
      'description': '',
      'amount': 0.0,
      'receipt': null,
    }];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      debugPrint('[TravelClaim] STEP 1 Resolve employee START');

      final ctx = await _resolveClaimContext(userData: widget.userData);

      if (ctx == null) {
        debugPrint('[TravelClaim] STEP 1 Resolve employee FAILED');
        throw 'Employee context not found';
      }

      debugPrint(
        '[TravelClaim] STEP 1 Resolve employee DONE '
            'employeeId=${ctx.employeeId} '
            'organizationId=${ctx.organizationId} '
            'managerPresent=${ctx.managerId != null}',
      );

      final total = items.fold<double>(0.0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0));
      final totalDays = toDate.difference(fromDate).inDays + 1;

      // === Insert travel claim ===
      // Mirror website payload exactly. claim_number is filled by DB trigger.
      final claimPayload = <String, dynamic>{
        'claim_number': '',
        'employee_id': ctx.employeeId,
        'organization_id': ctx.organizationId,
        'manager_id': ctx.managerId,
        'trip_purpose': _purposeController.text,
        'trip_destination': _destController.text,
        'from_location': _fromLocController.text,
        'trip_from_date': DateFormat('yyyy-MM-dd').format(fromDate),
        'trip_to_date': DateFormat('yyyy-MM-dd').format(toDate),
        'total_days': totalDays,
        'travel_type': travelType,
        'total_amount': total,
        'status': 'pending',
      };

      debugPrint(
        '[TravelClaim] STEP 3 Insert travel_claim START '
            'employeeId=${ctx.employeeId} '
            'organizationId=${ctx.organizationId} '
            'managerPresent=${ctx.managerId != null} '
            'itemCount=${items.length} '
            'total=$total',
      );

      final claim = await supabase
          .from('travel_claims')
          .insert(claimPayload)
          .select('id, claim_number')
          .single();

      final claimId = claim['id'].toString();

      debugPrint(
        '[TravelClaim] STEP 3 Insert travel_claim DONE '
            'claimId=$claimId claimNumber=${claim['claim_number']}',
      );

      // === Upload receipts & insert line items into travel_expenses ===
      // (website table = "travel_expenses", NOT "travel_claim_items")
      final List<Map<String, dynamic>> expensesToInsert = [];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String? receiptUrl;

        if (item['receipt'] != null) {
          debugPrint('[TravelClaim] STEP 2 Upload receipt START index=$i');

          final file = item['receipt'] as PlatformFile;
          final filePath = file.path;

          if (filePath == null || filePath.isEmpty) {
            debugPrint(
              '[TravelClaim] STEP 2 Upload receipt FAILED '
                  'index=$i reason=missing-local-path',
            );
            throw StateError('Selected receipt has no readable local path');
          }

          final ext = (file.extension ?? 'jpg').toLowerCase();
          final path =
              '${ctx.employeeId}/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

          final bytes = await File(filePath).readAsBytes();

          await supabase.storage.from('travel-receipts').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _mimeFor(ext),
              upsert: false,
            ),
          );

          receiptUrl =
              supabase.storage.from('travel-receipts').getPublicUrl(path);

          debugPrint(
            '[TravelClaim] STEP 2 Upload receipt DONE '
                'index=$i path=$path bytes=${bytes.length}',
          );
        }


        expensesToInsert.add({
          'claim_id': claimId,
          'organization_id': ctx.organizationId,
          'expense_date': item['expense_date'],
          'expense_type': item['expense_type'] ?? 'Other',
          'description': item['description'] ?? '',
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
          'receipt_url': receiptUrl,
        });
      }
      debugPrint(
        '[TravelClaim] STEP 4 Insert travel_expenses START '
            'claimId=$claimId rowCount=${expensesToInsert.length}',
      );

      if (expensesToInsert.isNotEmpty) {
        await supabase
            .from('travel_expenses')
            .insert(expensesToInsert);
      }

      debugPrint(
        '[TravelClaim] STEP 4 Insert travel_expenses DONE '
            'claimId=$claimId rowCount=${expensesToInsert.length}',
      );

      debugPrint('[TravelClaim] STEP 5 Finalize START claimId=$claimId');

      widget.onSuccess();

      debugPrint('[TravelClaim] STEP 5 Finalize DONE claimId=$claimId');

    } catch (error, stackTrace) {
      debugPrint('[TravelClaim] SUBMIT FAILED error=$error');
      debugPrint('[TravelClaim] SUBMIT FAILED stackTrace=$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade600,
          content: Text('Failed to submit travel claim: $error'),
        ),
      );
    }
    finally {
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
          TextFormField(controller: _purposeController, decoration: const InputDecoration(labelText: "Trip Purpose", border: OutlineInputBorder()), validator: (v) => (v == null || v.isEmpty) ? "Purpose required" : null),
          const SizedBox(height: 16),
          TextFormField(controller: _destController, decoration: const InputDecoration(labelText: "Destination", border: OutlineInputBorder()), validator: (v) => (v == null || v.isEmpty) ? "Destination required" : null),
          const SizedBox(height: 16),
          TextFormField(controller: _fromLocController, decoration: const InputDecoration(labelText: "From Location", border: OutlineInputBorder()), validator: (v) => (v == null || v.isEmpty) ? "From Location required" : null),
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
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: "Travel Type", border: OutlineInputBorder()),
            value: travelType,
            items: const [
              DropdownMenuItem(value: 'domestic', child: Text('Domestic')),
              DropdownMenuItem(value: 'international', child: Text('International')),
            ],
            onChanged: (v) => setState(() => travelType = v ?? 'domestic'),
          ),
          const SizedBox(height: 24),
          Text("Expense Items", style: EmployeeUi.title(16)),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => _buildItemRow(entry.key, entry.value)),
          TextButton.icon(
            onPressed: () => setState(() => items.add({
              'expense_date': DateFormat('yyyy-MM-dd').format(fromDate),
              'expense_type': 'Other',
              'description': '',
              'amount': 0.0,
              'receipt': null,
            })),
            icon: const Icon(Icons.add), label: const Text("Add Item"),
          ),
          const SizedBox(height: 24),
          submitting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
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
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: (item['expense_type'] as String?) ?? 'Other',
              isDense: true,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              items: _expenseTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => setState(() => item['expense_type'] = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: item['amount'].toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: "Amount", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
              onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0),
            ),
          ),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => setState(() => items.removeAt(index))),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: item['description'],
          decoration: const InputDecoration(hintText: "Description", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), isDense: true),
          onChanged: (v) => item['description'] = v,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
            );
            if (res != null) setState(() => item['receipt'] = res.files.first);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              Icon(Icons.attach_file, size: 14, color: EmployeeUi.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(item['receipt']?.name ?? "Upload Receipt", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// EXPENSE CLAIMS — LIST
// =============================================================================

class ExpenseClaimsList extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final int refreshKey;
  const ExpenseClaimsList({required this.email, required this.userData, this.refreshKey = 0, Key? key}) : super(key: key);
  @override
  State<ExpenseClaimsList> createState() => _ExpenseClaimsListState();
}

class _ExpenseClaimsListState extends State<ExpenseClaimsList> {
  final supabase = Supabase.instance.client;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant ExpenseClaimsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() => _future = _fetch());
    }
  }

  Future<List<dynamic>> _fetch() async {
    debugPrint("===== EXPENSE FETCH VIA RPC =====");
    debugPrint("userData = ${widget.userData}");

    final orgId = widget.userData['organization_id']?.toString();

    final rows = await supabase.rpc(
      'get_my_expense_claims',
      params: {
        '_organization_id': (orgId == null || orgId.isEmpty) ? null : orgId,
      },
    );

    debugPrint('Expense rows from RPC: $rows');
    return (rows as List?) ?? [];
  }


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const SkeletonTravelClaimsList();
        final claims = snapshot.data ?? [];
        if (claims.isEmpty) {
          return Center(child: Column(children: [
            const SizedBox(height: 60),
            SvgPicture.asset("assets/icons/payroll.svg", width: 80, colorFilter: const ColorFilter.mode(Colors.blueGrey, BlendMode.srcIn)),
            const SizedBox(height: 20),
            Text("No expense claims found", style: GoogleFonts.montserrat(color: Colors.black54)),
          ]));
        }
        return Column(children: claims.map((cl) => _buildClaimCard(context, cl)).toList());
      },
    );
  }

  Widget _buildClaimCard(BuildContext context, dynamic cl) {
    final status = (cl['status'] ?? '').toString().toLowerCase();
    Color statusColor = Colors.grey;
    if (status == 'approved' || status == 'paid' || status == 'manager_approved') statusColor = Colors.green;
    else if (status == 'pending') statusColor = Colors.orange;
    else if (status == 'rejected') statusColor = Colors.red;
    const pastelPalette = [
      Color(0xFFD7E8FF), // Soft Blue
      Color(0xFFFFECE6), // Soft Peach
      Color(0xFFDFF6E5), // Soft Mint
      Color(0xFFFCE4EC), // Soft Pink
      Color(0xFFEBDFF6), // Soft Lavender
      Color(0xFFFFF7D6), // Soft Yellow
    ];

    final colorSeed =
    (cl['claim_number'] ??
        cl['id'] ??
        cl['title'] ??
        '')
        .toString();

    final colorIndex =
        colorSeed.hashCode.abs() % pastelPalette.length;

    final baseDecoration = EmployeeUi.cardDecoration();

    // Website shows created_at (safer than expense_date which is often null).
    String dateLabel = '';
    final createdAt = (cl['created_at'] ?? cl['expense_date'])?.toString();
    if (createdAt != null && createdAt.isNotEmpty) {
      try { dateLabel = DateFormat('yyyy-MM-dd').format(DateTime.parse(createdAt)); } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: (baseDecoration is BoxDecoration)
          ? baseDecoration.copyWith(
        color: pastelPalette[colorIndex],
      )
          : BoxDecoration(
        color: pastelPalette[colorIndex],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(cl['title']?.toString() ?? 'Expense Claim', style: EmployeeUi.title(15)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 12),
          Text("Category: ${cl['category_name'] ?? cl['expense_categories']?['name'] ?? 'Uncategorized'}",
              style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("₹${NumberFormat('#,##,###').format(cl['total_amount'] ?? cl['amount'] ?? 0)}",
                style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold, color: EmployeeUi.primary)),
            Text(dateLabel, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black38)),
          ]),
        ],
      ),
    );
  }
}

// =============================================================================
// EXPENSE CLAIM — FORM
// =============================================================================

class ExpenseClaimForm extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  const ExpenseClaimForm({
    required this.email,
    required this.userData,
    required this.onCancel,
    required this.onSuccess,
    Key? key,
  }) : super(key: key);
  @override
  State<ExpenseClaimForm> createState() => _ExpenseClaimFormState();
}

class _ExpenseClaimFormState extends State<ExpenseClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? selectedCategoryId;
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> items = [];
  bool submitting = false;
  final supabase = Supabase.instance.client;

  static const int _maxFileBytes = 5 * 1024 * 1024;
  static const int _maxReceiptsPerClaim = 5;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    items = [{
      'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'description': '',
      'amount': 0.0,
      'receipt': null,
    }];
  }

  Future<void> _fetchCategories() async {
    final orgId = widget.userData['organization_id']?.toString();
    if (orgId == null || orgId.isEmpty) return;
    // Website: eq is_active=true, order by "name" (NOT category_name)
    final res = await supabase
        .from('expense_categories')
        .select('id, name, monthly_limit')
        .eq('organization_id', orgId)
        .eq('is_active', true)
        .order('name');
    if (!mounted) return;
    setState(() => categories = List<Map<String, dynamic>>.from(res));
  }

  int get _totalReceiptCount => items.where((i) => i['receipt'] != null).length;
  double get _totalAmount => items.fold<double>(0.0, (s, i) => s + ((i['amount'] as num?)?.toDouble() ?? 0.0));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a claim title")));
      return;
    }
    setState(() => submitting = true);
    try {
      final ctx = await _resolveClaimContext(userData: widget.userData);
      if (ctx == null) throw 'Employee context not found';

      // === Insert expense claim ===
      // claim_number is set by DB trigger.
      final firstItem = items.first;

      final firstExpenseDate = firstItem['expense_date'];

      final firstAmount =
          (firstItem['amount'] as num?)?.toDouble() ?? 0.0;
      final claimIdResult = await supabase.rpc(
        'create_my_expense_claim',
        params: {
          '_employee_id': ctx.employeeId,
          '_organization_id': ctx.organizationId,
          '_category_id': selectedCategoryId,
          '_title': _titleController.text.trim(),
          '_description': _descriptionController.text.trim(),
          '_claim_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          '_expense_date': firstExpenseDate,
          '_amount': firstAmount,
          '_total_amount': _totalAmount,
        },
      );
      final claimId = claimIdResult?.toString();
      if (claimId == null || claimId.isEmpty) {
        throw StateError('Expense claim was not created (empty id returned)');
      }

      // === Upload receipts + insert line items ===
      final List<Map<String, dynamic>> toInsert = [];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final desc = (item['description'] as String?)?.trim() ?? '';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        // Website: skip empty lines
        if (desc.isEmpty || amount <= 0) continue;
        String? receiptUrl;
        if (item['receipt'] != null) {
          final file = item['receipt'] as PlatformFile;
          final ext = (file.extension ?? 'jpg').toLowerCase();
          // Website path: {authUid}/{claimId}/{index}_{ts}.{ext}
          final path = '${ctx.authUid}/$claimId/${i}_${DateTime.now().millisecondsSinceEpoch}.$ext';

          await supabase.storage.from('expense-receipts').uploadBinary(
            path,
            await File(file.path!).readAsBytes(),
            fileOptions: FileOptions(contentType: _mimeFor(ext), upsert: false),
          );
          // Website uses a 1-hour signed URL (bucket is private).
          receiptUrl = await supabase.storage.from('expense-receipts').createSignedUrl(path, 60 * 60);
        }

        toInsert.add({
          'claim_id': claimId,
          'organization_id': ctx.organizationId,
          'expense_date': item['expense_date'],
          'description': desc,
          'amount': amount,
          'receipt_url': receiptUrl,
        });
      }
      if (toInsert.isEmpty) {
        throw Exception('At least one valid expense line item is required');
      }

      debugPrint(
        '[ExpenseClaim] Finalizing claim with ${toInsert.length} item(s)',
      );

      await supabase.rpc(
        'finalize_my_expense_claim',
        params: {
          '_claim_id': claimId,
          '_items': toInsert,
        },
      );

      debugPrint('[ExpenseClaim] Claim submitted successfully');


      // DO NOT call initialize_workflow — RPC does not exist.
      widget.onSuccess();
    } catch (e, stackTrace) {
      debugPrint('[ExpenseClaim] Submission failed: $e');
      debugPrint('[ExpenseClaim] Stack trace: $stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade600,
          content: Text('Failed to submit expense claim: $e'),
        ),
      );
    }
    finally {
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
          TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: "Claim Title *", border: OutlineInputBorder()), validator: (v) => (v == null || v.isEmpty) ? "Title required" : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
            value: selectedCategoryId,
            items: categories.map((c) {
              final limit = (c['monthly_limit'] as num?)?.toDouble() ?? 0.0;
              final label = limit > 0 ? '${c['name']} (Limit: ₹${NumberFormat('#,##,###').format(limit)})' : (c['name']?.toString() ?? '');
              return DropdownMenuItem(value: c['id'].toString(), child: Text(label));
            }).toList(),
            onChanged: (v) => setState(() => selectedCategoryId = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: "Description", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Line Items", style: EmployeeUi.title(16)),
            Text('Receipts: $_totalReceiptCount/$_maxReceiptsPerClaim',
                style: GoogleFonts.montserrat(fontSize: 11, color: Colors.black54)),
          ]),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => _buildItemRow(entry.key, entry.value)),
          TextButton.icon(
            onPressed: () => setState(() => items.add({
              'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
              'description': '',
              'amount': 0.0,
              'receipt': null,
            })),
            icon: const Icon(Icons.add), label: const Text("Add Item"),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: EmployeeUi.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Total", style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
              Text("₹${NumberFormat('#,##,###.##').format(_totalAmount)}",
                  style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: EmployeeUi.primary, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 24),
          submitting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
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
          Expanded(
            child: InkWell(
              onTap: () async {
                final initial = DateTime.tryParse(item['expense_date'] ?? '') ?? DateTime.now();
                final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (d != null) setState(() => item['expense_date'] = DateFormat('yyyy-MM-dd').format(d));
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: "Date", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), isDense: true),
                child: Text(item['expense_date'] ?? '', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: item['amount'].toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: "Amount", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
              onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0),
            ),
          ),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: items.length > 1 ? () => setState(() => items.removeAt(index)) : null),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: item['description'],
          decoration: const InputDecoration(hintText: "Item description", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), isDense: true),
          onChanged: (v) => item['description'] = v,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            if (_totalReceiptCount >= _maxReceiptsPerClaim && item['receipt'] == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Maximum $_maxReceiptsPerClaim receipts per claim')));
              return;
            }
            final res = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
            );
            if (res == null) return;
            final f = res.files.first;
            if ((f.size) > _maxFileBytes) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt must be smaller than 5MB')));
              return;
            }
            setState(() => item['receipt'] = f);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              Icon(Icons.attach_file, size: 14, color: EmployeeUi.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(item['receipt']?.name ?? "Upload Receipt (jpg/png/webp/pdf, max 5MB)", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// MIME helper — matches website validTypes.
// =============================================================================
String _mimeFor(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
