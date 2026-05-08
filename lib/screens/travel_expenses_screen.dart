// travel_expenses_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import '../widgets/drawer_route.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';



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

class _TravelExpensesScreenState extends State<TravelExpensesScreen> {
  bool showForm = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();


  int _bottomTabIndex = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      // ✅ RIGHT SIDE MENU
      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,                 // ✅ FIX
        fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
        currentRoute: DrawerRoute.travel,

        companyLogoUrl: null,
      ),
      appBar: AppBar(
        title: Text("Travel Claims"),
        elevation: 1,
        actions: [
          if (!showForm)
            IconButton(
              icon: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: Colors.white, size: 22),
              ),
              onPressed: () => setState(() => showForm = true),
            ),
          if (showForm)
            IconButton(
              icon: Icon(Icons.close, color: Colors.black),
              onPressed: () => setState(() => showForm = false),
            ),
          // ☰ MENU BUTTON (THIS WAS MISSING)
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          showForm
              ? TravelClaimForm(
            email: widget.email,
            onCancel: () => setState(() => showForm = false),
          )
              : TravelClaimsList(email: widget.email),

          // 🤖 TOFFY OVERLAY
        ],
      ),

      // ✅ BOTTOM NAVIGATION (NEXT STEP)
      bottomNavigationBar: _buildBottomNav(),
    );
  }
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 10,
      unselectedFontSize: 9,
      currentIndex: _bottomTabIndex,
      selectedItemColor: Colors.blueAccent,
      unselectedItemColor: Colors.grey,
      showSelectedLabels: true,
      showUnselectedLabels: true,

      onTap: (index) async {
        if (index == 0) {
          setState(() => _bottomTabIndex = 0);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                email: widget.email,
                employeeId: '',
              ),
            ),
          );
          return;
        }

        if (index == 1) {
          setState(() => _bottomTabIndex = 1);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeavesScreen(
                email: widget.email,
                userData: widget.userData,
                fetchHrmsContext: widget.fetchHrmsContext,
              ),

            ),
          );
          return;
        }

        if (index == 2) {
          setState(() => _bottomTabIndex = 2);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimeAttendanceScreen(
                userEmail: widget.email,
                userData: widget.userData,                 // ✅ FIX
                fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
              ),
            ),
          );
          return;
        }

        if (index == 3) {
          setState(() => _bottomTabIndex = 3);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PayslipScreen(
                userEmail: widget.email,
                userData: widget.userData,
                fetchHrmsContext: widget.fetchHrmsContext,
              ),

            ),
          );
          return;
        }

        if (index == 4) {
          _scaffoldKey.currentState?.openEndDrawer();
          return;
        }



      },

      items: [
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/dashboard.svg",
            width: 22,
            color:
            _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/leaves.svg",
            width: 22,
            color:
            _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Leave',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/attendance.svg",
            width: 22,
            color:
            _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Attendance',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/payroll.svg",
            width: 22,
            color:
            _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
          ),
          label: 'Payslip',
        ),
        BottomNavigationBarItem(
          icon: SvgPicture.asset(
            "assets/icons/menu.svg",
            width: 22,
            color: Colors.grey,
          ),
          label: 'More',
        ),

      ],
    );
  }

}
// CLAIM LIST
class TravelClaimsList extends StatelessWidget {
  final String email;
  final supabase = Supabase.instance.client;
  TravelClaimsList({required this.email, Key? key}) : super(key: key);
  Future<List<dynamic>> fetchClaims() async {
    final emp = await supabase
        .from('employee_records')
        .select('id, organization_id')
        .eq('email', email)
        .maybeSingle();
    if (emp == null) return [];
    final claims = await supabase
        .from('travel_claims')
        .select()
        .eq('employee_id', emp['id'])
        .order('created_at', ascending: false);
    return claims ?? [];
  }
  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 6,
          spreadRadius: 1,
          offset: Offset(0, 2),
        )
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: fetchClaims(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SkeletonTravelClaimsList();
        }
        List claims = snapshot.data ?? [];
        // ------------------------- EMPTY STATE -------------------------
        if (claims.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  "assets/icons/travel.svg",
                  height: 120,
                  width: 120,
                  color: Colors.blueGrey,
                ),
                SizedBox(height: 14),
                Text(
                  "No travel claims found",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }
        // ------------------------- LIST VIEW -------------------------
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          itemCount: claims.length,
          itemBuilder: (ctx, i) {
            final cl = claims[i];
            return Container(
              margin: EdgeInsets.only(bottom: 14),
              decoration: _cardDecoration(),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          cl['claim_number'] ?? '',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SizedBox(width: 8),
                        Chip(
                          label: Text(cl['status']?.toString().toUpperCase() ?? ''),
                          backgroundColor: _statusColor(cl['status']),
                          labelStyle: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          padding:
                          EdgeInsets.symmetric(vertical: 0, horizontal: 6),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.remove_red_eye_outlined),
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => TravelClaimDetailsScreen(
                                    claimId: cl['id'], email: email)));
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(cl['trip_purpose'] ?? '',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 15, color: Colors.blueGrey),
                        SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            cl['trip_destination'] ?? '-',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.calendar_today,
                            size: 15, color: Colors.blueGrey),
                        SizedBox(width: 2),
                        Text(
                          "${cl['trip_from_date'] ?? ''} - ${cl['trip_to_date'] ?? ''}",
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.currency_rupee, size: 15),
                        Text(
                          NumberFormat.currency(symbol: "₹")
                              .format(cl['total_amount'] ?? 0),
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Submitted on ${cl['created_at']?.toString().substring(0, 16) ?? ''}",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'approved':
      case 'paid':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
// CLAIM FORM
class TravelClaimForm extends StatefulWidget {
  final String email;
  final VoidCallback onCancel;
  const TravelClaimForm({required this.email, required this.onCancel, Key? key})
      : super(key: key);
  @override
  State<TravelClaimForm> createState() => _TravelClaimFormState();
}
class _TravelClaimFormState extends State<TravelClaimForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  String? _travelType;

  final TextEditingController _tripPurposeController =
  TextEditingController();

  final TextEditingController _fromLocController =
  TextEditingController();

  final TextEditingController _toLocController =
  TextEditingController();

  DateTime? _fromDate, _toDate;
  List<Map<String, dynamic>> expenses = [];
  bool loading = false;
  String? errorMessage;
  @override
  void initState() {
    super.initState();
    expenses = [
      {
        "expense_date": DateTime.now(),
        "expense_type": "Meals",
        "description": "",
        "amount": 0.0,
        "receipt_file": null,
        "receipt_url": null,
      }
    ];
  }
  // UI decoration helpers
  BoxDecoration _cardBox() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: Offset(0, 3),
        )
      ],
    );
  }
  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Color(0xFFE5E7EB), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Color(0xFFE5E7EB), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.blue, width: 1.3),
      ),
    );
  }
  // ---------------------- Expense Controls ----------------------
  void addExpense() {
    setState(() {
      expenses.add({
        "expense_date": DateTime.now(),
        "expense_type": "Meals",
        "description": "",
        "amount": 0.0,
        "receipt_file": null,
        "receipt_url": null,
      });
    });
  }
  void removeExpense(int index) {
    setState(() {
      expenses.removeAt(index);
    });
  }
  Future<void> pickReceipt(int index) async {
    final result = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (result != null) {
      setState(() {
        expenses[index]["receipt_file"] = result;
      });

      // 🔥 OCR START
      final inputImage = InputImage.fromFilePath(result.path);
      final textRecognizer = TextRecognizer();

      final RecognizedText recognizedText =
      await textRecognizer.processImage(inputImage);

      String extractedText = recognizedText.text;

      debugPrint("OCR TEXT: $extractedText");

      // 🔥 SIMPLE PARSING (Amount + Date)

      // Extract Amount (₹ or numbers)
      // 🔥 OCR TEXT
      String text = recognizedText.text
          .replaceAll('\n\n', '\n')
          .replaceAll(',', '')
          .toLowerCase();

      // --------------------------------------------------
// ✅ VALIDATE TRAVEL RECEIPT
// --------------------------------------------------

      final keywords = [
        "travel",
        "flight",
        "air ticket",
        "airlines",
        "receipt",
        "invoice",
        "booking",
        "trip",
      ];

      bool isTravelReceipt =
      keywords.any((k) => text.contains(k));

      if (!isTravelReceipt) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Invalid travel receipt"),
            backgroundColor: Colors.red,
          ),
        );

        setState(() {
          expenses[index]["receipt_file"] = null;
        });

        await textRecognizer.close();
        return;
      }

