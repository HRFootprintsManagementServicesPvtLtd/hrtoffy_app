import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/repositories/travel_repository.dart';

import '../helpers/test_auth.dart';

const _org = '/organizations/$testOrgId';

Map<String, dynamic> _claim(
  String id, {
  String created = '2026-10-01T10:00:00.000Z',
}) => {
  'id': id,
  'claim_number': 'TRV-0001',
  'employee_id': testEmployeeId,
  'trip_purpose': 'Client visit',
  'trip_destination': 'Pune',
  'trip_from_date': '2026-10-07T00:00:00.000Z',
  'trip_to_date': '2026-10-09T00:00:00.000Z',
  'total_amount': '5400.50',
  'status': 'pending',
  'created_at': created,
};

const _receipt = ReceiptFile(
  bytes: [1, 2, 3],
  name: 'bill.pdf',
  contentType: 'application/pdf',
);

/// Handles the calls of a full claim submission; [failLine] is the 1-based line number that fails.
Future<TestSession> _submitSession({int? failLine, bool failUpload = false}) {
  var lineCalls = 0;
  return signedIn((req) async {
    final path = req.url.path;
    if (path == '$_org/employees/me')
      return ok({'id': testEmployeeId, 'managerId': 'mgr-1'});
    if (path == '$_org/files') {
      if (failUpload)
        return jsonResponse({
          'success': false,
          'error': {'message': 'File too large'},
        }, 400);
      return ok({
        'bucket': 'travel-receipts',
        'path': '$testEmployeeId/r${lineCalls + 1}.pdf',
        'ref': 'travel-receipts/$testEmployeeId/r.pdf',
        'url': null,
        'size': 3,
      }, 201);
    }
    if (path == '$_org/travel/claims' && req.method == 'POST')
      return ok({
        'id': 'claim-1',
        'claim_number': 'TRV-1',
        'total_amount': '300.00',
      }, 201);
    if (path == '$_org/travel-expenses' && req.method == 'POST') {
      lineCalls++;
      if (failLine == lineCalls)
        return jsonResponse({
          'success': false,
          'error': {'message': 'boom'},
        }, 500);
      return ok({'id': 'line-$lineCalls'}, 201);
    }
    return jsonResponse({
      'success': false,
      'error': {'message': 'unexpected ${req.method} $path'},
    }, 404);
  });
}

final _lines = [
  const TravelLine(
    expenseDate: '2026-10-07',
    expenseType: 'Train Fare',
    description: 'Train',
    amount: 100,
    receipt: _receipt,
  ),
  const TravelLine(
    expenseDate: '2026-10-08',
    expenseType: 'Meals',
    description: 'Lunch',
    amount: 200,
  ),
];

Future<String> _submit(TestSession s) =>
    TravelRepository(auth: s.auth).submitClaim(
      tripPurpose: 'Client visit',
      tripDestination: 'Pune',
      fromLocation: 'Mumbai',
      tripFromDate: DateTime(2026, 10, 7),
      tripToDate: DateTime(2026, 10, 9),
      travelType: 'domestic',
      lines: _lines,
    );

