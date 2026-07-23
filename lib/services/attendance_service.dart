import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';
import 'geo_tracker_service.dart';

const String googleGeocodingApiKey = 'AIzaSyB4um8D3zbPD4QnrRkZEqCs30Bp6HCR5a0';

class AttendanceService {
  AttendanceService._();
  static final SupabaseClient supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> getTodayAttendance({
    required String employeeId,
  }) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final response = await supabase
        .from('attendance')
        .select()
        .eq('employee_id', employeeId)
        .eq('date', today)
        .maybeSingle();

    debugPrint("GET TODAY ATTENDANCE RAW:");
    debugPrint(response.toString());

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  static Future<void> updateAttendance({
    required String attendanceId,
    required Map<String, dynamic> values,
  }) async {
    debugPrint("========== UPDATE START ==========");
    debugPrint("Attendance ID: $attendanceId");
    debugPrint("Values: $values");

    final response = await supabase
        .from('attendance')
        .update(values)
        .eq('id', attendanceId)
        .select();

    debugPrint("UPDATED ROW:");
    debugPrint(response.toString());

    debugPrint("========== UPDATE END ==========");
  }

  static Future<Map<String, dynamic>> createAttendance({
    required Map<String, dynamic> values,
  }) async {
    final response = await supabase.from('attendance').insert(values).select('id').single();
    return Map<String, dynamic>.from(response);
  }

  static Future<void> insertPunchLog({
    required Map<String, dynamic> values,
  }) async {
    debugPrint("PUNCHLOG: Starting insert");

    await supabase
        .from('attendance_punch_logs')
        .insert(values);

    debugPrint("PUNCHLOG: Insert completed");
  }

