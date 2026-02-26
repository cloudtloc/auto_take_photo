import 'dart:convert';

import 'package:flutter_nominatim/flutter_nominatim.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline-first: uu tien doc cache dia chi, chi goi API khi khong co cache.
/// Ket qua tra ve duoc cache lai de lan sau (offline) van co ten dia diem.
class PlaceNameService {
  static const _cacheKey = 'place_name_cache';
  static const _precision = 3;

  static String _cacheKeyFor(double lat, double lon) {
    return '${lat.toStringAsFixed(_precision)}_${lon.toStringAsFixed(_precision)}';
  }

  static Future<Map<String, String>> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCache(Map<String, String> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(cache));
  }

  /// Tra ve ten dia diem cho (lat, lon). Uu tien cache; neu khong co va online thi goi Nominatim roi cache.
  /// Offline hoac loi thi tra null (ung dung van chup duoc, chi hien lat/lon).
  static Future<String?> getPlaceName(double lat, double lon) async {
    final key = _cacheKeyFor(lat, lon);
    final cache = await _loadCache();
    final cached = cache[key];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final place = await Nominatim.instance.getAddressFromLatLng(lat, lon);
      final name = place.displayName;
      if (name.isEmpty) return null;
      cache[key] = name;
      await _saveCache(cache);
      return name;
    } catch (_) {
      return null;
    }
  }
}
