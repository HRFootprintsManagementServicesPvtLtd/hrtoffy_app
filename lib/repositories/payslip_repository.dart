import 'dart:convert';
import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// One payslip of the signed-in employee that the server has released to them.
class PayslipSummary {
  const PayslipSummary({
    required this.id,
    required this.month,
    required this.year,
    this.financialYear,
  });

  final String id;
  final int month;
  final int year;
  final String? financialYear;
}

/// A payslip PDF rendered by the server.
class PayslipPdf {
  const PayslipPdf({
    required this.fileName,
    required this.bytes,
    this.netPay,
    this.summary,
  });

  final String fileName;
  final Uint8List bytes;

  /// The net pay the server reports for this payslip (a genuine 0 is possible).
  final num? netPay;

  /// The server's title for the payslip, e.g. "Payslip for November 2025".
  final String? summary;
}

/// The signed-in employee's own payslips (read-only).
///
/// Release and ownership are decided on the server: the list only contains payslips released to the employee,
/// and the document and PDF routes refuse any payslip that is not the caller's own, released one. The employee is
/// identified by the session; nothing here can request another employee's payslip.
class PayslipRepository extends BaseRepository {
  PayslipRepository({super.auth});

  /// `GET /organizations/:orgId/payroll/employees/:employeeId/payslips` with the caller's own employee id.
  /// For an employee the server returns only payslips released to employees (or individually granted), newest
  /// first, at most 12. Only `id`, `month`, `year` and `financial_year` are read.
  Future<List<PayslipSummary>> payslips() async {
    final data = await api.get(
      orgPath('/payroll/employees/$employeeId/payslips'),
    );
    final rows = <PayslipSummary>[];
    for (final r in asMapList(data)) {
      final m = Map<String, dynamic>.from(snakeKeys(r) as Map);
      final id = m['id']?.toString();
      final month = asInt(m['month']);
      final year = asInt(m['year']);
      if (id == null || id.isEmpty || month < 1 || month > 12 || year < 2000)
        continue;
      rows.add(
        PayslipSummary(
          id: id,
          month: month,
          year: year,
          financialYear: m['financial_year']?.toString(),
        ),
      );
    }
    rows.sort(
      (a, b) => (b.year * 12 + b.month).compareTo(a.year * 12 + a.month),
    );
    return rows;
  }

  /// `GET /organizations/:orgId/reports/payslip-pdf?payslipId=`: the same payslip as a PDF (base64 in the response).
  Future<PayslipPdf> pdf(String payslipId) async {
    final data = await api.get(
      orgPath('/reports/payslip-pdf'),
      query: {'payslipId': payslipId},
    );
    if (data is! Map ||
        data['base64'] is! String ||
        (data['base64'] as String).isEmpty) {
      throw const ApiException(
        502,
        'Unexpected response while preparing your payslip PDF.',
        code: 'PAYSLIP_BAD_RESPONSE',
      );
    }
    final bytes = base64Decode(data['base64'] as String);
    // A real PDF starts with "%PDF-"; anything else is not offered as a download.
    if (bytes.length < 5 ||
        String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
      throw const ApiException(
        502,
        'The payslip PDF could not be prepared.',
        code: 'PAYSLIP_BAD_PDF',
      );
    }
    final name = (data['filename'] ?? '').toString();
    return PayslipPdf(
      fileName: name.isEmpty
          ? 'Payslip.pdf'
          : name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
      bytes: Uint8List.fromList(bytes),
      netPay: asNum(data['netPay']),
      summary: data['summary']?.toString(),
    );
  }
}