// --------------------------------------------------
// ✅ TRIP PURPOSE
// --------------------------------------------------

      _tripPurposeController.text =
      "Business Travel";
      _travelType = "Domestic";

      // --------------------------------------------------
// ✅ SMART OCR EXTRACTION
// --------------------------------------------------

      final originalText = recognizedText.text;

// ✅ FROM CITY
      final fromRegex = RegExp(
        r'from\s*[:\-]?\s*([A-Za-z\s]+?)\s*\(',
        caseSensitive: false,
      );

      final fromResult = fromRegex.firstMatch(
        originalText.replaceAll('\n', ' '),
      );

      if (fromResult != null) {
        _fromLocController.text =
            fromResult.group(1)!.trim();
      }

// ✅ TO CITY
      final toRegex = RegExp(
        r'to\s*:?\s*([A-Za-z\s]+)\(',
        caseSensitive: false,
      );

      final toResult = toRegex.firstMatch(originalText);

      if (toResult != null) {
        _toLocController.text =
            toResult.group(1)!.trim();
      }

// ✅ DATE
      final dateRegex = RegExp(
        r'(\d{1,2}\s+[A-Za-z]+\s+\d{4})',
      );

      final dateResult = dateRegex.firstMatch(originalText);

      if (dateResult != null) {
        try {
          final parsedDate = DateFormat(
            "dd MMM yyyy",
          ).parse(dateResult.group(1)!);

          _fromDate = parsedDate;
          _toDate = parsedDate;

          expenses[index]['expense_date'] =
              parsedDate;
        } catch (e) {
          debugPrint("DATE ERROR: $e");
        }
      }

