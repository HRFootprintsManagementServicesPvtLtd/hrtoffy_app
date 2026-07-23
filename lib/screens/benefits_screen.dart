import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/bottom_nav_toffy_button.dart';

import '../widgets/app_drawer.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'payslip_screen.dart';
import 'attendance_screen.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

final supabase = Supabase.instance.client;

class BenefitsScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  const BenefitsScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });
  @override
  State<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends State<BenefitsScreen>
    with TickerProviderStateMixin, RefreshableScreen<BenefitsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0; // Benefits tab index
  String? employeeId, organizationId, grade, managerId;
  bool submitting = false;
  List<Map<String, dynamic>> claims = [];
  List<Map<String, dynamic>> benefits = [];
  Map<String, dynamic>? gradeLimitData;
  double claimedTotal = 0.0;
  @override
  void initState() {
    super.initState();
    startLoad();
  }

  @override
  Future<void> loadData() async {
    await fetchAll();
  }

  Future<void> fetchAll() async {
    final profile = await supabase
        .from('employee_records')
        .select()
        .eq('email', widget.userEmail)
        .maybeSingle();
    if (profile != null) {
      employeeId = profile['id'];
      organizationId = profile['organization_id'];
      grade = profile['grade_code'];
      managerId = profile['manager_id'];

      await Future.wait([fetchClaims(), fetchBenefits()]);
    }
    setState(() {});
  }

  Future<void> fetchClaims() async {
    if (employeeId == null) return;
    final res = await supabase
        .from('benefit_claims')
        .select('*, benefits_catalog(benefit_name, benefit_type)')
        .eq('employee_id', employeeId!)
        .order('claim_date', ascending: false);
    claims = List<Map<String, dynamic>>.from(res);
    final year = DateTime.now().year;
    claimedTotal = 0.0;
    for (final row in claims) {
      if ((row['claim_year'] ?? 0) == year && row['status'] != 'rejected') {
        claimedTotal += (row['approved_amount'] ?? row['claimed_amount'] ?? 0)
            .toDouble();
      }
    }
  }

  Future<void> fetchBenefits() async {
    if (organizationId == null) return;
    final res = await supabase
        .from('benefits_catalog')
        .select()
        .eq('organization_id', organizationId!)
        .eq('is_active', true);
    benefits = List<Map<String, dynamic>>.from(res);

    if (grade != null) {
      final gradeRes = await supabase
          .from('grade_structure')
          .select()
          .eq('organization_id', organizationId!)
          .eq('grade_code', grade!)
          .maybeSingle();
      gradeLimitData = gradeRes;
    }
  }

  // SUBMIT CLAIM (same logic)
  Future<void> submitClaim({
    required String benefitId,
    required double claimAmount,
    required String description,
    PlatformFile? attachment,
  }) async {
    setState(() => submitting = true);
    try {
      String? fileUrl;
      List<Map<String, String>> fileArr = [];
      if (attachment != null) {
        final path =
            '${employeeId}/${DateTime.now().millisecondsSinceEpoch}_${attachment.name}';
        await supabase.storage
            .from('claim-documents')
            .upload(path, File(attachment.path!));
        fileUrl = supabase.storage.from('claim-documents').getPublicUrl(path);
        fileArr.add({'name': attachment.name, 'url': fileUrl!});
      }
      final now = DateTime.now();
      final claimData = {
        'employee_id': employeeId,
        'organization_id': organizationId,
        'benefit_id': benefitId,
        'claimed_amount': claimAmount,
        'description': description,
        'claim_date': now.toIso8601String().substring(0, 10),
        'claim_month': now.month,
        'claim_year': now.year,
        'status': 'pending',
        'manager_id': managerId,
        'payment_mode': 'payroll',
        'supporting_documents': fileArr.isEmpty ? null : fileArr,
      };
      await supabase.from('benefit_claims').insert(claimData);
      await fetchClaims();
      setState(() => submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Claim submitted for approval.")),
      );
      Navigator.pop(context); // close the submit page
    } catch (e) {
      setState(() => submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Submission Error: ${e.toString().contains("Unauthorized") ? "You are not permitted to submit a claim." : e.toString()}",
          ),
        ),
      );
    }
  }

  // MAIN UI — SHOW ONLY MY BENEFITS
  @override
  Widget build(BuildContext context) {
    return buildRefreshable(
      skeleton: const SkeletonBenefits(),
      childBuilder: () => Scaffold(
        key: _scaffoldKey,
        backgroundColor: EmployeeUi.pageBg,
        endDrawer: AppDrawer(
          userEmail: widget.userEmail,
          userData: widget.userData,
          fetchHrmsContext: widget.fetchHrmsContext,
          currentRoute: DrawerRoute.benefits,
          companyLogoUrl: widget.userData['company_logo_url'],
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
                  padding: const EdgeInsets.only(right: 6, top: 12),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SubmitClaimPage(benefits: benefits, gradeLimitData: gradeLimitData, claimedTotal: claimedTotal, onSubmit: submitClaim)));
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: EmployeeUi.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 12),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                    child: IconButton(
                      icon: SvgPicture.asset("assets/icons/menu.svg", width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)),
                      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                  ),
                ),
                const SizedBox(width: 1),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFD7E8FF), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text("Benefits Hub", style: EmployeeUi.header(24)),
                      const SizedBox(height: 4),
                      Text("Manage your perks and claims", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
            SliverFillRemaining(
              child: MyBenefitsTab(claims: claims),
            ),
          ],
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
          onTap: (index) async {
            if (index == 0) {
              setState(() => _bottomTabIndex = 0);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    email: widget.userEmail,
                    employeeId: widget.userData['id'], // 👈 IMPORTANT
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
                    email: widget.userEmail,
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
                    userEmail: widget.userEmail,
                    userData: widget.userData,
                    fetchHrmsContext: widget.fetchHrmsContext,
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
                    userEmail: widget.userEmail,
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
            // 🤖 TOFFY ICON
          },
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/dashboard.svg",
                width: 22,
                color: _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/leaves.svg",
                width: 22,
                color: _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Leave',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/attendance.svg",
                width: 22,
                color: _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
              ),
              label: 'Attendance',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                "assets/icons/payroll.svg",
                width: 22,
                color: _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
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
        ),
      ),
    );
  }
}