void main() {
  group('TravelRepository.claims', () {
    test(
      'GET /travel/claims?employeeId=<own>; decimals become numbers, dates yyyy-MM-dd, newest first',
      () async {
        final s = await signedIn(
          (req) async => ok([
            _claim('old', created: '2026-09-01T00:00:00.000Z'),
            _claim('new'),
          ]),
        );
        final rows = await TravelRepository(auth: s.auth).claims();
        expect(s.last.method, 'GET');
        expect(s.last.path, '$_org/travel/claims');
        expect(s.last.query, {'employeeId': testEmployeeId});
        expect(s.last.headers['Authorization'], 'Bearer acc');
        expect(rows.map((r) => r['id']), ['new', 'old']);
        expect(rows.first['total_amount'], 5400.5);
        expect(rows.first['trip_from_date'], '2026-10-07');
        expect(rows.first['trip_to_date'], '2026-10-09');
        expect(rows.first['claim_number'], 'TRV-0001');
      },
    );

    test('empty list and API errors', () async {
      final s = await signedIn((req) async => ok([]));
      expect(await TravelRepository(auth: s.auth).claims(), isEmpty);
      final f = await signedIn(
        (req) async => jsonResponse({
          'success': false,
          'error': {'message': 'No'},
        }, 403),
      );
      await expectLater(
        TravelRepository(auth: f.auth).claims(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('TravelRepository.createClaim', () {
    test(
      'POST /travel/claims with the verified body and no claim_number',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'id': 'c1',
            'claim_number': 'TRV-9',
            'total_amount': '300.00',
          }, 201),
        );
        final c = await TravelRepository(auth: s.auth).createClaim(
          tripPurpose: 'Client visit',
          tripDestination: 'Pune',
          fromLocation: 'Mumbai',
          tripFromDate: DateTime(2026, 10, 7),
          tripToDate: DateTime(2026, 10, 9),
          travelType: 'domestic',
          totalAmount: 300,
          managerId: 'mgr-1',
        );
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/travel/claims');
        expect(s.last.json, {
          'employee_id': testEmployeeId,
          'trip_purpose': 'Client visit',
          'trip_destination': 'Pune',
          'from_location': 'Mumbai',
          'trip_from_date': '2026-10-07',
          'trip_to_date': '2026-10-09',
          'total_days': 3,
          'travel_type': 'domestic',
          'total_amount': 300.0,
          'status': 'pending',
          'manager_id': 'mgr-1',
        });
        expect((s.last.json as Map).containsKey('claim_number'), isFalse);
        expect(c['id'], 'c1');
        expect(c['total_amount'], 300);
      },
    );

    test('manager_id is left out when there is no manager', () async {
      final s = await signedIn((req) async => ok({'id': 'c1'}, 201));
      await TravelRepository(auth: s.auth).createClaim(
        tripPurpose: 'p',
        tripDestination: 'd',
        fromLocation: 'f',
        tripFromDate: DateTime(2026, 10, 7),
        tripToDate: DateTime(2026, 10, 7),
        travelType: 'domestic',
        totalAmount: 1,
      );
      expect((s.last.json as Map).containsKey('manager_id'), isFalse);
      expect(s.last.json['total_days'], 1);
    });

    test('a response without an id is an error', () async {
      final s = await signedIn((req) async => ok({'ok': true}, 201));
      await expectLater(
        TravelRepository(auth: s.auth).createClaim(
          tripPurpose: 'p',
          tripDestination: 'd',
          fromLocation: 'f',
          tripFromDate: DateTime(2026),
          tripToDate: DateTime(2026),
          travelType: 'domestic',
          totalAmount: 1,
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('TravelRepository.addLine', () {
    test(
      'POST /travel-expenses with the verified camelCase body and the receipt reference',
      () async {
        final s = await signedIn((req) async => ok({'id': 'l1'}, 201));
        await TravelRepository(auth: s.auth).addLine(
          'claim-1',
          const TravelLine(
            expenseDate: '2026-10-07',
            expenseType: 'Hotel',
            description: 'Stay',
            amount: 2500.5,
          ),
          receiptRef: 'travel-receipts/emp/x.pdf',
        );
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/travel-expenses');
        expect(s.last.json, {
          'claimId': 'claim-1',
          'amount': 2500.5,
          'expenseType': 'Hotel',
          'description': 'Stay',
          'expenseDate': '2026-10-07',
          'receiptUrl': 'travel-receipts/emp/x.pdf',
        });
      },
    );

    test('no receipt: receiptUrl is not sent', () async {
      final s = await signedIn((req) async => ok({'id': 'l1'}, 201));
      await TravelRepository(auth: s.auth).addLine(
        'c',
        const TravelLine(
          expenseDate: '2026-10-07',
          expenseType: 'Meals',
          description: 'x',
          amount: 1,
        ),
      );
      expect((s.last.json as Map).containsKey('receiptUrl'), isFalse);
    });
  });

  group('TravelRepository.uploadReceipt', () {
    test(
      'POST /files?bucket=travel-receipts and returns the bucket/path reference',
      () async {
        final s = await signedIn(
          (req) async => ok({
            'bucket': 'travel-receipts',
            'path': 'emp/1.pdf',
            'ref': 'travel-receipts/emp/1.pdf',
            'url': null,
            'size': 3,
          }, 201),
        );
        final ref = await TravelRepository(
          auth: s.auth,
        ).uploadReceipt(_receipt);
        expect(s.last.method, 'POST');
        expect(s.last.path, '$_org/files');
        expect(s.last.query['bucket'], 'travel-receipts');
        expect(ref, 'travel-receipts/emp/1.pdf');
      },
    );
  });

  group('TravelRepository.submitClaim', () {
    test(
      'uploads receipts, creates the claim once, then one line call per line with the file reference',
      () async {
        final s = await _submitSession();
        final id = await _submit(s);
        expect(id, 'claim-1');

        final calls = s.apiCalls.map((r) => '${r.method} ${r.path}').toList();
        expect(
          calls.where((c) => c == 'POST $_org/files'),
          hasLength(1),
        ); // only the line with a receipt
        expect(
          calls.where((c) => c == 'POST $_org/travel/claims'),
          hasLength(1),
        );
        expect(
          calls.where((c) => c == 'POST $_org/travel-expenses'),
          hasLength(2),
        );
        // receipts first, then the claim, then the lines
        expect(
          calls.indexOf('POST $_org/files'),
          lessThan(calls.indexOf('POST $_org/travel/claims')),
        );
        expect(
          calls.indexOf('POST $_org/travel/claims'),
          lessThan(calls.indexOf('POST $_org/travel-expenses')),
        );

        final create = s.apiCalls.firstWhere(
          (r) => r.path == '$_org/travel/claims',
        );
        expect(create.json['total_amount'], 300.0);
        expect(create.json['manager_id'], 'mgr-1');
        expect(create.json['total_days'], 3);

        final lines = s.apiCalls
            .where((r) => r.path == '$_org/travel-expenses')
            .toList();
        expect(lines[0].json['claimId'], 'claim-1');
        expect(
          lines[0].json['receiptUrl'],
          'travel-receipts/$testEmployeeId/r.pdf',
        );
        expect((lines[1].json as Map).containsKey('receiptUrl'), isFalse);
      },
    );

    test(
      'a failed line is reported as incomplete and the claim is NOT deleted',
      () async {
        final s = await _submitSession(failLine: 2);
        await expectLater(
          _submit(s),
          throwsA(
            isA<TravelClaimIncompleteException>()
                .having((e) => e.savedLines, 'savedLines', 1)
                .having((e) => e.totalLines, 'totalLines', 2)
                .having((e) => e.claimId, 'claimId', 'claim-1'),
          ),
        );
        expect(s.apiCalls.any((r) => r.method == 'DELETE'), isFalse);
        expect(
          s.apiCalls.where((r) => r.path == '$_org/travel/claims'),
          hasLength(1),
        );
      },
    );

    test(
      'a failure on the first line also leaves the claim alone and stops saving further lines',
      () async {
        final s = await _submitSession(failLine: 1);
        await expectLater(
          _submit(s),
          throwsA(
            isA<TravelClaimIncompleteException>().having(
              (e) => e.savedLines,
              'savedLines',
              0,
            ),
          ),
        );
        expect(s.apiCalls.any((r) => r.method == 'DELETE'), isFalse);
        expect(
          s.apiCalls.where((r) => r.path == '$_org/travel-expenses'),
          hasLength(1),
        );
      },
    );

    test('a failed receipt upload stops before anything is created', () async {
      final s = await _submitSession(failUpload: true);
      await expectLater(_submit(s), throwsA(isA<ApiException>()));
      expect(s.apiCalls.any((r) => r.path == '$_org/travel/claims'), isFalse);
      expect(s.apiCalls.any((r) => r.path == '$_org/travel-expenses'), isFalse);
    });

    test('a missing manager lookup does not block the submission', () async {
      var failedMe = false;
      final s = await signedIn((req) async {
        final path = req.url.path;
        if (path == '$_org/employees/me') {
          failedMe = true;
          return jsonResponse({
            'success': false,
            'error': {'message': 'x'},
          }, 500);
        }
        if (path == '$_org/files')
          return ok({
            'bucket': 'travel-receipts',
            'path': 'p',
            'ref': 'travel-receipts/p',
            'url': null,
            'size': 3,
          }, 201);
        if (path == '$_org/travel/claims') return ok({'id': 'claim-1'}, 201);
        return ok({'id': 'l'}, 201);
      });
      await _submit(s);
      expect(failedMe, isTrue);
      expect(
        (s.apiCalls.firstWhere((r) => r.path == '$_org/travel/claims').json
                as Map)
            .containsKey('manager_id'),
        isFalse,
      );
    });
  });
}
