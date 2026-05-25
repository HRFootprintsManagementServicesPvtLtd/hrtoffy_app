import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeoTrackerService {

  static final supabase =
      Supabase.instance.client;

  static Timer? timer;

  static bool isTracking = false;

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

    // immediate first capture
    await captureLocation(

      organizationId,
      employeeId,
      attendanceId,
      shiftEndTime,
    );

    timer = Timer.periodic(

      Duration(
        minutes: intervalMinutes,
      ),

          (_) async {

        // stop after shift ends
        if (DateTime.now().isAfter(
          shiftEndTime,
        )) {

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

      final position =
      await Geolocator.getCurrentPosition(

        desiredAccuracy:
        LocationAccuracy.high,
      );

      await supabase
          .from('attendance_punch_logs')
          .insert({

        'attendance_id': attendanceId,

        'organization_id': organizationId,

        'employee_id': employeeId,

        'punch_type': 'track',

        'punch_source': 'geo_tracker',

        'punch_lat': position.latitude,

        'punch_lng': position.longitude,

        'accuracy_m': position.accuracy,

        'punch_time':
        DateTime.now()
            .toUtc()
            .toIso8601String(),

        'created_at':
        DateTime.now()
            .toUtc()
            .toIso8601String(),
      });

    } catch (e) {

      print(
        'GeoTracker Error: $e',
      );
    }
  }
}