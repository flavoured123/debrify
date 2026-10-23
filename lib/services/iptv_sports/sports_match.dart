// Sports Hub — "find this match": the channels showing one game, best stream
// first, plus the other channels of that league / sport.
//
// Opened from outside the app with a link such as
//   debrify://sports/match?sport=football&league=Bundesliga
//       &home=VfB%20Stuttgart&away=Borussia%20M%C3%B6nchengladbach
//       &start=1761244200000
// (the Free My TV launcher sends these). Everything is matched against the
// user's own playlists and their guide; nothing is fetched from elsewhere.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../iptv_catalog_db.dart';
import '../iptv_epg_service.dart';
import 'sports_catalog.dart';
import 'sports_service.dart';

/// What the link asks for.
class SportsMatchRequest {
  /// Debrify sport id (cricket, football, wwe, tennis…), or empty.
  final String sport;
  final String title;
  final String league;

  /// Full team / player names ("VfB Stuttgart", "New Zealand").
  final List<String> teams;

  /// Short names guides like to use ("NZ", "IND"), one per team when known.
  final List<String> abbreviations;
  final DateTime? start;

  const SportsMatchRequest({
    required this.sport,
    required this.title,
    required this.league,
    required this.teams,
    required this.abbreviations,
    required this.start,
  });

