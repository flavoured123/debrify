// Sports Hub — scanning the user's own IPTV catalogs and reading their guide.
//
// Nothing here fetches from the internet on its own: channels come from the
// playlists the user already added, programme times from the guide that
// playlist already provides (XMLTV / Xtream EPG).

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/iptv_playlist.dart';
import '../iptv_catalog_db.dart';
import '../iptv_catalog_key.dart';
import '../iptv_epg_service.dart';
import '../profiles/profile_preferences.dart';
import 'sports_catalog.dart';

/// One live catalog the hub may scan (a playlist's live channels).
class SportsSource {
  final String playlistId;
  final String name;
  final String catalogKey;

  const SportsSource({
    required this.playlistId,
    required this.name,
    required this.catalogKey,
  });

  /// Sources for every real (non-virtual, non-file) playlist the user has.
  static List<SportsSource> fromPlaylists(Iterable<IptvPlaylist> playlists) {
    final out = <SportsSource>[];
    final seen = <String>{};
    for (final p in playlists) {
      if (p.isVirtual) continue;
      final key = IptvCatalogKey.forPlaylist(p, 'live');
      if (key == null || !seen.add(key)) continue;
      out.add(SportsSource(playlistId: p.id, name: p.name, catalogKey: key));
    }
    return out;
  }
}

class SportsScanResult {
  final List<SportsChannelGroup> groups;
  final int sourcesScanned;
  final int sourcesWithoutCatalog;

  const SportsScanResult({
    required this.groups,
    required this.sourcesScanned,
    required this.sourcesWithoutCatalog,
  });
}

/// A programme worth showing: a match / event on one logical channel.
class SportsEvent {
  final SportsChannelGroup channel;
  final EpgProgramme programme;
  final String sportId;
  final bool isReplay;

  /// Other channels airing the same title at the same time.
  final List<SportsChannelGroup> alsoOn;

  const SportsEvent({
    required this.channel,
    required this.programme,
    required this.sportId,
    required this.isReplay,
    this.alsoOn = const <SportsChannelGroup>[],
  });

  bool isLiveAt(DateTime t) => programme.airsAt(t);
}

class SportsPrefsStore {
  const SportsPrefsStore._();

  static const _kEnabled = 'iptv_sports_enabled';
  static const _kMulti = 'iptv_sports_multi';
  static const _kRegions = 'iptv_sports_regions';
  static const _kMinTier = 'iptv_sports_min_tier';
  static const _kCollapse = 'iptv_sports_collapse';
  static const _kPreferRaw = 'iptv_sports_prefer_raw';
  static const _kMyTeams = 'iptv_sports_my_teams';
  static const _kLastSport = 'iptv_sports_last_sport';

