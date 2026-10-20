import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/iptv_playlist.dart';
import '../../../utils/iptv_title_match.dart';
import '../../../utils/tv_keys.dart' show TvHoldOk, isActivateOrSpaceKey;
import '../styles/iptv_style.dart';

/// Poster-card tile for Movies / Series in the modern IPTV layout: a real
/// 2:3 poster, a quality badge, a resume bar and one line of title, with a
/// bright focus ring for the remote. OK plays (via the copies sheet the page
/// already shows), HOLD OK / long press opens [onHold].
class SpotlightPosterCard extends StatefulWidget {
  const SpotlightPosterCard({
    super.key,
    required this.channel,
    required this.focusNode,
    required this.onTap,
    this.onHold,
    this.onFocused,
    this.onHover,
    this.onDetached,
    this.progress,
    this.isFavorited = false,
  });

  final IptvChannel channel;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final VoidCallback? onFocused;

  /// Mouse resting on the card (desktop): updates the hero like focus does.
  final VoidCallback? onHover;
  final VoidCallback? onDetached;

  /// Watched fraction 0..1, if any.
  final double? progress;
  final bool isFavorited;

  @override
  State<SpotlightPosterCard> createState() => _SpotlightPosterCardState();
}

class _SpotlightPosterCardState extends State<SpotlightPosterCard> {
  late final TvHoldOk _hold = TvHoldOk(
    onTap: () => widget.onTap(),
    onHold: () => (widget.onHold ?? widget.onTap)(),
  );
  bool _focused = false;

  @override
  void dispose() {
    _hold.reset();
    widget.onDetached?.call();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (!focused) _hold.reset();
    setState(() => _focused = focused);
    if (focused) {
      widget.onFocused?.call();
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (isActivateOrSpaceKey(event.logicalKey)) return _hold.handle(event);
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.contextMenu &&
        widget.onHold != null) {
      widget.onHold!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final ch = widget.channel;
    final title = iptvDisplayTitle(ch.name);
    final quality = iptvCopyQualityLabel(ch.name);
    final logo = ch.logoUrl;
    final progress = widget.progress;
    final hasProgress = progress != null && progress > 0.01 && progress < 0.98;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => widget.onHover?.call(),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onHold,
        onSecondaryTap: widget.onHold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedScale(
                scale: _focused ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _focused ? t.fg : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: _focused
                        ? const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _placeholder(t, title),
                        if (logo != null && logo.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: logo,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                            placeholder: (_, _) => const SizedBox.shrink(),
                          ),
                        if (quality.isNotEmpty)
                          Positioned(
                            top: 7,
                            left: 7,
                            child: _badge(
                              quality,
                              strong: quality == '4K' || quality == 'RAW',
                              t: t,
                            ),
                          ),
                        if (widget.isFavorited)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: Color(0xFFFFD60A),
                            ),
                          ),
                        if (hasProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 4,
                              color: const Color(0x40FFFFFF),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(color: t.accent),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title.isEmpty ? ch.name : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
                color: _focused ? t.fg : t.fgDim,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _placeholder(IptvStyleTokens t, String title) {
    // A tinted card with the title, so missing artwork still reads.
    const tints = [
      Color(0xFF1E3A5F),
      Color(0xFF3B2A55),
      Color(0xFF4A2C2A),
      Color(0xFF173F3A),
      Color(0xFF3D3A1E),
      Color(0xFF2A2F4F),
      Color(0xFF43223A),
    ];
    final tint = tints[title.hashCode.abs() % tints.length];
    return Container(
      color: tint,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xCCFFFFFF),
        ),
      ),
    );
  }

  Widget _badge(String label, {required bool strong, required IptvStyleTokens t}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? t.accent : const Color(0xBF06111E),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}
