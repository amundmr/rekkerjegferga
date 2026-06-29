import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<LocationPermission> ensurePermission() async {
    // Only check current state — do not call requestPermission(), which fires
    // getCurrentPosition() and causes a redundant browser prompt.
    // watchPosition() (from positionStream) triggers the single browser prompt.
    return Geolocator.checkPermission();
  }

  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }
}