// MY BENEFITS TAB (unchanged UI)
class MyBenefitsTab extends StatelessWidget {
  final List<Map<String, dynamic>> claims;
  const MyBenefitsTab({required this.claims});
  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'paid':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) {
      return Center(
        child: Text("No claims found.", style: GoogleFonts.montserrat()),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: const EmployeeSectionHeader(
            title: "My Benefits",
            subtitle: "Track claim status and approved amounts",
          ),
        ),
        ListView.separated(
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          itemBuilder: (c, i) {
            final claim = claims[i];
            final benefit = claim['benefits_catalog'] ?? {};
            return Container(
              decoration: EmployeeUi.cardDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.book_outlined,
                          size: 21,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            benefit['benefit_name'] ?? 'Benefit',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      claim['description'] ?? '-',
                      style: GoogleFonts.montserrat(fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.event_note, size: 17),
                        const SizedBox(width: 3),
                        Text(
                          DateFormat(
                            'dd MMM yyyy',
                          ).format(DateTime.parse(claim['claim_date'])),
                          style: GoogleFonts.montserrat(fontSize: 13),
                        ),
                        Spacer(),
                        Text(
                          "₹${claim['claimed_amount'] ?? '-'}",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (claim['approved_amount'] != null)
                          Text(
                            "Approved: ₹${claim['approved_amount']}",
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w500,
                              color: Colors.green,
                            ),
                          ),
                        Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor(
                              claim['status'],
                            ).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            (claim['status'] ?? '').toString().toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: statusColor(claim['status']),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (c, i) => const SizedBox(height: 14),
          itemCount: claims.length,
        ),
      ],
    );
  }
}