// ✅ TOTAL AMOUNT
      double extractedAmount = 0;

      final cleanText = originalText
          .replaceAll(',', '')
          .replaceAll('\n', ' ')
          .replaceAll('₹', ' ');

      final amountRegex = RegExp(
        r'total\s+amount\s*([0-9]+(?:\.[0-9]+)?)',
        caseSensitive: false,
      );

      final amountResult =
      amountRegex.firstMatch(cleanText);

      if (amountResult != null) {
        extractedAmount =
            double.tryParse(amountResult.group(1)!) ?? 0.0;
      }

      expenses[index]['amount'] =
          extractedAmount;

// ✅ EXPENSE TYPE
      expenses[index]['expense_type'] =
      "Airfare";

// ✅ DESCRIPTION
      expenses[index]['description'] =
      "Flight ticket expense";

      setState(() {});

      debugPrint("OCR TEXT: $text");

// --------------------------------------------------
// ✅ VALIDATE TRAVEL RECEIPT
// --------------------------------------------------





// --------------------------------------------------


      setState(() {});

      await textRecognizer.close();
    }
  }
  double getTotalAmount() {
    double sum = 0;
    for (final e in expenses) {
      sum += (e['amount'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }
  // ---------------------- SUBMIT CLAIM ----------------------
  Future<void> submitClaim({bool draft = false}) async {
    if (!draft && !_formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final emp = await supabase
          .from('employee_records')
          .select('id, organization_id, manager_id')
          .eq('email', widget.email)
          .maybeSingle();
      if (emp == null) throw "Employee not found";
      final totalDays = (_fromDate != null && _toDate != null)
          ? _toDate!.difference(_fromDate!).inDays + 1
          : 0;
      final claimData = {
        'employee_id': emp['id'],
        'organization_id': emp['organization_id'],
        'trip_purpose':
        _tripPurposeController.text,
        'trip_destination':
        _toLocController.text,
        'trip_from_date': _fromDate?.toIso8601String(),
        'trip_to_date': _toDate?.toIso8601String(),
        'total_days': totalDays,
        'total_amount': getTotalAmount(),
        'status': draft ? 'draft' : 'pending',
        'manager_id': emp['manager_id'],
      };
      final resp = await supabase
          .from('travel_claims')
          .insert([claimData])
          .select()
          .maybeSingle();
      final claimId = resp?['id'];
      // Upload receipts
      for (final exp in expenses) {
        if (exp['receipt_file'] != null) {
          final file = exp['receipt_file'];
          final fileName =
              '${emp['id']}/${DateTime
              .now()
              .millisecondsSinceEpoch}_${expenses.indexOf(exp)}.jpg';
          await supabase.storage.from('travel-receipts').upload(fileName, file);
          final publicUrl =
          supabase.storage.from('travel-receipts').getPublicUrl(fileName);
          exp['receipt_url'] = publicUrl;
        }
      }
      await supabase.from('travel_expenses').delete().eq('claim_id', claimId);
      for (final exp in expenses) {
        await supabase.from('travel_expenses').insert({
          'claim_id': claimId,
          'organization_id': emp['organization_id'],
          'expense_date':
          (exp['expense_date'] as DateTime).toIso8601String(),
          'expense_type': exp['expense_type'],
          'description': exp['description'],
          'amount': exp['amount'],
          'receipt_url': exp['receipt_url'],
        });
      }
      setState(() => loading = false);
      // Close form
      widget.onCancel(); // 👈 correctly closes the form

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(draft ? "Draft saved." : "Claim submitted."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        loading = false;
        errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  // ---------------------- BUILD ----------------------
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Row(
          children: [
            Text("Submit Travel Claim",
                style: Theme.of(context).textTheme.titleMedium),
            Spacer(),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: widget.onCancel,
            ),
          ],
        ),
        Container(
          decoration: _cardBox(),
          margin: EdgeInsets.only(top: 8, bottom: 16),
          padding: EdgeInsets.all(14),
          child: _budgetWidget(),
        ),
        Container(
          width: double.infinity,
          decoration: _cardBox(),
          padding: EdgeInsets.all(14),
          margin: EdgeInsets.only(bottom: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Trip Details",
                    style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: 12),
                TextFormField(
                  controller: _tripPurposeController,
                  decoration: _inputStyle("Trip Purpose"),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: _inputStyle("Travel Type"),
                  value: _travelType,
                  items: ["Domestic", "International"]
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _travelType = v),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _fromLocController,
                  decoration: _inputStyle("From (Origin)"),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _toLocController,
                  decoration: _inputStyle("To (Destination)"),
                ),
                SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  decoration: _inputStyle("From Date"),
                  controller: TextEditingController(
                      text: _fromDate == null
                          ? ''
                          : DateFormat('yyyy-MM-dd').format(_fromDate!)),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _fromDate ?? DateTime.now(),
                      firstDate:
                      DateTime.now().subtract(Duration(days: 365)),
                      lastDate: DateTime.now().add(Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _fromDate = picked);
                  },
                  validator: (val) =>
                  _fromDate == null ? "Pick date" : null,
                ),
                SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  decoration: _inputStyle("To Date"),
                  controller: TextEditingController(
                      text: _toDate == null
                          ? ''
                          : DateFormat('yyyy-MM-dd').format(_toDate!)),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _toDate ?? DateTime.now(),
                      firstDate:
                      DateTime.now().subtract(Duration(days: 365)),
                      lastDate: DateTime.now().add(Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _toDate = picked);
                  },
                  validator: (val) =>
                  _toDate == null ? "Pick date" : null,
                ),
              ],
            ),
          ),
        ),
        ..._expenseFields(),
        SizedBox(height: 16),
        Text(
          "Total Amount: ₹${NumberFormat.currency(symbol: "").format(getTotalAmount())}",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (errorMessage != null)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(errorMessage!, style: TextStyle(color: Colors.red)),
          ),
        SizedBox(height: 14),
        loading
            ? const SkeletonTravelClaimForm()
            : Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
                onPressed: () => submitClaim(draft: true),
                child: Text("Save as Draft")),
            ElevatedButton(
                onPressed: () => submitClaim(draft: false),
                child: Text("Submit Claim")),
          ],
        ),
      ],
    );
  }
  Widget _budgetWidget() {
    final available = 220500.0;
    final used = 79500.0;
    final pct = used / 240000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Travel Budget Utilization (FY)",
            style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 4),

        Row(
          children: [
            Text(
              "₹${NumberFormat("#,##0").format(available)} available",
              style: TextStyle(color: Colors.green[700]),
            ),
            Spacer(),
            Text("Annual Budget: ₹240,000",
                style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ],
        ),

        SizedBox(height: 6),

        ClipRRect(
          borderRadius: BorderRadius.circular(50), // 👈 makes pill shape
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.green, // 👈 GREEN BAR
            ),
          ),
        ),

        SizedBox(height: 2),

        Text("${NumberFormat("#,##0").format(used)} used this year",
            style: TextStyle(fontSize: 12)),
      ],
    );
  }

  List<Widget> _expenseFields() {
    return List.generate(expenses.length, (i) {
      final _e = expenses[i];

      return Container(
        decoration: _cardBox(),
        margin: EdgeInsets.only(bottom: 14),
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: _inputStyle("Date"),
                    controller: TextEditingController(
                      text: DateFormat('yyyy-MM-dd')
                          .format(_e['expense_date'] ?? DateTime.now()),
                    ),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _e['expense_date'] ?? DateTime.now(),
                        firstDate:
                        DateTime.now().subtract(Duration(days: 180)),
                        lastDate:
                        DateTime.now().add(Duration(days: 365)),
                      );
                      if (picked != null)
                        setState(() => expenses[i]['expense_date'] = picked);
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: _inputStyle("Type"),
                    value: _e['expense_type'],
                    items: [
                      "Meals",
                      "Hotel",
                      "Airfare",
                      "Taxi",
                      "Fuel",
                      "Toll",
                      "Other"
                    ]
                        .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => expenses[i]['expense_type'] = v),
                  ),
                ),
                SizedBox(width: 6),
                IconButton(
                    icon: Icon(Icons.remove_circle, color: Colors.red),
                    onPressed:
                    expenses.length > 1 ? () => removeExpense(i) : null),
              ],
            ),

            SizedBox(height: 12),
            TextFormField(
              controller: TextEditingController(
                text: expenses[i]['description'] ?? '',
              ),
              decoration: _inputStyle("Description"),
              onChanged: (v) => expenses[i]['description'] = v,
            ),

            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: TextEditingController(
                      text: expenses[i]['amount'] == 0
                          ? ''
                          : expenses[i]['amount'].toString(),
                    ),
                    decoration: _inputStyle("Amount (₹)"),
                    keyboardType:
                    TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      setState(() {
                        expenses[i]['amount'] = double.tryParse(v) ?? 0.0;
                      });
                    },

                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.upload_file),
                    label: Text(_e['receipt_file'] != null
                        ? 'Change Receipt'
                        : 'Upload Receipt'),
                    onPressed: () => pickReceipt(i),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    })
      ..add(
        Container(
          margin: EdgeInsets.only(bottom: 12),
          child: ElevatedButton.icon(
            icon: Icon(Icons.add),
            label: Text("Add Expense"),
            onPressed: addExpense,
          ),
        ),
      );
  }
}

