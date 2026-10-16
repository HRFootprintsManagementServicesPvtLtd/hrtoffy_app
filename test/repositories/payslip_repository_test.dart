import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/payslip_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _row(
  String id,
  int month,
  int year, {
  String fy = '2026-2027',
}) => {
  'id': id,
  'employee_id': testEmployeeId,
  'month': month,
  'year': year,
  'financial_year': fy,
  'net_pay': '0',
};

String _pdfBase64([String head = '%PDF-1.4 minimal']) =>
    base64Encode(utf8.encode(head));

void main() {
  group('payslips()', () {
    test(
      'GET /payroll/employees/<own id>/payslips (no query); rows are read as id, month, year; newest first',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              _row('old', 8, 2026),
              _row('new', 10, 2026),
              _row('older', 12, 2025, fy: '2025-2026'),
            ],
            'total': 3,
          }),
        );
        final list = await PayslipRepository(auth: s.auth).payslips();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/payroll/employees/$testEmployeeId/payslips');
        expect(s.last.query, isEmpty);
        expect(list.map((p) => p.id), ['new', 'old', 'older']);
        expect(list.last.financialYear, '2025-2026');
        expect(list.first.month, 10);
      },
    );

    test(
      'rows without an id or with an impossible period are ignored; empty and null bodies give an empty list',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'items': [
              {'month': 9, 'year': 2026},
              {'id': 'x', 'month': 13, 'year': 2026},
              {'id': 'y', 'month': 9, 'year': 1999},
              _row('good', 9, 2026),
            ],
          }),
        );
        expect(
          (await PayslipRepository(auth: s.auth).payslips()).map((p) => p.id),
          ['good'],
        );
        for (final body in <Object?>[
          null,
          [],
          {'items': []},
        ]) {
          final e = await signedIn((req) async => ok(body));
          expect(await PayslipRepository(auth: e.auth).payslips(), isEmpty);
        }
      },
    );

    test(
      'a request for another employee cannot be made: the id always comes from the session',
      () async {
        final s = await signedIn((req) async => ok({'items': []}));
        await PayslipRepository(auth: s.auth).payslips();
        expect(s.last.path, contains(testEmployeeId));
      },
    );

    test('without a signed-in employee no request is made', () async {
      final s = await signedIn((req) async => ok({'items': []}));
      await s.auth.logout();
      s.requests.clear();
      await expectLater(
        PayslipRepository(auth: s.auth).payslips(),
        throwsA(isA<ApiException>()),
      );
      expect(s.requests, isEmpty);
    });

    test('API errors surface as typed ApiException', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'nope'},
        }, 403),
      );
      await expectLater(
        PayslipRepository(auth: s.auth).payslips(),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, '403', true)),
      );
    });
  });

  group('pdf()', () {
    test(
      'GET /reports/payslip-pdf?payslipId=; the base64 body becomes the PDF bytes, the net pay is the server\'s',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'filename': 'Payslip_GC-001_September_2026.pdf',
            'contentType': 'application/pdf',
            'base64': _pdfBase64(),
            'netPay': 46200.5,
            'summary': 'Payslip for September 2026',
          }),
        );
        final pdf = await PayslipRepository(auth: s.auth).pdf('p1');
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/reports/payslip-pdf');
        expect(s.last.query, {'payslipId': 'p1'});
        expect(pdf.fileName, 'Payslip_GC-001_September_2026.pdf');
        expect(String.fromCharCodes(pdf.bytes.sublist(0, 5)), '%PDF-');
        expect(pdf.netPay, 46200.5);
        expect(pdf.summary, 'Payslip for September 2026');
      },
    );

    test('a genuine net pay of 0 is kept as 0, never treated as a failure', () async {
      final s = await signedIn((req) async => ok({'filename': 'p.pdf', 'base64': _pdfBase64(), 'netPay': 0}));
      final pdf = await PayslipRepository(auth: s.auth).pdf('p1');
      expect(pdf.netPay, 0);
    });

    test('the retired details route is never called', () async {
      final s = await signedIn((req) async => ok({'filename': 'p.pdf', 'base64': _pdfBase64()}));
      await PayslipRepository(auth: s.auth).pdf('p1');
      expect(s.requests.every((r) => !r.path.contains('payslip-document')), isTrue);
    });

    test('an unsafe file name is made safe', () async {
      final s = await signedIn(
        (req) async => ok({'filename': '../a:b*c.pdf', 'base64': _pdfBase64()}),
      );
      expect(
        (await PayslipRepository(auth: s.auth).pdf('p1')).fileName,
        '.._a_b_c.pdf',
      );
      final blank = await signedIn((req) async => ok({'base64': _pdfBase64()}));
      expect(
        (await PayslipRepository(auth: blank.auth).pdf('p1')).fileName,
        'Payslip.pdf',
      );
    });

    test(
      'a response that is not a PDF is refused and never offered as a download',
      () async {
        final notPdf = await signedIn(
          (req) async => ok({
            'filename': 'x.pdf',
            'base64': base64Encode(utf8.encode('<html>error</html>')),
          }),
        );
        await expectLater(
          PayslipRepository(auth: notPdf.auth).pdf('p1'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'PAYSLIP_BAD_PDF',
            ),
          ),
        );
        for (final body in <Object?>[
          null,
          {},
          {'base64': ''},
          {'base64': 5},
        ]) {
          final s = await signedIn((req) async => ok(body));
          await expectLater(
            PayslipRepository(auth: s.auth).pdf('p1'),
            throwsA(isA<ApiException>()),
          );
        }
      },
    );

    test('a refusal (403) from the server is a typed failure', () async {
      final s = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'denied'},
        }, 403),
      );
      await expectLater(
        PayslipRepository(auth: s.auth).pdf('p1'),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, '403', true)),
      );
    });
  });
}
