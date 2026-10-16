import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_service.dart';
import '../repositories/attendance_repository.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';
import 'geo_tracker_service.dart';

const String googleGeocodingApiKey = 'AIzaSyB4um8D3zbPD4QnrRkZEqCs30Bp6HCR5a0';

class AttendanceService {
  AttendanceService._();
  // ---------------------------------------------------------------------------
  // Attendance goes through the HR Toffy API (AttendanceRepository); nothing here talks to the previous backend.
  // ---------------------------------------------------------------------------
  static AttendanceRepository? _repository;
  static Future<Position> Function()? _locationOverride;
  static Future<String> Function(double lat, double lng)? _addressOverride;

  static AttendanceRepository get _repo =>
      _repository ??= AttendanceRepository();

  /// Tests only: use a fake repository, location and reverse geocoder.
  @visibleForTesting
  static void debugOverride({
    AttendanceRepository? repository,
    Future<Position> Function()? location,
    Future<String> Function(double lat, double lng)? address,
  }) {
    _repository = repository;
    _locationOverride = location;
    _addressOverride = address;
  }

  @visibleForTesting
  static void debugReset() => debugOverride();

  /// Today's attendance row (the day as the server sees it), or null when there is none yet.
  static Future<Map<String, dynamic>?> getTodayAttendance({
    required String employeeId,
  }) async {
    final status = await _repo.punchStatus(employeeId: employeeId);
    return status['attendance'] as Map<String, dynamic>?;
  }

  /// Today's punch logs, oldest first. The full rows (location, address, fence result) come from the
  /// day-punch-logs endpoint; if that cannot be read the status endpoint's shorter log list is used.
  static Future<List<Map<String, dynamic>>> getTodayPunchLogs({
    required String employeeId,
  }) async {
    final status = await _repo.punchStatus(employeeId: employeeId);
    final att = status['attendance'] as Map<String, dynamic>?;
    if (att == null) return [];

    final today = status['today']?.toString();
    if (today != null && today.isNotEmpty) {
      try {
        return await _repo.dayPunchLogs(
          employeeId: employeeId,
          date: today,
          attendanceId: att['id']?.toString(),
        );
      } catch (e) {
        debugPrint(
          'getTodayPunchLogs detail error: ${friendlyAttendanceError(e)}',
        );
      }
    }
    return List<Map<String, dynamic>>.from(status['punchLogs'] as List);
  }

  /// The punch logs of one day (`yyyy-MM-dd`), oldest first (My History tab). Empty when the day has no
  /// attendance record or the logs cannot be read.
  ///
  /// The day's attendance record is found by its date (`GET /attendance/records?from=D&to=D`) and its logs are then read by
  /// attendance id (`GET /attendance/{id}/punch-logs`).
  ///
  /// TODO(timezone): the date is the attendance date as recorded by the AWS backend, which is the server's (UTC) day.
  /// An early-morning IST punch (about 00:00-05:30 IST) can therefore appear under the previous date. No
  /// timezone conversion is applied here on purpose; the fix belongs to the backend's attendance-date rule.
  static Future<List<Map<String, dynamic>>> getPunchLogs({
    required String employeeId,
    required String date,
  }) async {
    try {
      final records = await _repo.attendanceRecords(
        employeeId: employeeId,
        from: date,
        to: date,
      );
      if (records.isEmpty) return [];
      final attendanceId = records.first['id']?.toString();
      if (attendanceId == null || attendanceId.isEmpty) return [];
      return await _repo.attendancePunchLogs(attendanceId);
    } catch (e) {
      debugPrint('getPunchLogs error: ${friendlyAttendanceError(e)}');
      return [];
    }
  }

  /// The organization's attendance recording method (`in_system`, `both` or `biometric`).
  /// An organization that has none set records in the system.
  static Future<String> getAttendanceRecordingMethod() async {
    return await _repo.attendanceRecordingMethod() ?? 'in_system';
  }

  /// Files a regularization request for the signed-in employee. The server decides the employee and the
  /// approving manager. Returns the created request.
  static Future<Map<String, dynamic>> submitRegularization({
    required String date,
    required String requestedPunchIn,
    String? requestedPunchOut,
    required String reason,
  }) {
    return _repo.submitRegularization(
      date: date,
      requestedPunchIn: requestedPunchIn,
      requestedPunchOut: requestedPunchOut,
      reason: reason,
    );
  }

  /// The organization's geofence policy in the keys the screens read (`geo_fencing_enabled`,
  /// `geo_fencing_mode`, `geo_only_for_office`, ...). The organization is the signed-in session's.
  static Future<Map<String, dynamic>?> getGeoFencePolicy(String orgId) async {
    return _repo.geoPolicy();
  }

