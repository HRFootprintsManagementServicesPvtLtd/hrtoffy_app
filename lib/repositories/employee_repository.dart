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

  /// The only employee columns an employee may change themselves: the website's `ess_update_my_profile` whitelist
  /// (`ESS_EDITABLE_FIELDS` in `EditMyDetailsForm`). Bank, PAN, Aadhaar, UAN, work information and `email` are managed
  /// by HR and are never sent from the app.
  static const Set<String> editableProfileFields = {
    'full_name',
    'date_of_birth',
    'gender',
    'blood_group',
    'marital_status',
    'nationality',
    'phone',
    'mobile_number',
    'personal_email',
    'current_address',
    'permanent_address',
    'location',
    'emergency_contact_name',
    'emergency_contact_relationship',
    'emergency_contact_number',
  };

  /// `PATCH /organizations/:orgId/employees/me` - the employee's own personal and contact details.
  ///
  /// [changes] uses the UI's snake_case column names (`blood_group`, ...) and may only contain
  /// [editableProfileFields]; anything else (HR-managed fields, `email`) throws [ArgumentError] before any request.
  /// Returns the saved record.
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> changes) async {
    final restricted = changes.keys.where((k) => !editableProfileFields.contains(k)).toList();
    if (restricted.isNotEmpty) {
      throw ArgumentError('Not editable by the employee: ${restricted.join(', ')}');
    }
    final data = await api.patch(orgPath('/employees/me'), body: camelKeys(Map<String, dynamic>.from(changes)));
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
