import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';

class GeoTrackerService {
  static final supabase = Supabase.instance.client;
  static Timer? timer;
  static bool isTracking = false;
  static List<WorkSite> cachedSites = [];

  static Future<void> startTracking({
    required String organizationId,
    required String employeeId,
    required String attendanceId,
    required int intervalMinutes,
    required DateTime shiftEndTime,
  }) async {
    // prevent duplicate timers
    if (isTracking) return;
    isTracking = true;
    timer?.cancel();

    // Fetch sites once on start
    await _refreshSites(organizationId);

    // immediate first capture
    await captureLocation(
      organizationId,
      employeeId,
      attendanceId,
      shiftEndTime,
    );

    timer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) async {
        // stop after shift ends
        if (DateTime.now().isAfter(shiftEndTime)) {
          await stopTracking();
          return;
        }

        await captureLocation(
          organizationId,
          employeeId,
          attendanceId,
          shiftEndTime,
        );
      },
    );
  }

  static Future<void> _refreshSites(String orgId) async {
    try {
      debugPrint("GEOTRACKER: Refreshing sites for org $orgId...");
      final res = await supabase
          .from('work_sites')
          .select('id, name, latitude, longitude, radius_meters')
          .eq('organization_id', orgId)
          .eq('is_active', true);
      
      cachedSites = (res as List).map((s) => WorkSite.fromMap(s)).toList();
      debugPrint("GEOTRACKER: ${cachedSites.length} sites cached.");
    } catch (e) {
      debugPrint("GEOTRACKER: Refresh Sites Error: $e");
    }
  }

  static Future<void> stopTracking() async {
    timer?.cancel();
    timer = null;
    isTracking = false;
  }

  static Future<void> captureLocation(
    String organizationId,
    String employeeId,
    String attendanceId,
    DateTime shiftEndTime,
  ) async {
    try {
      debugPrint("GEOTRACKER: Capturing location...");
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final nearest = findNearestSite(
        userLat: position.latitude,
        userLng: position.longitude,
        sites: cachedSites,
      );

      final trackData = {
        'attendance_id': attendanceId,
        'organization_id': organizationId,
        'employee_id': employeeId,
        'punch_type': 'track',
        'punch_source': 'geo_tracker',
        'punch_lat': position.latitude,
        'punch_lng': position.longitude,
        'accuracy_m': position.accuracy,
        'site_id': nearest?['site']?.id,
        'in_fence': nearest?['inFence'] ?? false,
        'distance_m': nearest?['distance'],
        'punch_time': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint("========== GEOTRACK INSERT ==========");
      debugPrint(trackData.toString());

      debugPrint("GEOTRACKER: Inserting track log...");
      await supabase.from('attendance_punch_logs').insert(trackData);
      debugPrint("GEOTRACKER: Track log inserted.");
    } catch (e) {
      debugPrint('GEOTRACKER: Error: $e');
    }
  }
}
