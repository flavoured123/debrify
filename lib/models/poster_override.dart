import 'dart:async';

import '../services/profiles/profile_preferences.dart';

/// Rating posters from a poster service (BetterPosters, RPDB, TOP Posters…):
/// a URL pattern the user pastes once, applied to every title that has an
/// IMDb or TMDB id. Placeholders, as AIOMetadata names them:
///   {imdb_id} {imdb}   tt1234567
///   {tmdb_id} {tmdb}   12345   (only when the title carries a TMDB id)
///   {type}             movie | series
///   {id}               the addon's own id
/// Empty = the posters the catalog sends.
class PosterOverride {
  PosterOverride._();

  static const String _key = 'custom_poster_url_pattern';
  static String _pattern = '';
  static bool _loaded = false;

  /// Bumped when the pattern changes, so screens holding posters can redraw.
  static int revision = 0;

  static String get pattern {
    _ensureLoaded();
    return _pattern;
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    unawaited(load());
  }

  static Future<String> load() async {
    _loaded = true;
    try {
      final prefs = await ProfilePreferences.instance();
      _pattern = (prefs.getString(_key) ?? '').trim();
    } catch (_) {}
    return _pattern;
  }

  /// "{{imdb_id}}" and "%7Bimdb_id%7D" (a pasted, URL-encoded link) read as {imdb_id}.
  static String normalize(String value) => value
      .trim()
      .replaceAllMapped(RegExp(r'\{\{([a-z_]+)\}\}'), (m) => '{${m[1]}}')
      .replaceAllMapped(
        RegExp(r'%7B([a-z_]+)%7D', caseSensitive: false),
        (m) => '{${m[1]}}',
      );

  static Future<void> setPattern(String value) async {
    _pattern = normalize(value);
    _loaded = true;
    revision++;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(_key, _pattern);
    } catch (_) {}
  }

  /// Whether [value] is a usable pattern (http(s) with at least one id).
  static bool isValid(String value) {
    final v = normalize(value);
    if (v.isEmpty) return true;
    final uri = Uri.tryParse(v.replaceAll(RegExp(r'\{[a-z_]+\}'), 'x'));
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        RegExp(r'\{(imdb_id|imdb|tmdb_id|tmdb|id)\}').hasMatch(v);
  }

  /// The custom poster for a title, or null to keep the catalog's own.
  static String? urlFor({
    required String id,
    required String? imdbId,
    required String type,
  }) {
    final p = pattern;
    if (p.isEmpty) return null;
    final imdb = imdbId != null && imdbId.startsWith('tt')
        ? imdbId
        : (id.startsWith('tt') ? id.split(':').first : null);
    final tmdbMatch = RegExp(r'^tmdb:(\d+)').firstMatch(id);
    final tmdb = tmdbMatch?.group(1);
    final needsImdb = p.contains('{imdb_id}') || p.contains('{imdb}');
    final needsTmdb = p.contains('{tmdb_id}') || p.contains('{tmdb}');
    if (needsImdb && imdb == null) return null;
    if (needsTmdb && tmdb == null) return null;
    final kind = type == 'series' || type == 'tv' ? 'series' : 'movie';
    return p
        .replaceAll('{imdb_id}', imdb ?? '')
        .replaceAll('{imdb}', imdb ?? '')
        .replaceAll('{tmdb_id}', tmdb ?? '')
        .replaceAll('{tmdb}', tmdb ?? '')
        .replaceAll('{type}', kind)
        .replaceAll('{id}', Uri.encodeComponent(id));
  }
}
