import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart' show isActivateOrSpaceKey;
import '../styles/iptv_style.dart';

/// "List | Guide" pill for Live TV in the modern layout. One focus stop: OK
/// (or a click) flips between the channel list and the timeline guide.
class SpotlightViewToggle extends StatefulWidget {
  const SpotlightViewToggle({
    super.key,
    required this.listMode,
    required this.onChanged,
  });

  final bool listMode;
  final ValueChanged<bool> onChanged;

  @override
  State<SpotlightViewToggle> createState() => _SpotlightViewToggleState();
}

class _SpotlightViewToggleState extends State<SpotlightViewToggle> {
  bool _focused = false;

  void _flip() => widget.onChanged(!widget.listMode);

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    Widget half(String label, IconData icon, bool on) {
      final fg = on ? (t.focusInk ?? t.bg) : t.fgMid;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? (t.focusFill ?? t.fg) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: widget.listMode ? 'Switch to guide view' : 'Switch to list view',
      excludeSemantics: true,
      onTap: _flip,
      child: Focus(
        onFocusChange: (f) {
          if (f != _focused) setState(() => _focused = f);
        },
        onKeyEvent: (_, event) {
          if (isActivateOrSpaceKey(event.logicalKey)) {
            if (event is KeyDownEvent) _flip();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _flip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _focused ? t.fg : t.hairline2,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  half('List', Icons.view_list_rounded, widget.listMode),
                  half('Guide', Icons.calendar_view_day_rounded, !widget.listMode),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
