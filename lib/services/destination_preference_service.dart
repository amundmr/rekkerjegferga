import 'dart:convert';
import 'package:web/web.dart' as web;

class DestinationPreferenceService {
  static const _key = 'rekker_destination_prefs';

  static Map<String, String> load() {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  static void save(Map<String, String> preferences) {
    web.window.localStorage.setItem(_key, jsonEncode(preferences));
  }
}
