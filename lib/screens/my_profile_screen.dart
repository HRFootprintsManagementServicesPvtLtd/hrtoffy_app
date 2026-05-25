// my_profile_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../widgets/skeleton_layouts.dart';
import '../widgets/refreshable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../widgets/app_drawer.dart';
import '../widgets/bottom_nav_toffy_button.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import '../widgets/drawer_route.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
// 🔧 FIX 1: Update MyProfileScreen widget definition
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
  Map<String, dynamic>? _manager;
  Map<String, dynamic>? _reviewer;
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
    startLoad(); // keep this as it is
  }
  // when screen becomes visible again in navigation tree, reload fresh data
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasDependenciesRunOnce) {
      _hasDependenciesRunOnce = true; // skip first time (initState already loaded)
      return;
    }
    startLoad(); // reload data when coming back
  }
  // Utility: detect invalid avatar URL object names (no hard-coded domains)
  bool isInvalidAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      final path = uri.path; // e.g. /storage/v1/object/public/avatars/xyz.jpg
      if (!path.contains('/avatars/')) return false;
      final segs = uri.pathSegments;
      if (segs.isEmpty) return false;
      final last = segs.last.toString();
      if (last.contains('@') || last.contains('%40') || last.contains(' ')) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<void> loadData() async {
    try {
      final empResp = await supabase
          .from('employee_records')
          .select()
          .eq('email', widget.email)
          .maybeSingle();

      if (empResp == null) {
        setState(() {
          _emp = null;
          _org = null;
          _manager = null;
          _reviewer = null;
          _companyLogoUrl = null;
        });
        return;
      }
      final Map<String, dynamic> emp = Map<String, dynamic>.from(empResp);
      final employeeId = emp['id'];

      final gratuityData = await supabase
          .from('gratuity_nominees')
          .select()
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false);

      final insuranceData = await supabase
          .from('employee_insurance_policies')
          .select()
          .eq('employee_id', employeeId);

      final docsData = await supabase
          .from('employee_documents')
          .select()
          .eq('employee_id', employeeId)
          .or('document_type.like.personal_%,document_type.like.cert_%')
          .order('uploaded_at', ascending: false);
      // --- Organization info ---
      String? orgId = emp['organization_id']?.toString();
      Map<String, dynamic>? org;
      String? companyLogoUrl;
      if (orgId != null && orgId.isNotEmpty) {
        final orgResp = await supabase
            .from('organizations')
            .select()
            .eq('id', orgId)
            .maybeSingle();
        if (orgResp != null) org = Map<String, dynamic>.from(orgResp);

        if (org != null &&
            org['logo_url'] != null &&
            org['logo_url'].toString().isNotEmpty) {
          companyLogoUrl = org['logo_url'].toString();
        } else {
          try {
            final files =
            await supabase.storage.from('company-logos').list(path: orgId);
            if (files.isNotEmpty) {
              final fileObj = files.firstWhere(
                    (f) {
                  final n =
                      (f as Map)['name']?.toString().toLowerCase() ?? '';
                  return n.endsWith('.png') ||
                      n.endsWith('.jpg') ||
                      n.endsWith('.jpeg') ||
                      n.endsWith('.webp');
                },
                orElse: () => files.first,
              );
              final fileName = (fileObj as Map)['name'];
              if (fileName != null) {
                companyLogoUrl = supabase.storage
                    .from('company-logos')
                    .getPublicUrl('$orgId/$fileName');
              }
            }
          } catch (_) {
            companyLogoUrl = null;
          }
        }
      }

      // Manager
      Map<String, dynamic>? manager;
      if (emp['manager_id'] != null) {
        final m = await supabase
            .from('employee_records')
            .select()
            .eq('id', emp['manager_id'])
            .maybeSingle();
        if (m != null) manager = Map<String, dynamic>.from(m);
      } else if (emp['manager_email'] != null) {
        final m = await supabase
            .from('employee_records')
            .select()
            .eq('email', emp['manager_email'])
            .maybeSingle();
        if (m != null) manager = Map<String, dynamic>.from(m);
      }

      // Reviewer
      Map<String, dynamic>? reviewer;
      if (emp['reviewer_id'] != null) {
        final r = await supabase
            .from('employee_records')
            .select()
            .eq('id', emp['reviewer_id'])
            .maybeSingle();
        if (r != null) reviewer = Map<String, dynamic>.from(r);
      } else if (emp['reviewer_email'] != null) {
        final r = await supabase
            .from('employee_records')
            .select()
            .eq('email', emp['reviewer_email'])
            .maybeSingle();
        if (r != null) reviewer = Map<String, dynamic>.from(r);
      }

      setState(() {
        _emp = emp;
        _org = org;
        _companyLogoUrl = companyLogoUrl;
        _manager = manager;
        _reviewer = reviewer;

        gratuityNominees =
        List<Map<String, dynamic>>.from(gratuityData);

        insurancePolicies =
        List<Map<String, dynamic>>.from(insuranceData);

        employeeDocuments =
        List<Map<String, dynamic>>.from(docsData);
      });

      debugPrint('✅ Profile data loaded successfully.');
    } catch (e, st) {
      debugPrint('fetchAll error: $e\n$st');
    }
  }

  Map<String, String> _digitalIdData() {
    return {
      'name': (_emp?['full_name'] ?? '-').toString(),
      'designation': (_emp?['designation'] ?? '-').toString(),
      'dob': _formatDate(_emp?['date_of_birth']),
      'blood': (_emp?['blood_group'] ?? '-').toString(),
      'doj': _formatDate(_emp?['date_of_joining']),
      'phone': (_emp?['phone'] ?? '-').toString(),
      'company': (_org?['name'] ?? '-').toString(),
      'location': (_org?['location'] ?? '-').toString(),
    };
  }


  // Upload avatar (sanitized + overwrite safe)
  Future<void> _pickAndUploadAvatar() async {
    try {
      if (_emp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee record not loaded yet.')),
        );
        return;
      }

      final XFile? result = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (result == null) return;

      final bytes = await result.readAsBytes();

      // Sanitize filename
      String baseName;
      if (_emp?['employee_id'] != null &&
          _emp!['employee_id'].toString().isNotEmpty) {
        baseName = _emp!['employee_id'].toString();
      } else {
        baseName = (_emp?['email'] ?? widget.email).toString();
      }
      baseName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = '$baseName.jpg';

      // per-user folder
      final folderPath = supabase.auth.currentUser?.id ?? 'public';
      final filePath = '$folderPath/$fileName';

      debugPrint('Uploading avatar to: $filePath');

      // Upload to Supabase Storage (avatars bucket)
      final res = await supabase.storage.from('avatars').uploadBinary(
        filePath,
        bytes,
        fileOptions:
        const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

      debugPrint('Upload result: $res');

      // Get public URL
      final publicUrl =
      supabase.storage.from('avatars').getPublicUrl(filePath);

      // Update employee record with new avatar URL
      await supabase
          .from('employee_records')
          .update({'avatar_url': publicUrl})
          .eq('id', _emp?['id']);

      await onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Profile photo updated')),
      );
    } catch (e, st) {
      debugPrint('❌ upload avatar error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload avatar')),
      );
    }
  }

  // Delete avatar safely
  Future<void> _confirmAndDeleteAvatar() async {
    if (_emp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee record not loaded yet.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Profile Photo'),
        content:
        const Text('Are you sure you want to delete your profile photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      String baseName;
      if (_emp?['employee_id'] != null &&
          _emp!['employee_id'].toString().isNotEmpty) {
        baseName = _emp!['employee_id'].toString();
      } else {
        baseName = (_emp?['email'] ?? widget.email)
            .toString()
            .replaceAll('@', '_')
            .replaceAll('.', '_');
      }
      final fileName = '$baseName.jpg';

      final folderPath = supabase.auth.currentUser?.id ?? 'public';
      final filePath = '$folderPath/$fileName';

      await supabase.storage.from('avatars').remove([filePath]);

      await supabase
          .from('employee_records')
          .update({'avatar_url': null})
          .eq('id', _emp?['id']);

      await onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo deleted successfully')),
      );
    } catch (e) {
      debugPrint('delete avatar error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete profile photo')),
      );
    }
  }

  Future<void> _generateAndSavePdfDirectly() async {
    setState(() => isLoading = true);

    try {
      final data = _digitalIdData();
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(360, 520),
          build: (_) => pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blue),
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  data['company']!,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Divider(),

                pw.SizedBox(height: 12),
                pw.Container(
                  width: 64,
                  height: 64,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.grey),
                  ),
                  child: pw.Text(
                    data['name']!.isNotEmpty
                        ? data['name']![0].toUpperCase()
                        : '',
                    style: const pw.TextStyle(fontSize: 28),
                  ),
                ),


                pw.SizedBox(height: 10),
                pw.Text(
                  data['name']!,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  data['designation']!,
                  style: pw.TextStyle(color: PdfColors.blue),
                ),

                pw.Divider(),
                _pdfRow('DOB', data['dob']!),
                _pdfRow('Blood Group', data['blood']!),
                _pdfRow('DOJ', data['doj']!),
                _pdfRow('Mobile', data['phone']!),
              ],
            ),
          ),
        ),
      );


      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ID_Card_${data['name']}.pdf');
      await file.writeAsBytes(await doc.save());

      await OpenFilex.open(file.path);
    } catch (e) {
      debugPrint('❌ PDF error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate digital ID')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            flex: 6,
            child: pw.Text(value),
          ),
        ],
      ),
    );
  }




  Future<pw.MemoryImage?> _loadNetworkImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final bytes = await HttpClient()
          .getUrl(Uri.parse(url))
          .then((r) => r.close())
          .then((r) => consolidateHttpClientResponseBytes(r));
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }



  String _formatDate(dynamic raw) {
    try {
      if (raw == null) return '-';
      DateTime dt;
      if (raw is DateTime) {
        dt = raw;
      } else {
        dt = DateTime.parse(raw.toString());
      }
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (e) {
      return raw?.toString() ?? '-';
    }
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        children: [

          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _showEditDetailsDialog,
              icon: const Icon(Icons.edit),
              label: const Text("Edit My Details"),
            ),
          ),

          const SizedBox(height: 16),

          _sectionCard(
            title: "Basic Information",
            color: const Color(0xFFEAF4FF),
            icon: Icons.badge_outlined,
            child: _buildBasicInfo(),
          ),

          _sectionCard(
            title: "Work Information",
            color: const Color(0xFFF3ECFF),
            icon: Icons.work_outline,
            child: _buildWorkInfo(),
          ),

          _sectionCard(
            title: "Reporting Chain",
            color: const Color(0xFFFFF2EB),
            icon: Icons.account_tree_outlined,
            child: _buildReportingChain(),
          ),

          _sectionCard(
            title: "My Nominees (PF / Gratuity)",
            color: const Color(0xFFFFF5EE),
            icon: Icons.groups_outlined,
            action: ElevatedButton.icon(
              onPressed: _showAddNomineeDialog,
              icon: const Icon(Icons.add),
              label: const Text("Add Nominee"),
            ),
            child: _buildNominees(),
          ),

          _sectionCard(
            title: "My Insurance Nominees",
            color: const Color(0xFFEFFFFF),
            icon: Icons.health_and_safety_outlined,
            child: _buildInsuranceNominees(),
          ),

          _sectionCard(
            title: "My Documents & Certifications",
            color: const Color(0xFFEFFBFF),
            icon: Icons.description_outlined,
            action: ElevatedButton.icon(
              onPressed: _showUploadDocumentDialog,
              icon: const Icon(Icons.upload),
              label: const Text("Upload"),
            ),
            child: _buildDocuments(),
          ),
        ],
      ),
    );
  }

  Widget _smallLabelValue(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _buildDigitalIdFront({required double width}) {
    final name = (_emp?['full_name'] ?? '-').toString();
    final designation = (_emp?['designation'] ?? '-').toString();
    final empId = (_emp?['employee_id'] ?? '-').toString();
    final dob = _formatDate(_emp?['date_of_birth']);
    final blood = (_emp?['blood_group'] ?? '-').toString();
    final doj = _formatDate(_emp?['date_of_joining']);
    final phone = (_emp?['phone'] ?? '-').toString();

    return RepaintBoundary(

      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blueAccent, width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            // 🔹 ORGANIZATION LOGO
            if (_companyLogoUrl != null)
              SizedBox(
                height: 40,
                child: CachedNetworkImage(
                  imageUrl: _companyLogoUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const SizedBox(height: 40),
                ),
              ),


            const SizedBox(height: 8),
            const Divider(),

            // 🔹 AVATAR
            const SizedBox(height: 10),
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: (_emp?['avatar_url'] != null &&
                  _emp!['avatar_url'].toString().isNotEmpty)
                  ? CachedNetworkImageProvider(_emp!['avatar_url'])
                  : null,
              child: (_emp?['avatar_url'] == null ||
                  _emp!['avatar_url'].toString().isEmpty)
                  ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              )
                  : null,
            ),

            const SizedBox(height: 8),

            // 🔹 NAME + DESIGNATION
            Text(
              name,
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              designation,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.blueAccent,
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            _idRow('DOB', dob),
            _idRow('Blood Group', blood),
            _idRow('DOJ', doj),
            _idRow('Mobile', phone),
          ],
        ),
      ),
    );
  }
  Widget _idRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(value),
          ),
        ],
      ),
    );
  }



  Widget _buildDigitalIdBack({required double width}) {
    final company = (_org?['name'] ?? '-').toString();
    final location = (_org?['location'] ?? '-').toString();

    return RepaintBoundary(

      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blueAccent, width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              company,
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),

            const Text(
              'Corporate Office',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(location),

            const SizedBox(height: 14),

            const Text(
              'Emergency Contact',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('Contact not available'),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_tabController == null) {
      return const SizedBox.shrink();
    }

    super.build(context);

    final cardWidth = MediaQuery.of(context).size.width - 40;

    return Scaffold(
      key: _scaffoldKey,

      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,                 // ✅ FIX
        fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
        currentRoute: DrawerRoute.profile,

        companyLogoUrl: null,
      ),

      appBar: AppBar(
        title: const Text('My Profile'),
      ),

      // 🔥 BODY + TOFFY OVERLAY
      body: Stack(
        children: [
          buildRefreshable(
            skeleton: const SkeletonProfile(),
            childBuilder: () {
              if (_emp == null) {
                return const Center(child: Text("Failed to load profile."));
              }

              return Column(
                children: [
                  Container(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController!,

                      tabs: const [
                        Tab(text: 'Profile Details'),
                        Tab(text: 'Digital ID'),
                      ],
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      indicator: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  Expanded(
                    child: IndexedStack(
                      index: _tabController?.index ?? 0,

                      children: [
                        // TAB 0 — PROFILE DETAILS
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildProfileDetails(),
                        ),

                        // TAB 1 — DIGITAL ID (ALWAYS RENDERED)
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _buildDigitalIdFront(width: cardWidth),
                              const SizedBox(height: 14),
                              _buildDigitalIdBack(width: cardWidth),
                              const SizedBox(height: 16),

                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                ],
              );
            },
          ),

          // 🤖 TOFFY CHAT OVERLAY
        ],
      ),

      // ✅ BOTTOM NAVIGATION
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

          // 🤖 TOFFY


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
      ),
    );

  }

  Widget _sectionCard({
    required String title,
    required Color color,
    required IconData icon,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          LayoutBuilder(
            builder: (context, constraints) {

              final isMobile = constraints.maxWidth < 600;

              return isMobile

                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: [

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, color: Colors.blue),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (action != null) ...[
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: action,
                    ),
                  ],
                ],
              )

                  : Row(
                children: [

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.blue),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  if (action != null) action,
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          child,
        ],
      ),
    );
  }

  Widget _modernInfo(String label, dynamic value) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            value?.toString() ?? '-',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Wrap(
      spacing: 60,
      runSpacing: 24,
      children: [

        _modernInfo("Employee ID", _emp?['employee_id']),
        _modernInfo("Email", _emp?['email']),
        _modernInfo("Phone", _emp?['phone']),
        _modernInfo("Blood Group", _emp?['blood_group']),
        _modernInfo("Date of Birth",
            _formatDate(_emp?['date_of_birth'])),

        _modernInfo("Date of Joining",
            _formatDate(_emp?['date_of_joining'])),
      ],
    );
  }

  Widget _buildWorkInfo() {
    return Wrap(
      spacing: 60,
      runSpacing: 24,
      children: [

        _modernInfo("Department", _emp?['department']),
        _modernInfo("Designation", _emp?['designation']),
      ],
    );
  }

  Widget _buildReportingChain() {
    return Column(
      children: [

        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(_emp?['manager_name'] ?? '-'),
          subtitle: Text(_emp?['manager_email'] ?? '-'),
        ),

        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(_emp?['reviewer_name'] ?? '-'),
          subtitle: Text(_emp?['reviewer_email'] ?? '-'),
        ),
      ],
    );
  }

  Widget _buildNominees() {

    if (gratuityNominees.isEmpty) {
      return _emptyCard(
        "No nominees added yet. Add your PF / Gratuity nominees here.",
      );
    }

    return Column(
      children: gratuityNominees.map((nominee) {

        return Card(
          child: ListTile(
            title: Text(nominee['nominee_name'] ?? ''),
            subtitle: Text(
              "${nominee['relationship']} • ${nominee['share_percent']}%",
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInsuranceNominees() {

    if (insurancePolicies.isEmpty) {
      return _emptyCard(
        "No insurance policies assigned by HR yet.",
      );
    }

    return Column(
      children: insurancePolicies.map((policy) {

        return Card(
          child: ListTile(
            title: Text(policy['insurance_type'] ?? ''),
            subtitle: Text(policy['provider_name'] ?? ''),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDocuments() {

    if (employeeDocuments.isEmpty) {
      return _emptyCard("Nothing uploaded yet.");
    }

    return Column(
      children: employeeDocuments.map((doc) {

        return Card(
          child: ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: Text(doc['document_name'] ?? ''),
            subtitle: Text(doc['verification_status'] ?? ''),
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [

          Icon(
            Icons.inbox_outlined,
            size: 52,
            color: Colors.grey.shade400,
          ),

          const SizedBox(height: 12),

          Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  void _showAddNomineeDialog() {

    final nameController = TextEditingController();
    final relationController = TextEditingController();
    final shareController = TextEditingController();
    final dobController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {

        final isMobile =
            MediaQuery.of(context).size.width < 600;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 80,
            vertical: 24,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [

                      const Text(
                        "Add Nominee",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  const Text("Name *"),

                  const SizedBox(height: 8),

                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text("Relationship *"),

                  const SizedBox(height: 8),

                  TextField(
                    controller: relationController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Spouse, Mother',
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [

                            const Text("Share %"),

                            const SizedBox(height: 8),

                            TextField(
                              controller: shareController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [

                            const Text("Date of Birth"),

                            const SizedBox(height: 8),

                            TextField(
                              controller: dobController,
                              decoration: InputDecoration(
                                hintText: 'dd-mm-yyyy',
                                border: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  const Text("Address"),

                  const SizedBox(height: 8),

                  TextField(
                    controller: addressController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [

                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text("Cancel"),
                      ),

                      const SizedBox(width: 12),

                      ElevatedButton(
                        onPressed: () async {

                          await supabase
                              .from('gratuity_nominees')
                              .insert({

                            'employee_id': _emp?['id'],
                            'organization_id':
                            _emp?['organization_id'],
                            'nominee_name':
                            nameController.text,
                            'relationship':
                            relationController.text,
                            'share_percent':
                            shareController.text,
                            'date_of_birth':
                            DateFormat('yyyy-MM-dd').format(
                              DateFormat('dd-MM-yyyy')
                                  .parse(dobController.text),
                            ),
                            'address':
                            addressController.text,

                          });

                          Navigator.pop(context);

                          await onRefresh();
                        },
                        child: const Text(
                            "Submit for Approval"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  void _showUploadDocumentDialog() {

    String? selectedType;
    PlatformFile? selectedFile;
    bool uploading = false;

    final titleController =
    TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {

        final isMobile =
            MediaQuery.of(context).size.width < 600;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 100,
            vertical: 24,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 700,
              child: StatefulBuilder(
                builder: (context, setModalState) {

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [

                      Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [

                          const Text(
                            "Upload Document",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      const Text("Type *"),

                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(12),
                          ),
                        ),
                        items: const [

                          DropdownMenuItem(
                            value: 'personal_aadhaar',
                            child: Text('Aadhaar'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_pan',
                            child: Text('PAN'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_passport',
                            child: Text('Passport'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_address_proof',
                            child: Text('Address Proof'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_education',
                            child: Text('Education Certificate'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_experience',
                            child: Text('Experience Letter'),
                          ),

                          DropdownMenuItem(
                            value: 'personal_other',
                            child: Text('Other Document'),
                          ),
                        ],
                        onChanged: (v) {
                          setModalState(() {
                            selectedType = v;
                          });
                        },
                      ),

                      const SizedBox(height: 18),

                      const Text("Name / Title *"),

                      const SizedBox(height: 8),

                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText:
                          'e.g. AWS Solutions Architect',
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Text("File *"),

                      const SizedBox(height: 8),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.shade300,
                          ),
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [

                            ElevatedButton(
                              onPressed: () async {

                                final result =
                                await FilePicker.platform.pickFiles(
                                  allowMultiple: false,
                                  withData: true,
                                );

                                if (result != null &&
                                    result.files.isNotEmpty) {

                                  setModalState(() {
                                    selectedFile =
                                        result.files.first;
                                  });
                                }
                              },
                              child: const Text(
                                "Choose File",
                              ),
                            ),

                            const SizedBox(width: 16),

                            Expanded(
                              child: Text(
                                selectedFile?.name ??
                                    "No file chosen",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                  LayoutBuilder(
                  builder: (context, constraints) {

                  final isMobile =
                  constraints.maxWidth < 500;

                  return isMobile

                  ? Column(
                  children: [

                  SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                  onPressed: () {
                  Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                  ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                  onPressed: () {},
                  child: const Text(
                  "Submit for Verification",
                  ),
                  ),
                  ),
                  ],
                  )

                      : Row(
                  mainAxisAlignment:
                  MainAxisAlignment.end,
                  children: [

                  OutlinedButton(
                  onPressed: () {
                  Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                  ),

                  const SizedBox(width: 12),

                    ElevatedButton(
                      onPressed: () async {
                        setModalState(() {
                          uploading = true;
                        });

                        try {
                          if (titleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Enter document title"),
                              ),
                            );
                            return;
                          }

                          if (selectedType == null) {

                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content:
                                Text("Select document type"),
                              ),
                            );

                            return;
                          }

                          if (selectedFile == null) {

                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content:
                                Text("Choose a file"),
                              ),
                            );

                            return;
                          }

                          final bytes =
                              selectedFile!.bytes;

                          if (bytes == null) {

                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content:
                                Text("Invalid file"),
                              ),
                            );

                            return;
                          }

                          final filePath =
                              'personal/${supabase.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_${selectedFile!.name}';

                          await supabase.storage
                              .from('employee-documents')
                              .uploadBinary(
                            filePath,
                            bytes,
                            fileOptions:
                            FileOptions(
                              upsert: true,
                            ),
                          );

                          final fileUrl =
                          supabase.storage
                              .from('employee-documents')
                              .getPublicUrl(filePath);

                          await supabase
                              .from('employee_documents')
                              .insert({

                            'employee_id':
                            _emp?['id'],

                            'document_type':
                            selectedType,

                            'document_name':
                            titleController.text,

                            'file_url':
                            fileUrl,

                            'file_size':
                            selectedFile!.size,

                            'uploaded_by':
                            supabase.auth.currentUser!.id,

                          });

                          await onRefresh();

                          Navigator.pop(context);

                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.green,
                              content: Text("✅ Document uploaded successfully"),
                            ),
                          );


                        } catch (e) {
                          setModalState(() {
                            uploading = false;
                          });

                          debugPrint(e.toString());

                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString(),
                              ),
                            ),
                          );
                        }
                        finally {

                          setModalState(() {
                            uploading = false;
                          });
                        }
                      },
                      child: uploading
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        "Submit for Verification",
                      ),
                    ),
                  ],
                  );
                  },
                  ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
  void _showEditDetailsDialog() {

    final fullName =
    TextEditingController(
      text: _emp?['full_name'] ?? '',
    );

    final dob =
    TextEditingController(
      text: _formatDate(
        _emp?['date_of_birth'],
      ),
    );

    final phone =
    TextEditingController(
      text: _emp?['phone'] ?? '',
    );

    final personalEmail =
    TextEditingController(
      text: _emp?['personal_email'] ?? '',
    );

    final nationality =
    TextEditingController(
      text: _emp?['nationality'] ?? '',
    );

    final location =
    TextEditingController(
      text: _emp?['location'] ?? '',
    );

    final currentAddress =
    TextEditingController(
      text: _emp?['current_address'] ?? '',
    );

    final permanentAddress =
    TextEditingController(
      text: _emp?['permanent_address'] ?? '',
    );

    final emergencyName =
    TextEditingController(
      text: _emp?['emergency_contact_name'] ?? '',
    );

    final emergencyRelation =
    TextEditingController(
      text:
      _emp?['emergency_contact_relationship'] ?? '',
    );

    final emergencyPhone =
    TextEditingController(
      text:
      _emp?['emergency_contact_number'] ?? '',
    );

    String gender =
        _emp?['gender'] ?? '';

    String bloodGroup =
        _emp?['blood_group'] ?? 'O+';

    String maritalStatus =
        _emp?['marital_status'] ?? 'Single';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {

        return StatefulBuilder(
          builder: (context, setModalState) {

            return DraggableScrollableSheet(
              initialChildSize: 0.94,
              maxChildSize: 0.96,
              minChildSize: 0.85,
              builder: (_, controller) {

                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF4FF),
                    borderRadius:
                    BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [

                        Row(
                          children: [

                            Container(
                              padding:
                              const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.blue,
                              ),
                            ),

                            const SizedBox(width: 12),

                            const Text(
                              "Edit My Details",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        _editField(
                          "Full Name",
                          fullName,
                        ),

                        _editField(
                          "Date of Birth",
                          dob,
                        ),

                        _dropdownField(
                          title: "Gender",
                          value: gender,
                          items: const [
                            'Male',
                            'Female',
                            'Other',
                          ],
                          onChanged: (v) {
                            setModalState(() {
                              gender = v!;
                            });
                          },
                        ),

                        _dropdownField(
                          title: "Blood Group",
                          value: bloodGroup,
                          items: const [
                            'A+',
                            'A-',
                            'B+',
                            'B-',
                            'O+',
                            'O-',
                            'AB+',
                            'AB-',
                          ],
                          onChanged: (v) {
                            setModalState(() {
                              bloodGroup = v!;
                            });
                          },
                        ),

                        _dropdownField(
                          title: "Marital Status",
                          value: maritalStatus,
                          items: const [
                            'Single',
                            'Married',
                          ],
                          onChanged: (v) {
                            setModalState(() {
                              maritalStatus = v!;
                            });
                          },
                        ),

                        _editField(
                          "Nationality",
                          nationality,
                        ),

                        _editField(
                          "Phone",
                          phone,
                        ),

                        _editField(
                          "Personal Email",
                          personalEmail,
                        ),

                        _editField(
                          "City / Location",
                          location,
                        ),

                        _editField(
                          "Current Address",
                          currentAddress,
                          maxLines: 4,
                        ),

                        _editField(
                          "Permanent Address",
                          permanentAddress,
                          maxLines: 4,
                        ),

                        _editField(
                          "Emergency Contact Name",
                          emergencyName,
                        ),

                        _editField(
                          "Emergency Relationship",
                          emergencyRelation,
                        ),

                        _editField(
                          "Emergency Phone",
                          emergencyPhone,
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {

                              await supabase
                                  .from(
                                  'employee_records')
                                  .update({

                                'full_name':
                                fullName.text,

                                'date_of_birth':
                                dob.text,

                                'gender':
                                gender,

                                'blood_group':
                                bloodGroup,

                                'marital_status':
                                maritalStatus,

                                'nationality':
                                nationality.text,

                                'phone':
                                phone.text,

                                'personal_email':
                                personalEmail.text,

                                'location':
                                location.text,

                                'current_address':
                                currentAddress.text,

                                'permanent_address':
                                permanentAddress.text,

                                'emergency_contact_name':
                                emergencyName.text,

                                'emergency_contact_relationship':
                                emergencyRelation.text,

                                'emergency_contact_number':
                                emergencyPhone.text,

                              }).eq(
                                'id',
                                _emp?['id'],
                              );

                              Navigator.pop(context);

                              await onRefresh();
                            },
                            child: const Text(
                              "Save Changes",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  Widget _editField(
      String title,
      TextEditingController controller, {
        int maxLines = 1,
      }) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required String title,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          DropdownButtonFormField<String>(
            value: items.contains(value)
                ? value
                : null,
            items: items.map((e) {

              return DropdownMenuItem(
                value: e,
                child: Text(e),
              );
            }).toList(),
            onChanged: onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget webCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12), // Light border like web
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
