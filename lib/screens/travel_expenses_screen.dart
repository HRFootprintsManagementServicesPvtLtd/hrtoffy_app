import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api/api_client.dart';
import '../repositories/expense_repository.dart';
import '../repositories/travel_repository.dart';
import '../repositories/workflow_repository.dart';
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
// Data comes from the HR Toffy API (TravelRepository / ExpenseRepository):
//   * travel claims  : GET/POST /travel/claims, lines via POST /travel-expenses (one call per line)
//   * expense claims : GET/POST /expenses (lines in the same request), categories via GET /expenses/categories
//   * receipts       : Files API, buckets travel-receipts / expense-receipts (private; the stored value is the file reference)
//   * claim_number is assigned by the server; employee and organization come from the signed-in session
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

/// A short message that is safe to show: nothing about URLs, tokens or the server's internals.
String _errorText(Object e, String fallback) {
  if (e is TravelClaimIncompleteException) {
    return 'Some expense lines could not be saved and the claim may be incomplete. Please check your travel claims list and contact HR.';
  }
  if (e is ApiException) {
    if (e.isNetworkError) return 'No connection. Please check your internet and try again.';
    if (e.isServerError || e.isUnauthorized) return fallback;
    return e.message.isEmpty ? fallback : e.message;
  }
  if (e is StateError) return e.message;
  return fallback;
}

/// What the employee sees when an EXPENSE CLAIM could not be submitted: by status, never the server's text.
/// The server answers a 5xx when the database refuses the claim under the organization's expense policy (a category that
/// requires a receipt but none is attached, a category monthly limit, a missing or inactive category): the same error as any
/// server fault, so the message says what is worth checking instead of a bare "failed".
String expenseSubmitErrorMessage(Object e) {
  // A receipt that could not be uploaded: the claim was not created. Say which kind of problem it is, and never
  // suggest that receipts work when the receipt service is not on the server.
  if (e is ReceiptUploadException) {
    if (e.serviceUnavailable) {
      return "Receipts can't be uploaded from the app right now (the receipt service isn't available). Your claim was not submitted. Remove the receipt, or submit this claim on the website.";
    }
    if (e.statusCode == 0) return 'No connection. The receipt was not uploaded and your claim was not submitted.';
    return "The receipt couldn't be uploaded, so your claim was not submitted. Please try again.";
  }
  if (e is ApiException) {
    if (e.isNetworkError) return 'No connection. Please check your internet and try again.';
    if (e.isUnauthorized) return 'Session expired. Please sign in again.';
    if (e.isForbidden) return "You can't submit this claim. Please contact HR.";
    if (e.isNotFound) return 'The selected category is no longer available. Please choose another one.';
    if (e.statusCode == 400 || e.statusCode == 422) return 'Please check the claim details and try again.';
    if (e.isServerError) {
      return "The claim wasn't accepted. It may need a receipt, or be over the category's monthly limit. Attach a receipt or reduce the amount and try again, or contact HR.";
    }
  }
  return _errorText(e, 'Failed to submit expense claim. Please try again.');
}

/// Reads a picked receipt into memory for upload.
Future<ReceiptFile> _readReceipt(PlatformFile file) async {
  final path = file.path;
  if (path == null || path.isEmpty) throw StateError('The selected receipt could not be read. Please pick it again.');
  final ext = (file.extension ?? 'jpg').toLowerCase();
  return ReceiptFile(bytes: await File(path).readAsBytes(), name: file.name, contentType: _mimeFor(ext));
}

// =============================================================================
// TRAVEL CLAIMS — LIST
// =============================================================================

class TravelClaimsList extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final int refreshKey;
  final TravelRepository? repository;
  const TravelClaimsList({required this.email, required this.userData, this.refreshKey = 0, this.repository, Key? key}) : super(key: key);

  @override
  State<TravelClaimsList> createState() => _TravelClaimsListState();
}

class _TravelClaimsListState extends State<TravelClaimsList> {
  late final TravelRepository _travel = widget.repository ?? TravelRepository();
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

  Future<List<dynamic>> _fetch() => _travel.claims();



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
  final TravelRepository? repository;
  const TravelClaimForm({
    required this.email,
    required this.userData,
    required this.onCancel,
    required this.onSuccess,
    this.repository,
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
  late final TravelRepository _travel = widget.repository ?? TravelRepository();

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
      final lines = <TravelLine>[];
      for (final item in items) {
        final file = item['receipt'] as PlatformFile?;
        lines.add(TravelLine(
          expenseDate: item['expense_date'].toString(),
          expenseType: (item['expense_type'] ?? 'Other').toString(),
          description: (item['description'] ?? '').toString(),
          amount: (item['amount'] as num?)?.toDouble() ?? 0.0,
          receipt: file == null ? null : await _readReceipt(file),
        ));
      }

      await _travel.submitClaim(
        tripPurpose: _purposeController.text,
        tripDestination: _destController.text,
        fromLocation: _fromLocController.text,
        tripFromDate: fromDate,
        tripToDate: toDate,
        travelType: travelType,
        lines: lines,
      );

      if (!mounted) return;
      widget.onSuccess();
    } catch (error) {
      debugPrint('[TravelClaim] submit failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade600,
          content: Text(_errorText(error, 'Failed to submit travel claim. Please try again.')),
        ),
      );
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
  final ExpenseRepository? repository;
  const ExpenseClaimsList({required this.email, required this.userData, this.refreshKey = 0, this.repository, Key? key}) : super(key: key);
  @override
  State<ExpenseClaimsList> createState() => _ExpenseClaimsListState();
}

class _ExpenseClaimsListState extends State<ExpenseClaimsList> {
  late final ExpenseRepository _expenses = widget.repository ?? ExpenseRepository();
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
    // Claims carry category_id only: the names come from the category list (best effort).
    List<Map<String, dynamic>> categories = const [];
    try {
      categories = await _expenses.categories();
    } catch (_) {}
    return _expenses.claims(categories: categories);
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
  final ExpenseRepository? repository;

