import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The signed-in employee's own record, profile edits and avatar.
///
/// The backend returns a camelCase DTO; this repository hands the UI the same
/// snake_case map it used to read from `employee_records` (id, full_name,
/// organization_id, manager_name, avatar_url, ...).
class EmployeeRepository extends BaseRepository {
  EmployeeRepository({super.auth});

  /// `GET /organizations/:orgId/employees/me`
  Future<Map<String, dynamic>> getMe() async {
    final data = await api.get(orgPath('/employees/me'));
    return normalize(data);
  }

  /// `GET /organizations/:orgId/employees/by-email/:email` (a manager's name card).
  /// The backend answers 404 unless the caller is that person, HR, or on that person's reporting line
  /// (an employee asking for their OWN manager gets 404), so treat it as best effort.
  Future<Map<String, dynamic>> getByEmail(String email) async {
    final data = await api.get(orgPath('/employees/by-email/${Uri.encodeComponent(email)}'));
    return normalize(data);
  }

  /// `PATCH /organizations/:orgId/employees/me` - personal, contact, bank and statutory fields.
  ///
  /// [changes] uses the UI's snake_case column names (`blood_group`, `bank_ifsc_code`, ...).
  /// `email` is never sent: it is the sign-in identity and only HR can change it.
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> changes) async {
    final body = camelKeys({
      for (final e in changes.entries)
        if (e.key != 'email') e.key: e.value,
    });
    final data = await api.patch(orgPath('/employees/me'), body: body);
    return normalize(data);
  }

  /// `PATCH /organizations/:orgId/employees/me/avatar`. Pass null to remove the photo.
  Future<Map<String, dynamic>> setAvatarUrl(String? url) async {
    final data = await api.patch(orgPath('/employees/me/avatar'), body: {'avatarUrl': url});
    return normalize(data);
  }

  /// `GET /organizations/:orgId/payroll/me/sensitive-profile` - the caller's OWN decrypted
  /// `salary`, `pan_no`, `uan_no` and `bank_account_no` (null where nothing is stored).
  /// Replaces the `salary-encryption` edge function for the user's own record.
  Future<Map<String, dynamic>> getSensitiveProfile() async {
    final data = await api.get(orgPath('/payroll/me/sensitive-profile'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// camelCase DTO -> snake_case row. Dates stay `yyyy-MM-dd` strings.
  static Map<String, dynamic> normalize(dynamic dto) {
    if (dto is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(snakeKeys(dto) as Map);
  }
}
