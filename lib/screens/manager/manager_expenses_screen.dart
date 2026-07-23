import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../widgets/manager_drawer.dart';
import '../../widgets/drawer_route.dart';

class ManagerExpensesScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const ManagerExpensesScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<ManagerExpensesScreen> createState() => _ManagerExpensesScreenState();
}

class _ManagerExpensesScreenState extends State<ManagerExpensesScreen> {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String activeAction = 'none'; // none, my_expenses, submit, approvals, all_claims
  bool loading = true;
  int pendingCount = 0;

  String? employeeId, organizationId, empRole;
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => loading = true);
    try {
      employeeId = widget.userData['id']?.toString();
      organizationId = widget.userData['organization_id']?.toString();
      empRole = widget.userData['emp_role']?.toString();

      await Future.wait([
        _fetchApprovalCount(),
        _fetchCategories(),
      ]);
    } catch (e) {
      debugPrint("Error initializing manager expenses: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchApprovalCount() async {
    try {
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': employeeId});
      List<String> teamIds = [];
      if (hierarchy is List) {
        teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      }

      var query = supabase.from('expense_claims').select('id').inFilter('status', ['pending', 'manager_approved']);
      
      if (teamIds.isNotEmpty) {
        query = query.or('manager_id.eq.$employeeId,employee_id.in.(${teamIds.join(",")})');
      } else {
        query = query.eq('manager_id', employeeId!);
      }

      final res = await query;
      if (mounted) setState(() => pendingCount = (res as List).length);
    } catch (e) {
      debugPrint("Error fetching expense approval counts: $e");
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await supabase.from('expense_categories').select().eq('organization_id', organizationId!).eq('is_active', true);
      categories = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint("Error fetching expense categories: $e");
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
        currentRoute: DrawerRoute.expenses,
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
          colors: [const Color(0xFFD7E8FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Rewards that feel personal",
            style: GoogleFonts.playfairDisplay(color: const Color(0xFF444444), fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Track reimbursements, submit business expenses, and manage team claims in one place.",
            style: GoogleFonts.montserrat(color: const Color(0xFF666666), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final bool isApprover = ['manager', 'reviewer', 'hr', 'hr_manager', 'hr_head', 'admin'].contains(empRole?.toLowerCase());
    final bool isAdmin = ['admin', 'hr_head'].contains(empRole?.toLowerCase());

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.9,
      children: [
        _actionCard("My Expenses", "View your reimbursement history.", Icons.receipt_long, const Color(0xFFDFF6E5), 'my_expenses'),
        _actionCard("Submit Claim", "Raise a new expense claim.", Icons.add_circle_outline, const Color(0xFFD4F3F7), 'submit'),
        if (isApprover) _actionCard("Approvals", "Review pending team expenses.", Icons.fact_check_outlined, const Color(0xFFFFECE6), 'approvals', badge: pendingCount),
        if (isAdmin) _actionCard("All Claims", "Organization-wide expense view.", Icons.analytics_outlined, const Color(0xFFF5F5F5), 'all_claims'),
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
          color: color,
          borderRadius: BorderRadius.circular(20),
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
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.black87, size: 24),
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Color(0xFFEB5757), shape: BoxShape.circle),
                      child: Text(badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(label, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Expanded(
              child: Text(desc, style: GoogleFonts.montserrat(fontSize: 10, color: Colors.black54, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
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
      case 'my_expenses':
        title = "My Expenses";
        child = MyExpensesPanel(employeeId: employeeId!);
        break;
      case 'submit':
        title = "Submit Expense Claim";
        child = SubmitExpensePanel(
          employeeId: employeeId!,
          organizationId: organizationId!,
          categories: categories,
          onSuccess: () {
            setState(() => activeAction = 'none');
            _initData();
          },
        );
        break;
      case 'approvals':
        title = "Expense Approvals";
        child = ExpenseApprovalPanel(userData: widget.userData, onBack: () => setState(() => activeAction = 'none'));
        break;
      case 'all_claims':
        title = "All Claims";
        child = AllExpensesPanel(organizationId: organizationId!);
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

// 🔵 My Expenses Panel
class MyExpensesPanel extends StatefulWidget {
  final String employeeId;
  const MyExpensesPanel({super.key, required this.employeeId});

  @override
  State<MyExpensesPanel> createState() => _MyExpensesPanelState();
}

class _MyExpensesPanelState extends State<MyExpensesPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> claims = [];

  @override
  void initState() {
    super.initState();
    _fetchClaims();
  }

  Future<void> _fetchClaims() async {
    try {
      final res = await supabase.from('expense_claims').select('*, expense_categories!category_id(category_name)').eq('employee_id', widget.employeeId).order('created_at', ascending: false);
      if (mounted) setState(() => claims = res);
    } catch (e) {
      debugPrint("Error fetching my expenses: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (claims.isEmpty) return Center(child: Text("No expense claims found", style: GoogleFonts.montserrat(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: claims.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final claim = claims[index];
        final status = (claim['status'] ?? 'pending').toString().toLowerCase();
        
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade100)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade100)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(claim['claim_number'] ?? 'EXP-NEW', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade700)),
                _statusBadge(status),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(claim['title'] ?? 'Expense', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                Text(claim['expense_categories']?['category_name'] ?? '-', style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey)),
              ],
            ),
            children: [
              _buildClaimItems(claim['id']),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                    Text("₹${NumberFormat('#,##,###.00').format(claim['total_amount'] ?? 0)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue.shade800)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClaimItems(String claimId) {
    return FutureBuilder(
      future: supabase.from('expense_claim_items').select().eq('claim_id', claimId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final items = snapshot.data as List;
        return Column(
          children: items.map((item) => ListTile(
            dense: true,
            title: Text(item['description'] ?? 'Item', style: const TextStyle(fontSize: 12)),
            subtitle: Text(item['expense_date'] ?? '', style: const TextStyle(fontSize: 10)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("₹${item['amount']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                if (item['receipt_url'] != null)
                  IconButton(icon: const Icon(Icons.receipt, size: 16, color: Colors.blue), onPressed: () {}),
              ],
            ),
          )).toList(),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'draft': color = Colors.grey; break;
      case 'pending': color = const Color(0xFFF2994A); break;
      case 'manager_approved': color = const Color(0xFF2F80ED); break;
      case 'approved': case 'paid': color = const Color(0xFF219653); break;
      case 'rejected': color = const Color(0xFFEB5757); break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase().replaceAll('_', ' '), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}

// 🟢 Submit Expense Panel
class SubmitExpensePanel extends StatefulWidget {
  final String employeeId;
  final String organizationId;
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSuccess;

  const SubmitExpensePanel({super.key, required this.employeeId, required this.organizationId, required this.categories, required this.onSuccess});

  @override
  State<SubmitExpensePanel> createState() => _SubmitExpensePanelState();
}

class _SubmitExpensePanelState extends State<SubmitExpensePanel> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  String? title;
  String? selectedCategoryId;
  String? description;
  DateTime expenseDate = DateTime.now();
  
  List<Map<String, dynamic>> items = [{'description': '', 'amount': 0.0, 'receipt': null}];
  bool submitting = false;

  @override
  Widget build(BuildContext context) {
    double totalAmount = items.fold(0, (sum, item) => sum + (item['amount'] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldTitle("Title *"),
            TextFormField(
              decoration: _inputDecoration(hint: "e.g. Travel to client site"),
              onChanged: (v) => title = v,
              validator: (v) => v!.isEmpty ? "Required" : null,
            ),
            const SizedBox(height: 16),
            _fieldTitle("Category *"),
            DropdownButtonFormField<String>(
              items: widget.categories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['category_name']))).toList(),
              onChanged: (v) => setState(() => selectedCategoryId = v),
              decoration: _inputDecoration(),
              validator: (v) => v == null ? "Required" : null,
            ),
            const SizedBox(height: 16),
            _fieldTitle("Expense Date"),
            TextFormField(
              readOnly: true,
              decoration: _inputDecoration(hint: DateFormat('dd MMM yyyy').format(expenseDate)),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: expenseDate, firstDate: DateTime(2023), lastDate: DateTime.now());
                if (d != null) setState(() => expenseDate = d);
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Line Items", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(onPressed: () => setState(() => items.add({'description': '', 'amount': 0.0, 'receipt': null})), icon: const Icon(Icons.add), label: const Text("Add Item")),
              ],
            ),
            ...items.asMap().entries.map((entry) => _buildLineItem(entry.key, entry.value)),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total Claim Amount", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                  Text("₹${NumberFormat('#,##,###.00').format(totalAmount)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blue.shade800)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: submitting ? null : () => _submit('pending'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E90FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: submitting ? null : () => _submit('draft'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Save as Draft"),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItem(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: TextFormField(decoration: _inputDecoration(hint: "Description"), onChanged: (v) => item['description'] = v)),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: TextFormField(keyboardType: TextInputType.number, decoration: _inputDecoration(hint: "Amount"), onChanged: (v) => setState(() => item['amount'] = double.tryParse(v) ?? 0.0))),
              IconButton(onPressed: () => setState(() => items.removeAt(index)), icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
              if (res != null) setState(() => item['receipt'] = res.files.first);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(item['receipt']?.name ?? "Attach Receipt", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const Spacer(),
                  if (item['receipt'] != null) const Icon(Icons.check_circle, size: 16, color: Colors.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(String status) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      final total = items.fold(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));
      
      final claimRes = await supabase.from('expense_claims').insert({
        'employee_id': widget.employeeId,
        'organization_id': widget.organizationId,
        'category_id': selectedCategoryId,
        'title': title,
        'total_amount': total,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
        'status': status,
        'submitted_at': status == 'pending' ? DateTime.now().toIso8601String() : null,
      }).select().single();

      final claimId = claimRes['id'];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String? receiptUrl;
        if (item['receipt'] != null) {
          final file = item['receipt'] as PlatformFile;
          final path = '${widget.employeeId}/$claimId/${i}_${DateTime.now().millisecondsSinceEpoch}.${file.extension}';
          await supabase.storage.from('expense-receipts').upload(path, File(file.path!));
          receiptUrl = supabase.storage.from('expense-receipts').getPublicUrl(path);
        }

        await supabase.from('expense_claim_items').insert({
          'claim_id': claimId,
          'organization_id': widget.organizationId,
          'description': item['description'],
          'amount': item['amount'],
          'receipt_url': receiptUrl,
          'expense_date': expenseDate.toIso8601String().substring(0, 10),
        });
      }

      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  Widget _fieldTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13)));
}

// 🟠 Expense Approval Panel
class ExpenseApprovalPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  const ExpenseApprovalPanel({super.key, required this.userData, required this.onBack});

  @override
  State<ExpenseApprovalPanel> createState() => _ExpenseApprovalPanelState();
}

class _ExpenseApprovalPanelState extends State<ExpenseApprovalPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> claims = [];

  @override
  void initState() {
    super.initState();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    setState(() => loading = true);
    try {
      final myId = widget.userData['id'];
      final hierarchy = await supabase.rpc('get_manager_full_hierarchy', params: {'p_manager_id': myId});
      List<String> teamIds = [];
      if (hierarchy is List) {
        teamIds = hierarchy.map((i) => (i is Map ? i['id'] : i).toString()).toList();
      }

      var query = supabase.from('expense_claims').select('*, employee_records!expense_claims_employee_id_fkey(full_name, employee_id), expense_categories!category_id(category_name)');
      
      if (teamIds.isNotEmpty) {
        query = query.or('manager_id.eq.$myId,employee_id.in.(${teamIds.join(",")})');
      } else {
        query = query.eq('manager_id', myId!);
      }

      final res = await query.inFilter('status', ['pending', 'manager_approved']).order('created_at', ascending: false);
      if (mounted) setState(() => claims = res);
    } catch (e) {
      debugPrint("Error fetching expense approvals: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _handleAction(dynamic claim, String action, String comments) async {
    try {
      final isHR = ['hr', 'hr_manager', 'hr_head', 'admin'].contains(widget.userData['emp_role']?.toString().toLowerCase());
      String nextStatus = action == 'approve' ? (isHR ? 'approved' : 'manager_approved') : 'rejected';
      
      Map<String, dynamic> updates = {
        'status': nextStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (isHR) {
        updates['hr_approver_id'] = widget.userData['id'];
        updates['hr_approved_at'] = DateTime.now().toIso8601String();
        updates['hr_comments'] = comments;
      } else {
        updates['manager_id'] = widget.userData['id'];
        updates['manager_approved_at'] = DateTime.now().toIso8601String();
        updates['manager_comments'] = comments;
      }

      await supabase.from('expense_claims').update(updates).eq('id', claim['id']);
      _fetchApprovals();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: loading 
            ? const Center(child: CircularProgressIndicator())
            : claims.isEmpty 
              ? const Center(child: Text("No pending expense claims"))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: claims.length,
                  itemBuilder: (context, index) {
                    final claim = claims[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text(claim['employee_records']?['full_name'] ?? 'Employee', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                        subtitle: Text("${claim['title']} • ${claim['expense_categories']?['category_name']}"),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("₹${NumberFormat('#,##,###').format(claim['total_amount'] ?? 0)}", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            TextButton(onPressed: () => _showReviewDialog(claim), child: const Text("Review", style: TextStyle(fontSize: 11))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showReviewDialog(dynamic claim) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Review Expense"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${claim['title']} requested by ${claim['employee_records']?['full_name']}"),
            const SizedBox(height: 12),
            TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: "Comments...")),
          ],
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _handleAction(claim, 'reject', controller.text); }, child: const Text("Reject", style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _handleAction(claim, 'approve', controller.text); }, child: const Text("Approve")),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: InkWell(
        onTap: widget.onBack,
        child: Row(children: [const Icon(Icons.arrow_back, size: 18), const SizedBox(width: 8), Text("Back to inbox", style: GoogleFonts.montserrat(fontWeight: FontWeight.bold))]),
      ),
    );
  }
}

// ⚪ All Expenses Panel
class AllExpensesPanel extends StatefulWidget {
  final String organizationId;
  const AllExpensesPanel({super.key, required this.organizationId});

  @override
  State<AllExpensesPanel> createState() => _AllExpensesPanelState();
}

class _AllExpensesPanelState extends State<AllExpensesPanel> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<dynamic> claims = [];

  @override
  void initState() {
    super.initState();
    _fetchClaims();
  }

  Future<void> _fetchClaims() async {
    try {
      final res = await supabase.from('expense_claims').select('*, employee_records!expense_claims_employee_id_fkey(full_name, employee_id)').eq('organization_id', widget.organizationId).order('created_at', ascending: false);
      if (mounted) setState(() => claims = res);
    } catch (e) {
      debugPrint("Error fetching all expenses: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: claims.length,
      itemBuilder: (context, index) {
        final claim = claims[index];
        return ListTile(
          title: Text(claim['employee_records']?['full_name'] ?? 'Unknown', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          subtitle: Text("${claim['claim_number']} • ${claim['status']?.toUpperCase()}"),
          trailing: Text("₹${NumberFormat('#,##,###').format(claim['total_amount'] ?? 0)}"),
        );
      },
    );
  }
}
