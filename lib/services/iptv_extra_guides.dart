// Extra XMLTV guide URLs the user added (per profile). They fill in the
// programme data for channels the provider's own guide does not cover; see
// IptvEpgService.setExtraGuides.

import 'package:flutter/foundation.dart' show debugPrint;

import 'profiles/profile_preferences.dart';

class IptvExtraGuides {
  IptvExtraGuides._();

  static const String _key = 'iptv_extra_epg_urls';
  static const int maxGuides = 5;

  static Future<List<String>> load() async {
    try {
      final prefs = await ProfilePreferences.instance();
      return List<String>.of(prefs.getStringList(_key) ?? const <String>[]);
    } catch (e) {
      debugPrint('IptvExtraGuides: load failed: $e');
      return <String>[];
    }
  }

  static Future<void> save(List<String> urls) async {
    final clean = <String>[];
    for (final raw in urls) {
      final url = raw.trim();
      if (url.isEmpty || clean.contains(url)) continue;
      clean.add(url);
      if (clean.length >= maxGuides) break;
    }
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(_key, clean);
    } catch (e) {
      debugPrint('IptvExtraGuides: save failed: $e');
    }
  }

  /// Accepts http(s) URLs only.
  static bool looksValid(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
