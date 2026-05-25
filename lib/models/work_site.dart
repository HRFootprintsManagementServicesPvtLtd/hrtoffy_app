class WorkSite {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  WorkSite({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory WorkSite.fromMap(Map<String, dynamic> map) {
    return WorkSite(
      id: map['id'].toString(),
      name: map['name'] ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] ?? 100).toDouble(),
    );
  }
}