  /// The sport chip picked last time ('' = All), so the hub reopens on it.
  static Future<String?> loadLastSport() async {
    try {
      final p = await ProfilePreferences.instance();
      final v = p.getString(_kLastSport);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLastSport(String? sportId) async {
    try {
      final p = await ProfilePreferences.instance();
      await p.setString(_kLastSport, sportId ?? '');
    } catch (_) {}
  }

  static Future<SportsPrefs> load() async {
    final defaults = SportsPrefs.defaults();
    try {
      final p = await ProfilePreferences.instance();
      final enabled = p.getStringList(_kEnabled);
      final known = {for (final s in kSportDefs) s.id};
      final rawTier = p.getInt(_kMinTier) ?? 0;
      return SportsPrefs(
        enabledSports: enabled == null
            ? defaults.enabledSports
            : enabled.where(known.contains).toSet(),
        includeMultiSport: p.getBool(_kMulti) ?? defaults.includeMultiSport,
        preferredRegions: (p.getStringList(_kRegions) ?? const <String>[])
            .toSet(),
        minTier: rawTier < 0 ? 0 : (rawTier > 4 ? 4 : rawTier),
        collapseVariants: p.getBool(_kCollapse) ?? defaults.collapseVariants,
        preferRaw: p.getBool(_kPreferRaw) ?? defaults.preferRaw,
        myTeams: p.getStringList(_kMyTeams) ?? const <String>[],
      );
    } catch (e) {
      debugPrint('[SportsHub] prefs load failed: $e');
      return defaults;
    }
  }

  static Future<void> save(SportsPrefs prefs) async {
    try {
      final p = await ProfilePreferences.instance();
      await p.setStringList(_kEnabled, prefs.enabledSports.toList()..sort());
      await p.setBool(_kMulti, prefs.includeMultiSport);
      await p.setStringList(_kRegions, prefs.preferredRegions.toList()..sort());
      await p.setInt(_kMinTier, prefs.minTier);
      await p.setBool(_kCollapse, prefs.collapseVariants);
      await p.setBool(_kPreferRaw, prefs.preferRaw);
      await p.setStringList(_kMyTeams, prefs.myTeams);
    } catch (e) {
      debugPrint('[SportsHub] prefs save failed: $e');
    }
  }
}

class SportsService {
  const SportsService._();

  static const int _pageSize = 400;
  static const int _maxPerCategory = 4000;
  static const int _probeLimit = 300;

  /// Give the UI isolate a frame between database reads: catalog queries are
  /// synchronous and a 50k-row playlist must not freeze a TV remote.
  static Future<void> _breathe() => Future<void>.delayed(Duration.zero);

  /// Finds sports channels in every source. Region preferences affect only the
  /// ranking, so changing them needs a rescan but not a guide reload.
  static Future<SportsScanResult> scan({
    required List<SportsSource> sources,
    required Set<String> preferredRegions,
    bool preferRaw = true,
    bool Function()? cancelled,
  }) async {
    final found = <SportsChannel>[];
    var scanned = 0;
    var missing = 0;

    try {
      await IptvCatalogDb.open();
    } catch (e) {
      debugPrint('[SportsHub] catalog open failed: $e');
      return const SportsScanResult(
        groups: <SportsChannelGroup>[],
        sourcesScanned: 0,
        sourcesWithoutCatalog: 0,
      );
    }

    for (final src in sources) {
      if (cancelled?.call() ?? false) break;
      CatalogSnapshot? snap;
      try {
        snap = IptvCatalogDb.snapshot(src.catalogKey);
      } catch (e) {
        debugPrint('[SportsHub] snapshot failed for ${src.name}: $e');
      }
      if (snap == null) {
        missing++;
        continue;
      }
      scanned++;
      final seen = <int>{};

      void take(
        List<({int position, IptvChannel channel})> entries,
        bool fromCategory,
      ) {
        for (final e in entries) {
          if (!seen.add(e.position)) continue;
          final c = classifySportsChannel(
            channel: e.channel,
            sourceId: src.playlistId,
            sourceName: src.name,
            fromSportsCategory: fromCategory,
            preferredRegions: preferredRegions,
            preferRaw: preferRaw,
          );
          if (c != null) found.add(c);
        }
      }

      try {
        // 1) Folders that look like sports: walk them completely.
        for (final cat in snap.categories) {
          if (cancelled?.call() ?? false) break;
          if (!sportsContainsAny(sportsNormalize(cat), kSportsCategoryWords)) {
            continue;
          }
          var offset = 0;
          while (offset < _maxPerCategory) {
            final entries = snap.pageEntries(
              offset: offset,
              limit: _pageSize,
              group: cat,
              live: true,
            );
            take(entries, true);
            if (entries.length < _pageSize) break;
            offset += _pageSize;
            await _breathe();
          }
          await _breathe();
        }

        // 2) Strays filed under non-sports folders.
        for (final kw in kSportsProbeWords) {
          if (cancelled?.call() ?? false) break;
          take(
            snap.pageEntries(
              offset: 0,
              limit: _probeLimit,
              search: kw,
              live: true,
            ),
            false,
          );
          await _breathe();
        }
      } catch (e) {
        // A refresh can sweep the pinned generation mid-scan. Keep what we
        // already have rather than failing the whole hub.
        debugPrint('[SportsHub] scan of ${src.name} interrupted: $e');
      }
    }

    return SportsScanResult(
      groups: group(found),
      sourcesScanned: scanned,
      sourcesWithoutCatalog: missing,
    );
  }

  /// Collapses variants of the same channel and orders best stream first.
  static List<SportsChannelGroup> group(List<SportsChannel> channels) {
    final byKey = <String, List<SportsChannel>>{};
    for (final c in channels) {
      final key = c.groupKey.isEmpty ? c.channel.url : c.groupKey;
      byKey.putIfAbsent(key, () => <SportsChannel>[]).add(c);
    }
    final groups = <SportsChannelGroup>[];
    byKey.forEach((key, list) {
      list.sort((a, b) => b.score.compareTo(a.score));
      // Same URL listed twice is not a second variant.
      final urls = <String>{};
      final unique = <SportsChannel>[
        for (final c in list)
          if (urls.add(c.channel.url)) c,
      ];
      groups.add(SportsChannelGroup(key: key, variants: unique));
    });
    groups.sort((a, b) {
      final byScore = b.best.score.compareTo(a.best.score);
      if (byScore != 0) return byScore;
      return a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
    });
    return groups;
  }

  /// Applies the user's settings to a scan: sport switches, quality floor and
  /// the multi-sport toggle. Pure and fast — safe to call on every change.
  static List<SportsChannelGroup> visibleChannels(
    List<SportsChannelGroup> all,
    SportsPrefs prefs, {
    String? onlySport,
  }) {
    final out = <SportsChannelGroup>[];
    for (final g in all) {
      final variants = [
        for (final v in g.variants)
          if (v.tier >= prefs.minTier) v,
      ];
      if (variants.isEmpty) continue;
      final shown = SportsChannelGroup(key: g.key, variants: variants);
      final sports = shown.sports;
      if (onlySport != null) {
        if (!sports.contains(onlySport)) continue;
      } else if (sports.isEmpty) {
        if (!prefs.includeMultiSport) continue;
      } else if (!sports.any(prefs.enabledSports.contains)) {
        continue;
      }
      out.add(shown);
    }
    return out;
  }

  /// Reads the guide for the best channels and returns matches / events,
  /// soonest first. [onProgress] fires as batches finish so the UI can fill in
  /// while slower panels are still answering.
  static Future<List<SportsEvent>> loadEvents({
    required List<SportsChannelGroup> channels,
    required SportsPrefs prefs,
    int maxChannels = 70,
    Duration horizon = const Duration(hours: 48),
    void Function(List<SportsEvent> partial)? onProgress,
    bool Function()? cancelled,
  }) async {
    final now = DateTime.now();
    final until = now.add(horizon);
    final candidates = channels.take(maxChannels).toList();
    final raw = <SportsEvent>[];

    Future<void> one(SportsChannelGroup g) async {
      List<EpgProgramme> schedule = const <EpgProgramme>[];
      // Variants usually share a guide id, but a backup feed sometimes has no
      // binding — try the best two before giving up.
      for (final v in g.variants.take(2)) {
        try {
          schedule = await IptvEpgService.instance
              .schedule(v.channel.url)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          schedule = const <EpgProgramme>[];
        }
        if (schedule.isNotEmpty) break;
      }
      for (final p in schedule) {
        if (!p.stop.isAfter(now) || p.start.isAfter(until)) continue;
        if (sportsTitleIsOffAir(p.title)) continue;
        final sport = _sportFor(g, p.title, prefs);
        if (sport == null) continue;
        raw.add(
          SportsEvent(
            channel: g,
            programme: p,
            sportId: sport,
            isReplay: sportsTitleLooksLikeReplay(p.title),
          ),
        );
      }
    }

    const batch = 4;
    for (var i = 0; i < candidates.length; i += batch) {
      if (cancelled?.call() ?? false) break;
      final slice = candidates.skip(i).take(batch);
      await Future.wait(slice.map(one));
      if (onProgress != null) onProgress(mergeEvents(raw));
    }
    return mergeEvents(raw);
  }

  /// Which enabled sport a programme belongs to, or null to skip it.
  static String? _sportFor(
    SportsChannelGroup g,
    String title,
    SportsPrefs prefs,
  ) {
    final inTitle = sportsInTitle(title).where(prefs.enabledSports.contains);
    if (inTitle.isNotEmpty) {
      // A dedicated channel's own sport wins a tie.
      for (final s in inTitle) {
        if (g.sports.contains(s)) return s;
      }
      return inTitle.first;
    }
    // Dedicated channel, generic title ("Live", "Match Day"): trust the channel.
    for (final s in g.sports) {
      if (prefs.enabledSports.contains(s)) return s;
    }
    return null;
  }

  /// Merges the same title airing at the same time on several channels into
  /// one event (best-quality channel first, others in [SportsEvent.alsoOn]).
  static List<SportsEvent> mergeEvents(List<SportsEvent> events) {
    final buckets = <String, List<SportsEvent>>{};
    for (final e in events) {
      final t = e.programme.start.millisecondsSinceEpoch ~/ (30 * 60 * 1000);
      final title = sportsNormalize(e.programme.title).trim();
      buckets.putIfAbsent('$t|$title', () => <SportsEvent>[]).add(e);
    }
    final merged = <SportsEvent>[];
    for (final list in buckets.values) {
      list.sort((a, b) => b.channel.best.score.compareTo(a.channel.best.score));
      final lead = list.first;
      merged.add(
        SportsEvent(
          channel: lead.channel,
          programme: lead.programme,
          sportId: lead.sportId,
          isReplay: lead.isReplay,
          alsoOn: [for (final e in list.skip(1)) e.channel],
        ),
      );
    }
    merged.sort((a, b) {
      // Real live events before replays, then by start time.
      if (a.isReplay != b.isReplay) return a.isReplay ? 1 : -1;
      return a.programme.start.compareTo(b.programme.start);
    });
    return merged;
  }
}