// ---------------------------------------------------------------------
// CLAIM DETAILS SCREEN
// ---------------------------------------------------------------------

class TravelClaimDetailsScreen extends StatelessWidget {
  final String claimId;
  final String email;
  final supabase = Supabase.instance.client;

  TravelClaimDetailsScreen(
      {required this.claimId, required this.email, Key? key})
      : super(key: key);

  Future<Map<String, dynamic>?> fetchClaimDetails() async {
    final claim = await supabase
        .from('travel_claims')
        .select()
        .eq('id', claimId)
        .maybeSingle();

    if (claim == null) return null;

    final expenses = await supabase
        .from('travel_expenses')
        .select()
        .eq('claim_id', claimId)
        .order('expense_date');

    claim['expenses'] = expenses;
    return claim;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Claim Details")),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: fetchClaimDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SkeletonTravelClaimDetails();
          }

          final cl = snapshot.data!;

          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              Text("Claim #: ${cl['claim_number']}",
                  style: Theme.of(context).textTheme.titleMedium),
              Row(
                children: [
                  Chip(
                    label: Text(cl['status']?.toString().toUpperCase() ?? ''),
                    backgroundColor: Colors.blue,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              SizedBox(height: 8),

              Text("Trip Purpose: ${cl['trip_purpose'] ?? '-'}"),
              Text("Destination: ${cl['trip_destination'] ?? '-'}"),
              Text("Dates: ${cl['trip_from_date']} - ${cl['trip_to_date']}"),
              Text("Total Amount: ₹${cl['total_amount']}"),

              Divider(),
              Text("Expenses",
                  style: Theme.of(context).textTheme.titleSmall),

              ...((cl['expenses'] ?? []) as List).map((e) {
                return ListTile(
                  title: Text(e['expense_type']),
                  subtitle:
                  Text("${e['expense_date']} - ${e['description']}"),
                  trailing: Text("₹${e['amount']}"),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
