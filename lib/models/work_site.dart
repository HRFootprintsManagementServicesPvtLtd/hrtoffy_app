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
      id: (map['id'] ?? '').toString(),
      name: map['name'] ?? '',
      latitude: double.tryParse((map['latitude'] ?? 0.0).toString()) ?? 0.0,
      longitude: double.tryParse((map['longitude'] ?? 0.0).toString()) ?? 0.0,
      radiusMeters: double.tryParse((map['radius_meters'] ?? 100).toString()) ?? 100.0,
    );
  }
}
