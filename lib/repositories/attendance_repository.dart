import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import '../core/auth/auth_service.dart';
import 'base_repository.dart';

/// What `POST /attendance/punch` returns in `data` once the punch is recorded.
class PunchResult {
  const PunchResult({
    required this.attendanceId,
    required this.punchLogId,
    required this.punchTime,
    required this.punchType,
    required this.inFence,
    required this.distanceM,
    required this.siteId,
    required this.isSuspicious,
    required this.suspicionReasons,
  });

  /// The day's attendance row: the id the location tracker is attached to.
  final String? attendanceId;
  final String? punchLogId;
  final DateTime? punchTime;
  final String? punchType;

  /// The server's own geofence result (it resolves the fence itself); null when it did not evaluate one.
  final bool? inFence;
  final num? distanceM;
  final String? siteId;
  final bool isSuspicious;
  final List<String> suspicionReasons;

  factory PunchResult.fromJson(Map<String, dynamic> data) {
    final reasons = data['suspicion_reasons'];
    return PunchResult(
      attendanceId: data['attendance_id']?.toString(),
      punchLogId: data['punch_log_id']?.toString(),
      punchTime: asDate(data['punch_time']),
      punchType: data['punch_type']?.toString(),
      inFence: data['in_fence'] is bool ? data['in_fence'] as bool : null,
      distanceM: asNum(data['distance_m']),
      siteId: data['site_id']?.toString(),
      isSuspicious: data['is_suspicious'] == true,
      suspicionReasons: reasons is List
          ? reasons.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// A message that is safe to show for an attendance call: never raw database or server internals.
String friendlyAttendanceError(Object e) {
  if (e is ApiException) {
    if (e.isNetworkError) {
      return 'Network problem. Check your connection and retry.';
    }
    if (e.isUnauthorized) {
      return 'Session expired - please sign in again.';
    }
    if (e.isServerError) {
      return 'Could not record your attendance right now. Please try again.';
    }
    if (e.message.trim().isNotEmpty) {
      return e.message; // 4xx: a message the API chose for the employee
    }
    if (e.isForbidden) {
      return "You don't have permission to do this.";
    }
    return 'Could not complete the request. Please try again.';
  }
  if (e is AuthFlowException) {
    return e.message;
  }
  return 'Something went wrong. Please try again.';
}

/// The signed-in employee's attendance through the HR Toffy API.
///
/// Organization and employee come from the session (see [BaseRepository]); no id is hardcoded and
/// every call goes through the HR Toffy API.
class AttendanceRepository extends BaseRepository {
  AttendanceRepository({super.auth});

  static const _numericLogFields = [
    'punch_lat',
    'punch_lng',
    'distance_m',
    'accuracy_m',
  ];

  /// `POST /organizations/:orgId/attendance/punch`.
  ///
  /// Sends exactly the fields the API reads. The server decides the punch time and the date (nothing about
  /// either is sent). When no work site was evaluated pass null for [siteId], [inFence] and [distanceM] and the
  /// server resolves the fence itself.
  ///
  /// The API answers HTTP 200 even when the punch function reports failure, so `data.success != true` is
  /// turned into an [ApiException] here.
  Future<PunchResult> punch({
    String? employeeId,
    required String punchType,
    required String workType,
    String punchSource = 'mobile',
    double? latitude,
    double? longitude,
    double? accuracy,
    String? address,
    String? siteId,
    bool? inFence,
    double? distanceM,
  }) async {
    final data = await api.post(
      orgPath('/attendance/punch'),
      body: {
        'employeeId': employeeId ?? this.employeeId,
        'punchType': punchType,
        'workType': workType,
        'punchSource': punchSource,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'address': address,
        'siteId': siteId,
        'inFence': inFence,
        'distanceM': distanceM,
        'clientSignals': null,
      },
    );
    if (data is! Map) {
      throw const ApiException(
        502,
        'Unexpected response while recording your punch.',
        code: 'PUNCH_BAD_RESPONSE',
      );
    }
    final map = Map<String, dynamic>.from(data);
    if (map['success'] != true) {
      final reason = map['error'] ?? map['message'] ?? map['reason'];
      final text = reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : 'Your punch could not be recorded.';
      throw ApiException(422, text, code: 'PUNCH_REJECTED');
    }
    return PunchResult.fromJson(map);
  }

  /// `GET /organizations/:orgId/employees/:employeeId/punch-status` ->
  /// `{latestPunch, attendance (the day's row or null), punchLogs [{punch_time, punch_type, work_type, punch_source}], today}`.
  /// "Today" is the day the server uses.
  Future<Map<String, dynamic>> punchStatus({String? employeeId}) async {
    final data = await api.get(
      orgPath('/employees/${employeeId ?? this.employeeId}/punch-status'),
    );
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return {
      'latestPunch': map['latestPunch'] is Map
          ? Map<String, dynamic>.from(map['latestPunch'] as Map)
          : null,
      'attendance': map['attendance'] is Map
          ? Map<String, dynamic>.from(map['attendance'] as Map)
          : null,
      'punchLogs': asMapList(map['punchLogs']),
      'today': map['today']?.toString(),
    };
  }

  /// `GET /organizations/:orgId/attendance/records?employeeId=&from=&to=` (dates `yyyy-MM-dd`), newest first.
  Future<List<Map<String, dynamic>>> attendanceRecords({
    String? employeeId,
    String? from,
    String? to,
  }) async {
    final data = await api.get(
      orgPath('/attendance/records'),
      query: {
        'employeeId': employeeId ?? this.employeeId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    );
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/attendance/employees/:employeeId/day-punch-logs?date=&attendanceId=`:
  /// the day's punch logs with their location fields, oldest first.
  Future<List<Map<String, dynamic>>> dayPunchLogs({
    String? employeeId,
    required String date,
    String? attendanceId,
  }) async {
    final data = await api.get(
      orgPath(
        '/attendance/employees/${employeeId ?? this.employeeId}/day-punch-logs',
      ),
      query: {
        'date': date,
        if (attendanceId != null) 'attendanceId': attendanceId,
      },
    );
    return asMapList(data).map(_normalizeLog).toList();
  }

  /// `GET /organizations/:orgId/geo-fencing-policy`, in the keys the attendance screens read
  /// (`geo_fencing_enabled`, `geo_fencing_mode`, `geo_only_for_office`, ...).
  ///
  /// The API reports its own defaults for settings an organization never saved
  /// (for example `onlyForOffice` is true when unset); the values are passed through as reported.
  Future<Map<String, dynamic>> geoPolicy() async {
    final data = await api.get(orgPath('/geo-fencing-policy'));
    final m = data is Map ? data : const {};
    return {
      'geo_fencing_enabled': m['enabled'] == true,
      'geo_fencing_mode': (m['mode'] ?? 'strict').toString(),
      'geo_only_for_office': m['onlyForOffice'] == true,
      'geo_track_all_punches': m['trackAllPunches'] == true,
      'geo_fencing_radius': asNum(m['defaultRadiusMeters']) ?? 100,
    };
  }

  /// `GET /organizations/:orgId/work-sites`, one map per site with snake_case keys
  /// (`id, name, latitude, longitude, radius_meters, branch_id, entity_id, is_active`).
  Future<List<Map<String, dynamic>>> workSites({
    String? branchId,
    String? entityId,
    bool? isActive,
  }) async {
    final data = await api.get(
      orgPath('/work-sites'),
      query: {
        if (branchId != null) 'branchId': branchId,
        if (entityId != null) 'entityId': entityId,
        if (isActive != null) 'isActive': isActive.toString(),
      },
    );
    return asMapList(
      data,
    ).map((s) => Map<String, dynamic>.from(snakeKeys(s) as Map)).toList();
  }

  /// `GET /organizations/:orgId/work-site-assignments?employeeId=`: the sites assigned to the employee
  /// (`work_site_id`, `employee_id`, ...).
  Future<List<Map<String, dynamic>>> workSiteAssignments({
    String? employeeId,
  }) async {
    final data = await api.get(
      orgPath('/work-site-assignments'),
      query: {'employeeId': employeeId ?? this.employeeId},
    );
    return asMapList(
      data,
    ).map((s) => Map<String, dynamic>.from(snakeKeys(s) as Map)).toList();
  }

  /// `GET /organizations/:orgId/attendance/:attendanceId/punch-logs`: every punch log of one attendance row,
  /// oldest first, with its location fields. It looks logs up by attendance id (no time window), so the day
  /// is whatever the server's attendance row says.
  Future<List<Map<String, dynamic>>> attendancePunchLogs(
    String attendanceId,
  ) async {
    final data = await api.get(orgPath('/attendance/$attendanceId/punch-logs'));
    return asMapList(data).map(_normalizeLog).toList();
  }

  /// `GET /organizations/:orgId` -> `attendance_recording_method` (`in_system`, `both` or `biometric`),
  /// or null when the organization has none set.
  Future<String?> attendanceRecordingMethod() async {
    final data = await api.get(orgPath(''));
    final value = data is Map ? data['attendance_recording_method'] : null;
    return value?.toString();
  }

  /// `POST /organizations/:orgId/attendance/regularizations`.
  ///
  /// [date] is `yyyy-MM-dd`; [requestedPunchIn] and [requestedPunchOut] are UTC ISO-8601 instants. The employee
  /// (the caller) and the approving manager are decided by the server, so neither id is sent. Returns the
  /// created request row.
  Future<Map<String, dynamic>> submitRegularization({
    required String date,
    required String requestedPunchIn,
    String? requestedPunchOut,
    required String reason,
  }) async {
    final data = await api.post(
      orgPath('/attendance/regularizations'),
      body: {
        'date': date,
        'requestedPunchIn': requestedPunchIn,
        if (requestedPunchOut != null) 'requestedPunchOut': requestedPunchOut,
        'reason': reason,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Decimal columns arrive as strings; the UI reads numbers.
  static Map<String, dynamic> _normalizeLog(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    for (final k in _numericLogFields) {
      if (out[k] != null) out[k] = asNum(out[k]) ?? out[k];
    }
    return out;
  }
}
