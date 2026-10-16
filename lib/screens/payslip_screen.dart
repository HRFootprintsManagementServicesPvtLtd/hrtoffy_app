import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../core/api/api_client.dart';
import '../core/payslip_files.dart';
import '../repositories/employee_repository.dart';
import '../repositories/organization_repository.dart';
import '../repositories/payslip_repository.dart';
import '../widgets/skeleton_layouts.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';

import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import '../widgets/employee_ui.dart';

/// Fixed texts for failures: the server's own text is never shown.
const String kPayslipListFailedMessage =
    "Couldn't load your payslips. Please try again.";
const String kPayslipPdfFailedMessage =
    "Couldn't prepare the payslip PDF. Please try again.";

/// The server refuses a payslip that is not the caller's own, is not released, or whose salary the caller may not read,
/// and answers all of those the same way (403) so that payslip ids cannot be probed.
const String kPayslipForbiddenMessage =
    "You don't have access to this payslip. Please contact HR if you think this is a mistake.";
const String kPayslipPdfNotAvailableMessage =
    "This payslip isn't available right now. Please contact HR.";
const String kPayslipSavedNoViewerMessage =
    "Payslip saved, but no app on this device could open it. Install a PDF viewer and try again.";

/// What the employee sees when the PDF of a payslip could not be retrieved. Never the server's own text.
String payslipPdfErrorMessage(Object e) {
  if (e is ApiException) {
    if (e.isNetworkError)
      return 'Network problem. Check your connection and try again.';
    if (e.isUnauthorized) return 'Session expired. Please sign in again.';
    if (e.isForbidden) return kPayslipForbiddenMessage;
    if (e.isNotFound) return kPayslipPdfNotAvailableMessage;
  }
  return kPayslipPdfFailedMessage;
}

/// The payslip was retrieved and saved, but the device could not open it.
class PayslipOpenFailedException implements Exception {
  const PayslipOpenFailedException();
}

/// What a period with no payslip shows. The server only lists payslips released to the employee, so "not
/// released" and "not generated" look the same to the app by design.
const String kPayslipNoneForPeriodMessage =
    'No payslip is available for this month and year.';

/// The server lists at most the 12 most recent released payslips and has no paging for it, so a period older than
/// the oldest one listed (when the list is full) is not shown as "none": older payslips may exist.
const int kPayslipListCap = 12;
const String kPayslipOlderMessage =
    'Only your 12 most recent released payslips can be shown here. An older payslip may exist; please contact HR for it.';
const String kPayslipFuturePeriodMessage =
    'Payslip not processed for this month and year.';

/// Saves a downloaded payslip PDF and returns where it went (the default also opens it).
typedef PayslipFileSaver =
    Future<String> Function(PayslipPdf pdf, {required bool open});

/// Payslip PDFs are written, unencrypted, to the app's private temporary directory (see [PayslipFiles]): other apps
/// cannot read it, but the files are NOT encrypted. They are deleted by the app after a delay once opened, when stale
/// at app start, and at sign-out; none of that is guaranteed (see [PayslipFiles] for the limits). The file is not
/// deleted right after it is opened, because the viewer may not have read it yet.
Future<String> _saveAndOpenPdf(PayslipPdf pdf, {required bool open}) async {
  final files = PayslipFiles.instance;
  final path = await files.save(pdf.bytes, pdf.fileName);
  try {
    if (open) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) throw const PayslipOpenFailedException();
    }
  } finally {
    files.scheduleDelete(path);
  }
  return path;
}

/// Saves a copy of [pdf] where the employee chooses (the system "save as" dialog), so it outlives the app's private
/// cache. True only when a file was actually written; false when the dialog was cancelled.
typedef PayslipFileExporter = Future<bool> Function(PayslipPdf pdf);

Future<bool> _exportPdf(PayslipPdf pdf) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save payslip',
    fileName: safePayslipFileName(pdf.fileName),
    bytes: pdf.bytes,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return path != null;
}

class PayslipScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;
  final EmployeeRepository? employeeRepository;
  final OrganizationRepository? organizationRepository;
  final PayslipRepository? payslipRepository;
  final PayslipFileSaver? fileSaver;
  final PayslipFileExporter? fileExporter;

  const PayslipScreen({
    Key? key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
    this.employeeRepository,
    this.organizationRepository,
    this.payslipRepository,
    this.fileSaver,
    this.fileExporter,
  }) : super(key: key);

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  late final EmployeeRepository _employees =
      widget.employeeRepository ?? EmployeeRepository();
  late final OrganizationRepository _orgs =
      widget.organizationRepository ?? OrganizationRepository();
  late final PayslipRepository _payslips =
      widget.payslipRepository ?? PayslipRepository();
  late final PayslipFileSaver _saveFile = widget.fileSaver ?? _saveAndOpenPdf;
  late final PayslipFileExporter _exportFile = widget.fileExporter ?? _exportPdf;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 3; // Payslip tab index

  bool isLoading = true;
  String? errorMsg;
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  Map<String, dynamic>? employee;
  Map<String, dynamic>? organization;

  /// The payslips the server has released to this employee; null until loaded or when loading failed.
  List<PayslipSummary>? released;
  bool releasedFailed = false;

  /// The released payslip listed for the selected period, if any. Nothing is requested when a period is chosen: the
  /// payslip is only fetched (as a PDF, `GET /reports/payslip-pdf?payslipId=`) when the employee asks to view or save
  /// it, and every fetch is authorized and audited by the server.
  PayslipSummary? selected;

  /// The PDF last fetched for [_pdfFor], kept so a second action on the same payslip does not fetch it again.
  PayslipPdf? _pdf;
  String? _pdfFor;
  bool isFuturePeriod = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }
  // -------------------------
  // Loading (employee, organization, released payslips, the selected payslip)
  // -------------------------
  Future<void> _initialize() async {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });
    try {
      employee = await _employees.getMe();
    } catch (_) {
      // Never show the server's text.
      if (!mounted) return;
      setState(() {
        errorMsg = "Couldn't load your details. Please try again.";
        isLoading = false;
      });
      return;
    }
    // Branding is cosmetic: a failure just means no name/logo.
    try {
      organization = await _orgs.getOrganization();
    } catch (_) {
      organization = null;
    }
    await _loadReleased();
    if (!mounted) return;
    setState(() => isLoading = false);
    await _processPeriodChange(selectedMonth, selectedYear);
  }

  Future<void> _loadReleased() async {
    try {
      final list = await _payslips.payslips();
      released = list;
      releasedFailed = false;
      // Start on the latest released payslip (the server lists them newest first).
      if (list.isNotEmpty) {
        selectedMonth = list.first.month;
        selectedYear = list.first.year;
      }
    } catch (_) {
      released = null;
      releasedFailed = true;
    }
  }

  PayslipSummary? _summaryFor(int month, int year) {
    for (final p in released ?? const <PayslipSummary>[]) {
      if (p.month == month && p.year == year) return p;
    }
    return null;
  }

  /// The list is full (the server's cap) and [month]/[year] is older than its oldest entry: the payslip may exist
  /// but was cut off by the cap. [released] is sorted newest first.
  bool _isBeyondListedHistory(int month, int year) {
    final list = released;
    if (list == null ||
        list.length < kPayslipListCap ||
        _summaryFor(month, year) != null)
      return false;
    final oldest = list.last;
    return year * 12 + month < oldest.year * 12 + oldest.month;
  }

  /// A period change only selects what the server has listed for it: no request is made. (The payslip itself is read
  /// with `GET /reports/payslip-pdf?payslipId=` when the employee asks to view or save it.)
  Future<void> _processPeriodChange(int month, int year) async {
    final now = DateTime.now();
    final future = DateTime(year, month).isAfter(DateTime(now.year, now.month));
    final summary = future || releasedFailed ? null : _summaryFor(month, year);
    setState(() {
      isFuturePeriod = future;
      selected = summary;
      if (_pdfFor != summary?.id) {
        _pdf = null;
        _pdfFor = null;
      }
    });
  }

  // -------------------------
  // Downloads
  // -------------------------
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The selected payslip's PDF, fetched once and kept. A failure is a [ApiException] etc. for the caller to word.
  Future<PayslipPdf> _pdfForSelected() async {
    final s = selected!;
    final cached = _pdf;
    if (cached != null && _pdfFor == s.id) return cached;
    final pdf = await _payslips.pdf(s.id);
    if (mounted && selected?.id == s.id) {
      setState(() {
        _pdf = pdf;
        _pdfFor = s.id;
      });
    }
    return pdf;
  }

  /// The selected payslip as a PDF from the server, saved to the app's private folder and opened. Success is reported
  /// only after the PDF was retrieved, validated and written; a device that cannot open it is told so. Whatever the
  /// PDF says (including a net pay of 0, which can be genuine) is the server's: it is neither judged nor changed here.
  /// A 403 here is the server's real answer for this payslip (it decides ownership, release and salary access).
  Future<void> _downloadSingle() async {
    if (selected == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final pdf = await _pdfForSelected();
      await _saveFile(pdf, open: true);
      _toast('Payslip saved.');
    } on PayslipOpenFailedException {
      _toast(kPayslipSavedNoViewerMessage);
    } catch (e) {
      _toast(payslipPdfErrorMessage(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Saves a copy of the selected payslip where the employee chooses (system "save as"). Reported only when written.
  Future<void> _saveSelectedCopy() async {
    if (selected == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final pdf = await _pdfForSelected();
      if (await _exportFile(pdf)) _toast('Payslip saved.');
    } catch (e) {
      _toast(payslipPdfErrorMessage(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// The newest [count] payslips the server has released, each fetched as its own PDF (nothing is merged or recomputed
  /// on the device). They are held in memory and offered in a list where each one can be opened or saved to a place
  /// the employee chooses: the app's private cache is not reachable by the employee and is cleaned up after a while.
  Future<void> _downloadRecent(int count) async {
    if (_downloading) return;
    final wanted = (released ?? const <PayslipSummary>[]).take(count).toList();
    if (wanted.isEmpty) {
      _toast('No released payslips to download.');
      return;
    }
    setState(() => _downloading = true);
    final ready = <PayslipPdf>[];
    Object? firstError;
    try {
      for (final s in wanted) {
        try {
          ready.add(await _payslips.pdf(s.id));
        } catch (e) {
          firstError ??= e;
          // A refusal (403) or an expired session will not get better for the next payslip.
          if (e is ApiException && (e.isForbidden || e.isUnauthorized)) break;
        }
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
    if (!mounted) return;
    if (ready.isEmpty) {
      _toast(payslipPdfErrorMessage(firstError ?? 'none'));
      return;
    }
    if (ready.length < wanted.length) {
      _toast(
        '${ready.length} of ${wanted.length} payslips were prepared. ${payslipPdfErrorMessage(firstError ?? 'none')}',
      );
    }
    await _showReadyPayslips(ready);
  }

  Future<void> _showReadyPayslips(List<PayslipPdf> ready) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    ready.length == 1
                        ? '1 payslip ready'
                        : '${ready.length} payslips ready',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Open a payslip, or save a copy to your device.',
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final pdf in ready)
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf),
                          title: Text(
                            safePayslipFileName(pdf.fileName),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Open',
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () => _openReady(pdf),
                              ),
                              IconButton(
                                tooltip: 'Save a copy',
                                icon: const Icon(Icons.save_alt),
                                onPressed: () => _saveCopy(pdf),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Close'),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openReady(PayslipPdf pdf) async {
    try {
      await _saveFile(pdf, open: true);
    } on PayslipOpenFailedException {
      _toast(kPayslipSavedNoViewerMessage);
    } catch (_) {
      _toast(kPayslipPdfFailedMessage);
    }
  }

  Future<void> _saveCopy(PayslipPdf pdf) async {
    try {
      if (await _exportFile(pdf)) _toast('Payslip saved.');
    } catch (_) {
      _toast("Couldn't save the payslip. Please try again.");
    }
  }

  void _showBulkOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              for (final n in const [3, 6, 12])
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text('Latest $n payslips (PDF)'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _downloadRecent(n);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------
  // UI
  // -------------------------
  Widget _employeeCard() {
    if (employee == null) return const SizedBox();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: Colors.blue[700], size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee?['full_name'] ?? '',
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${employee?['employee_id'] ?? ''} · ${employee?['designation'] ?? ''} · ${employee?['department'] ?? ''}',
                  style: GoogleFonts.montserrat(
                    color: Colors.grey[700],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// True when the list is complete (not cut off by the server's cap of 12), so a period that is not in it has no
  /// released payslip and need not be selectable. With nothing released, or a full list, every period stays selectable.
  bool get _restrictToListed {
    final list = released;
    return list != null && list.isNotEmpty && list.length < kPayslipListCap;
  }

  /// "Payslips are available from November 2025 onwards.": the oldest released payslip the server listed, only when the
  /// list is complete (a full list may have older payslips cut off, so no start month can be claimed).
  String? get _availableFromText {
    final list = released;
    if (!_restrictToListed || list == null) return null;
    final oldest = list.last;
    return 'Payslips are available from ${DateFormat.MMMM().format(DateTime(oldest.year, oldest.month))} ${oldest.year} onwards.';
  }

  Widget _periodSelectorCard() {
    final months = List.generate(12, (i) => i + 1);
    // Every month and the recent years are always selectable; a period without a released payslip says so
    // (kPayslipNoneForPeriodMessage) instead of being hidden or greyed out.
    final defaultYears = List.generate(6, (i) => DateTime.now().year - 5 + i);
    final years = {...defaultYears, ...?released?.map((p) => p.year), selectedYear}.toList()..sort((a, b) => b.compareTo(a));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: Colors.blue[800],
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Select Period',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Choose the month and year to view your payslip',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  value: selectedMonth,
                  decoration: InputDecoration(
                    labelText: 'Month',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: months.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(
                        DateFormat.MMMM().format(DateTime(2020, m)),
                        style: GoogleFonts.montserrat(),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => selectedMonth = val);
                    await _processPeriodChange(selectedMonth, selectedYear);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: selectedYear,
                  decoration: InputDecoration(
                    labelText: 'Year',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: years
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text(
                            y.toString(),
                            style: GoogleFonts.montserrat(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => selectedYear = val);
                    await _processPeriodChange(selectedMonth, selectedYear);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle(bool enabled) => ElevatedButton.styleFrom(
    backgroundColor: Colors.blue[700],
    disabledBackgroundColor: Colors.blue[700]!.withValues(alpha: 0.35),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );

  Widget _actionsRow() {
    final canBulk = !_downloading && (released?.isNotEmpty ?? false);
    final canSingle = !_downloading && selected != null;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canBulk ? _showBulkOptionsMenu : null,
            icon: const Icon(Icons.file_download_outlined, color: Colors.white),
            label: Text(
              'Bulk Download',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            style: _buttonStyle(canBulk),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canSingle ? _downloadSingle : null,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_outlined, color: Colors.white),
            label: Text(
              'Download PDF',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            style: _buttonStyle(canSingle),
          ),
        ),
      ],
    );
  }

  Widget _infoChipAndBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFDF7F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange[100]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.orange[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _availableFromText ??
                  'Payslips appear here once your organization releases them to you.',
              style: GoogleFonts.montserrat(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(IconData icon, String text, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(color: Colors.grey[700]),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  /// "₹46,200.00" for a number; "Not available" when the server gave none (never a made-up 0).
  String _money(num? v) => v == null
      ? 'Not available'
      : NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: 2,
        ).format(v);

  /// The payslip listed for the selected period. It shows what the server has said so far: that the payslip is released
  /// to this employee, and, once the PDF has been fetched, the title and net pay the server reported (a genuine 0 stays
  /// 0). The amounts are never computed or guessed here.
  Widget _selectedPayslipCard() {
    final s = selected!;
    final pdf = _pdfFor == s.id ? _pdf : null;
    final title = (pdf?.summary ?? '').isNotEmpty
        ? pdf!.summary!
        : 'Payslip for ${DateFormat.MMMM().format(DateTime(s.year, s.month))} ${s.year}';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Released to you',
            style: GoogleFonts.montserrat(fontSize: 12, color: Colors.green[700]),
          ),
          if (pdf?.netPay != null) ...[
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('NET PAY', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700)),
                Text(_money(pdf!.netPay), style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _downloadSingle,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('View PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _saveSelectedCopy,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save a copy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payslipCardOrMessage() {
    if (errorMsg != null)
      return _messageCard(Icons.error_outline, errorMsg!, onRetry: _initialize);
    if (releasedFailed)
      return _messageCard(
        Icons.error_outline,
        kPayslipListFailedMessage,
        onRetry: _initialize,
      );
    if (isFuturePeriod)
      return _messageCard(Icons.schedule, kPayslipFuturePeriodMessage);
    if (selected != null) return _selectedPayslipCard();
    if (_isBeyondListedHistory(selectedMonth, selectedYear))
      return _messageCard(Icons.history, kPayslipOlderMessage);
    return _messageCard(
      Icons.receipt_long,
      (released?.isEmpty ?? true)
          ? 'No payslips have been released to you yet.'
          : kPayslipNoneForPeriodMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.userEmail,
        userData: employee ?? {},
        companyLogoUrl: organization?['logo_url'],
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.payroll,
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
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: SvgPicture.asset(
                      "assets/icons/menu.svg",
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        EmployeeUi.primary,
                        BlendMode.srcIn,
                      ),
                    ),
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
                    colors: [Color(0xFFEBDFF6), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Payroll & Payslips", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text(
                      "View and download your salary statements",
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: EmployeeUi.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: isLoading
                ? const SkeletonPayslipPage()
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const EmployeeSectionHeader(
                          title: 'My Payslips',
                          subtitle: 'View and download your payslips',
                        ),
                        const SizedBox(height: 12),
                        _employeeCard(),
                        const SizedBox(height: 12),
                        _periodSelectorCard(),
                        const SizedBox(height: 12),
                        _actionsRow(),
                        const SizedBox(height: 12),
                        if (selected == null || _availableFromText != null)
                          _infoChipAndBanner(),
                        const SizedBox(height: 12),
                        _payslipCardOrMessage(),
                      ],
                    ),
                  ),
          ),

          // 🤖 TOFFY CHAT OVERLAY
        ],
      ),

      // 🔥 SVG BOTTOM NAVIGATION
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
          setState(() => _bottomTabIndex = index);

          switch (index) {
            case 0:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    email: widget.userEmail,
                    employeeId: employee?['id'] ?? '',
                  ),
                ),
              );
              break;

            case 1:
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
              break;

            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimeAttendanceScreen(
                    userEmail: widget.userEmail,
                    userData: widget.userData, // ✅ FIX
                    fetchHrmsContext: widget.fetchHrmsContext, // ✅ FIX
                  ),
                ),
              );
              break;

            case 3:
              // ✅ CORRECT: already on Payslip → do nothing
              break;

            case 4:
              _scaffoldKey.currentState?.openEndDrawer();
              break;
          }
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
    );
  }
}
