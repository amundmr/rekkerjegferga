import 'dart:convert';
import 'package:http/http.dart' as http;

class DriveTimeService {
  static const _baseUrl = 'https://gateway.amund-56d.workers.dev';

  static Future<Duration?> getDriveTime({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/drive-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
        }),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final seconds = data['seconds'] as int?;
      if (seconds == null) return null;
      return Duration(seconds: seconds);
    } catch (_) {
      return null;
    }
  }
}
