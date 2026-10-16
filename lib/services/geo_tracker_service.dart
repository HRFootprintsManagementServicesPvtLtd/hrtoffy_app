import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/work_site.dart';
import '../utils/geo_fence.dart';

/// Writes one location point of the employee's trail. The HR Toffy API has no endpoint for this yet, so
/// no writer is installed and tracking stays disabled (see [GeoTrackerService.trackWriter]).
typedef TrackWriter = Future<void> Function(Map<String, dynamic> point);

class GeoTrackerService {
  static Timer? timer;
  static bool isTracking = false;
  static List<WorkSite> cachedSites = [];

  /// Where track points are sent. Intentionally null for now: there is no verified AWS tracking-write
  /// endpoint, and nothing is written to the previous backend. Install a writer here when the backend provides one;
  /// until then [startTracking] does nothing, so the device is not asked for locations that would be dropped.
  static TrackWriter? trackWriter;

  static bool get isEnabled => trackWriter != null;

  /// Starts periodic tracking for [attendanceId] (the id returned by the punch-in).
  /// [sites] are the work sites the punch flow already loaded; no site lookup is made here.
  static Future<void> startTracking({
    required String organizationId,
    required String employeeId,
    required String attendanceId,
    required int intervalMinutes,
    required DateTime shiftEndTime,
    List<WorkSite>? sites,
  }) async {
    if (!isEnabled) {
      debugPrint(
        'GEOTRACKER: disabled (no AWS tracking endpoint); not tracking.',
      );
      return;
    }

    // prevent duplicate timers
    if (isTracking) return;
    isTracking = true;
    timer?.cancel();

    if (sites != null) cachedSites = sites;

    // immediate first capture
    await captureLocation(
      organizationId,
      employeeId,
      attendanceId,
      shiftEndTime,
    );

    timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) async {
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
    });
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
    final writer = trackWriter;
    if (writer == null) return;

    try {
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

      await writer(trackData);
    } catch (e) {
      debugPrint('GEOTRACKER: Error: $e');
    }
  }
}
