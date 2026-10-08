import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/api_client.dart';
import 'package:hrms_app/core/auth/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<TokenStore> _storeWithSession({String access = 'access-1', String refresh = 'refresh-1'}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final store = TokenStore();
  await store.save(StoredSession(accessToken: access, refreshToken: refresh, userId: 'u1', organizationId: 'o1'));
  return store;
}

void main() {
  test('sends Bearer token and unwraps {success,data}', () async {
    final store = await _storeWithSession();
    String? auth;
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        auth = req.headers['Authorization'];
        return _json({'success': true, 'data': {'id': 'x'}});
      }),
    );
    final data = await api.get('/auth/me');
    expect(auth, 'Bearer access-1');
    expect(data, {'id': 'x'});
  });

  test('bodies without a success key (login/refresh style) pass through', () async {
    final store = await _storeWithSession();
    final api = ApiClient(tokenStore: store, httpClient: MockClient((_) async => _json({'accessToken': 'a'})));
    expect(await api.post('/auth/login', auth: false), {'accessToken': 'a'});
  });

  test('error envelope becomes a typed ApiException', () async {
    final store = await _storeWithSession();
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((_) async => _json({'success': false, 'error': {'code': 'FORBIDDEN', 'message': 'nope'}}, 403)),
    );
    await expectLater(
      api.get('/x'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403).having((e) => e.code, 'code', 'FORBIDDEN').having((e) => e.message, 'message', 'nope')),
    );
  });

  test('401 triggers exactly one refresh and one retry', () async {
    final store = await _storeWithSession();
    var refreshCalls = 0;
    var dataCalls = 0;
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshCalls++;
          return _json({'accessToken': 'access-2', 'refreshToken': 'refresh-2', 'expiresIn': 900});
        }
        dataCalls++;
        return req.headers['Authorization'] == 'Bearer access-2'
            ? _json({'success': true, 'data': 'ok'})
            : _json({'success': false, 'error': {'message': 'expired'}}, 401);
      }),
    );
    expect(await api.get('/things'), 'ok');
    expect(refreshCalls, 1);
    expect(dataCalls, 2);
    expect(store.accessToken, 'access-2');
    expect(store.refreshToken, 'refresh-2');
  });

  test('concurrent 401s share a single refresh (single-flight)', () async {
    final store = await _storeWithSession();
    var refreshCalls = 0;
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _json({'accessToken': 'access-2', 'refreshToken': 'refresh-2', 'expiresIn': 900});
        }
        return req.headers['Authorization'] == 'Bearer access-2'
            ? _json({'success': true, 'data': req.url.path})
            : _json({'success': false}, 401);
      }),
    );
    final results = await Future.wait([api.get('/a'), api.get('/b'), api.get('/c')]);
    expect(results, ['/a', '/b', '/c']);
    expect(refreshCalls, 1);
  });

  test('a still-401 retry is not refreshed again', () async {
    final store = await _storeWithSession();
    var refreshCalls = 0;
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshCalls++;
          return _json({'accessToken': 'access-2', 'refreshToken': 'refresh-2', 'expiresIn': 900});
        }
        return _json({'success': false}, 401);
      }),
    );
    await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
    expect(refreshCalls, 1);
  });

  test('rejected refresh clears the session and fires onSessionExpired', () async {
    final store = await _storeWithSession();
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async => req.url.path == '/auth/refresh' ? _json({'success': false}, 401) : _json({'success': false}, 401)),
    );
    var expired = 0;
    api.onSessionExpired.listen((_) => expired++);
    await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(store.current, isNull);
    expect(expired, 1);
    expect(await TokenStore().load(), isNull);
  });

  test('network failure during refresh keeps the session', () async {
    final store = await _storeWithSession();
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path == '/auth/refresh') throw http.ClientException('offline');
        return _json({'success': false}, 401);
      }),
    );
    await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
    expect(store.current, isNotNull);
  });

  test('auth:false sends no token and never refreshes', () async {
    final store = await _storeWithSession();
    var refreshCalls = 0;
    String? auth;
    final api = ApiClient(
      tokenStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path == '/auth/refresh') refreshCalls++;
        auth = req.headers['Authorization'];
        return _json({'success': false, 'error': {'message': 'bad creds'}}, 401);
      }),
    );
    await expectLater(api.post('/auth/login', auth: false, body: {'a': 1}), throwsA(isA<ApiException>().having((e) => e.message, 'm', 'bad creds')));
    expect(auth, isNull);
    expect(refreshCalls, 0);
    expect(store.current, isNotNull);
  });

  test('network error is reported with statusCode 0', () async {
    final store = await _storeWithSession();
    final api = ApiClient(tokenStore: store, httpClient: MockClient((_) async => throw http.ClientException('down')));
    await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'net', true)));
  });
}
