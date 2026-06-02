import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../models/work_site.dart';
import '../../../utils/geo_fence.dart';

class EmployeeGeoDialog extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String organizationId;

  const EmployeeGeoDialog({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.organizationId,
  });

  @override
  State<EmployeeGeoDialog> createState() => _EmployeeGeoDialogState();
}

class _EmployeeGeoDialogState extends State<EmployeeGeoDialog> {
  final supabase = Supabase.instance.client;
  DateTime selectedDate = DateTime.now();
  List<dynamic> trailPoints = [];
  List<WorkSite> workSites = [];
  bool loading = true;

  GoogleMapController? mapController;
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Set<Circle> circles = {};

  double totalKm = 0.0;
  int breachCount = 0;
  String? lastSeen;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      await Future.wait([
        _fetchWorkSites(),
        _fetchTrail(),
      ]);
      _buildMapElements();
    } catch (e) {
      debugPrint("Geo Dialog Load Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _fetchWorkSites() async {
    final res = await supabase
        .from('work_sites')
        .select()
        .eq('organization_id', widget.organizationId);
    workSites = (res as List).map((s) => WorkSite.fromMap(s)).toList();
  }

  Future<void> _fetchTrail() async {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 0, 0, 0);
    final end = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 23, 59, 59);

    final res = await supabase
        .from('attendance_punch_logs')
        .select('punch_time, punch_lat, punch_lng, in_fence')
        .eq('employee_id', widget.employeeId)
        .eq('punch_type', 'track')
        .gte('punch_time', start.toUtc().toIso8601String())
        .lte('punch_time', end.toUtc().toIso8601String())
        .order('punch_time', ascending: true);

    trailPoints = res as List<dynamic>;
  }

  void _buildMapElements() {
    markers.clear();
    polylines.clear();
    circles.clear();
    totalKm = 0.0;
    breachCount = 0;
    lastSeen = null;

    if (trailPoints.isEmpty) return;

    List<LatLng> polylinePoints = [];
    
    for (int i = 0; i < trailPoints.length; i++) {
      final p = trailPoints[i];
      final lat = (p['punch_lat'] as num).toDouble();
      final lng = (p['punch_lng'] as num).toDouble();
      final pos = LatLng(lat, lng);
      final inFence = p['in_fence'] ?? false;
      
      polylinePoints.add(pos);
      
      if (!inFence) breachCount++;

      // Calculation for total distance
      if (i > 0) {
        final prev = trailPoints[i - 1];
        totalKm += haversineDistance(
          (prev['punch_lat'] as num).toDouble(),
          (prev['punch_lng'] as num).toDouble(),
          lat,
          lng,
        ) / 1000.0;
      }

      // Markers for first, last and breaches
      if (i == 0 || i == trailPoints.length - 1 || !inFence) {
        markers.add(Marker(
          markerId: MarkerId('point_$i'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == trailPoints.length - 1 ? BitmapDescriptor.hueBlue : (inFence ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed)
          ),
          infoWindow: InfoWindow(
            title: DateFormat('hh:mm a').format(DateTime.parse(p['punch_time']).toLocal()),
            snippet: inFence ? "Inside Fence" : "Outside Fence",
          ),
        ));
      }
    }

    if (polylinePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('trail'),
        points: polylinePoints,
        color: Colors.blue.withOpacity(0.6),
        width: 4,
      ));
      
      lastSeen = DateFormat('hh:mm a').format(DateTime.parse(trailPoints.last['punch_time']).toLocal());
    }

    // Work site circles
    for (final s in workSites) {
      circles.add(Circle(
        circleId: CircleId(s.id),
        center: LatLng(s.latitude, s.longitude),
        radius: s.radiusMeters,
        fillColor: Colors.blue.withOpacity(0.1),
        strokeColor: Colors.blue.withOpacity(0.3),
        strokeWidth: 2,
      ));
    }

    _fitBounds();
  }

  void _fitBounds() {
    if (mapController == null || trailPoints.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;

    for (final p in trailPoints) {
      final lat = (p['punch_lat'] as num).toDouble();
      final lng = (p['punch_lng'] as num).toDouble();
      if (minLat == null || lat < minLat) minLat = lat;
      if (maxLat == null || lat > maxLat) maxLat = lat;
      if (minLng == null || lng < minLng) minLng = lng;
      if (maxLng == null || lng > maxLng) maxLng = lng;
    }

    mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat!, minLng!),
        northeast: LatLng(maxLat!, maxLng!),
      ),
      50,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "${widget.employeeName} — Location Trail",
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context), 
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDatePicker(),
            const SizedBox(height: 12),
            _buildStatsBar(),
            const SizedBox(height: 16),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMap(),
            ),
            if (!loading && trailPoints.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  "No tracking points recorded for this date.",
                  style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime.now().subtract(const Duration(days: 90)),
          lastDate: DateTime.now(),
        );
        if (date != null) {
          setState(() => selectedDate = date);
          _loadData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('dd-MM-yyyy').format(selectedDate), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _statChip("${trailPoints.length} points"),
        const SizedBox(width: 8),
        _statChip("${totalKm.toStringAsFixed(2)} km"),
      ],
    );
  }

  Widget _statChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
    );
  }

  Widget _buildMap() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GoogleMap(
        initialCameraPosition: const CameraPosition(target: LatLng(17.3850, 78.4867), zoom: 12),
        onMapCreated: (c) {
          mapController = c;
          if (trailPoints.isNotEmpty) _fitBounds();
        },
        markers: markers,
        polylines: polylines,
        circles: circles,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
        mapType: MapType.normal,
      ),
    );
  }
}
