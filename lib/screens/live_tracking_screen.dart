import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/employee_ui.dart';

class LiveTrackingMapScreen extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const LiveTrackingMapScreen({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Scaffold(
        appBar: EmployeeUi.appBar(title: "Employee Tracking"),
        backgroundColor: EmployeeUi.pageBg,
        body: Center(child: Text("No tracking records found", style: GoogleFonts.montserrat(color: Colors.grey))),
      );
    }

    final first = logs.first;
    return Scaffold(
      appBar: EmployeeUi.appBar(title: "Location History"),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(first['punch_lat'], first['punch_lng']), zoom: 15),
        markers: logs.map<Marker>((log) {
          return Marker(
            markerId: MarkerId(log['id']),
            position: LatLng(log['punch_lat'], log['punch_lng']),
            infoWindow: InfoWindow(title: log['punch_type'], snippet: log['punch_time']),
          );
        }).toSet(),
      ),
    );
  }
}
