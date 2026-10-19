import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/iptv_name_tags.dart';
import '../../../utils/tv_keys.dart' show TvHoldOk, isActivateOrSpaceKey;
import '../styles/iptv_style.dart';

/// Lets the page move DPAD focus into the sidebar (e.g. LEFT from the guide).
class SpotlightFolderSidebarController {
  _SpotlightFolderSidebarState? _state;

  /// Focuses the selected folder (or the first entry). False when the
  /// sidebar is not mounted or has nothing focusable.
  bool focusSelected() => _state?._focusSelected() ?? false;
}

/// The always-visible folder column of the modern IPTV layout.
///
/// Replaces "open a dialog, scroll a huge list, pick, close" with a list that
/// is always on screen: country chips on top (built from "DE|", "IN:" style
/// folder prefixes), pinned folders, then every folder with its count.
/// OK opens a folder and keeps focus here, so folders can be browsed while
/// the guide on the right follows. RIGHT enters the channels, LEFT goes to
/// the sources rail, HOLD OK (or long press / right click) opens the folder
/// menu (pin, default, hide).
class SpotlightFolderSidebar extends StatefulWidget {
  const SpotlightFolderSidebar({
    super.key,
    required this.categories,
    required this.counts,
    required this.selected,
    required this.allCount,
    required this.pinned,
    required this.onSelect,
    required this.onExitRight,
    required this.onExitLeft,
    this.onOptions,
    this.onSearch,
    this.onExitUp,
    this.controller,
    this.allLabel = 'All channels',
  });

  /// Folder names in display order (already without hidden folders).
  final List<String> categories;
  final Map<String, int> counts;

  /// The open folder; null = all channels.
  final String? selected;
  final int allCount;
  final Set<String> pinned;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String>? onOptions;
  final VoidCallback? onSearch;
  final VoidCallback onExitRight;
  final VoidCallback onExitLeft;
  final VoidCallback? onExitUp;
  final SpotlightFolderSidebarController? controller;
  final String allLabel;

  @override
  State<SpotlightFolderSidebar> createState() => _SpotlightFolderSidebarState();
}

/// One row of the list: a section header or a folder (null name = "All").
class _Entry {
  const _Entry.header(this.label) : folder = null, isHeader = true, isAll = false;
  const _Entry.all(this.label) : folder = null, isHeader = false, isAll = true;
  const _Entry.folder(String name)
    : folder = name,
      label = name,
      isHeader = false,
      isAll = false;

  final String? folder;
  final String label;
  final bool isHeader;
  final bool isAll;
}

class _SpotlightFolderSidebarState extends State<SpotlightFolderSidebar> {
  static const double _rowExtent = 42;
  static const double _headerExtent = 30;
  static const int _maxCountryChips = 7;

  final ScrollController _scroll = ScrollController();
  final FocusNode _searchNode = FocusNode(debugLabel: 'folder-sidebar-search');
  final Map<int, FocusNode> _rowNodes = {};
  final Map<int, FocusNode> _chipNodes = {};
  final Map<int, TvHoldOk> _holds = {};

  /// Country filter for the list ('' = all countries). Session only.
  String _country = '';

  List<String> _chips = const [];
  List<_Entry> _entries = const [];

