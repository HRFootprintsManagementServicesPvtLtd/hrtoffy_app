import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/core/auth/auth_service.dart';
import 'package:hrms_app/core/auth/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

const _org1 = '11111111-1111-1111-1111-111111111111';
const _org2 = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> _login(String org) => {
      'accessToken': 'acc',
      'refreshToken': 'ref',
      'sessionId': 's1',
      'expiresIn': 900,
      'user': {'id': 'user-1', 'email': 'a@b.com', 'organizationId': org},
    };

AuthService _service(Future<http.Response> Function(http.Request) handler, {TokenStore? store}) {
  final s = store ?? TokenStore();
  return AuthService(api: ApiClient(tokenStore: s, httpClient: MockClient(handler)), tokenStore: s);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('login: single org -> login -> resolve-user, session stored', () async {
    final seen = <String>[];
    Map<String, dynamic>? loginBody;
    final auth = _service((req) async {
      seen.add('${req.method} ${req.url.path}');
      switch (req.url.path) {
        case '/auth/discover-tenants':
          return _json({'organizations': [{'id': _org1, 'name': 'Goodclap'}]});
        case '/auth/login':
          loginBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _json(_login(_org1));
        case '/auth/resolve-user':
          expect(req.headers['Authorization'], 'Bearer acc');
          return _json({'success': true, 'data': {'id': 'user-1', 'email': 'a@b.com', 'fullName': 'User', 'organizationId': _org1, 'employeeId': 'emp-1', 'empRole': 'manager', 'isHrRole': false}});
      }
      return _json({}, 404);
    });

    final user = await auth.login('  a@b.com ', 'pw');
    expect(seen, ['POST /auth/discover-tenants', 'POST /auth/login', 'GET /auth/resolve-user']);
    expect(loginBody, {'organizationId': _org1, 'email': 'a@b.com', 'authMethod': 'password', 'credentials': {'password': 'pw'}});
    expect(user.employeeId, 'emp-1');
    expect(user.isManager, isTrue);
    expect(auth.isAuthenticated, isTrue);
    final persisted = await TokenStore().load();
    expect(persisted?.employeeId, 'emp-1');
    expect(persisted?.organizationId, _org1);
  });

  test('login: several organizations -> MultipleOrganizationsException, then pick one', () async {
    var discoverCalls = 0;
    final auth = _service((req) async {
      switch (req.url.path) {
        case '/auth/discover-tenants':
          discoverCalls++;
          return _json({'organizations': [{'id': _org1, 'name': 'A'}, {'id': _org2, 'name': 'B'}]});
        case '/auth/login':
          return _json(_login((jsonDecode(req.body) as Map)['organizationId'] as String));
        case '/auth/resolve-user':
          return _json({'success': true, 'data': {'id': 'user-1', 'email': 'a@b.com', 'organizationId': _org1, 'employeeId': 'emp-org1', 'empRole': 'employee',
            'organizations': [
              {'id': _org1, 'name': 'A', 'employeeId': 'emp-org1', 'empRole': 'employee', 'isHrRole': false},
              {'id': _org2, 'name': 'B', 'employeeId': 'emp-org2', 'empRole': 'hr', 'isHrRole': true},
            ]}});
      }
      return _json({}, 404);
    });

    await expectLater(auth.login('a@b.com', 'pw'), throwsA(isA<MultipleOrganizationsException>().having((e) => e.organizations.length, 'n', 2)));
    final user = await auth.login('a@b.com', 'pw', organizationId: _org2);
    expect(discoverCalls, 1, reason: 'no discovery when the organization is given');
    expect(user.employeeId, 'emp-org2', reason: 'employee id comes from the logged-in organization entry');
    expect(user.isHrRole, isTrue);
  });

  test('login: no organization -> AuthFlowException', () async {
    final auth = _service((_) async => _json({'organizations': []}));
    await expectLater(auth.login('a@b.com', 'pw'), throwsA(isA<AuthFlowException>()));
    expect(auth.isAuthenticated, isFalse);
  });

  test('login: wrong password -> ApiException 401 and nothing stored', () async {
    final auth = _service((req) async => req.url.path == '/auth/discover-tenants'
        ? _json({'organizations': [{'id': _org1, 'name': 'A'}]})
        : _json({'success': false, 'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Invalid credentials'}}, 401));
    await expectLater(auth.login('a@b.com', 'bad'), throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 401)));
    expect(await TokenStore().load(), isNull);
  });

  test('login: resolve-user failure rolls the session back', () async {
    final auth = _service((req) async {
      switch (req.url.path) {
        case '/auth/discover-tenants':
          return _json({'organizations': [{'id': _org1, 'name': 'A'}]});
        case '/auth/login':
          return _json(_login(_org1));
      }
      return _json({'success': false, 'error': {'message': 'boom'}}, 500);
    });
    await expectLater(auth.login('a@b.com', 'pw'), throwsA(isA<ApiException>()));
    expect(auth.isAuthenticated, isFalse);
    expect(await TokenStore().load(), isNull);
  });

  test('restoreSession: no stored session -> false', () async {
    final auth = _service((_) async => _json({}, 500));
    expect(await auth.restoreSession(), isFalse);
  });

  test('restoreSession: valid stored session is validated via resolve-user', () async {
    final store = TokenStore();
    await store.save(StoredSession(accessToken: 'acc', refreshToken: 'ref', userId: 'user-1', email: 'a@b.com', organizationId: _org1, expiresAt: DateTime.now().add(const Duration(minutes: 5))));
    final auth = _service((req) async => _json({'success': true, 'data': {'id': 'user-1', 'email': 'a@b.com', 'organizationId': _org1, 'employeeId': 'emp-1', 'empRole': 'employee'}}), store: TokenStore());
    expect(await auth.restoreSession(), isTrue);
    expect(auth.currentUser?.employeeId, 'emp-1');
  });

  test('restoreSession: expired access token is refreshed first', () async {
    final store = TokenStore();
    await store.save(StoredSession(accessToken: 'old', refreshToken: 'ref', userId: 'user-1', email: 'a@b.com', organizationId: _org1, expiresAt: DateTime.now().subtract(const Duration(minutes: 1))));
    final order = <String>[];
    final s2 = TokenStore();
    final auth = _service((req) async {
      order.add(req.url.path);
      if (req.url.path == '/auth/refresh') return _json({'accessToken': 'new', 'refreshToken': 'ref2', 'expiresIn': 900});
      expect(req.headers['Authorization'], 'Bearer new');
      return _json({'success': true, 'data': {'id': 'user-1', 'email': 'a@b.com', 'organizationId': _org1, 'employeeId': 'emp-1'}});
    }, store: s2);
    expect(await auth.restoreSession(), isTrue);
    expect(order, ['/auth/refresh', '/auth/resolve-user']);
  });

  test('restoreSession: rejected session is cleared -> false', () async {
    final store = TokenStore();
    await store.save(StoredSession(accessToken: 'old', refreshToken: 'ref', userId: 'user-1', email: 'a@b.com', organizationId: _org1, expiresAt: DateTime.now().add(const Duration(minutes: 5))));
    final auth = _service((_) async => _json({'success': false}, 401), store: TokenStore());
    expect(await auth.restoreSession(), isFalse);
    expect(await TokenStore().load(), isNull);
  });

  test('restoreSession: offline keeps the stored identity', () async {
    final store = TokenStore();
    await store.save(StoredSession(accessToken: 'acc', refreshToken: 'ref', userId: 'user-1', email: 'a@b.com', organizationId: _org1, employeeId: 'emp-1', expiresAt: DateTime.now().add(const Duration(minutes: 5))));
    final auth = _service((_) async => throw http.ClientException('offline'), store: TokenStore());
    expect(await auth.restoreSession(), isTrue);
    expect(auth.currentUser?.employeeId, 'emp-1');
  });

  test('logout: calls /auth/logout, clears the session even if the call fails', () async {
    final store = TokenStore();
    await store.save(StoredSession(accessToken: 'acc', refreshToken: 'ref', userId: 'user-1', email: 'a@b.com', organizationId: _org1));
    final s2 = TokenStore();
    var logoutCalled = false;
    final auth = _service((req) async {
      if (req.url.path == '/auth/logout') {
        logoutCalled = true;
        throw http.ClientException('offline');
      }
      return _json({'success': true, 'data': {'id': 'user-1', 'email': 'a@b.com', 'organizationId': _org1, 'employeeId': 'e'}});
    }, store: s2);
    await auth.restoreSession();
    await auth.logout();
    expect(logoutCalled, isTrue);
    expect(auth.isAuthenticated, isFalse);
    expect(await TokenStore().load(), isNull);
    expect(() => auth.requireUser(), throwsA(isA<ApiException>()));
  });
}
