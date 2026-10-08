import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'token_store.dart';

/// Organization returned by `POST /auth/discover-tenants`.
class AuthOrganization {
  final String id;
  final String name;
  const AuthOrganization(this.id, this.name);
}

/// Thrown by [AuthService.login] for non-HTTP failures (e.g. no organization).
class AuthFlowException implements Exception {
  final String message;
  const AuthFlowException(this.message);
  @override
  String toString() => 'AuthFlowException: $message';
}

/// Thrown when the email belongs to several organizations and none was chosen.
/// Call [AuthService.login] again with `organizationId` set to one of them.
class MultipleOrganizationsException extends AuthFlowException {
  final List<AuthOrganization> organizations;
  const MultipleOrganizationsException(this.organizations)
      : super('Multiple organizations found; choose one');
}

/// Authenticated user information exposed to the app.
class AuthUser {
  final String id;
  final String email;
  final String? fullName;
  final String organizationId;
  final String? organizationName;

  /// `employee_records.id` in the current organization, when one exists.
  final String? employeeId;

  /// Employee role (e.g. `manager`, `hr`, `employee`), when known.
  final String? empRole;
  final bool isHrRole;

  const AuthUser({
    required this.id,
    required this.email,
    required this.organizationId,
    this.fullName,
    this.organizationName,
    this.employeeId,
    this.empRole,
    this.isHrRole = false,
  });

  bool get isManager => empRole == 'manager';
}

/// Email/password authentication against the HR Toffy AWS backend
/// (`/auth/*`). Does not use Supabase Auth.
class AuthService extends ChangeNotifier {
  /// Pass the same [tokenStore] that [api] was built with when supplying both.
  AuthService({ApiClient? api, TokenStore? tokenStore})
      : this._(tokenStore ?? TokenStore(), api);

  AuthService._(TokenStore tokens, ApiClient? api)
      : _tokens = tokens,
        _api = api ?? ApiClient(tokenStore: tokens) {
    _expiredSub = _api.onSessionExpired.listen((_) {
      _user = null;
      notifyListeners();
    });
  }

  /// Convenience singleton sharing one [TokenStore] and [ApiClient].
  static final AuthService instance = _createDefault();

  static AuthService _createDefault() {
    final store = TokenStore();
    return AuthService(api: ApiClient(tokenStore: store), tokenStore: store);
  }

  final TokenStore _tokens;
  final ApiClient _api;
  // ignore: unused_field
  StreamSubscription<void>? _expiredSub;

  AuthUser? _user;

  /// Shared client for authenticated calls (already wired to this session).
  ApiClient get api => _api;

  AuthUser? get currentUser => _user;
  bool get isAuthenticated => _user != null;

  /// The signed-in user, or an [ApiException] 401 if there is none. Used by
  /// repositories so a missing session surfaces like any other auth failure.
  AuthUser requireUser() {
    final u = _user;
    if (u == null) throw const ApiException(401, 'Not signed in', code: 'UNAUTHORIZED');
    return u;
  }

  // ----------------------------------------------------------------- login

  /// Signs in with email + password.
  ///
  /// 1. `POST /auth/discover-tenants` (uses the only organization returned;
  ///    throws [MultipleOrganizationsException] if there are several and
  ///    [organizationId] was not given).
  /// 2. `POST /auth/login`, storing tokens/session.
  /// 3. `GET /auth/resolve-user` to determine the employee id and role.
  Future<AuthUser> login(
    String email,
    String password, {
    String? organizationId,
  }) async {
    final cleanEmail = email.trim();

    final orgId = organizationId ?? await _pickOrganization(cleanEmail);

    final data = await _api.post(
      '/auth/login',
      auth: false,
      body: {
        'organizationId': orgId,
        'email': cleanEmail,
        'authMethod': 'password',
        'credentials': {'password': password},
      },
    );

    if (data is! Map || data['accessToken'] is! String || data['refreshToken'] is! String) {
      throw const AuthFlowException('Unexpected login response');
    }

    final user = data['user'];
    final expiresIn = _asInt(data['expiresIn']);
    await _tokens.save(StoredSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      sessionId: data['sessionId']?.toString(),
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      userId: user is Map ? user['id']?.toString() : null,
      email: user is Map ? (user['email']?.toString() ?? cleanEmail) : cleanEmail,
      organizationId: orgId,
    ));