  /// Indices into [_entries] that can take focus (everything but headers).
  List<int> _focusable = const [];

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _rebuildModel();
  }

  @override
  void didUpdateWidget(SpotlightFolderSidebar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
    if (!identical(old.categories, widget.categories) ||
        old.categories.length != widget.categories.length ||
        !_sameSet(old.pinned, widget.pinned) ||
        old.allLabel != widget.allLabel) {
      _rebuildModel();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    _scroll.dispose();
    _searchNode.dispose();
    for (final n in _rowNodes.values) {
      n.dispose();
    }
    for (final n in _chipNodes.values) {
      n.dispose();
    }
    for (final h in _holds.values) {
      h.reset();
    }
    super.dispose();
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _rebuildModel() {
    // Country chips: the most common folder prefixes, biggest first.
    final perCountry = <String, int>{};
    for (final c in widget.categories) {
      final code = iptvFolderCountryCode(c);
      if (code != null) perCountry[code] = (perCountry[code] ?? 0) + 1;
    }
    final codes = perCountry.keys.toList()
      ..sort((a, b) => perCountry[b]!.compareTo(perCountry[a]!));
    _chips = perCountry.length >= 2
        ? codes.take(_maxCountryChips).toList(growable: false)
        : const [];
    if (_country.isNotEmpty && !_chips.contains(_country)) _country = '';

    final pinned = [
      for (final c in widget.categories)
        if (widget.pinned.contains(c)) c,
    ];
    final rest = [
      for (final c in widget.categories)
        if (!widget.pinned.contains(c) &&
            (_country.isEmpty || iptvFolderCountryCode(c) == _country))
          c,
    ];

    final entries = <_Entry>[_Entry.all(widget.allLabel)];
    if (pinned.isNotEmpty) {
      entries.add(const _Entry.header('PINNED'));
      entries.addAll(pinned.map(_Entry.folder));
    }
    entries.add(
      _Entry.header(
        _country.isEmpty
            ? 'ALL FOLDERS · ${rest.length}'
            : 'FOLDERS · $_country · ${rest.length}',
      ),
    );
    entries.addAll(rest.map(_Entry.folder));
    _entries = entries;
    _focusable = [
      for (var i = 0; i < entries.length; i++)
        if (!entries[i].isHeader) i,
    ];
  }

  FocusNode _rowNode(int entryIndex) => _rowNodes.putIfAbsent(
    entryIndex,
    () => FocusNode(debugLabel: 'folder-row-$entryIndex'),
  );

  FocusNode _chipNode(int i) =>
      _chipNodes.putIfAbsent(i, () => FocusNode(debugLabel: 'folder-chip-$i'));

  TvHoldOk _hold(int entryIndex) => _holds.putIfAbsent(entryIndex, () {
    return TvHoldOk(
      onTap: () => _activate(entryIndex),
      onHold: () => _options(entryIndex),
    );
  });

  double _offsetOf(int entryIndex) {
    var y = 0.0;
    for (var i = 0; i < entryIndex && i < _entries.length; i++) {
      y += _entries[i].isHeader ? _headerExtent : _rowExtent;
    }
    return y;
  }

  /// Scrolls [entryIndex] into view (building it if needed), then focuses it.
  void _focusEntry(int entryIndex) {
    if (entryIndex < 0 || entryIndex >= _entries.length) return;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      final top = _offsetOf(entryIndex);
      final bottom = top + _rowExtent;
      var target = pos.pixels;
      // Keep a row of context above/below the focused folder.
      if (top - _rowExtent < pos.pixels) {
        target = top - _rowExtent;
      } else if (bottom + _rowExtent > pos.pixels + pos.viewportDimension) {
        target = bottom + _rowExtent - pos.viewportDimension;
      }
      target = math.max(0.0, math.min(target, pos.maxScrollExtent));
      if (target != pos.pixels) _scroll.jumpTo(target);
    }
    final node = _rowNode(entryIndex);
    if (node.context != null) {
      node.requestFocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });
    }
  }

  int get _selectedEntryIndex {
    final sel = widget.selected;
    for (final i in _focusable) {
      final e = _entries[i];
      if (sel == null ? e.isAll : e.folder == sel) return i;
    }
    return _focusable.isEmpty ? -1 : _focusable.first;
  }

  bool _focusSelected() {
    if (!mounted || _focusable.isEmpty) return false;
    _focusEntry(_selectedEntryIndex);
    return true;
  }

  void _activate(int entryIndex) {
    final e = _entries[entryIndex];
    widget.onSelect(e.isAll ? null : e.folder);
  }

  void _options(int entryIndex) {
    final folder = _entries[entryIndex].folder;
    if (folder != null) widget.onOptions?.call(folder);
  }

  void _focusChipsOrSearch() {
    if (_chips.isNotEmpty) {
      final i = _country.isEmpty ? 0 : _chips.indexOf(_country) + 1;
      _chipNode(i < 0 ? 0 : i).requestFocus();
    } else if (widget.onSearch != null) {
      _searchNode.requestFocus();
    } else {
      widget.onExitUp?.call();
    }
  }

  KeyEventResult _onRowKey(int entryIndex, KeyEvent event) {
    final key = event.logicalKey;
    if (isActivateOrSpaceKey(key)) return _hold(entryIndex).handle(event);
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      _options(entryIndex);
      return KeyEventResult.handled;
    }
    final pos = _focusable.indexOf(entryIndex);
    if (key == LogicalKeyboardKey.arrowDown) {
      if (pos >= 0 && pos + 1 < _focusable.length) {
        _focusEntry(_focusable[pos + 1]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (pos > 0) {
        _focusEntry(_focusable[pos - 1]);
      } else {
        _focusChipsOrSearch();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      final next = math.min(pos + 8, _focusable.length - 1);
      _focusEntry(_focusable[next]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      final prev = math.max(pos - 8, 0);
      _focusEntry(_focusable[prev]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onExitRight();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onExitLeft();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _pickCountry(String code) {
    setState(() {
      _country = code;
      _rebuildModel();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  KeyEventResult _onChipKey(int chipIndex, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final count = _chips.length + 1; // "All" + codes
    if (key == LogicalKeyboardKey.arrowRight) {
      if (chipIndex + 1 < count) {
        _chipNode(chipIndex + 1).requestFocus();
      } else {
        widget.onExitRight();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (chipIndex > 0) {
        _chipNode(chipIndex - 1).requestFocus();
      } else {
        widget.onExitLeft();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_focusable.isNotEmpty) _focusEntry(_focusable.first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onSearch != null) {
        _searchNode.requestFocus();
      } else {
        widget.onExitUp?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSearchKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_chips.isNotEmpty) {
        _focusChipsOrSearch();
      } else if (_focusable.isNotEmpty) {
        _focusEntry(_focusable.first);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onExitUp?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onExitLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onExitRight();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onSearch != null) _searchButton(t),
            if (_chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              _countryChips(t),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: _entries.length,
                // Rows must exist for DPAD focus a little beyond the edge.
                cacheExtent: 400,
                itemBuilder: (context, i) {
                  final e = _entries[i];
                  if (e.isHeader) return _header(t, e.label);
                  return _row(t, i, e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchButton(IptvStyleTokens t) {
    return Focus(
      focusNode: _searchNode,
      onKeyEvent: (_, e) {
        if (isActivateOrSpaceKey(e.logicalKey)) {
          if (e is KeyUpEvent) widget.onSearch?.call();
          return KeyEventResult.handled;
        }
        return _onSearchKey(e);
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: widget.onSearch,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: focused ? t.focusFill : t.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: focused ? t.fg : t.hairline2),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: focused ? t.focusInk : t.fgDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search ${widget.categories.length} folders…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: focused ? t.focusInk : t.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _countryChips(IptvStyleTokens t) {
    final labels = ['All', ..._chips];
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final code = i == 0 ? '' : labels[i];
          final on = _country == code;
          return Focus(
            focusNode: _chipNode(i),
            onKeyEvent: (_, e) {
              if (isActivateOrSpaceKey(e.logicalKey)) {
                if (e is KeyUpEvent) _pickCountry(code);
                return KeyEventResult.handled;
              }
              return _onChipKey(i, e);
            },
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                final bg = focused
                    ? t.focusFill
                    : on
                    ? t.selectedTint
                    : Colors.transparent;
                final fg = focused
                    ? t.focusInk
                    : on
                    ? t.fg
                    : t.fgMid;
                return GestureDetector(
                  onTap: () => _pickCountry(code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on || focused ? Colors.transparent : t.hairline2,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _header(IptvStyleTokens t, String label) {
    return SizedBox(
      height: _headerExtent,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: t.fgFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IptvStyleTokens t, int entryIndex, _Entry e) {
    final selected = e.isAll
        ? widget.selected == null
        : e.folder == widget.selected;
    final count = e.isAll ? widget.allCount : (widget.counts[e.folder] ?? 0);
    final pinned = e.folder != null && widget.pinned.contains(e.folder);
    final name = e.isAll ? e.label : iptvStripTags(e.label).trim();
    return SizedBox(
      height: _rowExtent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Focus(
          focusNode: _rowNode(entryIndex),
          onFocusChange: (has) {
            if (!has) _holds[entryIndex]?.reset();
            setState(() {});
          },
          onKeyEvent: (_, event) => _onRowKey(entryIndex, event),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              final bg = focused
                  ? t.focusFill
                  : selected
                  ? t.selectedTint
                  : Colors.transparent;
              final fg = focused ? t.focusInk : (selected ? t.fg : t.fgMid);
              final dim = focused ? t.focusInk : t.fgFaint;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _activate(entryIndex),
                onLongPress: e.folder == null ? null : () => _options(entryIndex),
                onSecondaryTap: e.folder == null
                    ? null
                    : () => _options(entryIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (e.isAll)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.apps_rounded, size: 16, color: fg),
                        )
                      else if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.push_pin_rounded, size: 14, color: fg),
                        )
                      else if (selected && !focused)
                        Container(
                          width: 3,
                          height: 18,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: t.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          name.isEmpty ? e.label : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected || focused
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: fg,
                          ),
                        ),
                      ),
                      if (count > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: dim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
