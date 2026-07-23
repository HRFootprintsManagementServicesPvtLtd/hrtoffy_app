// my_profile_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/skeleton_layouts.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';

class MyProfileScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  
  const MyProfileScreen({
    Key? key,
    required this.email,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        RefreshableScreen<MyProfileScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  Map<String, dynamic>? _emp;
  Map<String, dynamic>? _org;
  List<Map<String, dynamic>> gratuityNominees = [];
  List<Map<String, dynamic>> insurancePolicies = [];
  List<Map<String, dynamic>> employeeDocuments = [];
  String? _companyLogoUrl;
  TabController? _tabController;
  final ImagePicker _picker = ImagePicker();
  bool _hasDependenciesRunOnce = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      if (mounted) setState(() {});
    });
    startLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasDependenciesRunOnce) {
      _hasDependenciesRunOnce = true;
      return;
    }
    startLoad();
  }

  @override
  Future<void> loadData() async {
    try {
      final empResp = await supabase
          .from('employee_records')
          .select()
          .eq('email', widget.email)
          .maybeSingle();

      if (empResp == null) return;
      
      var emp = Map<String, dynamic>.from(empResp);
      final employeeId = emp['id'];

      // Decrypt sensitive fields
      try {
        final session = supabase.auth.currentSession;
        if (session != null && session.accessToken != null) {
          final decrypted = await supabase.functions.invoke(
            'salary-encryption',
            body: {
              'action': 'decrypt',
              'table': 'employee_records',
              'record_id': employeeId,
            },
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
            },
          );

          final body = decrypted.data is String ? jsonDecode(decrypted.data) : decrypted.data;
          final decryptedBody = Map<String, dynamic>.from(body ?? {});

          if (decryptedBody['success'] == true) {
            final decryptedData = Map<String, dynamic>.from(decryptedBody['data'] ?? {});
            emp = {...emp, ...decryptedData};
          }
        }
      } catch (e) {
        debugPrint('decryption error: $e');
      }

      final results = await Future.wait([
        supabase.from('gratuity_nominees').select().eq('employee_id', employeeId).order('created_at', ascending: false),
        supabase.from('employee_insurance_policies').select().eq('employee_id', employeeId),
        supabase.from('employee_documents').select().eq('employee_id', employeeId).order('uploaded_at', ascending: false),
        if (emp['organization_id'] != null) supabase.from('organizations').select().eq('id', emp['organization_id']).maybeSingle(),
      ]);

      setState(() {
        _emp = emp;
        gratuityNominees = List<Map<String, dynamic>>.from(results[0] as List);
        insurancePolicies = List<Map<String, dynamic>>.from(results[1] as List);
        employeeDocuments = List<Map<String, dynamic>>.from(results[2] as List);
        _org = results[3] != null ? Map<String, dynamic>.from(results[3] as Map) : null;
        _companyLogoUrl = _org?['logo_url']?.toString();
      });
    } catch (e) {
      debugPrint('fetchAll error: $e');
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    try {
      setState(() => isLoading = true);
      await supabase.from('employee_records').update(updates).eq('id', _emp!['id']);
      await loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    try {
      setState(() => isLoading = true);
      final file = File(image.path);
      final fileName = '${_emp!['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'avatars/$fileName';

      await supabase.storage.from('avatars').upload(path, file);
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

      await _updateProfile({'avatar_url': publicUrl});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _uploadDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    try {
      setState(() => isLoading = true);
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final path = 'docs/${_emp!['id']}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      await supabase.storage.from('claim-documents').upload(path, file);
      final publicUrl = supabase.storage.from('claim-documents').getPublicUrl(path);

      await supabase.from('employee_documents').insert({
        'employee_id': _emp!['id'],
        'organization_id': _emp!['organization_id'],
        'document_name': fileName,
        'document_type': 'personal_upload',
        'document_url': publicUrl,
        'status': 'verified'
      });

      await loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Document uploaded successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _editField(String title, String field, dynamic currentValue) {
    final controller = TextEditingController(text: currentValue?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $title"),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: "Enter $title")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _updateProfile({field: controller.text});
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = raw is DateTime ? raw : DateTime.parse(raw.toString());
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) { return raw.toString(); }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) return const SizedBox.shrink();
    super.build(context);
    final cardWidth = MediaQuery.of(context).size.width - 40;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.profile,
        companyLogoUrl: _companyLogoUrl,
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
                    Text("My Profile", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Your personal and professional details", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: buildRefreshable(
              skeleton: const SkeletonProfile(),
              childBuilder: () {
                if (_emp == null) return const Center(child: Text("Failed to load profile."));
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmployeeUi.border)),
                      child: TabBar(
                        controller: _tabController!,
                        tabs: const [Tab(text: 'Profile Details'), Tab(text: 'Digital ID')],
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.black87,
                        indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SliverFillRemaining(
            child: _emp == null ? const SizedBox.shrink() : TabBarView(
              controller: _tabController!,
              children: [
                Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: _buildProfileDetails())),
                SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [_buildDigitalIdFront(width: cardWidth), const SizedBox(height: 20), _buildDigitalIdBack(width: cardWidth)])),
              ],
            ),
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
        onTap: (index) {
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.email, employeeId: _emp!['id']))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: ColorFilter.mode(_bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: ColorFilter.mode(_bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: ColorFilter.mode(_bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: ColorFilter.mode(_bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildProfileDetails() {
    return Column(
      children: [
        _buildAvatarHeader(),
        _sectionCard(title: "Basic Information", color: const Color(0xFFEAF4FF), icon: Icons.badge_outlined, child: _buildBasicInfo()),
        _sectionCard(title: "Work Information", color: const Color(0xFFF3ECFF), icon: Icons.work_outline, child: _buildWorkInfo()),
        _sectionCard(title: "Reporting Chain", color: const Color(0xFFFFF2EB), icon: Icons.account_tree_outlined, child: _buildReportingChain()),
        _sectionCard(title: "Personal Information", color: const Color(0xFFFFF9E1), icon: Icons.person_outline, onEdit: () => _editPersonalDialog(), child: _buildPersonalInfo()),
        _sectionCard(title: "Bank Details", color: const Color(0xFFE8F5E9), icon: Icons.account_balance_outlined, onEdit: () => _editBankDialog(), child: _buildBankDetails()),
        _sectionCard(title: "Statutory Details", color: const Color(0xFFFCE4EC), icon: Icons.gavel_outlined, onEdit: () => _editStatutoryDialog(), child: _buildStatutoryDetails()),
        _sectionCard(title: "Emergency Contact", color: const Color(0xFFFFEBEE), icon: Icons.contact_phone_outlined, onEdit: () => _editEmergencyDialog(), child: _buildEmergencyContact()),
        _sectionCard(title: "My Nominees", color: const Color(0xFFFFF5EE), icon: Icons.groups_outlined, child: _buildNominees()),
        _sectionCard(title: "Insurance", color: const Color(0xFFEFFFFF), icon: Icons.health_and_safety_outlined, child: _buildInsurance()),
        _sectionCard(title: "Documents", color: const Color(0xFFEFFBFF), icon: Icons.description_outlined, onEdit: () => _uploadDocument(), child: _buildDocuments()),
      ],
    );
  }

  Widget _buildAvatarHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(children: [
        Stack(children: [
          CircleAvatar(radius: 50, backgroundColor: Colors.blue.shade100, backgroundImage: _emp?['avatar_url'] != null ? CachedNetworkImageProvider(_emp!['avatar_url']) : null, child: _emp?['avatar_url'] == null ? Text(_emp?['full_name']?[0] ?? '', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)) : null),
          Positioned(bottom: 0, right: 0, child: InkWell(onTap: _uploadAvatar, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: EmployeeUi.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.camera_alt, color: Colors.white, size: 16)))),
        ]),
        const SizedBox(height: 12),
        Text(_emp?['full_name'] ?? '', style: EmployeeUi.title(20)),
        Text(_emp?['designation'] ?? '', style: TextStyle(color: EmployeeUi.primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sectionCard({required String title, required Color color, required IconData icon, required Widget child, VoidCallback? onEdit}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.blue, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          if (onEdit != null) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.black54)),
        ]),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }

  Widget _modernInfo(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54, fontSize: 13))),
        Expanded(child: Text(value?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
      ]),
    );
  }

  Widget _buildBasicInfo() {
    return Column(children: [
      _modernInfo("Employee ID", _emp?['employee_id']),
      _modernInfo("Email", _emp?['email']),
      _modernInfo("Phone", _emp?['phone']),
      _modernInfo("DOB", _formatDate(_emp?['date_of_birth'])),
      _modernInfo("Joined", _formatDate(_emp?['date_of_joining'])),
    ]);
  }

  Widget _buildWorkInfo() {
    return Column(children: [
      _modernInfo("Department", _emp?['department']),
      _modernInfo("Designation", _emp?['designation']),
      _modernInfo("Grade", _emp?['grade_code']),
      _modernInfo("Location", _emp?['location']),
      _modernInfo("Worksite", _emp?['assigned_worksite']),
      _modernInfo("Status", _emp?['employment_status']),
    ]);
  }

  Widget _buildReportingChain() {
    return Column(children: [
      _modernInfo("Manager", _emp?['manager_name']),
      _modernInfo("Reviewer", _emp?['reviewer_name']),
    ]);
  }

  Widget _buildPersonalInfo() {
    return Column(children: [
      _modernInfo("Father's Name", _emp?['father_name']),
      _modernInfo("Mother's Name", _emp?['mother_name']),
      _modernInfo("Gender", _emp?['gender']),
      _modernInfo("Blood Group", _emp?['blood_group']),
      _modernInfo("Marital Status", _emp?['marital_status']),
      _modernInfo("Current Address", _emp?['current_address']),
      _modernInfo("Permanent Address", _emp?['permanent_address']),
    ]);
  }

  Widget _buildBankDetails() {
    return Column(children: [
      _modernInfo("Bank Name", _emp?['bank_name']),
      _modernInfo("Account Number", _emp?['account_number']),
      _modernInfo("IFSC Code", _emp?['ifsc_code']),
      _modernInfo("Branch", _emp?['bank_branch']),
    ]);
  }

  Widget _buildStatutoryDetails() {
    return Column(children: [
      _modernInfo("PAN Number", _emp?['pan_number']),
      _modernInfo("Aadhaar Number", _emp?['aadhaar_number']),
      _modernInfo("UAN Number", _emp?['uan_number']),
      _modernInfo("PF Number", _emp?['pf_number']),
      _modernInfo("ESI Number", _emp?['esi_number']),
    ]);
  }

  Widget _buildEmergencyContact() {
    return Column(children: [
      _modernInfo("Contact Name", _emp?['emergency_contact_name']),
      _modernInfo("Relationship", _emp?['emergency_contact_relationship']),
      _modernInfo("Phone Number", _emp?['emergency_contact_number']),
    ]);
  }

  Widget _buildNominees() {
    if (gratuityNominees.isEmpty) return const Text("No nominees added.");
    return Column(children: gratuityNominees.map((n) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        _modernInfo("Nominee", n['nominee_name']),
        _modernInfo("Relation", n['relationship']),
        _modernInfo("Share %", n['share_percent']),
      ]),
    )).toList());
  }

  Widget _buildInsurance() {
    if (insurancePolicies.isEmpty) return const Text("No insurance assigned.");
    return Column(children: insurancePolicies.map((p) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        _modernInfo("Type", p['insurance_type']),
        _modernInfo("Provider", p['provider_name']),
        _modernInfo("Policy #", p['policy_number']),
        _modernInfo("Sum Insured", p['sum_insured']),
      ]),
    )).toList());
  }

  Widget _buildDocuments() {
    if (employeeDocuments.isEmpty) return const Text("No documents uploaded.");
    return Column(children: employeeDocuments.map((d) => ListTile(
      leading: const Icon(Icons.file_present, color: Colors.blue),
      title: Text(d['document_name'] ?? 'Document', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(d['document_type'] ?? ''),
      trailing: IconButton(icon: const Icon(Icons.download_outlined), onPressed: () => _viewDocument(d['document_url'])),
    )).toList());
  }

  Future<void> _viewDocument(String? url) async {
    if (url == null) return;
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  void _editPersonalDialog() {
    final marital = TextEditingController(text: _emp?['marital_status'] ?? '');
    final cAddr = TextEditingController(text: _emp?['current_address'] ?? '');
    final pAddr = TextEditingController(text: _emp?['permanent_address'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Personal Info"),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: marital, decoration: const InputDecoration(labelText: "Marital Status")),
          TextField(controller: cAddr, decoration: const InputDecoration(labelText: "Current Address"), maxLines: 2),
          TextField(controller: pAddr, decoration: const InputDecoration(labelText: "Permanent Address"), maxLines: 2),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _updateProfile({'marital_status': marital.text, 'current_address': cAddr.text, 'permanent_address': pAddr.text});
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _editBankDialog() {
    final bName = TextEditingController(text: _emp?['bank_name'] ?? '');
    final acc = TextEditingController(text: _emp?['account_number'] ?? '');
    final ifsc = TextEditingController(text: _emp?['ifsc_code'] ?? '');
    final br = TextEditingController(text: _emp?['bank_branch'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Bank Details"),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: bName, decoration: const InputDecoration(labelText: "Bank Name")),
          TextField(controller: acc, decoration: const InputDecoration(labelText: "Account Number")),
          TextField(controller: ifsc, decoration: const InputDecoration(labelText: "IFSC Code")),
          TextField(controller: br, decoration: const InputDecoration(labelText: "Branch")),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _updateProfile({'bank_name': bName.text, 'account_number': acc.text, 'ifsc_code': ifsc.text, 'bank_branch': br.text});
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _editStatutoryDialog() {
    final pan = TextEditingController(text: _emp?['pan_number'] ?? '');
    final aadhaar = TextEditingController(text: _emp?['aadhaar_number'] ?? '');
    final uan = TextEditingController(text: _emp?['uan_number'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Statutory Details"),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pan, decoration: const InputDecoration(labelText: "PAN Number")),
          TextField(controller: aadhaar, decoration: const InputDecoration(labelText: "Aadhaar Number")),
          TextField(controller: uan, decoration: const InputDecoration(labelText: "UAN Number")),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _updateProfile({'pan_number': pan.text, 'aadhaar_number': aadhaar.text, 'uan_number': uan.text});
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _editEmergencyDialog() {
    final name = TextEditingController(text: _emp?['emergency_contact_name'] ?? '');
    final rel = TextEditingController(text: _emp?['emergency_contact_relationship'] ?? '');
    final ph = TextEditingController(text: _emp?['emergency_contact_number'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Emergency Contact"),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: "Contact Name")),
          TextField(controller: rel, decoration: const InputDecoration(labelText: "Relationship")),
          TextField(controller: ph, decoration: const InputDecoration(labelText: "Phone Number")),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _updateProfile({'emergency_contact_name': name.text, 'emergency_contact_relationship': rel.text, 'emergency_contact_number': ph.text});
          }, child: const Text("Save")),
        ],
      ),
    );
  }

  Widget _buildDigitalIdFront({required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
      child: Column(children: [
        if (_companyLogoUrl != null) CachedNetworkImage(imageUrl: _companyLogoUrl!, height: 40),
        const Divider(height: 32),
        CircleAvatar(radius: 40, backgroundColor: Colors.blue.shade100, backgroundImage: _emp?['avatar_url'] != null ? CachedNetworkImageProvider(_emp!['avatar_url']) : null, child: _emp?['avatar_url'] == null ? Text(_emp?['full_name']?[0] ?? '') : null),
        const SizedBox(height: 16),
        Text(_emp?['full_name'] ?? '', style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(_emp?['designation'] ?? '', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        _idRow("Emp ID", _emp?['employee_id']),
        _idRow("Blood", _emp?['blood_group']),
        _idRow("Phone", _emp?['phone']),
      ]),
    );
  }

  Widget _buildDigitalIdBack({required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_org?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        const Text("Address:", style: TextStyle(color: Colors.grey, fontSize: 12)),
        Text(_org?['location'] ?? '-'),
        const SizedBox(height: 20),
        const Text("Emergency Contact:", style: TextStyle(fontWeight: FontWeight.bold)),
        Text(_emp?['emergency_contact_number'] ?? 'Not set'),
      ]),
    );
  }

  Widget _idRow(String label, dynamic value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(value?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))]));
  }
}
