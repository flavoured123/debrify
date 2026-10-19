// Movie details from an Xtream panel (get_vod_info): plot, year, rating and
// the YouTube trailer the panel lists for it.
//
// Best effort only: many panels leave these fields empty, and nothing here
// may block playback — every failure simply returns null.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/iptv_playlist.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_collection_resource_facade.dart';

class IptvVodInfo {
  final String? plot;
  final String? year;
  final String? rating;
  final String? genre;
  final String? duration;

  /// 11-character YouTube video id of the trailer, when the panel has one.
  final String? youtubeId;

  const IptvVodInfo({
    this.plot,
    this.year,
    this.rating,
    this.genre,
    this.duration,
    this.youtubeId,
  });

  bool get isEmpty =>
      plot == null &&
      year == null &&
      rating == null &&
      genre == null &&
      duration == null &&
      youtubeId == null;
}

class IptvVodInfoService {
  IptvVodInfoService._();

  static final Map<String, Future<IptvVodInfo?>> _cache = {};
  static const int _maxCached = 120;

  /// The panel's numeric stream id from a movie URL
  /// (`…/movie/<user>/<pass>/<id>.<ext>`), or null for anything else.
  static String? vodIdFromUrl(String url) {
    final m = RegExp(r'/movie/[^/]+/[^/]+/(\d+)(?:\.[A-Za-z0-9]+)?(?:[?#].*)?$')
        .firstMatch(url);
    return m?.group(1);
  }

  /// Plot/trailer for [channel] from [playlist]'s panel. Null when the
  /// playlist is not Xtream, the URL is not a panel movie, or anything fails.
  static Future<IptvVodInfo?> fetch(
    IptvPlaylist playlist,
    IptvChannel channel,
  ) {
    if (!playlist.isXtreamCodes || playlist.credentialsRedacted) {
      return Future.value(null);
    }
    final id = vodIdFromUrl(channel.url);
    if (id == null) return Future.value(null);
    final cacheKey = '${playlist.id}|$id';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final future = _fetch(playlist, id);
    _cache[cacheKey] = future;
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  static Future<IptvVodInfo?> _fetch(IptvPlaylist playlist, String id) async {
    try {
      await ProfileCollectionResourceFacade.authorizeExecution(
        resourceId: playlist.connectionResourceId,
        resourceRevision: playlist.connectionResourceRevision,
        acceptedTypes: const {ConnectionResourceType.iptvXtream},
        feature: ProfileFeature.iptv,
      );
      final user = Uri.encodeQueryComponent(playlist.username ?? '');
      final pass = Uri.encodeQueryComponent(playlist.password ?? '');
      final uri = Uri.parse(
        '${playlist.serverUrl}/player_api.php?username=$user&password=$pass'
        '&action=get_vod_info&vod_id=$id',
      );
      final response = await http
          .get(uri, headers: const {'User-Agent': kIptvDefaultUserAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.length > 512000) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final info = decoded['info'];
      if (info is! Map) return null;

      String? text(Object? value) {
        if (value == null) return null;
        final s = value.toString().trim();
        return s.isEmpty || s == '0' || s.toLowerCase() == 'null' ? null : s;
      }

      final release = text(info['releasedate']) ?? text(info['release_date']);
      final result = IptvVodInfo(
        plot: text(info['plot']) ?? text(info['description']),
        year: text(info['year']) ??
            (release != null && release.length >= 4
                ? release.substring(0, 4)
                : null),
        rating: text(info['rating']),
        genre: text(info['genre']),
        duration: text(info['duration']),
        youtubeId: youtubeIdFrom(
          text(info['youtube_trailer']) ?? text(info['trailer']),
        ),
      );
      return result.isEmpty ? null : result;
    } catch (e) {
      debugPrint('IptvVodInfoService: get_vod_info failed: $e');
      return null;
    }
  }

  /// Accepts a bare id or any common YouTube URL form.
  static String? youtubeIdFrom(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(s)) return s;
    final m = RegExp(
      r'(?:v=|youtu\.be/|embed/|shorts/)([A-Za-z0-9_-]{11})',
    ).firstMatch(s);
    return m?.group(1);
  }
}