    try {
      return await _resolveAndStoreUser();
    } catch (_) {
      // A session without a resolved profile is not a usable login.
      await _tokens.clear();
      _user = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<String> _pickOrganization(String email) async {
    final data = await _api.post(
      '/auth/discover-tenants',
      auth: false,
      body: {'email': email},
    );
    final raw = (data is Map ? data['organizations'] : null);
    final orgs = <AuthOrganization>[
      if (raw is List)
        for (final o in raw)
          if (o is Map && o['id'] != null)
            AuthOrganization(o['id'].toString(), o['name']?.toString() ?? ''),
    ];
    if (orgs.isEmpty) {
      throw const AuthFlowException('No organization found for this email');
    }
    if (orgs.length > 1) throw MultipleOrganizationsException(orgs);
    return orgs.first.id;
  }

  // --------------------------------------------------------------- session

  /// Restores a persisted session (app start). Returns true when signed in.
  ///
  /// A network failure keeps the stored session (user shown from stored data);
  /// a rejected/expired session returns false and is cleared.
  Future<bool> restoreSession() async {
    final stored = await _tokens.load();
    if (stored == null) {
      _user = null;
      notifyListeners();
      return false;
    }

    if (stored.isAccessTokenExpired) {
      await _api.refreshSession();
      if (_tokens.current == null) {
        _user = null;
        notifyListeners();
        return false;
      }
    }

    try {
      await _resolveAndStoreUser();
      return true;
    } on ApiException catch (e) {
      if (e.isNetworkError || e.isServerError) {
        final s = _tokens.current ?? stored;
        if (s.userId != null && s.email != null && s.organizationId != null) {
          _user = AuthUser(
            id: s.userId!,
            email: s.email!,
            organizationId: s.organizationId!,
            employeeId: s.employeeId,
          );
          notifyListeners();
          return true;
        }
        return false;
      }
      await _tokens.clear();
      _user = null;
      notifyListeners();
      return false;
    }
  }

  /// Forces a token refresh (shares the single-flight with [ApiClient]).
  Future<bool> refresh() async {
    final ok = await _api.refreshSession();
    if (!ok && _tokens.current == null) {
      _user = null;
      notifyListeners();
    }
    return ok;
  }

  /// Revokes the session on the server (best effort) and clears local state.
  Future<void> logout() async {
    try {
      if (_tokens.accessToken != null) {
        await _api.post('/auth/logout');
      }
    } catch (_) {
      // Always sign out locally, even if the server call fails.
    }
    await _tokens.clear();
    _user = null;
    notifyListeners();
  }

  // -------------------------------------------------------------- internals

  Future<AuthUser> _resolveAndStoreUser() async {
    final data = await _api.get('/auth/resolve-user');
    if (data is! Map) {
      throw const AuthFlowException('Unexpected resolve-user response');
    }

    final stored = _tokens.current;
    final orgId = stored?.organizationId ?? data['organizationId']?.toString();
    if (orgId == null || orgId.isEmpty) {
      throw const AuthFlowException('Organization could not be determined');
    }

    // Prefer the entry for the organization we logged in to; resolve-user's
    // top-level fields describe its own "active" org, which may differ.
    String? employeeId;
    String? empRole;
    bool isHr = false;
    String? orgName;

    final orgs = data['organizations'];
    if (orgs is List) {
      for (final o in orgs) {
        if (o is Map && o['id']?.toString() == orgId) {
          employeeId = _nonEmpty(o['employeeId']);
          empRole = _nonEmpty(o['empRole']);
          isHr = o['isHrRole'] == true;
          orgName = _nonEmpty(o['name']);
          break;
        }
      }
    }
    if (employeeId == null &&
        (orgs is! List || orgs.isEmpty || data['organizationId']?.toString() == orgId)) {
      employeeId = _nonEmpty(data['employeeId']);
      empRole ??= _nonEmpty(data['empRole']);
      isHr = isHr || data['isHrRole'] == true;
      orgName ??= _nonEmpty(data['organizationName']);
    }

    final userId = data['id']?.toString() ?? stored?.userId;
    final email = data['email']?.toString() ?? stored?.email;
    if (userId == null || email == null) {
      throw const AuthFlowException('User could not be determined');
    }

    if (stored != null) {
      await _tokens.save(stored.copyWith(
        userId: userId,
        email: email,
        organizationId: orgId,
        employeeId: employeeId,
      ));
    }

    _user = AuthUser(
      id: userId,
      email: email,
      fullName: _nonEmpty(data['fullName']),
      organizationId: orgId,
      organizationName: orgName,
      employeeId: employeeId,
      empRole: empRole,
      isHrRole: isHr,
    );
    notifyListeners();
    return _user!;
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  void dispose() {
    _expiredSub?.cancel();
    super.dispose();
  }
}
