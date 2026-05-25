import 'dart:math';
import '../models/work_site.dart';

double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    ) {
  const R = 6371000;

  double dLat = _deg2rad(lat2 - lat1);
  double dLon = _deg2rad(lon2 - lon1);

  double a =
      sin(dLat / 2) * sin(dLat / 2) +
          cos(_deg2rad(lat1)) *
              cos(_deg2rad(lat2)) *
              sin(dLon / 2) *
              sin(dLon / 2);

  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c;
}

double _deg2rad(double deg) {
  return deg * (pi / 180);
}

Map<String, dynamic>? findNearestSite({
  required double userLat,
  required double userLng,
  required List<WorkSite> sites,
}) {
  if (sites.isEmpty) return null;

  WorkSite? nearest;
  double nearestDistance = double.infinity;

  for (final s in sites) {
    final d = haversineDistance(
      userLat,
      userLng,
      s.latitude,
      s.longitude,
    );

    if (d < nearestDistance) {
      nearestDistance = d;
      nearest = s;
    }
  }

  if (nearest == null) return null;

  return {
    'site': nearest,
    'distance': nearestDistance,
    'inFence': nearestDistance <= nearest.radiusMeters,
  };
}