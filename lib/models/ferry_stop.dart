class FerryStop {
  const FerryStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}
