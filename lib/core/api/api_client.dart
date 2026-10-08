import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../auth/token_store.dart';

/// Typed error for every failed API call. Never contains token values.
class ApiException implements Exception {
  /// HTTP status, or 0 when no response was received (network error/timeout).
  final int statusCode;
  final String message;

  /// Backend error code (e.g. `UNAUTHORIZED`), when provided.
  final String? code;

  const ApiException(this.statusCode, this.message, {this.code});

  bool get isNetworkError => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ', $code' : ''}): $message';
}

/// Minimal HTTP client for the HR Toffy AWS backend.
///
/// * Sends `Authorization: Bearer <accessToken>` from [TokenStore].
/// * Unwraps the backend `{success, data}` envelope (responses without a
///   `success` key, such as login/refresh, are returned as-is).
/// * On a 401 for an authenticated call, performs ONE token refresh
///   (single-flight across concurrent requests) and retries the call once.
/// * Never logs tokens.
class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    http.Client? httpClient,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
  })  : _tokens = tokenStore,
        _http = httpClient ?? http.Client(),
        baseUrl = _trimSlash(baseUrl ?? defaultBaseUrl);

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hrtoffy.in',
  );

  final String baseUrl;
  final Duration timeout;
  final TokenStore _tokens;
  final http.Client _http;

  Future<bool>? _refreshInFlight;
  final StreamController<void> _sessionExpired =
      StreamController<void>.broadcast();

  /// Fires when a refresh was definitively rejected and the stored session
  /// was cleared. The UI layer can listen to send the user to login.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  // ---------------------------------------------------------------- verbs

  Future<dynamic> get(String path,
          {Map<String, dynamic>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _send('POST', path, body: body, query: query, auth: auth);

  Future<dynamic> put(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _send('PUT', path, body: body, query: query, auth: auth);

  Future<dynamic> patch(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _send('PATCH', path, body: body, query: query, auth: auth);

  Future<dynamic> delete(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _send('DELETE', path, body: body, query: query, auth: auth);

  /// `multipart/form-data` upload of one file. A fresh request is built for
  /// every attempt, so a 401 -> refresh -> retry works exactly like the JSON verbs.
  Future<dynamic> postMultipart(
    String path, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    String? contentType,
    Map<String, String>? fields,
    Map<String, dynamic>? query,
    bool auth = true,
  }) {
    final mediaType = contentType == null ? null : MediaType.parse(contentType);
    return _send(
      'POST',
      path,
      query: query,
      auth: auth,
      build: (uri) {
        final req = http.MultipartRequest('POST', uri);
        if (fields != null) req.fields.addAll(fields);
        req.files.add(http.MultipartFile.fromBytes(fileField, bytes,
            filename: filename, contentType: mediaType));
        return req;
      },
    );
  }

  void close() {
    _http.close();
    _sessionExpired.close();
  }

  // ------------------------------------------------------------- internals

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required bool auth,
    http.BaseRequest Function(Uri uri)? build,
  }) async {
    final usedToken = auth ? _tokens.accessToken : null;
    var response = await _request(method, path, body, query, usedToken, build: build);

    if (auth && response.statusCode == 401 && _tokens.refreshToken != null) {
      // If another request already refreshed while this one was in flight,
      // just retry with the new token; otherwise refresh (single-flight).
      final current = _tokens.accessToken;
      final alreadyRefreshed = current != null && current != usedToken;
      final ok = alreadyRefreshed || await _refreshSession();
      if (ok) {
        response = await _request(method, path, body, query, _tokens.accessToken, build: build);
      }
    }

    return _decode(response);
  }

  Future<http.Response> _request(
    String method,
    String path,
    Object? body,
    Map<String, dynamic>? query,
    String? accessToken, {
    http.BaseRequest Function(Uri uri)? build,
  }) async {
    final uri = _uri(path, query);
    final http.BaseRequest request = build != null ? build(uri) : http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (build == null && body != null) {
      request.headers['Content-Type'] = 'application/json';
      (request as http.Request).body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(0, 'Request timed out');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Network error: ${e.message}');
    } catch (e) {
      throw ApiException(0, 'Network error: ${e.runtimeType}');
    }
  }

  Uri _uri(String path, Map<String, dynamic>? query) {
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$p');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{...uri.queryParameters};
    query.forEach((k, v) {
      if (v != null) params[k] = v.toString();
    });
    return uri.replace(queryParameters: params);
  }

  dynamic _decode(http.Response res) {
    dynamic json;
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        json = null;
      }
    }

    final failedEnvelope = json is Map && json['success'] == false;
    if (res.statusCode < 200 || res.statusCode >= 300 || failedEnvelope) {
      throw _errorFrom(res.statusCode, json);
    }

    if (json is Map && json.containsKey('success')) {
      return json['data'];
    }
    return json;
  }

  ApiException _errorFrom(int status, dynamic json) {
    String? message;
    String? code;
    if (json is Map) {
      final err = json['error'];
      if (err is Map) {
        message = err['message']?.toString();
        code = err['code']?.toString();
      } else if (err is String) {
        message = err;
      }
      message ??= json['message']?.toString();
      code ??= json['code']?.toString();
    }
    return ApiException(status, message ?? 'Request failed (HTTP $status)',
        code: code);
  }

  /// Single-flight token refresh. Returns true when new tokens were stored.
  Future<bool> _refreshSession() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  /// Public hook so AuthService.refresh() shares the same single-flight.
  Future<bool> refreshSession() => _refreshSession();

  Future<bool> _doRefresh() async {
    final session = _tokens.current;
    final refreshToken = session?.refreshToken;
    if (session == null || refreshToken == null || refreshToken.isEmpty) {
      await _expire();
      return false;
    }

    http.Response res;
    try {
      res = await _request(
          'POST', '/auth/refresh', {'refreshToken': refreshToken}, null, null);
    } on ApiException {
      // Network failure: keep the session so the user is not logged out
      // just because connectivity dropped.
      return false;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final data = _decode(res);
        if (data is Map && data['accessToken'] is String) {
          final expiresIn = _asInt(data['expiresIn']);
          await _tokens.save(session.copyWith(
            accessToken: data['accessToken'] as String,
            refreshToken: (data['refreshToken'] is String)
                ? data['refreshToken'] as String
                : refreshToken,
            expiresAt: expiresIn == null
                ? session.expiresAt
                : DateTime.now().add(Duration(seconds: expiresIn)),
          ));
          return true;
        }
      } on ApiException {
        // fall through to expire
      }
      await _expire();
      return false;
    }

    // Definitive rejection of the refresh token: the session is dead.
    if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
      await _expire();
    }
    return false;
  }

  Future<void> _expire() async {
    await _tokens.clear();
    if (!_sessionExpired.isClosed) _sessionExpired.add(null);
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
