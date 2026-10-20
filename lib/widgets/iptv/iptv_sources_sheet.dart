// "Which copy?" — shown when a movie or series exists in several provider
// folders (Netflix 4K, 4K Movies, Netflix Multi, India Hindi …). Copies are
// listed best quality first; the dialog also shows the movie's plot and a
// Trailer button when the provider has them.

import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_vod_info_service.dart';
import '../../services/tmdb_metadata_repository.dart';
import '../../utils/iptv_title_match.dart';
import '../../utils/tv_keys.dart' show TvHeldKeyGuard;
import 'styles/iptv_style.dart';

enum IptvSourceAction { play, trailer }

class IptvSourceChoice {
  final IptvSourceAction action;
  final IptvChannel channel;

  /// Panel YouTube id for [IptvSourceAction.trailer], when it has one (the
  /// caller falls back to TMDB / IMDb otherwise).
  final String? youtubeId;

  const IptvSourceChoice.play(this.channel)
    : action = IptvSourceAction.play,
      youtubeId = null;

  const IptvSourceChoice.trailer(this.channel, this.youtubeId)
    : action = IptvSourceAction.trailer;
}

/// [sources] must already be ordered best first. Returns null when dismissed.
Future<IptvSourceChoice?> showIptvSourcesSheet({
  required BuildContext context,
  required String title,
  required List<IptvChannel> sources,
  Future<IptvVodInfo?>? info,
  bool isSeries = false,
}) {
  return showDialog<IptvSourceChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => _IptvSourcesDialog(
      title: title,
      sources: sources,
      info: info,
      isSeries: isSeries,
    ),
  );
}

class _IptvSourcesDialog extends StatelessWidget {
  final String title;
  final List<IptvChannel> sources;
  final Future<IptvVodInfo?>? info;
  final bool isSeries;

  const _IptvSourcesDialog({
    required this.title,
    required this.sources,
    required this.info,
    required this.isSeries,
  });

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final size = MediaQuery.sizeOf(context);
    final folders = {
      for (final s in sources)
        if ((s.group ?? '').isNotEmpty) s.group!,
    };
    final best = sources.first;

    return TvHeldKeyGuard(
      child: Dialog(
        backgroundColor: t.panel,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: t.hairline2),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: size.height - 40 < 680 ? size.height - 40 : 680,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.fg,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                    CloseButton(onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                if (info != null)
                  FutureBuilder<IptvVodInfo?>(
                    future: info,
                    builder: (context, snap) {
                      final data = snap.data;
                      if (data == null) {
                        return snap.connectionState == ConnectionState.waiting
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Loading details…',
                                  style: TextStyle(color: t.fgFaint),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final meta = <String>[
                        if (data.year != null) data.year!,
                        if (data.genre != null) data.genre!,
                        if (data.duration != null) data.duration!,
                        if (data.rating != null) '★ ${data.rating}',
                      ].join('  ·  ');
                      return Padding(
                        padding: const EdgeInsets.only(top: 6, right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.fgDim, fontSize: 13),
                              ),
                            if (data.plot != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data.plot!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.fgMid,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      autofocus: true,
                      style: FilledButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(IptvSourceChoice.play(best)),
                      icon: Icon(
                        isSeries
                            ? Icons.video_library_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        isSeries ? 'Open best copy' : 'Play best copy',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (info != null)
                      FutureBuilder<IptvVodInfo?>(
                        future: info,
                        builder: (context, snap) {
                          final id = snap.data?.youtubeId;
                          // Without a panel trailer the caller can still
                          // find one through TMDB / IMDb.
                          if (id == null &&
                              !TmdbMetadataRepository.instance.configured) {
                            return const SizedBox.shrink();
                          }
                          return OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.fg,
                              side: BorderSide(color: t.hairline2),
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                            ),
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(IptvSourceChoice.trailer(best, id)),
                            icon: const Icon(Icons.movie_filter_outlined),
                            label: const Text('Trailer'),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  sources.length == 1
                      ? '1 copy'
                      : '${sources.length} copies in ${folders.length} '
                            'folder${folders.length == 1 ? '' : 's'} · best first',
                  style: TextStyle(
                    color: t.fgDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    itemBuilder: (context, i) {
                      final s = sources[i];
                      final label = iptvCopyQualityLabel(s.name);
                      final strong =
                          label == '4K' || label == 'FHD' || label == 'RAW';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Container(
                          width: 50,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: strong
                                ? t.accent
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label.isEmpty ? '—' : label,
                            style: TextStyle(
                              color: strong ? Colors.white : t.fgMid,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: (s.group ?? '').isEmpty
                            ? null
                            : Text(
                                s.group!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.fgDim, fontSize: 12),
                              ),
                        trailing: i == 0
                            ? Text(
                                'Best',
                                style: TextStyle(
                                  color: t.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(IptvSourceChoice.play(s)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
