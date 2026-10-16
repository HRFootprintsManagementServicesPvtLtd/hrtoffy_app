import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/repositories/employee_repository.dart';
import 'package:hrms_app/repositories/organization_repository.dart';
import 'package:hrms_app/repositories/payslip_repository.dart';
import 'package:hrms_app/screens/payslip_screen.dart';
import 'package:intl/intl.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';
const _pdfRoute = '$_org/reports/payslip-pdf';
const _detailsRoute = '$_org/reports/payslip-document';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 4200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _now = DateTime.now();
final _current = DateTime(_now.year, _now.month);
DateTime _monthsAgo(int n) => DateTime(_now.year, _now.month - n);
String _monthName(DateTime d) => DateFormat.MMMM().format(d);

class _Saved {
  final List<PayslipPdf> files = [];
  final List<bool> opened = [];
  final List<PayslipPdf> exported = [];
  bool openFails = false;
  bool exportCancelled = false;
  Future<bool> export(PayslipPdf pdf) async {
    if (exportCancelled) return false;
    exported.add(pdf);
    return true;
  }

  Future<String> call(PayslipPdf pdf, {required bool open}) async {
    files.add(pdf);
    opened.add(open);
    if (open && openFails) throw const PayslipOpenFailedException();
    return '/tmp/${pdf.fileName}';
  }
}

Widget _screen(TestSession s, _Saved saved) => MaterialApp(
  home: PayslipScreen(
    userEmail: 'me@x.com',
    userData: const {'id': testEmployeeId},
    fetchHrmsContext: () async => {},
    employeeRepository: EmployeeRepository(auth: s.auth),
    organizationRepository: OrganizationRepository(auth: s.auth),
    payslipRepository: PayslipRepository(auth: s.auth),
    fileSaver: saved.call,
    fileExporter: saved.export,
  ),
);

final _boom = jsonResponse({
  'success': false,
  'error': {'message': 'db exploded at https://api.hrtoffy.in'},
}, 500);

Map<String, dynamic> _row(String id, DateTime d) => {
  'id': id,
  'employee_id': testEmployeeId,
  'month': d.month,
  'year': d.year,
  'financial_year': '2026-27',
};

String _pdf64() => base64Encode(utf8.encode('%PDF-1.4 test'));

/// A staging-like server. `payslip-document` answers 403 for everything, because that is what the deployed server does
/// for a route it does not have (it is caught by the generic `/reports/:reportId`, which needs `reports.view`): the app
/// must never ask for it.
Future<TestSession> _session({
  List<DateTime>? periods,
  Set<String> failing = const {},
  Map<String, int> statuses = const {},
  Set<String> failPdfIds = const {},
  Object? pdfNet = 46200.5,
  Object? pdfBody,
}) {
  final ps = periods ?? [_current, _monthsAgo(1)];
  final byId = {for (var i = 0; i < ps.length; i++) 'p$i': ps[i]};
  return signedIn((req) async {
    if (req.method != 'GET')
      return jsonResponse({
        'success': false,
        'error': {'message': 'unexpected write'},
      }, 500);
    final path = req.url.path;
    if (failing.contains(path)) return _boom;
    if (statuses.containsKey(path)) {
      return jsonResponse({
        'success': false,
        'error': {'message': 'server text that must not be shown'},
      }, statuses[path]!);
    }
    switch (path) {
      case '$_org/employees/me':
        return ok({
          'id': testEmployeeId,
          'organizationId': testOrgId,
          'fullName': 'Asha Rao',
          'employeeId': 'GC-001',
          'designation': 'Analyst',
          'department': 'Finance',
        });
      case '$_org/info':
        return ok({'organization_id': testOrgId, 'organization_name': 'Goodclap'});
      case '$_org/branding':
        return ok({'logoUrl': null});
      case '$_org/payroll/employees/$testEmployeeId/payslips':
        return ok({
          'items': [for (final e in byId.entries) _row(e.key, e.value)],
          'total': ps.length,
        });
      case _detailsRoute:
        return jsonResponse({
          'success': false,
          'error': {'message': 'Missing permission reports.view'},
        }, 403);
      case _pdfRoute:
        final id = req.url.queryParameters['payslipId'] ?? '';
        if (failPdfIds.contains(id)) return _boom;
        final d = byId[id];
        if (d == null) {
          return jsonResponse({
            'success': false,
            'error': {'message': 'You do not have access to this payslip'},
          }, 403);
        }
        return ok(
          pdfBody ??
              {
                'filename': 'Payslip_$id.pdf',
                'contentType': 'application/pdf',
                'base64': _pdf64(),
                'netPay': pdfNet,
                'summary': 'Payslip for ${_monthName(d)} ${d.year}',
              },
        );
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected $path'},
    }, 404);
  });
}

