// Sports Hub — live scores from ESPN's public scoreboard, independent of the
// playlist's guide: every live cricket and football match (with its score)
// even when the provider's EPG doesn't name it. Selecting one opens the match
// finder (SportsMatchScreen), which looks for the channels showing it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'sports_match.dart';

class LiveScore {
  final String id;

  /// Debrify sport id: cricket | football.
  final String sport;
  final String league;
  final String home, away, homeAbbr, awayAbbr;
  final String homeScore, awayScore;

  /// "in" (live), "pre" or "post".
  final String state;

  /// Cricket's state of play ("India need 45 runs from 30 balls") or the
  /// football clock ("67'", "HT").
  final String detail;
  final DateTime? start;

  /// Higher first: India, Bundesliga, the big competitions.
  final int priority;

  const LiveScore({
    required this.id,
    required this.sport,
    required this.league,
    required this.home,
    required this.away,
    required this.homeAbbr,
    required this.awayAbbr,
    required this.homeScore,
    required this.awayScore,
    required this.state,
    required this.detail,
    required this.start,
    required this.priority,
  });

  bool get live => state == 'in';

  SportsMatchRequest toRequest() => SportsMatchRequest(
    sport: sport,
    title: '',
    league: league,
    teams: [home, away],
    abbreviations: [homeAbbr, awayAbbr],
    start: start,
  );
}

class SportsScores {
  const SportsScores._();

  static const _base = 'https://site.api.espn.com/apis/personalized/v2/scoreboard/header';

  /// ESPN football leagues worth listing (others are dropped).
  static const _football = <String, int>{
    'ger.1': 9,
    'uefa.champions': 8,
    'fifa.world': 8,
    'uefa.euro': 8,
    'fifa.worldq.uefa': 7,
    'uefa.nations': 7,
    'fifa.friendly': 6,
    'ger.dfb_pokal': 6,
    'eng.1': 5,
    'esp.1': 5,
    'uefa.europa': 4,
    'ita.1': 3,
    'fra.1': 2,
    'ger.2': 1,
  };

  static List<LiveScore> _cache = const [];
  static DateTime _cacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Live matches first, then today's next ones. Cached for a minute.
  static Future<List<LiveScore>> load({bool force = false}) async {
    if (!force &&
        DateTime.now().difference(_cacheAt) < const Duration(minutes: 1) &&
        _cache.isNotEmpty) {
      return _cache;
    }
    final results = await Future.wait([
      _fetch('cricket', 'in'),
      _fetch('soccer', 'de'),
    ]);
    final all = [...results[0], ...results[1]];
    all.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      return (a.start ?? DateTime(2100)).compareTo(b.start ?? DateTime(2100));
    });
    if (all.isNotEmpty) {
      _cache = all;
      _cacheAt = DateTime.now();
    }
    return all.isEmpty ? _cache : all;
  }

  static Future<List<LiveScore>> _fetch(String sport, String region) async {
    try {
      final res = await http
          .get(Uri.parse('$_base?sport=$sport&region=$region&lang=en'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body);
      final out = <LiveScore>[];
      final seen = <String>{};
      final now = DateTime.now();
      for (final s in (data['sports'] as List? ?? const [])) {
        for (final league in (s['leagues'] as List? ?? const [])) {
          final slug = '${league['slug'] ?? ''}';
          final football = sport == 'soccer';
          final leaguePriority = football ? _football[slug] : 0;
          if (leaguePriority == null) continue;
          final leagueName = '${league['name'] ?? league['abbreviation'] ?? ''}';
          for (final e in (league['events'] as List? ?? const [])) {
            final id = '${e['id']}';
            if (!seen.add(id)) continue;
            final state = '${e['status'] ?? 'pre'}';
            final start = DateTime.tryParse('${e['date'] ?? ''}')?.toLocal();
            if (state == 'post') continue;
            // Only today's (and live) games: ESPN lists a series' next game
            // even when it is days away.
            if (state != 'in' &&
                (start == null || start.difference(now) > const Duration(hours: 18))) {
              continue;
            }
            final comps = (e['competitors'] as List? ?? const []);
            if (comps.length < 2) continue;
            Map c(int i) => comps[i] as Map;
            var homeIndex = 0, awayIndex = 1;
            if (football && '${c(0)['homeAway']}' == 'away') {
              homeIndex = 1;
              awayIndex = 0;
            }
            String name(Map m) => '${m['displayName'] ?? m['name'] ?? ''}';
            String score(Map m) => '${m['score'] ?? ''}';
            final text = '$leagueName ${name(c(0))} ${name(c(1))}'.toLowerCase();
            final cricketPriority = (text.contains('india') ? 10 : 0) +
                (text.contains('icc') || text.contains('world cup') || text.contains('ipl') ? 3 : 0) -
                (text.contains('under-19') || text.contains(' xi') ? 2 : 0) -
                (text.contains('women') ? 1 : 0);
            final summary = '${e['summary'] ?? ''}';
            final clock = '${e['clock'] ?? ''}';
            out.add(
              LiveScore(
                id: id,
                sport: football ? 'football' : 'cricket',
                league: leagueName,
                home: name(c(homeIndex)),
                away: name(c(awayIndex)),
                homeAbbr: '${c(homeIndex)['abbreviation'] ?? ''}',
                awayAbbr: '${c(awayIndex)['abbreviation'] ?? ''}',
                homeScore: score(c(homeIndex)),
                awayScore: score(c(awayIndex)),
                state: state,
                detail: state == 'in'
                    ? (football
                          ? (clock.isNotEmpty && clock != "0'" ? clock : summary)
                          : summary)
                    : '',
                start: start,
                priority: football ? leaguePriority : cricketPriority,
              ),
            );
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('[SportsScores] $sport failed: $e');
      return const [];
    }
  }
}