  static bool isGeoTrackOnly({
    required Map<String, dynamic> policy,
    required String selectedWorkType,
  }) {
    final onlyForOffice = policy['geo_only_for_office'] == true;
    return onlyForOffice && selectedWorkType != 'on-duty';
  }

  /// The work sites that apply to this employee, by the same priority as before: sites assigned to the
  /// employee; else the branch's active sites; else the entity's; else the organization's active sites.
  static Future<List<WorkSite>> getResolvedWorkSites(
    Map<String, dynamic> employee,
  ) async {
    final empId = employee['id']?.toString();
    final branchId = employee['branch_id']?.toString();
    final entityId = employee['entity_id']?.toString();

    if (empId == null) return [];

    List<Map<String, dynamic>> data = [];

    try {
      final all = await _repo.workSites();
      final assignments = await _repo.workSiteAssignments(employeeId: empId);
      final assignedIds = assignments
          .map((a) => a['work_site_id']?.toString())
          .whereType<String>()
          .toSet();

      bool active(Map<String, dynamic> s) => s['is_active'] != false;

      if (assignedIds.isNotEmpty) {
        data = all
            .where((s) => assignedIds.contains(s['id']?.toString()))
            .toList();
      }
      if (data.isEmpty && branchId != null) {
        data = all
            .where((s) => active(s) && s['branch_id']?.toString() == branchId)
            .toList();
      }
      if (data.isEmpty && entityId != null) {
        data = all
            .where((s) => active(s) && s['entity_id']?.toString() == entityId)
            .toList();
      }
      if (data.isEmpty) {
        data = all.where(active).toList();
      }
      debugPrint('getResolvedWorkSites: ${data.length} sites');
    } catch (e) {
      debugPrint('getResolvedWorkSites error: ${friendlyAttendanceError(e)}');
      return [];
    }

    return data.map(WorkSite.fromMap).toList();
  }

  static Future<Position> getLocation() =>
      (_locationOverride ?? _deviceLocation)();

  static Future<Position> _deviceLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services disabled');
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static Future<String> getAddress(double lat, double lng) =>
      (_addressOverride ?? _reverseGeocode)(lat, lng);

  static Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      debugPrint("GEOCODE: Fetching address for $lat, $lng...");
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleGeocodingApiKey';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(res.body);