Finder get _viewPdf => find.widgetWithText(OutlinedButton, 'View PDF');
Finder get _saveCopy => find.widgetWithText(OutlinedButton, 'Save a copy');

int _pdfRequests(TestSession s) => s.requests.where((r) => r.path == _pdfRoute).length;

void main() {
  group('loading and selecting', () {
    testWidgets('loads the employee, organization and released list, selects the newest payslip and requests no payslip yet', (tester) async {
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);

      expect(s.requests.map((r) => '${r.method} ${r.path}').toSet(), {
        'GET $_org/employees/me',
        'GET $_org/info',
        'GET $_org/branding',
        'GET $_org/payroll/employees/$testEmployeeId/payslips',
      });
      expect(find.text('Payslip for ${_monthName(_current)} ${_current.year}'), findsOneWidget);
      expect(find.text('Released to you'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing, reason: 'no amount before the server has been asked');
    });

    testWidgets('the retired payslip-document route is never requested, however the screen is used', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      await tester.tap(_saveCopy);
      await _settle(tester);
      expect(s.requests.where((r) => r.path.contains('payslip-document')), isEmpty);
    });

    testWidgets('choosing an earlier released month shows its card and requests nothing; an unlisted month can be chosen and says there is no payslip', (tester) async {
      if (_now.month < 3) {
        markTestSkipped('needs at least three months in the current year');
        return;
      }
      _tall(tester);
      final s = await _session();
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      final before = s.requests.length;

      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_monthName(_monthsAgo(1))).last);
      await _settle(tester);
      expect(find.text('Payslip for ${_monthName(_monthsAgo(1))} ${_monthsAgo(1).year}'), findsOneWidget);
      expect(s.requests.length, before, reason: 'selecting a period asks the server for nothing');

      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_monthName(_monthsAgo(2))).last);
      await _settle(tester);
      expect(find.text(kPayslipNoneForPeriodMessage), findsOneWidget, reason: 'a month without a released payslip says so');
      expect(find.text('Payslip for ${_monthName(_monthsAgo(1))} ${_monthsAgo(1).year}'), findsNothing);
      expect(s.requests.length, before, reason: 'still asks the server for nothing');
    });

    testWidgets('with nothing released the screen says so', (tester) async {
      _tall(tester);
      final s = await _session(periods: []);
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      expect(find.text('No payslips have been released to you yet.'), findsOneWidget);
      expect(find.textContaining('are available from'), findsNothing);
      expect(_viewPdf, findsNothing);
    });

    testWidgets('a failed list is a failure with Retry, not "nothing released"', (tester) async {
      _tall(tester);
      final s = await _session(failing: {'$_org/payroll/employees/$testEmployeeId/payslips'});
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      expect(find.text(kPayslipListFailedMessage), findsOneWidget);
      expect(find.text('No payslips have been released to you yet.'), findsNothing);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('Download PDF in the action row is enabled only when a payslip is selected', (tester) async {
      _tall(tester);
      final withOne = await _session();
      await tester.pumpWidget(_screen(withOne, _Saved()));
      await _settle(tester);
      var b = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Download PDF'), matching: find.byType(ElevatedButton)));
      expect(b.onPressed, isNotNull);

      final none = await _session(periods: []);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_screen(none, _Saved()));
      await _settle(tester);
      b = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Download PDF'), matching: find.byType(ElevatedButton)));
      expect(b.onPressed, isNull);
    });
  });

  group('available periods', () {
    testWidgets('"Payslips are available from <month year> onwards" comes from the oldest listed payslip, shown with the payslip', (tester) async {
      _tall(tester);
      final s = await _session(periods: [_current, _monthsAgo(1), _monthsAgo(3)]);
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      final oldest = _monthsAgo(3);
      expect(find.text('Payslips are available from ${_monthName(oldest)} ${oldest.year} onwards.'), findsOneWidget);
      expect(find.text('Released to you'), findsOneWidget);
    });

    testWidgets('a full list (the server cap) claims no start month and leaves every period selectable', (tester) async {
      _tall(tester);
      final s = await _session(periods: [for (var i = 0; i < kPayslipListCap; i++) _monthsAgo(i)]);
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      expect(find.textContaining('are available from'), findsNothing);
    });

    testWidgets('every month and the recent years are selectable, even with a complete list that has only some of them', (tester) async {
      _tall(tester);
      final s = await _session(periods: [DateTime(2025, 12), DateTime(2025, 11)]);
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      expect(find.text('Payslip for December 2025'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      final items = tester.widgetList<DropdownMenuItem<int>>(find.byType(DropdownMenuItem<int>)).toList();
      final enabled = items.where((i) => i.enabled && i.value! <= 12).map((i) => i.value).toSet();
      expect(enabled, {for (var m = 1; m <= 12; m++) m}, reason: 'no month is greyed out');
      // choose a month that has no payslip: it says so instead of being unavailable
      await tester.tap(find.text('March').last);
      await tester.pumpAndSettle();
      expect(find.text(kPayslipNoneForPeriodMessage), findsOneWidget);
      expect(find.text('Payslip for December 2025'), findsNothing);

      // and the year list is the recent years, not only the years that have a payslip
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      final years = tester.widgetList<DropdownMenuItem<int>>(find.byType(DropdownMenuItem<int>)).map((i) => i.value!).where((v) => v > 1900).toSet();
      final now = DateTime.now().year;
      expect(years, containsAll([now, now - 1, now - 2, now - 3, now - 4, now - 5]));
      expect(years.length, greaterThanOrEqualTo(6));
    });
  });

  group('viewing and saving one payslip (GET /reports/payslip-pdf?payslipId=)', () {
    testWidgets('View PDF fetches that payslip, saves and opens it, and shows the server\'s title and net pay', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);

      await tester.tap(_viewPdf);
      await _settle(tester);

      final req = s.requests.where((r) => r.path == _pdfRoute).single;
      expect(req.method, 'GET');
      expect(req.query, {'payslipId': 'p0'});
      expect(saved.files.single.fileName, 'Payslip_p0.pdf');
      expect(saved.opened, [true]);
      expect(find.text('Payslip saved.'), findsOneWidget);
      expect(find.text('NET PAY'), findsOneWidget);
      expect(find.textContaining('46,200.50'), findsOneWidget);
    });

    testWidgets('the top Download PDF button does the same', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(find.text('Download PDF'));
      await _settle(tester);
      expect(_pdfRequests(s), 1);
      expect(saved.files, hasLength(1));
    });

    testWidgets('the PDF is fetched once: a second action on the same payslip reuses it', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      await tester.tap(_saveCopy);
      await _settle(tester);
      expect(_pdfRequests(s), 1);
      expect(saved.exported, hasLength(1));
    });

    testWidgets('Save a copy alone fetches and exports, and reports success only when a file was written', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved()..exportCancelled = true;
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_saveCopy);
      await _settle(tester);
      expect(saved.exported, isEmpty);
      expect(find.text('Payslip saved.'), findsNothing, reason: 'the save dialog was cancelled');

      saved.exportCancelled = false;
      await tester.tap(_saveCopy);
      await _settle(tester);
      expect(saved.exported, hasLength(1));
      expect(find.text('Payslip saved.'), findsOneWidget);
    });

    testWidgets('a genuine net pay of 0 is shown as 0 and the payslip is still saved', (tester) async {
      _tall(tester);
      final s = await _session(pdfNet: 0);
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      expect(saved.files, hasLength(1));
      expect(find.textContaining('0.00'), findsOneWidget);
      expect(find.text('Payslip saved.'), findsOneWidget);
    });

    testWidgets('a refusal (403) is the server\'s real answer: access refused, nothing saved, no server text', (tester) async {
      _tall(tester);
      final s = await _session(statuses: {_pdfRoute: 403});
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      expect(find.text(kPayslipForbiddenMessage), findsOneWidget);
      expect(find.textContaining('server text'), findsNothing);
      expect(saved.files, isEmpty);
      expect(find.text('Payslip saved.'), findsNothing);
    });

    testWidgets('404, 401 and a server error each get their own plain message', (tester) async {
      final expected = {
        404: kPayslipPdfNotAvailableMessage,
        401: 'Session expired',
        500: kPayslipPdfFailedMessage,
      };
      for (final e in expected.entries) {
        _tall(tester);
        final s = await _session(statuses: {_pdfRoute: e.key});
        final saved = _Saved();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_screen(s, saved));
        await _settle(tester);
        await tester.tap(_viewPdf);
        await _settle(tester);
        expect(find.textContaining(e.value), findsOneWidget, reason: 'HTTP ${e.key}');
        expect(find.textContaining('server text'), findsNothing);
        expect(saved.files, isEmpty);
      }
    });

    testWidgets('a file that was saved but cannot be opened is reported as such, never as a plain success', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved()..openFails = true;
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      expect(find.text(kPayslipSavedNoViewerMessage), findsOneWidget);
      expect(find.text('Payslip saved.'), findsNothing);
    });

    testWidgets('a body that is not a PDF is refused: nothing saved, no success message', (tester) async {
      _tall(tester);
      final s = await _session(pdfBody: {'filename': 'x.pdf', 'base64': base64Encode(utf8.encode('<html>nope</html>'))});
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await tester.tap(_viewPdf);
      await _settle(tester);
      expect(saved.files, isEmpty);
      expect(find.text(kPayslipPdfFailedMessage), findsOneWidget);
      expect(find.text('Payslip saved.'), findsNothing);
    });
  });

  group('bulk download', () {
    Future<void> chooseBulk(WidgetTester tester, int n) async {
      await tester.tap(find.text('Bulk Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest $n payslips (PDF)'));
      await _settle(tester);
    }

    testWidgets('fetches one server PDF per released payslip (newest first) and offers them to open or save; nothing is reported saved until the employee acts', (tester) async {
      _tall(tester);
      final s = await _session(periods: [_current, _monthsAgo(1), _monthsAgo(8)]);
      final saved = _Saved();
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);

      await chooseBulk(tester, 3);
      expect(s.requests.where((r) => r.path == _pdfRoute).map((r) => r.query['payslipId']).toList(), ['p0', 'p1', 'p2']);
      expect(find.text('3 payslips ready'), findsOneWidget);
      expect(find.text('Payslip saved.'), findsNothing);
      expect(saved.files, isEmpty);

      await tester.tap(find.byTooltip('Open').first);
      await _settle(tester);
      expect(saved.opened, [true]);

      await tester.tap(find.byTooltip('Save a copy').first);
      await _settle(tester);
      expect(saved.exported, hasLength(1));
      expect(find.text('Payslip saved.'), findsOneWidget);
    });

    testWidgets('a cancelled "save a copy" is not reported as saved', (tester) async {
      _tall(tester);
      final s = await _session();
      final saved = _Saved()..exportCancelled = true;
      await tester.pumpWidget(_screen(s, saved));
      await _settle(tester);
      await chooseBulk(tester, 3);
      await tester.tap(find.byTooltip('Save a copy').first);
      await _settle(tester);
      expect(saved.exported, isEmpty);
      expect(find.text('Payslip saved.'), findsNothing);
    });

    testWidgets('the newest N are the newest RELEASED payslips, not the calendar months before today', (tester) async {
      _tall(tester);
      final s = await _session(periods: [_monthsAgo(14), _monthsAgo(15)]);
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      await chooseBulk(tester, 3);
      expect(_pdfRequests(s), 2);
      expect(find.text('2 payslips ready'), findsOneWidget);
    });

    testWidgets('one payslip failing does not lose the others: they are offered and the shortfall is said', (tester) async {
      _tall(tester);
      final s = await _session(periods: [_current, _monthsAgo(1), _monthsAgo(2)], failPdfIds: {'p1'});
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      await chooseBulk(tester, 3);
      expect(find.text('2 payslips ready'), findsOneWidget);
      expect(find.textContaining('2 of 3 payslips were prepared'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('a refusal (403) stops at the first payslip and is explained; no list, no server text', (tester) async {
      _tall(tester);
      final s = await _session(statuses: {_pdfRoute: 403});
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      await chooseBulk(tester, 3);
      expect(_pdfRequests(s), 1);
      expect(find.text(kPayslipForbiddenMessage), findsOneWidget);
      expect(find.textContaining('payslips ready'), findsNothing);
      expect(find.textContaining('server text'), findsNothing);
    });

    testWidgets('every payslip failing shows the fixed failure message', (tester) async {
      _tall(tester);
      final s = await _session(failing: {_pdfRoute});
      await tester.pumpWidget(_screen(s, _Saved()));
      await _settle(tester);
      await chooseBulk(tester, 3);
      expect(find.text(kPayslipPdfFailedMessage), findsOneWidget);
      expect(find.textContaining('payslips ready'), findsNothing);
    });
  });

  testWidgets('no write request is ever made', (tester) async {
    _tall(tester);
    final s = await _session();
    await tester.pumpWidget(_screen(s, _Saved()));
    await _settle(tester);
    await tester.tap(_viewPdf);
    await _settle(tester);
    expect(s.requests.every((r) => r.method == 'GET'), isTrue);
  });

  test('the screen has no Supabase code, no token logging, no salary arithmetic and no call to the retired details route', () {
    final src = File('lib/screens/payslip_screen.dart').readAsStringSync();
    final repo = File('lib/repositories/payslip_repository.dart').readAsStringSync();
    for (final banned in [
      'supabase',
      'Supabase',
      'print(',
      'debugPrint(',
      'accessToken',
      'salary-encryption',
      'net_pay',
      'total_earnings',
      'sensitive-profile',
      'payslip-document',
    ]) {
      expect(src.contains(banned), isFalse, reason: 'screen: found "$banned"');
      expect(repo.contains(banned), isFalse, reason: 'repository: found "$banned"');
    }
    expect(RegExp(r'netPay\s*[=:]\s*[^;,]*[-+*/]').hasMatch(src), isFalse);
  });
}
