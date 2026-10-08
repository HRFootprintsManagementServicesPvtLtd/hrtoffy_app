import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';

/// Base class for feature repositories.
///
/// Screens call a repository; the repository calls [ApiClient] on
/// `https://api.hrtoffy.in`. It resolves the signed-in user's organization
/// and employee once from [AuthService], so screens no longer look the
/// employee up by email.
abstract class BaseRepository {
  BaseRepository({AuthService? auth}) : auth = auth ?? AuthService.instance;

  final AuthService auth;

  ApiClient get api => auth.api;

  AuthUser get user => auth.requireUser();

  String get organizationId => user.organizationId;

  /// The caller's `employee_records.id` in the current organization.
  String get employeeId {
    final id = user.employeeId;
    if (id == null || id.isEmpty) {
      throw const ApiException(403, 'No employee record for this user', code: 'NO_EMPLOYEE');
    }
    return id;
  }

  /// `/organizations/<orgId><suffix>` (suffix must start with `/`).
  String orgPath(String suffix) => '/organizations/$organizationId$suffix';
}
