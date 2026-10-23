import 'dart:async';

import 'profiles/profile_preferences.dart';

/// How long a card must stay focused / hovered before its trailer starts.
///
/// "Instant" (the default) waits only long enough that cards flown past
/// while scrolling never start a trailer; "Normal" is the original 2 s.
class TrailerTiming {
  TrailerTiming._();

  static const String _key = 'trailer_instant_start';
  static const String _reduceMotionKey = 'trailer_respect_reduce_motion';
  static bool _instant = false;
  static bool _respectReduceMotion = false;

  /// How long the Home hero waits on a title before its trailer starts.
  static const Duration heroDelay = Duration(seconds: 2);

  /// Whether trailers stay still when the OS asks for reduced motion
  /// (Windows "Animation effects" off, Android "Remove animations"). Off by
  /// default: handhelds and TV boxes often have animations off for speed,
  /// and that silently stopped every trailer in the app.
  static bool get respectReduceMotion {
    _ensureLoaded();
    return _respectReduceMotion;
  }

  /// The OS reduced-motion flag, as far as trailers are concerned.
  static bool reduceMotion(bool osFlag) => osFlag && respectReduceMotion;
  static bool _loaded = false;

  static bool get instant {
    _ensureLoaded();
    return _instant;
  }

  static Duration get cardDwell {
    _ensureLoaded();
    return _instant
        ? const Duration(milliseconds: 450)
        : const Duration(seconds: 2);
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    unawaited(load());
  }

  static Future<bool> load() async {
    _loaded = true;
    try {
      final prefs = await ProfilePreferences.instance();
      _instant = prefs.getBool(_key) ?? false;
      _respectReduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
    } catch (_) {}
    return _instant;
  }

  static Future<void> setRespectReduceMotion(bool value) async {
    _respectReduceMotion = value;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_reduceMotionKey, value);
    } catch (_) {}
  }

  static Future<void> setInstant(bool value) async {
    _instant = value;
    _loaded = true;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
