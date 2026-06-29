import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/departure.dart';
import '../models/ferry_stop.dart';

class FerryService {
  static const _endpoint = 'https://api.entur.io/journey-planner/v3/graphql';
  static const _headers = {
    'Content-Type': 'application/json',
    'ET-Client-Name': 'hand-built-rekkerjegferga',
  };

  static const _carFerrySubmodes = {
    'localCarFerry',
    'nationalCarFerry',
    'internationalCarFerry'
  };

  static bool _hasCarFerry(Map<String, dynamic> place) {
    final quays = place['quays'] as List? ?? [];
    for (final quay in quays) {
      for (final line in (quay['lines'] as List? ?? [])) {
        if (_carFerrySubmodes.contains(line['transportSubmode'])) return true;
      }
    }
    return false;
  }

  static Future<List<FerryStop>> nearbyStops(double lat, double lng) async {
    const query = r'''
      query($lat: Float!, $lng: Float!) {
        nearest(
          latitude: $lat
          longitude: $lng
          maximumDistance: 100000
          filterByPlaceTypes: [stopPlace]
          filterByModes: [water]
        ) {
          edges {
            node {
              distance
              place {
                id
                ... on StopPlace {
                  name
                  latitude
                  longitude
                  quays {
                    lines {
                      transportSubmode
                    }
                  }
                }
              }
            }
          }
        }
      }
    ''';
    try {
      final res = await http.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode({'query': query, 'variables': {'lat': lat, 'lng': lng}}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final edges = body['data']['nearest']['edges'] as List;
      return edges
          .where((e) => _hasCarFerry(e['node']['place'] as Map<String, dynamic>))
          .map((e) {
            final place = e['node']['place'] as Map<String, dynamic>;
            return FerryStop(
              id: place['id'] as String,
              name: place['name'] as String,
              latitude: (place['latitude'] as num).toDouble(),
              longitude: (place['longitude'] as num).toDouble(),
              distanceMeters: (e['node']['distance'] as num).toDouble(),
            );
          })
          .toList();
    } catch (e, st) {
      // ignore: avoid_print
      print('[FerryService] nearbyStops error: $e\n$st');
      return [];
    }
  }

  static Future<List<Departure>> departures(String stopId) async {
    final startTime = DateTime.now()
        .subtract(const Duration(hours: 2))
        .toUtc()
        .toIso8601String();
    const query = r'''
      query($id: String!, $startTime: DateTime!) {
        stopPlace(id: $id) {
          quays {
            estimatedCalls(startTime: $startTime, timeRange: 21600, numberOfDepartures: 20) {
              expectedDepartureTime
              destinationDisplay { frontText }
              serviceJourney { transportSubmode }
            }
          }
        }
      }
    ''';
    try {
      final res = await http.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode(
            {'query': query, 'variables': {'id': stopId, 'startTime': startTime}}),
      );
      final quays =
          jsonDecode(res.body)['data']['stopPlace']['quays'] as List;
      final all = <Departure>[];
      for (final quay in quays) {
        for (final call in (quay['estimatedCalls'] as List)) {
          final submode = call['serviceJourney']['transportSubmode'] as String?;
          if (!_carFerrySubmodes.contains(submode)) continue;
          all.add(Departure(
            time: DateTime.parse(call['expectedDepartureTime'] as String),
            destination: call['destinationDisplay']?['frontText'] as String?,
          ));
        }
      }
      all.sort((a, b) => a.time.compareTo(b.time));
      final seen = <String>{};
      return all.where((d) {
        final key = '${d.time.hour}:${d.time.minute}';
        return seen.add(key);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
