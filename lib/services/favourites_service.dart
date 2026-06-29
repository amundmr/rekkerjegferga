import 'dart:convert';
import 'package:web/web.dart' as web;

class FavouritesService {
  static const _key = 'rekker_favourites';

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

  static void save(Map<String, String> favourites) {
    web.window.localStorage.setItem(_key, jsonEncode(favourites));
  }
}
