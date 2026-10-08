// my_profile_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../repositories/employee_repository.dart';
import '../repositories/file_repository.dart';
import '../repositories/profile_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'full_screen_profile_image.dart';
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
  final _employees = EmployeeRepository();
  final _profile = ProfileRepository();
  final _files = FileRepository();
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
  bool _isUploadingAvatar = false;
  bool _loading = false;

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
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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

  // ------------ Error helper ------------
  String _friendly(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) return 'Network problem. Check your connection and retry.';
      if (e.isForbidden) return "You don't have permission to perform this action.";
      if (e.isUnauthorized) return 'Session expired — please sign in again.';
      if (e.isServerError) return 'The server is busy right now. Please pull to retry.';
      return e.message;
    }
    if (e is AuthFlowException) return e.message;
    if (e is TimeoutException) {
      return 'Taking longer than usual — pull to retry.';
    }
    return e.toString();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------ Load / reload ------------
  @override
  Future<void> loadData() async {
    if (_loading) return;
    _loading = true;
    try {
      // The signed-in employee's own record (the API resolves "me" from the session).
      final emp = await _fetchEmployee().timeout(const Duration(seconds: 20));

      // Nominees, insurance and documents load in parallel. One of them failing (for example a
      // module switched off for the organization) leaves just that section empty.
      Future<List<Map<String, dynamic>>> safe(String what, Future<List<Map<String, dynamic>>> f) =>
          f.catchError((Object e) {
            debugPrint('$what load error: $e');
            return <Map<String, dynamic>>[];
          });
      final lists = await Future.wait<List<Map<String, dynamic>>>([
        safe('nominees', _profile.nominees()),
        safe('insurance', _profile.insurancePolicies()),
        safe('documents', _profile.documents()),
      ]);

      if (!mounted) return;
      setState(() {
        _emp = emp;
        gratuityNominees = lists[0];
        insurancePolicies = lists[1];
        employeeDocuments = lists[2];
        _org = null;
        _companyLogoUrl = null;
      });
    } on TimeoutException {
      _snack('Taking longer than usual — pull to retry.');
    } catch (e) {
      debugPrint('loadData error: $e');
      _snack(_friendly(e));
    } finally {
      _loading = false;
    }
  }

  /// The employee record with the encrypted fields (PAN, UAN, bank account, salary) filled in
  /// from the caller's own decrypted values. A decrypt failure just leaves them as returned.
  Future<Map<String, dynamic>> _fetchEmployee() async {
    final emp = await _employees.getMe();
    try {
      final sensitive = await _employees.getSensitiveProfile();
      sensitive.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) emp[key] = value;
      });
    } catch (e) {
      debugPrint('decrypt error: $e');
    }
    return emp;
  }

  Future<void> _reloadEmployee() async {
    try {
      final emp = await _fetchEmployee().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _emp = emp);
    } catch (e) {
      debugPrint('_reloadEmployee error: $e');
    }
  }

  Future<void> _reloadNominees() async {
    if (_emp == null) return;
    try {
      final rows = await _profile.nominees().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => gratuityNominees = rows);
    } catch (e) {
      debugPrint('_reloadNominees error: $e');
    }
  }

  Future<void> _reloadDocuments() async {
    if (_emp == null) return;
    try {
      final rows = await _profile.documents().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => employeeDocuments = rows);
    } catch (e) {
      debugPrint('_reloadDocuments error: $e');
    }
  }

  Future<void> _reloadInsurance() async {
    if (_emp == null) return;
    try {
      final rows = await _profile.insurancePolicies().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => insurancePolicies = rows);
    } catch (e) {
      debugPrint('_reloadInsurance error: $e');
    }
  }

  // ------------ Update profile (only success on a real server write) ------------
  Future<bool> _updateProfile(
      Map<String, dynamic> updates, {
        bool showSnack = true,
      }) async {
    try {
      final changes = Map<String, dynamic>.from(updates);
      // date_of_birth is a calendar date: send yyyy-MM-dd, not a timestamp.
      final dob = changes['date_of_birth'];
      if (dob is String && dob.length > 10) changes['date_of_birth'] = dob.substring(0, 10);

      await _employees.updateMe(changes);
      await _reloadEmployee();
      if (showSnack) _snack("Updated");
      return true;
    } catch (e) {
      _snack(_friendly(e));
      return false;
    }
  }

  // ------------ Documents: preview/download ------------
  /// A stored document reference is a `bucket/path` reference from the file API, a legacy bare path
  /// (`personal/<id>/x.pdf`) or a full URL from the Supabase era; the server resolves all three.
  String _docBucketHint(String raw) {
    final p = raw.startsWith('/') ? raw.substring(1) : raw;
    return p.startsWith('claim-documents/') ? 'claim-documents' : 'employee-documents';
  }

  Future<String?> _signedUrlForDoc(Map<String, dynamic> doc) async {
    final raw = (doc['file_url'] ?? '').toString();
    if (raw.isEmpty) {
      _snack('This document has no file.');
      return null;
    }
    final hint = _docBucketHint(raw);
    try {
      return await _files.url(raw, bucketHint: hint, expiresInSeconds: 3600);
    } on ApiException catch (e) {
      // Some old rows point at the other documents bucket: retry once with it.
      if (!raw.startsWith('http') && (e.statusCode == 404 || e.statusCode == 400)) {
        final other = hint == 'employee-documents' ? 'claim-documents' : 'employee-documents';
        try {
          return await _files.url(raw, bucketHint: other, expiresInSeconds: 3600);
        } catch (_) {}
      }
      _snack(_friendly(e));
      return null;
    } catch (e) {
      _snack(_friendly(e));
      return null;
    }
  }

  Future<void> _downloadDocument(
      Map<String, dynamic> doc,
      ) async {
    final url = await _signedUrlForDoc(doc);
    if (url == null) return;

    _snack("Downloading...");
    HttpClient? client;
    try {
      client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        _snack("Download failed (${resp.statusCode})");
        return;
      }
      final bytes = await consolidateHttpClientResponseBytes(resp);
      if (bytes.isEmpty) {
        _snack("Downloaded file is empty.");
        return;
      }

      // Filename + extension inference
      var fileName = (doc['document_name'] ?? 'document').toString();
      if (!fileName.contains('.')) {
        final ctype = resp.headers.contentType?.mimeType ?? '';
        final ext = _extensionFromMime(ctype);
        if (ext.isNotEmpty) fileName = '$fileName.$ext';
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _snack("Downloaded but could not open: ${result.message}");
      } else if (mounted) {
        _snack("Download completed");
      }
    } catch (e) {
      _snack("Download failed: ${_friendly(e)}");
    } finally {
      client?.close(force: true);
    }
  }

  String _extensionFromMime(String mime) {
    switch (mime) {
      case 'application/pdf':
        return 'pdf';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'application/msword':
        return 'doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return 'docx';
      case 'application/vnd.ms-excel':
        return 'xls';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return 'xlsx';
      default:
        return '';
    }
  }

  Future<void> _viewDocument(Map<String, dynamic> doc) async {
    final url = await _signedUrlForDoc(doc);
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } else {
      _snack("Cannot open preview.");
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Document"),
        content: const Text("Are you sure you want to delete this document?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _profile.deleteDocument(doc["id"].toString());

      // Best effort: also remove the stored file (old Supabase-era URLs cannot be removed here).
      final raw = (doc['file_url'] ?? '').toString();
      if (raw.isNotEmpty && !raw.startsWith('http')) {
        try {
          await _files.delete(raw, bucketHint: _docBucketHint(raw));
        } catch (e) {
          debugPrint('stored file remove error: $e');
        }
      }

      if (mounted) {
        setState(() {
          employeeDocuments.removeWhere(
                (e) => e["id"] == doc["id"],
          );
        });
      }

      _snack("Document deleted successfully");
    } catch (e) {
      _snack("Delete failed: ${_friendly(e)}");
    }
  }

  // ------------ Nominee edit ------------
  Future<void> _editSingleNominee(Map<String, dynamic> nominee) async {
    final name = TextEditingController(text: nominee['nominee_name'] ?? '');
    final relation =
    TextEditingController(text: nominee['relationship'] ?? '');
    final share = TextEditingController(
      text: nominee['share_percent']?.toString() ?? '',
    );

    try {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Edit Nominee"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration:
                  const InputDecoration(labelText: "Nominee Name"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relation,
                  decoration:
                  const InputDecoration(labelText: "Relationship"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: share,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Share %"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _profile.updateNominee(
                    nominee["id"].toString(),
                    name: name.text.trim(),
                    relationship: relation.text.trim(),
                    sharePercent: double.tryParse(share.text) ?? 0,
                  ).timeout(const Duration(seconds: 15));
                  if (mounted) Navigator.pop(context);
                  await _reloadNominees();
                  _snack("Nominee updated successfully");
                } catch (e) {
                  _snack("Update failed: ${_friendly(e)}");
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      relation.dispose();
      share.dispose();
    }
  }

  // ------------ Avatar ------------
  Future<void> _uploadAvatar() async {
    if (AuthService.instance.currentUser == null) {
      _snack("Session expired — please sign in again.");
      return;
    }
    final XFile? image =
    await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    try {
      setState(() => _isUploadingAvatar = true);
      final ts = DateTime.now().millisecondsSinceEpoch;

      // The photo goes through the API into the public avatars bucket; the API returns its URL,
      // which is then saved on the employee record.
      final uploaded = await _files.upload(
        bucket: 'avatars',
        bytes: await image.readAsBytes(),
        fileName: 'avatar_$ts.jpg',
        contentType: 'image/jpeg',
      );
      final publicUrl = uploaded.url;
      if (publicUrl == null) throw const ApiException(500, 'Upload did not return a photo URL');

      await _employees.setAvatarUrl(publicUrl);
      await _reloadEmployee();
      _snack("Profile photo updated.");
    } catch (e) {
      _snack("Upload failed: ${_friendly(e)}");
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Change Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _uploadAvatar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Remove Photo",
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeAvatar() async {
    try {
      setState(() => _isUploadingAvatar = true);
      await _employees.setAvatarUrl(null);
      await _reloadEmployee();
      _snack("Profile photo removed.");
    } catch (e) {
      _snack(_friendly(e));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ------------ Upload document (personal) ------------
  Future<void> _uploadDocument() async {
    if (AuthService.instance.currentUser == null) {
      _snack("Session expired — please sign in again.");
      return;
    }
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    try {
      setState(() => isLoading = true);
      final picked = result.files.single;
      final fileName = picked.name;

      // The file goes through the API into the employee's own documents folder; the
      // returned `bucket/path` reference is what the document record stores.
      final uploaded = await _files.upload(
        bucket: 'employee-documents',
        bytes: await File(picked.path!).readAsBytes(),
        fileName: fileName,
      );
      await _profile.addDocument(
        name: fileName,
        type: 'personal_upload',
        fileRef: uploaded.ref,
        size: uploaded.size,
      );

      await _reloadDocuments();
      _snack("Document uploaded successfully");
    } catch (e) {
      _snack("Upload failed: ${_friendly(e)}");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _editField(String title, String field, dynamic currentValue) {
    final controller =
    TextEditingController(text: currentValue?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $title"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: "Enter $title"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateProfile({field: controller.text});
              },
              child: const Text("Save")),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = raw is DateTime ? raw : DateTime.parse(raw.toString());
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  // ============ BUILD ============
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
                  decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]),
                  child: IconButton(
                    icon: SvgPicture.asset("assets/icons/menu.svg",
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                            EmployeeUi.primary, BlendMode.srcIn)),
                    onPressed: () =>
                        _scaffoldKey.currentState?.openEndDrawer(),
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
                    Text("Your personal and professional details",
                        style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: EmployeeUi.muted,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EmployeeUi.border),
              ),
              child: TabBar(
                controller: _tabController!,
                tabs: const [
                  Tab(text: 'Profile Details'),
                  Tab(text: 'Digital ID'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black87,
                indicator: BoxDecoration(
                  color: EmployeeUi.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ),
          ),
          SliverFillRemaining(
            child: buildRefreshable(
              skeleton: const SkeletonProfile(),
              childBuilder: () {
                return TabBarView(
                  controller: _tabController!,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        child: _buildProfileDetails(),
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildDigitalIdFront(width: cardWidth),
                          const SizedBox(height: 20),
                          _buildDigitalIdBack(width: cardWidth),
                        ],
                      ),
                    ),
                  ],
                );
              },
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
          if (index == 0) {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                        email: widget.email, employeeId: _emp!['id'])));
            return;
          }
          if (index == 1) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => LeavesScreen(
                        email: widget.email,
                        userData: widget.userData,
                        fetchHrmsContext: widget.fetchHrmsContext)));
            return;
          }
          if (index == 2) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TimeAttendanceScreen(
                        userEmail: widget.email,
                        userData: widget.userData,
                        fetchHrmsContext: widget.fetchHrmsContext)));
            return;
          }
          if (index == 3) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PayslipScreen(
                        userEmail: widget.email,
                        userData: widget.userData,
                        fetchHrmsContext: widget.fetchHrmsContext)));
            return;
          }
          if (index == 4) {
            _scaffoldKey.currentState?.openEndDrawer();
            return;
          }
        },
        items: [
          BottomNavigationBarItem(
              icon: SvgPicture.asset("assets/icons/dashboard.svg",
                  width: 22,
                  colorFilter: ColorFilter.mode(
                      _bottomTabIndex == 0 ? Colors.blueAccent : Colors.grey,
                      BlendMode.srcIn)),
              label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: SvgPicture.asset("assets/icons/leaves.svg",
                  width: 22,
                  colorFilter: ColorFilter.mode(
                      _bottomTabIndex == 1 ? Colors.blueAccent : Colors.grey,
                      BlendMode.srcIn)),
              label: 'Leave'),
          BottomNavigationBarItem(
              icon: SvgPicture.asset("assets/icons/attendance.svg",
                  width: 22,
                  colorFilter: ColorFilter.mode(
                      _bottomTabIndex == 2 ? Colors.blueAccent : Colors.grey,
                      BlendMode.srcIn)),
              label: 'Attendance'),
          BottomNavigationBarItem(
              icon: SvgPicture.asset("assets/icons/payroll.svg",
                  width: 22,
                  colorFilter: ColorFilter.mode(
                      _bottomTabIndex == 3 ? Colors.blueAccent : Colors.grey,
                      BlendMode.srcIn)),
              label: 'Payslip'),
          BottomNavigationBarItem(
              icon: SvgPicture.asset("assets/icons/menu.svg",
                  width: 22,
                  colorFilter: const ColorFilter.mode(
                      Colors.grey, BlendMode.srcIn)),
              label: 'More'),
        ],
      ),
    );
  }

  Widget _buildProfileDetails() {
    return Column(
      children: [
        _buildAvatarHeader(),
        _sectionCard(
          title: "Basic Information",
          color: const Color(0xFFEAF4FF),
          icon: Icons.badge_outlined,
          onEdit: () => _editBasicDialog(),
          child: _buildBasicInfo(),
        ),
        _sectionCard(
          title: "Work Information",
          color: const Color(0xFFF3ECFF),
          icon: Icons.work_outline,
          onEdit: null,
          child: _buildWorkInfo(),
        ),
        _sectionCard(
            title: "Reporting Chain",
            color: const Color(0xFFFFF2EB),
            icon: Icons.account_tree_outlined,
            child: _buildReportingChain()),
        _sectionCard(
          title: "Personal Information",
          color: const Color(0xFFFFF9E1),
          icon: Icons.person_outline,
          onEdit: () => _editPersonalDialog(),
          child: _buildPersonalInfo(),
        ),
        _sectionCard(
          title: "Bank Details",
          color: const Color(0xFFE8F5E9),
          icon: Icons.account_balance_outlined,
          onEdit: () => _editBankDialog(),
          child: _buildBankDetails(),
        ),
        _sectionCard(
          title: "Statutory Details",
          color: const Color(0xFFFCE4EC),
          icon: Icons.gavel_outlined,
          onEdit: () => _editStatutoryDialog(),
          child: _buildStatutoryDetails(),
        ),
        _sectionCard(
          title: "Emergency Contact",
          color: const Color(0xFFFFEBEE),
          icon: Icons.contact_phone_outlined,
          onEdit: () => _editEmergencyDialog(),
          child: _buildEmergencyContact(),
        ),
        _sectionCard(
          title: "My Nominees",
          color: const Color(0xFFFFF5EE),
          icon: Icons.groups_outlined,
          onEdit: () => _editNomineeDialog(),
          child: _buildNominees(),
        ),
        _sectionCard(
            title: "Insurance",
            color: const Color(0xFFEFFFFF),
            icon: Icons.health_and_safety_outlined,
            child: _buildInsurance()),
        _sectionCard(
          title: "Documents",
          color: const Color(0xFFEFFBFF),
          icon: Icons.description_outlined,
          onEdit: () => _uploadDocument(),
          child: _buildDocuments(),
        ),
      ],
    );
  }

  Widget _buildAvatarHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (_emp?['avatar_url'] == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenProfileImage(
                        imageUrl: _emp!['avatar_url'],
                      ),
                    ),
                  );
                },
                child: Hero(
                  tag: 'profile-image',
                  child: CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: _emp?['avatar_url'] != null
                        ? CachedNetworkImageProvider(_emp!['avatar_url'])
                        : null,
                    child: _emp?['avatar_url'] == null
                        ? Text(
                      (_emp?['full_name'] ?? "U")[0],
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.bold),
                    )
                        : null,
                  ),
                ),
              ),
              if (_isUploadingAvatar)
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(150, 0, 0, 0),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child:
                    CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              Positioned(
                bottom: -2,
                right: -2,
                child: InkWell(
                  onTap: _showAvatarOptions,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: EmployeeUi.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(_emp?['full_name'] ?? '', style: EmployeeUi.title(20)),
          Text(
            _emp?['designation'] ?? '',
            style: const TextStyle(
                color: EmployeeUi.primary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
      {required String title,
        required Color color,
        required IconData icon,
        required Widget child,
        VoidCallback? onEdit}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration:
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Colors.blue, size: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold))),
          if (onEdit != null)
            IconButton(
                onPressed: () {
                  try {
                    onEdit();
                  } catch (e) {
                    _snack("Could not open editor: ${_friendly(e)}");
                  }
                },
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: Colors.black54)),
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
        SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                    fontSize: 13))),
        Expanded(
            child: Text(value?.toString() ?? '-',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14))),
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
      _modernInfo("Account Number", _emp?['bank_account_no']),
      _modernInfo("IFSC Code", _emp?['bank_ifsc_code']),
    ]);
  }

  Widget _buildStatutoryDetails() {
    return Column(children: [
      _modernInfo("PAN Number", _emp?['pan_no']),
      _modernInfo("Aadhaar Number", _emp?['aadhaar_number']),
      _modernInfo("UAN Number", _emp?['uan_no']),
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
    return Column(
        children: gratuityNominees
            .map((n) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _modernInfo("Nominee", n['nominee_name']),
            _modernInfo("Relation", n['relationship']),
            _modernInfo("Share %", n['share_percent']),
          ]),
        ))
            .toList());
  }

  Widget _buildInsurance() {
    if (insurancePolicies.isEmpty) return const Text("No insurance assigned.");
    return Column(
        children: insurancePolicies
            .map((p) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _modernInfo("Type", p['insurance_type']),
            _modernInfo("Provider", p['provider_name']),
            _modernInfo("Policy #", p['policy_number']),
            _modernInfo("Sum Insured", p['sum_insured']),
          ]),
        ))
            .toList());
  }

  Widget _buildDocuments() {
    if (employeeDocuments.isEmpty) {
      return const Text("No documents uploaded.");
    }
    return Column(
      children: employeeDocuments.map((doc) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xffEAF4FF),
              child: Icon(Icons.description, color: Colors.blue),
            ),
            title: Text(doc['document_name'] ?? "Document",
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(doc['document_type'] ?? ""),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "Preview",
                  icon: const Icon(Icons.visibility),
                  onPressed: () => _viewDocument(doc),
                ),
                IconButton(
                  tooltip: "Delete",
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteDocument(doc),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ============ DIALOGS ============
  void _editPersonalDialog() {
    final currentAddress =
    TextEditingController(text: _emp?['current_address']?.toString() ?? '');
    final permanentAddress =
    TextEditingController(text: _emp?['permanent_address']?.toString() ?? '');
    String gender = (_emp?['gender'] ?? '').toString();
    String blood = (_emp?['blood_group'] ?? '').toString();
    String marital = (_emp?['marital_status'] ?? '').toString();

    const genders = ["Male", "Female", "Other"];
    const bloodGroups = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];
    const maritalStatus = ["Single", "Married", "Divorced", "Widowed"];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Edit Personal Information"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: genders.contains(gender) ? gender : null,
                      decoration:
                      const InputDecoration(labelText: "Gender"),
                      items: genders
                          .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => gender = v ?? ""),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                      bloodGroups.contains(blood) ? blood : null,
                      decoration:
                      const InputDecoration(labelText: "Blood Group"),
                      items: bloodGroups
                          .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => blood = v ?? ""),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: maritalStatus.contains(marital)
                          ? marital
                          : null,
                      decoration: const InputDecoration(
                          labelText: "Marital Status"),
                      items: maritalStatus
                          .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => marital = v ?? ""),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: currentAddress,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: "Current Address"),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: permanentAddress,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: "Permanent Address"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _updateProfile({
                        'gender': gender,
                        'blood_group': blood,
                        'marital_status': marital,
                        'current_address': currentAddress.text.trim(),
                        'permanent_address': permanentAddress.text.trim(),
                      });
                    },
                    child: const Text("Save")),
              ],
            );
          },
        );
      },
    ).then((_) {
      currentAddress.dispose();
      permanentAddress.dispose();
    });
  }

  void _editBankDialog() {
    final bName = TextEditingController(text: _emp?['bank_name']?.toString() ?? '');
    final acc = TextEditingController(text: _emp?['bank_account_no']?.toString() ?? '');
    final ifsc = TextEditingController(text: _emp?['bank_ifsc_code']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Bank Details"),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: bName,
                  decoration: const InputDecoration(labelText: "Bank Name")),
              TextField(
                  controller: acc,
                  decoration:
                  const InputDecoration(labelText: "Account Number")),
              TextField(
                  controller: ifsc,
                  decoration: const InputDecoration(labelText: "IFSC Code")),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateProfile({
                  'bank_name': bName.text.trim(),
                  'bank_account_no': acc.text.trim(),
                  'bank_ifsc_code': ifsc.text.trim(),
                });
              },
              child: const Text("Save")),
        ],
      ),
    ).then((_) {
      bName.dispose();
      acc.dispose();
      ifsc.dispose();
    });
  }

  Future<void> _editStatutoryDialog() async {
    final pan = TextEditingController(
      text: _emp?['pan_no']?.toString() ?? '',
    );

    final aadhaar = TextEditingController(
      text: _emp?['aadhaar_number']?.toString() ?? '',
    );

    final uan = TextEditingController(
      text: _emp?['uan_no']?.toString() ?? '',
    );

    try {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Edit Statutory Details"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: pan,
                    decoration:
                    const InputDecoration(labelText: "PAN Number")),
                const SizedBox(height: 12),
                TextField(
                    controller: aadhaar,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Aadhaar Number")),
                const SizedBox(height: 12),
                TextField(
                    controller: uan,
                    decoration:
                    const InputDecoration(labelText: "UAN Number")),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _updateProfile({
                    'pan_no': pan.text.trim(),
                    'aadhaar_number': aadhaar.text.trim(),
                    'uan_no': uan.text.trim(),
                  });
                },
                child: const Text("Save")),
          ],
        ),
      );
    } catch (e) {
      _snack("Could not open editor: ${_friendly(e)}");
    } finally {
      pan.dispose();
      aadhaar.dispose();
      uan.dispose();
    }
  }

  void _editEmergencyDialog() {
    final name =
    TextEditingController(text: _emp?['emergency_contact_name']?.toString() ?? '');
    final phone = TextEditingController(
        text: _emp?['emergency_contact_number']?.toString() ?? '');
    String relationship =
    (_emp?['emergency_contact_relationship'] ?? '').toString();

    const relations = [
      "Father",
      "Mother",
      "Brother",
      "Sister",
      "Spouse",
      "Friend",
      "Guardian",
      "Other",
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Edit Emergency Contact"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: "Contact Name")),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: relations.contains(relationship)
                          ? relationship
                          : null,
                      decoration:
                      const InputDecoration(labelText: "Relationship"),
                      items: relations
                          .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) =>
                          setStateDialog(() => relationship = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: const InputDecoration(
                          labelText: "Phone Number"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () async {
                      if (phone.text.length != 10) {
                        _snack("Enter valid mobile number");
                        return;
                      }
                      Navigator.pop(context);
                      await _updateProfile({
                        'emergency_contact_name': name.text.trim(),
                        'emergency_contact_relationship': relationship,
                        'emergency_contact_number': phone.text.trim(),
                      });
                    },
                    child: const Text("Save")),
              ],
            );
          },
        );
      },
    ).then((_) {
      name.dispose();
      phone.dispose();
    });
  }

  void _editBasicDialog() {
    final phone = TextEditingController(text: _emp?['phone']?.toString() ?? '');
    final email = TextEditingController(text: _emp?['email']?.toString() ?? '');
    DateTime? dob = _emp?['date_of_birth'] != null
        ? DateTime.tryParse(_emp!['date_of_birth'].toString())
        : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Edit Basic Information"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      enabled: false,
                      controller: TextEditingController(
                          text: _emp?['employee_id']?.toString() ?? ''),
                      decoration:
                      const InputDecoration(labelText: "Employee ID"),
                    ),
                    const SizedBox(height: 12),
                    // The email is the sign-in identity: only HR can change it, so it is shown read-only.
                    TextField(
                        enabled: false,
                        controller: email,
                        decoration:
                        const InputDecoration(labelText: "Email")),
                    const SizedBox(height: 12),
                    TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: "Phone Number")),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: dob ?? DateTime(2000),
                          firstDate: DateTime(1950),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => dob = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: "Date of Birth",
                            border: OutlineInputBorder()),
                        child: Text(dob == null
                            ? "Select Date"
                            : DateFormat("yyyy-MM-dd").format(dob!)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      enabled: false,
                      controller: TextEditingController(
                          text: _formatDate(_emp?['date_of_joining'])),
                      decoration:
                      const InputDecoration(labelText: "Date Joined"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _updateProfile({
                        'phone': phone.text.trim(),
                        'date_of_birth':
                        dob == null ? null : DateFormat('yyyy-MM-dd').format(dob!),
                      });
                    },
                    child: const Text("Save")),
              ],
            );
          },
        );
      },
    ).then((_) {
      phone.dispose();
      email.dispose();
    });
  }

  void _editWorkDialog() {
    final department = TextEditingController(
      text: _emp?['department']?.toString() ?? '',
    );

    final designation = TextEditingController(
      text: _emp?['designation']?.toString() ?? '',
    );

    final grade = TextEditingController(
      text: _emp?['grade_code']?.toString() ?? '',
    );

    final location = TextEditingController(
      text: _emp?['location']?.toString() ?? '',
    );

    final status = TextEditingController(
      text: _emp?['employment_status']?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Work Information"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: department,
                decoration: const InputDecoration(
                  labelText: "Department",
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: designation,
                decoration: const InputDecoration(
                  labelText: "Designation",
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: grade,
                decoration: const InputDecoration(
                  labelText: "Grade",
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: location,
                decoration: const InputDecoration(
                  labelText: "Location",
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: status,
                decoration: const InputDecoration(
                  labelText: "Employment Status",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final updates = {
                'department': department.text.trim(),
                'designation': designation.text.trim(),
                'grade_code': grade.text.trim(),
                'location': location.text.trim(),
                'employment_status': status.text.trim(),
              };

              Navigator.pop(context);

              if (!mounted) return;

              await _updateProfile(updates);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    ).then((_) {
      department.dispose();
      designation.dispose();
      grade.dispose();
      location.dispose();
      status.dispose();
    });
  }

  void _editNomineeDialog() {
    if (gratuityNominees.isEmpty) {
      _snack("No nominees available.");
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Nominee"),
        content: SizedBox(
          width: 350,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: gratuityNominees.length,
            itemBuilder: (context, index) {
              final nominee = gratuityNominees[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(nominee['nominee_name'] ?? ''),
                subtitle: Text(nominee['relationship'] ?? ''),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  Navigator.pop(context);
                  _editSingleNominee(nominee);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ============ Digital ID ============
  Widget _buildDigitalIdFront({required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
          ]),
      child: Column(children: [
        if (_companyLogoUrl != null)
          CachedNetworkImage(
            imageUrl: _companyLogoUrl!,
            height: 72,
            fit: BoxFit.contain,
          ),
        const Divider(height: 32),
        CircleAvatar(
            radius: 40,
            backgroundColor: Colors.blue.shade100,
            backgroundImage: _emp?['avatar_url'] != null
                ? CachedNetworkImageProvider(_emp!['avatar_url'])
                : null,
            child: _emp?['avatar_url'] == null
                ? Text(_emp?['full_name']?[0] ?? '')
                : null),
        const SizedBox(height: 16),
        Text(_emp?['full_name'] ?? '',
            style: GoogleFonts.montserrat(
                fontSize: 20, fontWeight: FontWeight.bold)),
        Text(_emp?['designation'] ?? '',
            style: const TextStyle(
                color: Colors.blueAccent, fontWeight: FontWeight.w600)),
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
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:
          Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_org?['name'] ?? '',
            style:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        const Text("Address:",
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        Text(_org?['location'] ?? '-'),
        const SizedBox(height: 20),
        const Text("Emergency Contact:",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _idRow("Name", _emp?['emergency_contact_name']),
        _idRow("Relation", _emp?['emergency_contact_relationship']),
        _idRow("Number", _emp?['emergency_contact_number']),
      ]),
    );
  }

  Widget _idRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Flexible(
              child: Text(value?.toString() ?? '-',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
    );
  }
}
