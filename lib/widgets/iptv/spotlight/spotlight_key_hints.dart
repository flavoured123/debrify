import 'package:flutter/material.dart';

import '../styles/iptv_style.dart';

/// The thin "what do the buttons do" strip at the foot of the modern IPTV
/// layout. Remote wording on TV, mouse wording on desktop.
class SpotlightKeyHints extends StatelessWidget {
  const SpotlightKeyHints({
    super.key,
    required this.isTelevision,
    required this.contentType,
  });

  final bool isTelevision;

  /// 'live', 'vod' or 'series'.
  final String contentType;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final live = contentType == 'live';
    final hints = isTelevision
        ? <(String, String)>[
            ('OK', live ? 'Preview · OK again = full screen' : 'Open'),
            ('◀', 'Folders'),
            ('HOLD OK', live ? 'Menu: hide, favourite' : 'Menu: add to list'),
            ('BACK', 'Back'),
          ]
        : <(String, String)>[
            ('Click', live ? 'Watch' : 'Open'),
            ('Right-click', live ? 'Menu: hide, favourite' : 'Menu'),
            ('Folders', 'Left column · right-click to pin'),
          ];
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: ClipRect(
        child: Row(
          children: [
            for (final (button, label) in hints) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: t.hairline2),
                ),
                child: Text(
                  button,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.fg,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.fgDim),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ],
        ),
      ),
    );
  }
}