      if (data['results'] != null && data['results'].isNotEmpty) {
        for (final r in data['results']) {
          final formatted = r['formatted_address'] as String;
          if (!formatted.contains('+')) {
            debugPrint("GEOCODE: Success.");
            return formatted;
          }
        }
        return data['results'][0]['formatted_address'];
      }
    } catch (e) {
      debugPrint('GEOCODE ERROR: $e');
    }
    return '$lat, $lng';
  }

  static Future<Map<String, dynamic>?> checkGeoFence({
    required List<WorkSite> workSites,
  }) async {
    final pos = await getLocation();
    final nearest = findNearestSite(
      userLat: pos.latitude,
      userLng: pos.longitude,
      sites: workSites,
    );

    if (nearest == null) return null;

    final site = nearest['site'] as WorkSite?;
    if (site == null) return null;

    return {
      'position': pos,
      'site': site,
      'distance': nearest['distance'],
      'inFence': nearest['inFence'],
    };
  }

  static Future<void> punchIn({
    required Map<String, dynamic> employee,
    required String selectedWorkType,
    required bool geoEnabled,
    required String geoMode,
    required bool geoTrackOnly,
    required List<WorkSite> workSites,
    required Future<bool> Function(
      String siteName,
      double distance,
      double allowed,
    )
    onShowGeoConfirm,
    required Future<void> Function() onSuccess,
    required Function(String error) onError,
    required Function(bool loading) onLoading,
  }) async {
    return _punch(
      type: 'punch_in',
      employee: employee,
      selectedWorkType: selectedWorkType,
      geoEnabled: geoEnabled,
      geoMode: geoMode,
      geoTrackOnly: geoTrackOnly,
      workSites: workSites,
      onShowGeoConfirm: onShowGeoConfirm,
      onSuccess: onSuccess,
      onError: onError,
      onLoading: onLoading,
    );
  }

  static Future<void> punchOut({
    required Map<String, dynamic> employee,
    required String selectedWorkType,
    required bool geoEnabled,
    required String geoMode,
    required bool geoTrackOnly,
    required List<WorkSite> workSites,
    required Future<bool> Function(
      String siteName,
      double distance,
      double allowed,
    )
    onShowGeoConfirm,
    required VoidCallback onSuccess,
    required Function(String error) onError,
    required Function(bool loading) onLoading,
  }) async {
    return _punch(
      type: 'punch_out',
      employee: employee,
      selectedWorkType: selectedWorkType,
      geoEnabled: geoEnabled,
      geoMode: geoMode,
      geoTrackOnly: geoTrackOnly,
      workSites: workSites,
      onShowGeoConfirm: onShowGeoConfirm,
      onSuccess: onSuccess,
      onError: onError,
      onLoading: onLoading,
    );
  }

  static Future<void> _punch({
    required String type,
    required Map<String, dynamic> employee,
    required String selectedWorkType,
    required bool geoEnabled,
    required String geoMode,
    required bool geoTrackOnly,
    required List<WorkSite> workSites,
    required Future<bool> Function(
      String siteName,
      double distance,
      double allowed,
    )
    onShowGeoConfirm,
    required VoidCallback onSuccess,
    required Function(String error) onError,
    required Function(bool loading) onLoading,
  }) async {
    onLoading(true);
    try {
      final empId = employee['id'];
      final orgId = employee['organization_id'];
      if (empId == null || orgId == null)
        throw Exception('Invalid employee data');

      Position pos;
      WorkSite? site;
      bool inFence = true;
      double? distance;
      double? gpsAccuracy;

      if (geoEnabled && !geoTrackOnly) {
        final geoResult = await checkGeoFence(workSites: workSites);
        if (geoResult == null) {
          if (geoMode == 'strict') {
            onError("Location required to punch");
            onLoading(false);
            return;
          }
          pos = await getLocation();
        } else {
          pos = geoResult['position'];
          site = geoResult['site'];
          inFence = geoResult['inFence'];
          distance = geoResult['distance'];
          gpsAccuracy = pos.accuracy;

          if (!inFence && geoMode == 'strict') {
            onError(
              "You are outside allowed office radius (${distance!.toStringAsFixed(0)}m)",
            );
            onLoading(false);
            return;
          }

          if (!inFence && geoMode == 'lenient') {
            final confirmed = await onShowGeoConfirm(
              site!.name,
              distance!,
              site.radiusMeters,
            );
            if (!confirmed) {
              onLoading(false);
              return;
            }
          }
        }
      } else {
        pos = await getLocation();
        gpsAccuracy = pos.accuracy;
        if (geoTrackOnly) {
          final nearest = findNearestSite(
            userLat: pos.latitude,
            userLng: pos.longitude,
            sites: workSites,
          );
          if (nearest != null) {
            site = nearest['site'] as WorkSite;
            inFence = nearest['inFence'];
            distance = nearest['distance'];
          }
        }
      }

      final addr = await getAddress(pos.latitude, pos.longitude);

      // Today's attendance, as the server sees it: its work type must match to punch out.
      final attendance = await getTodayAttendance(employeeId: empId.toString());

      if (attendance != null && type == 'punch_out') {
        if (attendance['work_type'] != selectedWorkType) {
          onError(
            "Work type mismatch. Please select '${attendance['work_type']}' to punch out.",
          );
          onLoading(false);
          return;
        }
      }

      // The server records the punch (it sets the time and the date and resolves the fence itself).
      // When no work site was evaluated, no fence result is claimed.
      final result = await _repo.punch(
        employeeId: empId.toString(),
        punchType: type,
        workType: selectedWorkType,
        punchSource: 'mobile',
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: gpsAccuracy ?? pos.accuracy,
        address: addr,
        siteId: site?.id,
        inFence: site == null ? null : inFence,
        distanceM: site == null ? null : distance,
      );

      final attId = result.attendanceId;
      if (type == 'punch_in' && attId != null) {
        final shiftEndTime = DateTime.now().copyWith(hour: 17, minute: 0);

        GeoTrackerService.startTracking(
          organizationId: orgId.toString(),
          employeeId: empId.toString(),
          attendanceId: attId,
          intervalMinutes: 2,
          shiftEndTime: shiftEndTime,
          sites: workSites,
        ).catchError((e) => debugPrint("GEOTRACKER START ERROR: $e"));
      }

      debugPrint("PUNCH COMPLETED");

      onSuccess();
    } catch (e) {
      final safe = (e is ApiException || e is AuthFlowException)
          ? friendlyAttendanceError(e)
          : e.toString();
      debugPrint("PUNCH ERROR: $safe");
      onError(safe);
    } finally {
      onLoading(false);
    }
  }
}
