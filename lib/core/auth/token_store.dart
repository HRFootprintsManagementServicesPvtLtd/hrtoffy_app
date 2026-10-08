import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Immutable snapshot of the persisted AWS-backend session.
///
/// Token values are intentionally excluded from [toString] so they can never
/// end up in logs.
class StoredSession {
  final String accessToken;
  final String refreshToken;
  final String? sessionId;
  final DateTime? expiresAt;
  final String? userId;
  final String? email;
  final String? organizationId;
  final String? employeeId;

  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
    this.expiresAt,
    this.userId,
    this.email,
    this.organizationId,
    this.employeeId,
  });

  StoredSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? sessionId,
    DateTime? expiresAt,
    String? userId,
    String? email,
    String? organizationId,
    String? employeeId,
  }) {
    return StoredSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      sessionId: sessionId ?? this.sessionId,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      organizationId: organizationId ?? this.organizationId,
      employeeId: employeeId ?? this.employeeId,
    );
  }

  bool get isAccessTokenExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  @override
  String toString() =>
      'StoredSession(userId: $userId, organizationId: $organizationId, '
      'employeeId: $employeeId, expiresAt: $expiresAt)';
}

/// Persists the AWS-backend session in the platform secure storage
/// (Android Keystore / iOS Keychain). Never logs token values.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _kAccessToken = 'aws_access_token';
  static const _kRefreshToken = 'aws_refresh_token';
  static const _kSessionId = 'aws_session_id';
  static const _kExpiresAt = 'aws_expires_at';
  static const _kUserId = 'aws_user_id';
  static const _kEmail = 'aws_email';
  static const _kOrganizationId = 'aws_organization_id';
  static const _kEmployeeId = 'aws_employee_id';

  static const _allKeys = [
    _kAccessToken,
    _kRefreshToken,
    _kSessionId,
    _kExpiresAt,
    _kUserId,
    _kEmail,
    _kOrganizationId,
    _kEmployeeId,
  ];

  final FlutterSecureStorage _storage;

  StoredSession? _cache;

  /// Last loaded/saved session, available synchronously.
  StoredSession? get current => _cache;

  String? get accessToken => _cache?.accessToken;
  String? get refreshToken => _cache?.refreshToken;

  /// Reads the persisted session. Returns null when none (or a corrupt/partial
  /// one) is stored.
  Future<StoredSession?> load() async {
    try {
      final all = await _storage.readAll();
      final access = all[_kAccessToken];
      final refresh = all[_kRefreshToken];
      if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
        _cache = null;
        return null;
      }
      final expiresMs = int.tryParse(all[_kExpiresAt] ?? '');
      _cache = StoredSession(
        accessToken: access,
        refreshToken: refresh,
        sessionId: all[_kSessionId],
        expiresAt: expiresMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresMs),
        userId: all[_kUserId],
        email: all[_kEmail],
        organizationId: all[_kOrganizationId],
        employeeId: all[_kEmployeeId],
      );
      return _cache;
    } catch (_) {
      // Secure storage can fail (e.g. keystore reset). Treat as signed out.
      _cache = null;
      return null;
    }
  }

  /// Persists [session] (overwriting any previous one).
  Future<void> save(StoredSession session) async {
    _cache = session;
    await _write(_kAccessToken, session.accessToken);
    await _write(_kRefreshToken, session.refreshToken);
    await _write(_kSessionId, session.sessionId);
    await _write(_kExpiresAt, session.expiresAt?.millisecondsSinceEpoch.toString());
    await _write(_kUserId, session.userId);
    await _write(_kEmail, session.email);
    await _write(_kOrganizationId, session.organizationId);
    await _write(_kEmployeeId, session.employeeId);
  }

  /// Removes every persisted value.
  Future<void> clear() async {
    _cache = null;
    for (final key in _allKeys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
  }

  Future<void> _write(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}