  /// Tests only: starts the approval chain after the claim is stored.
  final WorkflowRepository? workflowRepository;
  const ExpenseClaimForm({
    required this.email,
    required this.userData,
    required this.onCancel,
    required this.onSuccess,
    this.repository,
    this.workflowRepository,
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
  late final ExpenseRepository _expenses = widget.repository ?? ExpenseRepository();
  late final WorkflowRepository _workflows = widget.workflowRepository ?? WorkflowRepository();

  /// The employee's own claims, read to know what is already used this month in a category (policy pre-check).
  List<Map<String, dynamic>> _ownClaims = const [];

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
    try {
      final res = await _expenses.categories();
      if (!mounted) return;
      setState(() => categories = res);
    } catch (_) {
      // The category is optional: the form still works without the list.
    }
    try {
      final own = await _expenses.claims(categories: categories);
      if (mounted) _ownClaims = own;
    } catch (_) {
      // Best effort: without it the monthly-limit check counts only this claim.
    }
  }

  int get _totalReceiptCount => items.where((i) => i['receipt'] != null).length;
  double get _totalAmount => items.fold<double>(0.0, (s, i) => s + ((i['amount'] as num?)?.toDouble() ?? 0.0));

  /// The first thing the organization's expense policy would object to, from the real category rows and what this
  /// employee has already claimed in the category this month (see [expensePolicyIssue]). It is advice, not a block:
  /// the server decides, and only when the organization enforces the policy.
  String? _policyIssue({List<ExpenseLine>? lines}) {
    final total = lines == null ? _totalAmount : lines.fold<double>(0, (s, l) => s + l.amount);
    final hasReceipt = lines == null ? _totalReceiptCount > 0 : lines.any((l) => l.receipt != null);
    final dateRaw = (lines != null && lines.isNotEmpty ? lines.first.expenseDate : items.first['expense_date']).toString();
    final date = DateTime.tryParse(dateRaw) ?? DateTime.now();
    final used = selectedCategoryId == null
        ? 0.0
        : expenseUsedThisMonth(_ownClaims, categoryId: selectedCategoryId!, date: date);
    return expensePolicyIssue(
      categories: categories,
      categoryId: selectedCategoryId,
      total: total,
      usedThisMonth: used,
      hasReceipt: hasReceipt,
    );
  }

  List<Widget> _categoryHints() {
    // The category must be chosen before a hint makes sense (no category is only "required" when submitting).
    if (selectedCategoryId == null) return const [];
    final issue = _policyIssue();
    return [
      if (issue != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(issue, style: GoogleFonts.montserrat(fontSize: 11, color: Colors.orange.shade800)),
        ),
    ];
  }

  /// Warns before sending a claim the policy would object to; true when the employee chooses to submit anyway.
  Future<bool> _confirmDespitePolicy(String issue) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check before submitting'),
        content: Text('$issue\n\nYour organization may reject this claim. Receipts can only be attached when the receipt service is available.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit anyway')),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a claim title")));
      return;
    }
    setState(() => submitting = true);
    try {
      final lines = <ExpenseLine>[];
      for (final item in items) {
        final desc = (item['description'] as String?)?.trim() ?? '';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        // Same as the website: empty lines are skipped (and their receipt is not uploaded).
        if (desc.isEmpty || amount <= 0) continue;
        final file = item['receipt'] as PlatformFile?;
        lines.add(ExpenseLine(
          expenseDate: item['expense_date'].toString(),
          description: desc,
          amount: amount,
          receipt: file == null ? null : await _readReceipt(file),
        ));
      }
      if (lines.isEmpty) throw StateError('At least one valid expense line item is required');

      // The policy pre-check, on the real category data: the employee is told what the organization's policy would
      // object to and chooses. (Whether it is enforced is the server's decision, which the app cannot read.)
      final issue = _policyIssue(lines: lines);
      if (issue != null) {
        final go = await _confirmDespitePolicy(issue);
        if (!go || !mounted) {
          if (mounted) setState(() => submitting = false);
          return;
        }
      }

      final created = await _expenses.createClaim(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: selectedCategoryId,
        lines: lines,
      );

      // The claim is stored. Start its approval chain as a separate step, like the website; a failure here is not a
      // failed claim (the call never throws), it only changes what the employee is told.
      final routed = await _workflows.initialize(WorkflowRepository.expenses, created['id']?.toString());

      if (!mounted) return;
      if (!routed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: const Text("Claim submitted. We couldn't confirm that approval routing started, so your manager may not be notified yet."),
          ),
        );
      }
      widget.onSuccess();
    } catch (e) {
      // Status only (never the server's text or any claim data), so a failure can be told apart in the log.
      debugPrint('[ExpenseClaim] submission failed: ${e is ApiException ? e.statusCode : e.runtimeType}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade600,
          content: Text(expenseSubmitErrorMessage(e)),
        ),
      );
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
          ..._categoryHints(),
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