  /// Reads a `debrify://sports/...` link, or returns null for anything else.
  static SportsMatchRequest? fromUri(Uri uri) {
    if (uri.scheme != 'debrify' || uri.host != 'sports') return null;
    final q = uri.queryParameters;
    String s(String key) => (q[key] ?? '').trim();
    var sport = s('sport').toLowerCase();
    if (sport == 'wrestling') sport = 'wwe';
    if (sport == 'soccer') sport = 'football';
    final teams = [s('home'), s('away')].where((t) => t.isNotEmpty).toList();
    final abbr = [
      s('homeAbbr'),
      s('awayAbbr'),
    ].where((t) => t.isNotEmpty).toList();
    final ms = int.tryParse(s('start'));
    final title = s('title');
    if (title.isEmpty && teams.isEmpty) return null;
    return SportsMatchRequest(
      sport: sport,
      title: title,
      league: s('league'),
      teams: teams,
      abbreviations: abbr,
      start: ms == null || ms <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  String get heading => title.isNotEmpty ? title : teams.join(' v ');
}

/// One channel that can show the match.
class SportsMatchOption {
  final SportsChannelGroup group;

  /// What the guide says is on at match time, if it names the match.
  final EpgProgramme? programme;

  /// How many of the teams the guide or the channel name mentions (2 = both).
  final int teamHits;

  const SportsMatchOption({
    required this.group,
    this.programme,
    this.teamHits = 0,
  });
}

class SportsMatchResult {
  /// Channels whose guide or name names this match, best first.
  final List<SportsMatchOption> match;

  /// Other channels of the league / sport, best stream first.
  final List<SportsMatchOption> more;

  const SportsMatchResult({required this.match, required this.more});
}

class SportsMatchFinder {
  const SportsMatchFinder._();

  static const _stopWords = <String>{
    'fc', 'cf', 'sc', 'sv', 'ac', 'as', 'afc', 'vfb', 'vfl', 'tsg', 'rb',
    'bsc', 'fsv', 'ssc', 'club', 'city', 'united', 'real', 'sporting',
    'borussia', 'eintracht', 'athletic', 'football', 'calcio', 'deportivo',
    'women', 'woman', 'under', 'team', 'national', 'the', 'and', 'new',
    'west', 'south', 'north', 'east', 'saint', 'santa', 'royal', 'olympique',
    'wwe', 'live', 'match', 'game', 'cricket', 'tennis',
  };

  /// Leagues → words that name their usual channels (DE/UK/IN providers).
  static const _leagueChannels = <String, List<String>>{
    'bundesliga': ['bundesliga', 'sky sport bundesliga', 'sky sport top event', 'dazn', 'sport1'],
    'champions league': ['champions league', 'dazn', 'prime video', 'amazon prime', 'tnt sports', 'sky sport'],
    'europa league': ['europa league', 'rtl', 'dazn', 'tnt sports'],
    'premier league': ['premier league', 'sky sports premier', 'sky sport premier', 'tnt sports'],
    'laliga': ['laliga', 'la liga', 'dazn', 'movistar'],
    'serie a': ['serie a', 'dazn'],
    'ligue 1': ['ligue 1', 'dazn', 'bein'],
    'dfb pokal': ['dfb pokal', 'sky sport', 'ard', 'zdf', 'sport1'],
    'internationals': ['rtl', 'ard', 'zdf', 'magenta', 'dazn', 'sky sport', 'sport1'],
    'nations league': ['ard', 'zdf', 'rtl', 'dazn'],
    'world cup': ['ard', 'zdf', 'magenta', 'telekom', 'dazn'],
    'euro': ['ard', 'zdf', 'magenta', 'telekom'],
  };

  static const _sportChannels = <String, List<String>>{
    'cricket': ['star sports', 'sky sports cricket', 'willow', 'sony ten', 'sony sports', 'jio', 'fox cricket', 'supersport', 'ptv sports', 'a sports'],
    'wwe': ['wwe', 'netflix', 'usa network', 'the cw'],
    'tennis': ['tennis', 'sky sport tennis', 'eurosport'],
  };

  /// Lowercase ASCII words: umlauts and accents folded, "oe" read as "o"
  /// (Moenchengladbach = Mönchengladbach), padded with spaces.
  static String fold(String input) {
    var s = input.toLowerCase();
    const map = {
      'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss', 'é': 'e', 'è': 'e',
      'ê': 'e', 'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'í': 'i',
      'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c', 'ñ': 'n',
      'ø': 'o', 'å': 'a', 'æ': 'ae', 'ł': 'l', 'ı': 'i', 'ş': 's',
      'ğ': 'g', 'č': 'c', 'š': 's', 'ž': 'z', 'ć': 'c', 'ř': 'r',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(map[ch] ?? ch);
    }
    s = b.toString().replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return ' $s ';
  }

  /// The words that identify each team (one list per team).
  static List<List<String>> teamWords(SportsMatchRequest r) {
    final names = r.teams.isNotEmpty ? r.teams : <String>[r.title];
    final out = <List<String>>[];
    for (var i = 0; i < names.length; i++) {
      final words = <String>[];
      for (final w in fold(names[i]).trim().split(' ')) {
        final min = r.sport == 'wwe' ? 3 : 4;
        if (w.length >= min && !_stopWords.contains(w)) words.add(w);
      }
      if (i < r.abbreviations.length) {
        final a = fold(r.abbreviations[i]).trim();
        if (a.length >= 2 && a.length <= 4) words.add(a);
      }
      if (words.isNotEmpty) out.add(words);
    }
    return out;
  }

  /// How many teams [text] mentions. A long word also matches its tail
  /// ("Gladbach" in the guide for "Mönchengladbach").
  static int hits(String text, List<List<String>> teams) {
    final folded = fold(text);
    final words = folded.trim().split(' ');
    var n = 0;
    for (final team in teams) {
      var found = false;
      for (final t in team) {
        if (folded.contains(' $t ')) {
          found = true;
          break;
        }
        if (t.length >= 6) {
          for (final w in words) {
            if (w.length >= 6 && (t.endsWith(w) || w.endsWith(t))) {
              found = true;
              break;
            }
          }
        }
        if (found) break;
      }
      if (found) n++;
    }
    return n;
  }

  static List<String> _channelWords(SportsMatchRequest r) {
    final league = fold(r.league).trim();
    final words = <String>[];
    _leagueChannels.forEach((k, v) {
      if (league.contains(k)) words.addAll(v);
    });
    words.addAll(_sportChannels[r.sport] ?? const <String>[]);
    return words;
  }

  // The scan walks whole playlists: keep it a while, so the next match opens fast.
  static SportsScanResult? _scan;
  static String _scanKey = '';
  static DateTime _scanAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<SportsScanResult> _cachedScan(
    List<SportsSource> sources,
    SportsPrefs prefs,
    bool Function()? cancelled,
  ) async {
    final key = sources.map((s) => s.catalogKey).join('|');
    final fresh = DateTime.now().difference(_scanAt) < const Duration(minutes: 20);
    final cached = _scan;
    if (cached != null && key == _scanKey && fresh) return cached;
    final scan = await SportsService.scan(
      sources: sources,
      preferredRegions: prefs.preferredRegions,
      preferRaw: prefs.preferRaw,
      cancelled: cancelled,
    );
    _scan = scan;
    _scanKey = key;
    _scanAt = DateTime.now();
    return scan;
  }

  static int _byQuality(SportsChannelGroup a, SportsChannelGroup b) {
    final t = b.best.tier.compareTo(a.best.tier);
    if (t != 0) return t;
    return b.best.score.compareTo(a.best.score);
  }

  static Future<SportsMatchResult> find({
    required List<SportsSource> sources,
    required SportsMatchRequest request,
    bool Function()? cancelled,
  }) async {
    final prefs = await SportsPrefsStore.load();
    final teams = teamWords(request);
    final scan = await _cachedScan(sources, prefs, cancelled);

    // 1) Channels named after the match ("EVENT 03: Stuttgart vs Gladbach"),
    //    searched across the whole playlist, not only its sports folders.
    final named = <SportsChannel>[];
    try {
      await IptvCatalogDb.open();
      final searchWords = <String>[
        for (final team in teams)
          for (final w in team)
            if (w.length >= 4) w,
      ].take(6);
      for (final src in sources) {
        if (cancelled?.call() ?? false) break;
        final snap = IptvCatalogDb.snapshot(src.catalogKey);
        if (snap == null) continue;
        for (final w in searchWords) {
          final entries = snap.pageEntries(
            offset: 0,
            limit: 150,
            search: w,
            live: true,
          );
          for (final e in entries) {
            final c = classifySportsChannel(
              channel: e.channel,
              sourceId: src.playlistId,
              sourceName: src.name,
              fromSportsCategory: true,
              preferredRegions: prefs.preferredRegions,
              preferRaw: prefs.preferRaw,
            );
            if (c == null) continue;
            final text = '${e.channel.name} ${e.channel.group ?? ''}';
            if (hits(text, teams) > 0) named.add(c);
          }
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (e) {
      debugPrint('[SportsMatch] name search failed: $e');
    }

    final match = <String, SportsMatchOption>{};
    for (final g in SportsService.group(named)) {
      match[g.key] = SportsMatchOption(
        group: g,
        teamHits: hits(g.displayName, teams),
      );
    }

    // 2) The guide: what the league's, the sport's and the multi-sport
    //    channels show around kick-off.
    final channelWords = _channelWords(request);
    final groups = scan.groups;
    bool namesLeague(SportsChannelGroup g) {
      final n = sportsNormalize(
        '${g.best.channel.name} ${g.best.channel.group ?? ''}',
      );
      return channelWords.any((w) => n.contains(' ${sportsNormalize(w).trim()} '));
    }

    final league = [for (final g in groups) if (namesLeague(g)) g]..sort(_byQuality);
    final sport = [
      for (final g in groups)
        if (request.sport.isNotEmpty && g.sports.contains(request.sport) && !namesLeague(g)) g,
    ]..sort(_byQuality);
    final multi = [for (final g in groups) if (g.isMultiSport && !namesLeague(g)) g];
    final seen = <String>{};
    final guide = <SportsChannelGroup>[
      for (final g in [...league, ...sport, ...multi.take(40)])
        if (seen.add(g.key)) g,
    ].take(90).toList();

    final now = DateTime.now();
    final start = request.start;
    final from = start == null
        ? now.subtract(const Duration(hours: 3))
        : start.subtract(const Duration(minutes: 45));
    final until = start == null
        ? now.add(const Duration(hours: 3))
        : start.add(const Duration(hours: 4));

    Future<void> read(SportsChannelGroup g) async {
      if (match.containsKey(g.key) && match[g.key]!.programme != null) return;
      List<EpgProgramme> schedule = const <EpgProgramme>[];
      for (final v in g.variants.take(2)) {
        try {
          schedule = await IptvEpgService.instance
              .schedule(v.channel.url)
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          schedule = const <EpgProgramme>[];
        }
        if (schedule.isNotEmpty) break;
      }
      EpgProgramme? best;
      var bestHits = 0;
      for (final p in schedule) {
        if (!p.stop.isAfter(from) || p.start.isAfter(until)) continue;
        if (sportsTitleIsOffAir(p.title)) continue;
        final h = hits(p.title, teams);
        if (h > bestHits) {
          best = p;
          bestHits = h;
        }
      }
      if (best != null) {
        final before = match[g.key];
        match[g.key] = SportsMatchOption(
          group: g,
          programme: best,
          teamHits: before == null || before.teamHits < bestHits ? bestHits : before.teamHits,
        );
      }
    }

    const batch = 6;
    for (var i = 0; i < guide.length; i += batch) {
      if (cancelled?.call() ?? false) break;
      await Future.wait(guide.skip(i).take(batch).map(read));
    }

    final matched = match.values.toList()
      ..sort((a, b) {
        final h = b.teamHits.compareTo(a.teamHits);
        if (h != 0) return h;
        // A replay ("Wiederholung", "Highlights") after the live airing.
        final ra = a.programme != null && sportsTitleLooksLikeReplay(a.programme!.title);
        final rb = b.programme != null && sportsTitleLooksLikeReplay(b.programme!.title);
        if (ra != rb) return ra ? 1 : -1;
        return _byQuality(a.group, b.group);
      });
    final taken = {for (final m in matched) m.group.key};
    final more = <SportsMatchOption>[
      for (final g in [...league, ...sport])
        if (!taken.contains(g.key)) SportsMatchOption(group: g),
    ].take(40).toList();
    return SportsMatchResult(match: matched, more: more);
  }
}