  static Future<List<Map<String, dynamic>>> getTodayPunchLogs({
    required String employeeId,
  }) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return getPunchLogs(employeeId: employeeId, date: today);
  }

  static Future<List<Map<String, dynamic>>> getPunchLogs({
    required String employeeId,
    required String date,
  }) async {
    try {
      final att = await supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', employeeId)
          .eq('date', date)
          .maybeSingle();

      if (att == null) return [];
      
      final res = await supabase
          .from('attendance_punch_logs')
          .select('id, attendance_id, punch_time, punch_type, punch_address, site_id, in_fence, distance_m, accuracy_m, work_type')
          .eq('attendance_id', att['id'])
          .order('punch_time', ascending: true);

      return List<Map<String, dynamic>>.from(res ?? []);
    } catch (e) {
      debugPrint("getPunchLogs error: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getGeoFencePolicy(String orgId) async {
    final org = await supabase.from('organization_settings').select('attendance_policies').eq('organization_id', orgId).maybeSingle();
    return org?['attendance_policies'];
  }

  static bool isGeoTrackOnly({
    required Map<String, dynamic> policy,
    required String selectedWorkType,
  }) {
    final onlyForOffice = policy['geo_only_for_office'] == true;
    return onlyForOffice && selectedWorkType != 'on-duty';
  }

  static Future<List<WorkSite>> getResolvedWorkSites(Map<String, dynamic> employee) async {
    final empId = employee['id']?.toString();
    final branchId = employee['branch_id']?.toString();
    final entityId = employee['entity_id']?.toString();
    final orgId = employee['organization_id']?.toString();

    if (empId == null) return [];

    List<dynamic> data = [];
    try {
      final direct = await supabase
          .from('work_site_assignments')
          .select('work_sites(id, name, latitude, longitude, radius_meters)')
          .eq('employee_id', empId);

      if (direct.isNotEmpty) {
        data = direct.map((e) => e['work_sites']).where((e) => e != null).toList();
      } else {
        if (branchId != null) {
          final branchSites = await supabase
              .from('work_sites')
              .select('id, name, latitude, longitude, radius_meters')
              .eq('branch_id', branchId)
              .eq('is_active', true);
          if (branchSites.isNotEmpty) {
            data = branchSites;
          }
        }
        
        if (data.isEmpty && entityId != null) {
          final entitySites = await supabase
              .from('work_sites')
              .select('id, name, latitude, longitude, radius_meters')
              .eq('entity_id', entityId)
              .eq('is_active', true);
          if (entitySites.isNotEmpty) {
            data = entitySites;
          }
        }
        
        if (data.isEmpty && orgId != null) {
          final orgSites = await supabase
              .from('work_sites')
              .select('id, name, latitude, longitude, radius_meters')
              .eq('organization_id', orgId)
              .eq('is_active', true);
          data = orgSites;
        }
      }
    } catch (e) {
      debugPrint("getResolvedWorkSites error: $e");
    }

    return data.whereType<Map<String, dynamic>>().map(WorkSite.fromMap).toList();
  }

  static Future<Position> getLocation() async {
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

  static Future<String> getAddress(double lat, double lng) async {
    try {
      debugPrint("GEOCODE: Fetching address for $lat, $lng...");
      final url = 'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleGeocodingApiKey';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
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

  static Future<Map<String, dynamic>?> checkGeoFence({required List<WorkSite> workSites}) async {
    final pos = await getLocation();
    final nearest = findNearestSite(userLat: pos.latitude, userLng: pos.longitude, sites: workSites);

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
    required Future<bool> Function(String siteName, double distance, double allowed) onShowGeoConfirm,
    required VoidCallback onSuccess,
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
    required Future<bool> Function(String siteName, double distance, double allowed) onShowGeoConfirm,
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
    required Future<bool> Function(String siteName, double distance, double allowed) onShowGeoConfirm,
    required VoidCallback onSuccess,
    required Function(String error) onError,
    required Function(bool loading) onLoading,
  }) async {
    onLoading(true);
    try {
      final empId = employee['id'];
      final orgId = employee['organization_id'];
      if (empId == null || orgId == null) throw Exception('Invalid employee data');

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
            onError("You are outside allowed office radius (${distance!.toStringAsFixed(0)}m)");
            onLoading(false);
            return;
          }

          if (!inFence && geoMode == 'lenient') {
            final confirmed = await onShowGeoConfirm(site!.name, distance!, site.radiusMeters);
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
          final nearest = findNearestSite(userLat: pos.latitude, userLng: pos.longitude, sites: workSites);
          if (nearest != null) {
            site = nearest['site'] as WorkSite;
            inFence = nearest['inFence'];
            distance = nearest['distance'];
          }
        }
      }

      final addr = await getAddress(pos.latitude, pos.longitude);
      final localNow = DateTime.now();
      final utcIso = localNow.toUtc().toIso8601String();
      final date = DateFormat('yyyy-MM-dd').format(localNow);

      debugPrint("STEP 1: Before getTodayAttendance");

      var attendance = await getTodayAttendance(employeeId: empId);

      debugPrint("STEP 1: After getTodayAttendance");

      if (attendance != null && type == 'punch_out') {
        if (attendance['work_type'] != selectedWorkType) {
          onError("Work type mismatch. Please select '${attendance['work_type']}' to punch out.");
          onLoading(false);
          return;
        }
      }

      if (attendance == null && type == 'punch_in') {

        debugPrint("STEP 2: Before createAttendance");

        attendance = await createAttendance(values: {
          'employee_id': empId,
          'organization_id': orgId,
          'date': date,
          'punch_in_time': utcIso,
          'punch_in_lat': pos.latitude,
          'punch_in_lng': pos.longitude,
          'punch_in_address': addr,
          'status': 'present',
          'work_type': selectedWorkType,
          'created_at': utcIso,
        });

        debugPrint("STEP 2: After createAttendance");
      } else if (attendance != null && type == 'punch_out') {
        await updateAttendance(attendanceId: attendance['id'], values: {
          'punch_out_time': utcIso,
          'punch_out_lat': pos.latitude,
          'punch_out_lng': pos.longitude,
          'punch_out_address': addr,
          'updated_at': utcIso,
        });
      } else if (attendance != null && type == 'punch_in') {
         await updateAttendance(attendanceId: attendance['id'], values: {
            'status': 'present',
            'punch_in_time': utcIso,
            'punch_out_time': null,
            'work_type': selectedWorkType,
            'updated_at': utcIso,
         });
      }

      final attId = attendance?['id'];
      if (attId != null) {
        await insertPunchLog(values: {
          'attendance_id': attId,
          'employee_id': empId,
          'organization_id': orgId,
          'punch_time': utcIso,
          'punch_type': type,
          'work_type': selectedWorkType,
          'punch_lat': pos.latitude,
          'punch_lng': pos.longitude,
          'punch_address': addr,
          'created_at': utcIso,
          'site_id': site?.id,
          'in_fence': inFence,
          'distance_m': distance,
          'accuracy_m': gpsAccuracy,
          'punch_source': 'mobile',
        });
      }

      if (type == 'punch_in' && attId != null) {
        final shiftEndTime = localNow.copyWith(hour: 17, minute: 0);
        // Start tracking without awaiting to prevent punch flow timeout
        GeoTrackerService.startTracking(
          organizationId: orgId.toString(),
          employeeId: empId.toString(),
          attendanceId: attId.toString(),
          intervalMinutes: 2,
          shiftEndTime: shiftEndTime,
        ).catchError((e) => debugPrint("GEOTRACKER START ERROR: $e"));
      }

      onSuccess();
    } catch (e, st) {
      debugPrint("PUNCH ERROR: $e");
      debugPrintStack(stackTrace: st);
      onError(e.toString());
    } finally {
      onLoading(false);
    }
  }
}