// SUBMIT CLAIM PAGE (full screen)
class SubmitClaimPage extends StatefulWidget {
  final List<Map<String, dynamic>> benefits;
  final Map<String, dynamic>? gradeLimitData;
  final double claimedTotal;
  final Future<void> Function({
    required String benefitId,
    required double claimAmount,
    required String description,
    PlatformFile? attachment,
  })
  onSubmit;
  const SubmitClaimPage({
    required this.benefits,
    required this.gradeLimitData,
    required this.claimedTotal,
    required this.onSubmit,
  });
  @override
  State<SubmitClaimPage> createState() => _SubmitClaimPageState();
}

class _SubmitClaimPageState extends State<SubmitClaimPage> {
  String? selectedBenefitId;
  double? claimAmount;
  String? description;
  PlatformFile? attachment;
  final _formKey = GlobalKey<FormState>();
  String? warning;
  @override
  Widget build(BuildContext context) {
    final totalLimit =
        widget.gradeLimitData?['benefit_annual_limit']?.toDouble() ?? 1000.0;
    final alreadyUsed = widget.claimedTotal;
    final remaining = totalLimit - alreadyUsed;

    final usagePercent = totalLimit > 0
        ? (alreadyUsed / totalLimit).clamp(0.0, 1.0)
        : 0.0;

    Color progressColor;
    if (usagePercent < 0.5) {
      progressColor = Colors.green;
    } else if (usagePercent < 0.8) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.red;
    }

    final claimExceeds = (claimAmount ?? 0) > remaining;

    if (claimExceeds && claimAmount != null) {
      warning =
          "Not eligible. Your grade allows maximum ₹${totalLimit.toStringAsFixed(0)} per year. "
          "You've already claimed ₹${alreadyUsed.toStringAsFixed(2)}.";
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Submit Claim")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Limits box
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 32,
                ),

                child: Column(
                  children: [
                    Text(
                      "Benefit Claim Limits",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _limitBox(
                            "Total Limit",
                            "₹${totalLimit.toStringAsFixed(0)}",
                            Colors.black,
                          ),
                        ),
                        Expanded(
                          child: _limitBox(
                            "Already Used",
                            "₹${alreadyUsed.toStringAsFixed(0)}",
                            Colors.red,
                          ),
                        ),
                        Expanded(
                          child: _limitBox(
                            "Remaining",
                            "₹${remaining.toStringAsFixed(0)}",
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: usagePercent,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation(progressColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (warning != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  warning!,
                  style: GoogleFonts.montserrat(color: Colors.red),
                ),
              ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedBenefitId,
                    decoration: const InputDecoration(
                      labelText: "Select Benefit",
                    ),
                    items: widget.benefits
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'],
                            child: Text(b['benefit_name'] ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selectedBenefitId = v),
                    validator: (v) =>
                        v == null ? "Please select a benefit" : null,
                  ),
                  const SizedBox(height: 16), // 👈 GAP
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Claim Amount (₹)",
                    ),
                    onChanged: (v) =>
                        setState(() => claimAmount = double.tryParse(v)),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val <= 0) {
                        return "Enter a valid amount";
                      }
                      if (val > remaining) {
                        return "Claim exceeds limit";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8), // 👈 GAP
                  TextFormField(
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: "Description"),
                    onChanged: (v) => description = v,
                    validator: (v) =>
                        v == null || v.isEmpty ? "Description required" : null,
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'jpg', 'png'],
                          );
                          if (result != null) {
                            setState(() => attachment = result.files.first);
                          }
                        },
                        icon: const Icon(Icons.upload_file),
                        label: const Text("Attach File"),
                      ),
                      if (attachment != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            attachment!.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => attachment = null),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;

                      await widget.onSubmit(
                        benefitId: selectedBenefitId!,
                        claimAmount: claimAmount!,
                        description: description ?? '',
                        attachment: attachment,
                      );
                    },
                    child: const Text("Submit Claim"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }
}
