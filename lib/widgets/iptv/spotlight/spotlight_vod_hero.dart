import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/iptv_vod_info_service.dart';
import '../../../utils/iptv_name_tags.dart';
import '../../../utils/iptv_title_match.dart';
import '../styles/iptv_style.dart';

/// Movies / Series hero of the modern IPTV layout: the focused (or hovered)
/// title with its plot, year, genre, rating and quality, Play and Trailer
/// buttons, and the backdrop on the right. Details come from the panel's
/// `get_vod_info` (movies) or the series row's own attributes, loaded with a
/// short delay so arrowing across posters never floods the panel.
class SpotlightVodHero extends StatefulWidget {
  const SpotlightVodHero({
    super.key,
    required this.channel,
    required this.playlist,
    required this.folderLabel,
    required this.onPlay,
    this.onTrailer,
    this.playFocusNode,
  });

  /// The title to describe; null shows a short hint.
  final IptvChannel? channel;
  final IptvPlaylist? playlist;
  final String folderLabel;
  final void Function(IptvChannel channel) onPlay;

  /// Movies only. Receives the panel's YouTube id when it has one.
  final void Function(IptvChannel channel, String? youtubeId)? onTrailer;
  final FocusNode? playFocusNode;

  @override
  State<SpotlightVodHero> createState() => _SpotlightVodHeroState();
}

class _SpotlightVodHeroState extends State<SpotlightVodHero> {
  Timer? _debounce;
  Future<IptvVodInfo?>? _info;
  String? _infoFor;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SpotlightVodHero old) {
    super.didUpdateWidget(old);
    if (old.channel?.url != widget.channel?.url) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool get _isSeries => widget.channel?.contentType == 'series';

  void _schedule() {
    _debounce?.cancel();
    final ch = widget.channel;
    final playlist = widget.playlist;
    if (ch == null ||
        _isSeries ||
        playlist == null ||
        !playlist.isXtreamCodes ||
        IptvVodInfoService.vodIdFromUrl(ch.url) == null) {
      if (_info != null) setState(() => _info = null);
      _infoFor = null;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted || widget.channel?.url != ch.url) return;
      setState(() {
        _infoFor = ch.url;
        _info = IptvVodInfoService.fetch(playlist, ch);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final ch = widget.channel;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.hairline),
      ),
      child: ch == null
          ? Center(
              child: Text(
                'Pick a title to see its details',
                style: TextStyle(color: t.fgDim, fontSize: 13),
              ),
            )
          : FutureBuilder<IptvVodInfo?>(
              future: _infoFor == ch.url ? _info : null,
              builder: (context, snap) => _content(t, ch, snap.data),
            ),
    );
  }

  Widget _content(IptvStyleTokens t, IptvChannel ch, IptvVodInfo? info) {
    final a = ch.attributes;
    final title = iptvStripTags(ch.name).trim();
    final quality = iptvCopyQualityLabel(ch.name);
    String? clean(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty || s == '0' || s == 'null') ? null : s;
    }

    final release = clean(a['releaseDate']) ?? clean(a['releasedate']);
    final year =
        info?.year ??
        clean(a['year']) ??
        ((release != null && release.length >= 4)
            ? release.substring(0, 4)
            : null);
    final genre = info?.genre ?? clean(a['genre']);
    final rating = info?.rating ?? clean(a['rating']);
    final duration = info?.duration;
    final plot = info?.plot ?? clean(a['plot']);
    final art =
        info?.backdropUrl ??
        clean(a['backdrop']) ??
        info?.coverUrl ??
        ch.logoUrl;

    final meta = <String>[
      if (year != null) year,
      if (duration != null && iptvNiceDuration(duration).isNotEmpty)
        iptvNiceDuration(duration),
      if (genre != null) genre,
    ];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.folderLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: t.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title.isEmpty ? ch.name : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (meta.isNotEmpty)
                      Text(
                        meta.join('  ·  '),
                        style: TextStyle(fontSize: 12.5, color: t.fgMid),
                      ),
                    if (quality.isNotEmpty) _badge(t, quality),
                    if (rating != null)
                      Text(
                        '★ $rating',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFD60A),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    plot ?? '',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: t.fgMid,
                    ),
                  ),
                ),
                Row(
                  children: [
                    FilledButton.icon(
                      focusNode: widget.playFocusNode,
                      style: FilledButton.styleFrom(
                        backgroundColor: t.fg,
                        foregroundColor: t.bg,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      onPressed: () => widget.onPlay(ch),
                      icon: Icon(
                        _isSeries
                            ? Icons.video_library_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        _isSeries ? 'Episodes' : 'Play',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!_isSeries && widget.onTrailer != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.fg,
                          side: BorderSide(color: t.hairline2),
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: () =>
                            widget.onTrailer!(ch, info?.youtubeId),
                        icon: const Icon(Icons.movie_filter_outlined),
                        label: const Text('Trailer'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: t.bg),
                  if (art != null && art.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: art,
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      fadeInDuration: const Duration(milliseconds: 180),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                      placeholder: (_, _) => const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IptvStyleTokens t, String label) {
    final strong = label == '4K' || label == 'RAW';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? t.accent : const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
