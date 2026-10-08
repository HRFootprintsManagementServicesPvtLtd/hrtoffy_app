import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/core/auth/auth_service.dart';
import 'package:hrms_app/core/auth/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testOrgId = '11111111-1111-1111-1111-111111111111';
const testEmployeeId = '22222222-2222-2222-2222-222222222222';
const testUserId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Wraps a backend payload in the standard `{success, data}` envelope.
http.Response ok(Object? data, [int status = 200]) => jsonResponse({'success': true, 'data': data}, status);

class Recorded {
  Recorded(this.method, this.path, this.query, this.body, this.headers, this.bodyBytes);
  final String method;
  final String path;
  final Map<String, String> query;
  final String body;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  dynamic get json => body.isEmpty ? null : jsonDecode(body);
}

class TestSession {
  TestSession(this.auth, this.requests);
  final AuthService auth;
  final List<Recorded> requests;

  Recorded get last => requests.last;

  /// Requests made after sign-in (sign-in itself calls discover/login/resolve-user).
  List<Recorded> get apiCalls => requests.where((r) => !r.path.startsWith('/auth/')).toList();
}

/// An [AuthService] that is already signed in as employee [testEmployeeId] in organization
/// [testOrgId]. Every other request is passed to [handler], and all requests are recorded.
Future<TestSession> signedIn(
  Future<http.Response> Function(http.Request req) handler, {
  String empRole = 'employee',
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final requests = <Recorded>[];
  final store = TokenStore();
  final client = MockClient((req) async {
    requests.add(Recorded(req.method, req.url.path, req.url.queryParameters, req.body, req.headers, req.bodyBytes));
    switch (req.url.path) {
      case '/auth/discover-tenants':
        return jsonResponse({'organizations': [{'id': testOrgId, 'name': 'Goodclap'}]});
      case '/auth/login':
        return jsonResponse({
          'accessToken': 'acc',
          'refreshToken': 'ref',
          'sessionId': 's1',
          'expiresIn': 900,
          'user': {'id': testUserId, 'email': 'me@x.com', 'organizationId': testOrgId},
        });
      case '/auth/resolve-user':
        return ok({
          'id': testUserId,
          'email': 'me@x.com',
          'organizationId': testOrgId,
          'employeeId': testEmployeeId,
          'empRole': empRole,
          'isHrRole': false,
        });
    }
    return handler(req);
  });
  final auth = AuthService(api: ApiClient(tokenStore: store, httpClient: client), tokenStore: store);
  await auth.login('me@x.com', 'pw');
  requests.clear();
  return TestSession(auth, requests);
}
