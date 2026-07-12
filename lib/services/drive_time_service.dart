import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

typedef DriveTimeResult = ({Duration? duration, double? distanceMeters, List<LatLng> route});

class DriveTimeService {
  static const _baseUrl = 'https://gateway.amund-56d.workers.dev';

  static Future<DriveTimeResult> getDriveTime({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String? destinationStopId,
    String? destinationName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/drive-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
          'destinationStopId': ?destinationStopId,
          'destinationName': ?destinationName,
        }),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final seconds = data['seconds'] as int?;
      final distanceMeters = (data['distanceMeters'] as num?)?.toDouble();
      final rawPoints = data['points'] as List?;
      final route = rawPoints
              ?.map((p) => LatLng(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ))
              .toList() ??
          <LatLng>[];
      return (
        duration: seconds != null ? Duration(seconds: seconds) : null,
        distanceMeters: distanceMeters,
        route: route,
      );
    } catch (_) {
      return (duration: null, distanceMeters: null, route: <LatLng>[]);
    }
  }
}
