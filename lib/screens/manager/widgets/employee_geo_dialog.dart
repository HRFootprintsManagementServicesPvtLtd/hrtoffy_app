import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/work_site.dart';
import '../../../repositories/manager_attendance_repository.dart';
import '../../../utils/geo_fence.dart';

/// Builds the map for the dialog; tests replace it (a real map needs a platform view).
typedef GeoMapBuilder =
    Widget Function(
      List<Map<String, dynamic>> points,
      List<WorkSite> sites,
      void Function(GoogleMapController) onCreated,
    );

/// A team member's location for one day, from the punches the server records (`day-punch-logs`).
///
/// The server's continuous geo trail is HR-only, so this is NOT a trail: it draws the day's tracking points when the
/// server has any (`punch_type == 'track'`), otherwise the punch in/out positions, and says which it is showing.
class EmployeeGeoDialog extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final ManagerAttendanceRepository? repository;
  final DateTime? initialDate;
  final GeoMapBuilder? mapBuilder;

  const EmployeeGeoDialog({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.repository,
    this.initialDate,
    this.mapBuilder,
  });

  @override
  State<EmployeeGeoDialog> createState() => _EmployeeGeoDialogState();
}

class _EmployeeGeoDialogState extends State<EmployeeGeoDialog> {
  late final ManagerAttendanceRepository _repo =
      widget.repository ?? ManagerAttendanceRepository();
  late DateTime selectedDate = widget.initialDate ?? DateTime.now();

  DayPunches? day;
  List<WorkSite> workSites = [];
  bool loading = true;
  String? error;
  int _request = 0;

  GoogleMapController? _map;
  double totalKm = 0;
  int outsideCount = 0;

  List<Map<String, dynamic>> get _points => day?.points ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    DayPunches? loaded;
    String? failure;
    try {
      loaded = await _repo.dayPunches(widget.employeeId, date: selectedDate);
    } catch (e) {
      failure = friendlyManagerAttendanceError(e);
    }
    var sites = workSites;
    if (failure == null && sites.isEmpty) {
      // Work-site circles are context only: without them the points still show.
      try {
        sites = (await _repo.workSites()).map(WorkSite.fromMap).toList();
      } catch (_) {}
    }
    if (!mounted || request != _request) return;
    setState(() {
      day = loaded;
      error = failure;
      workSites = sites;
      loading = false;
      _measure();
    });
  }

  void _measure() {
    totalKm = 0;
    outsideCount = 0;
    final pts = _points;
    for (var i = 0; i < pts.length; i++) {
      if (pts[i]['in_fence'] == false) outsideCount++;
      if (i > 0) {
        totalKm +=
            haversineDistance(
              (pts[i - 1]['punch_lat'] as num).toDouble(),
              (pts[i - 1]['punch_lng'] as num).toDouble(),
              (pts[i]['punch_lat'] as num).toDouble(),
              (pts[i]['punch_lng'] as num).toDouble(),
            ) /
            1000.0;
      }
    }
  }

  static String _time(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    return d == null ? '-' : DateFormat('hh:mm a').format(d.toLocal());
  }

  static String _punchLabel(dynamic type) {
    switch (type?.toString().toLowerCase()) {
      case 'in':
      case 'punch_in':
      case 'check_in':
        return 'Punch in';
      case 'out':
      case 'punch_out':
      case 'check_out':
        return 'Punch out';
      case 'track':
        return 'Tracking point';
      default:
        return 'Punch';
    }
  }

  void _fitBounds() {
    final c = _map;
    final pts = _points;
    if (c == null || pts.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in pts) {
      final lat = (p['punch_lat'] as num).toDouble();
      final lng = (p['punch_lng'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (minLat == maxLat && minLng == maxLng) {
      c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 16));
      return;
    }
    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50,
      ),
    );
  }

  Widget _defaultMap(
    List<Map<String, dynamic>> pts,
    List<WorkSite> sites,
    void Function(GoogleMapController) onCreated,
  ) {
    final markers = <Marker>{};
    final line = <LatLng>[];
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final pos = LatLng(
        (p['punch_lat'] as num).toDouble(),
        (p['punch_lng'] as num).toDouble(),
      );
      line.add(pos);
      final inFence = p['in_fence'] != false;
      final isTrack = p['punch_type']?.toString().toLowerCase() == 'track';
      if (!isTrack || i == 0 || i == pts.length - 1 || !inFence) {
        markers.add(
          Marker(
            markerId: MarkerId('point_$i'),
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              i == pts.length - 1
                  ? BitmapDescriptor.hueBlue
                  : (inFence
                        ? BitmapDescriptor.hueGreen
                        : BitmapDescriptor.hueRed),
            ),
            infoWindow: InfoWindow(
              title:
                  '${_punchLabel(p['punch_type'])} ${_time(p['punch_time'])}',
              snippet: inFence ? 'Inside fence' : 'Outside fence',
            ),
          ),
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: line.first, zoom: 14),
        onMapCreated: onCreated,
        markers: markers,
        polylines: {
          if (line.length > 1)
            Polyline(
              polylineId: const PolylineId('trail'),
              points: line,
              color: Colors.blue.withValues(alpha: 0.6),
              width: 4,
            ),
        },
        circles: {
          for (final s in sites)
            Circle(
              circleId: CircleId(s.id),
              center: LatLng(s.latitude, s.longitude),
              radius: s.radiusMeters,
              fillColor: Colors.blue.withValues(alpha: 0.1),
              strokeColor: Colors.blue.withValues(alpha: 0.3),
              strokeWidth: 2,
            ),
        },
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = day;
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
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.employeeName} - Location',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
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
            Row(
              children: [
                _datePicker(),
                const Spacer(),
                if (d != null && _points.isNotEmpty) ...[
                  _statChip(
                    d.hasTrack
                        ? '${_points.length} tracking points'
                        : '${_points.length} punches',
                  ),
                  const SizedBox(width: 8),
                  _statChip('${totalKm.toStringAsFixed(2)} km'),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.red[700],
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final d = day!;
    if (_points.isEmpty) {
      return Center(
        child: Text(
          'No location was recorded for this date.',
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    final builder = widget.mapBuilder ?? (p, s, c) => _defaultMap(p, s, c);
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: builder(_points, workSites, (c) {
            _map = c;
            _fitBounds();
          }),
        ),
        const SizedBox(height: 8),
        Text(
          d.hasTrack
              ? 'Tracking points recorded during the day.'
              : 'Shows where each punch was recorded. A continuous trail is not available.',
          style: GoogleFonts.montserrat(fontSize: 10, color: Colors.grey),
        ),
        if (outsideCount > 0)
          Text(
            '$outsideCount outside the work-site fence',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              color: Colors.red.shade400,
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          flex: 2,
          child: ListView(
            children: [
              for (final p in _points)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    p['in_fence'] == false
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 16,
                    color: p['in_fence'] == false ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    '${_punchLabel(p['punch_type'])} - ${_time(p['punch_time'])}',
                    style: GoogleFonts.montserrat(fontSize: 11),
                  ),
                  subtitle: p['site_name'] == null
                      ? null
                      : Text(
                          p['site_name'].toString(),
                          style: GoogleFonts.montserrat(fontSize: 10),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _datePicker() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final date = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: now.subtract(const Duration(days: 90)),
          lastDate: now,
        );
        if (date != null) {
          selectedDate = date;
          _load();
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
            Text(
              DateFormat('dd-MM-yyyy').format(selectedDate),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }
}
