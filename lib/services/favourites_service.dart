import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavouritesService {
  // v2 key stores id→name as JSON; v1 (id-only list) is intentionally not migrated.
  static const _key = 'favourite_stops_v2';

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.cast<String, String>();
  }

  static Future<void> save(Map<String, String> favourites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(favourites));
  }
}
