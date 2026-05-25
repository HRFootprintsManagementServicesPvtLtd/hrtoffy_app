import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LiveTrackingMapScreen extends StatelessWidget {

  final List<Map<String, dynamic>> logs;

  const LiveTrackingMapScreen({
    super.key,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {

    if (logs.isEmpty) {

      return const Scaffold(
        body: Center(
          child: Text(
            "No tracking records found",
          ),
        ),
      );
    }

    final first = logs.first;

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Employee Tracking",
        ),
      ),

      body: GoogleMap(

        initialCameraPosition: CameraPosition(

          target: LatLng(
            first['punch_lat'],
            first['punch_lng'],
          ),

          zoom: 15,
        ),

        markers:
        logs.map<Marker>((log) {

          return Marker(

            markerId:
            MarkerId(log['id']),

            position: LatLng(
              log['punch_lat'],
              log['punch_lng'],
            ),

            infoWindow: InfoWindow(

              title:
              log['punch_type'],

              snippet:
              log['punch_time'],
            ),
          );
        }).toSet(),
      ),
    );
  }
}