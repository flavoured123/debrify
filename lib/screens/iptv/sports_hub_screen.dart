// Sports Hub — live now, upcoming and best-quality sports channels, built from
// the user's own IPTV playlists and their guide data.
//
// Works with touch, mouse and a TV remote: every interactive element is a
// standard focusable widget, so D-pad navigation needs no special handling.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_sports/sports_catalog.dart';
import '../../services/iptv_sports/sports_match.dart';
import '../../services/iptv_sports/sports_service.dart';
import '../../services/video_player_launcher.dart';
import '../../widgets/iptv/styles/iptv_style.dart';

enum _HubTab { live, upcoming, channels }

class SportsHubScreen extends StatefulWidget {
  final List<IptvPlaylist> playlists;

  const SportsHubScreen({super.key, required this.playlists});

  @override
  State<SportsHubScreen> createState() => _SportsHubScreenState();
}

class _SportsHubScreenState extends State<SportsHubScreen> {
  SportsPrefs _prefs = SportsPrefs.defaults();
  SportsScanResult? _scan;
  List<SportsEvent> _events = const <SportsEvent>[];
  bool _scanning = true;
  bool _loadingEvents = false;
  _HubTab _tab = _HubTab.live;
  String? _sportFilter;

  /// Upcoming tab: show one day only (0 = today … 6). Null = every day.
  int? _dayFilter;
  int _run = 0;
  Timer? _clock;
  late final List<SportsSource> _sources;

  @override
  void initState() {
    super.initState();
    _sources = SportsSource.fromPlaylists(widget.playlists);
    // Keeps "live now" / progress bars honest without re-reading the guide.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _run++;
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SportsPrefsStore.load();
    final lastSport = await SportsPrefsStore.loadLastSport();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      // Reopen on the sport picked last time (Tivideck-style), if it is
      // still switched on.
      _sportFilter = (lastSport != null && prefs.enabledSports.contains(lastSport))
          ? lastSport
          : null;
    });
    await _rescan();
  }

  void _selectSport(String? sportId) {
    setState(() => _sportFilter = sportId);
    unawaited(SportsPrefsStore.saveLastSport(sportId));
  }

  Future<void> _rescan() async {
    final run = ++_run;
    setState(() {
      _scanning = true;
      _events = const <SportsEvent>[];
    });
    final scan = await SportsService.scan(
      sources: _sources,
      preferredRegions: _prefs.preferredRegions,
      preferRaw: _prefs.preferRaw,
      cancelled: () => !mounted || run != _run,
    );
    if (!mounted || run != _run) return;
    setState(() {
      _scan = scan;
      _scanning = false;
    });
    await _reloadEvents();
  }

  List<SportsChannelGroup> get _allGroups =>
      _scan?.groups ?? const <SportsChannelGroup>[];

  /// Channels whose guide is worth reading: dedicated first, then multi-sport.
  List<SportsChannelGroup> get _eventChannels {
    final visible = SportsService.visibleChannels(
      _allGroups,
      _prefs.copyWith(includeMultiSport: true),
    );
    final dedicated = [
      for (final g in visible)
        if (!g.isMultiSport) g,
    ];
    final multi = [
      for (final g in visible)
        if (g.isMultiSport) g,
    ];
    return [...dedicated, ...multi];
  }

  Future<void> _reloadEvents() async {
    final run = ++_run;
    final channels = _eventChannels;
    if (channels.isEmpty) {
      if (mounted) {
        setState(() {
          _events = const <SportsEvent>[];
          _loadingEvents = false;
        });
      }
      return;
    }
    setState(() => _loadingEvents = true);
    final result = await SportsService.loadEvents(
      channels: channels,
      prefs: _prefs,
      maxChannels: 90,
      // A week ahead: the Upcoming tab lets the user pick a day.
      horizon: const Duration(days: 7),
      onProgress: (partial) {
        if (mounted && run == _run) setState(() => _events = partial);
      },
      cancelled: () => !mounted || run != _run,
    );
    if (!mounted || run != _run) return;
    setState(() {
      _events = result;
      _loadingEvents = false;
    });
  }

  Future<void> _applyPrefs(SportsPrefs next) async {
    // Region and RAW preferences change the ranking computed during the
    // scan, so they need a rescan; the rest only filters.
    final regionsChanged =
        !_sameSet(next.preferredRegions, _prefs.preferredRegions) ||
        next.preferRaw != _prefs.preferRaw;
    final eventsAffected =
        regionsChanged ||
        !_sameSet(next.enabledSports, _prefs.enabledSports) ||
        next.minTier != _prefs.minTier;
    setState(() {
      _prefs = next;
      if (_sportFilter != null && !next.enabledSports.contains(_sportFilter)) {
        _sportFilter = null;
      }
    });
    unawaited(SportsPrefsStore.save(next));
    if (regionsChanged) {
      await _rescan();
    } else if (eventsAffected) {
      await _reloadEvents();
    }
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  // ── Playback ────────────────────────────────────────────────────────────

  IptvChannel _withOrigin(SportsChannel sc) {
    final c = sc.channel;
    return IptvChannel(
      channelNumber: c.channelNumber,
      name: c.name,
      url: c.url,
      logoUrl: c.logoUrl,
      group: c.group,
      duration: c.duration,
      contentType: c.contentType,
      attributes: {...c.attributes, 'source_playlist_id': sc.sourceId},
      httpHeaders: c.httpHeaders,
    );
  }

  /// Opens [target] fullscreen. [queue] becomes the in-player channel list,
  /// so channel up/down zaps through the other sports channels.
  Future<void> _play(
    SportsChannel target, {
    List<SportsChannelGroup> queue = const <SportsChannelGroup>[],
  }) async {
    final list = <SportsChannel>[];
    final urls = <String>{};
    for (final g in queue.take(300)) {
      if (urls.add(g.best.channel.url)) list.add(g.best);
    }
    var index = list.indexWhere((c) => c.channel.url == target.channel.url);
    if (index < 0) {
      list.insert(0, target);
      index = 0;
    } else {
      list[index] = target;
    }
    final channels = [for (final c in list) _withOrigin(c)];
    final ch = target.channel;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: ch.url,
        title: ch.name,
        subtitle: ch.group ?? 'Sports',
        channelName: ch.name,
        channelNumber: ch.channelNumber,
        showChannelName: true,
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: channels,
        iptvStartIndex: index,
        iptvContentType: 'live',
        iptvSourceId: target.sourceId,
        iptvSourceName: target.sourceName,
        httpHeaders: ch.playbackHeaders,
      ),
    );
  }

  Future<void> _pickSource(List<SportsChannelGroup> groups, String title) async {
    final options = <SportsChannel>[for (final g in groups) ...g.variants];
    if (options.isEmpty) return;
    final picked = await showModalBottomSheet<SportsChannel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SourceSheet(title: title, options: options),
    );
    if (picked != null && mounted) await _play(picked, queue: groups);
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    final regions = <String>{
      for (final g in _allGroups)
        for (final v in g.variants)
          if (v.region != null) v.region!,
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SettingsSheet(
        initial: _prefs,
        detectedRegions: regions,
        onChanged: _applyPrefs,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final live = _liveEvents(now);
    final upcoming = _upcomingEvents(now);
    final channels = _channelGroups();

    return Theme(
      data: _hubTheme(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: IptvStyleTokens.spotlight.bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, channels.length),
                _sportChips(context),
                _tabBar(
                  context,
                  live.length,
                  upcoming.length,
                  channels.length,
                ),
                if (_tab == _HubTab.upcoming) _dayChips(context, now),
                if (_scanning || _loadingEvents)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _body(context, now, live, upcoming, channels),
                ),
                const _HubKeyHints(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The modern IPTV look (deep navy, light cards) for the whole hub,
  /// whatever the app theme is.
  static ThemeData _hubTheme(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final base = Theme.of(context);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: Brightness.dark,
        ).copyWith(
          surface: t.bg,
          onSurface: t.fg,
          onSurfaceVariant: t.fgDim,
          surfaceContainerHigh: t.panel,
          surfaceContainerHighest: const Color(0xFF13263D),
          primary: t.accent,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF16406F),
          onPrimaryContainer: t.fg,
          secondaryContainer: const Color(0xFF1C3150),
          onSecondaryContainer: t.fg,
          outline: t.hairline2,
          outlineVariant: t.hairline,
        );
    return base.copyWith(
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      iconTheme: IconThemeData(color: t.fg),
      textTheme: base.textTheme.apply(
        bodyColor: t.fg,
        displayColor: t.fg,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.panel,
        selectedColor: t.fg,
        side: BorderSide(color: t.hairline2),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: t.fg, fontWeight: FontWeight.w700),
        secondaryLabelStyle: TextStyle(
          color: t.bg,
          fontWeight: FontWeight.w800,
        ),
        checkmarkColor: t.bg,
      ),
    );
  }

  Widget _header(BuildContext context, int channelCount) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final scan = _scan;
    final subtitle = scan == null
        ? 'Scanning your playlists…'
        : '$channelCount channels · ${scan.sourcesScanned} '
              'source${scan.sourcesScanned == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sports Hub',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _scanning ? null : _rescan,
          ),
          IconButton(
            tooltip: 'Sports settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _sportChips(BuildContext context) {
    final enabled = [
      for (final s in kSportDefs)
        if (_prefs.enabledSports.contains(s.id)) s,
    ];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _sportFilter == null,
              onSelected: (_) => _selectSport(null),
            ),
          ),
          for (final s in enabled)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(s.icon, size: 18),
                label: Text(s.label),
                selected: _sportFilter == s.id,
                onSelected: (_) => _selectSport(s.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar(BuildContext context, int live, int upcoming, int channels) {
    Widget chip(_HubTab tab, String label, int count, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text('$label · $count'),
          selected: _tab == tab,
          onSelected: (_) => setState(() => _tab = tab),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(_HubTab.live, 'Live now', live, Icons.sensors_rounded),
            chip(
              _HubTab.upcoming,
              'Upcoming',
              upcoming,
              Icons.schedule_rounded,
            ),
            chip(
              _HubTab.channels,
              'Channels',
              channels,
              Icons.live_tv_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayChips(BuildContext context, DateTime now) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime(now.year, now.month, now.day);
    String label(int offset) {
      if (offset == 0) return 'Today';
      if (offset == 1) return 'Tomorrow';
      final d = today.add(Duration(days: offset));
      return '${names[d.weekday - 1]} ${d.day}';
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All days'),
              selected: _dayFilter == null,
              onSelected: (_) => setState(() => _dayFilter = null),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label(i)),
                selected: _dayFilter == i,
                onSelected: (_) => setState(() => _dayFilter = i),
              ),
            ),
        ],
      ),
    );
  }

  bool _onSelectedDay(DateTime start, DateTime now) {
    final offset = _dayFilter;
    if (offset == null) return true;
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    return start.year == day.year &&
        start.month == day.month &&
        start.day == day.day;
  }

  // ── Data views ──────────────────────────────────────────────────────────

  bool _eventAllowed(SportsEvent e) {
    if (!_prefs.enabledSports.contains(e.sportId)) return false;
    return _sportFilter == null || e.sportId == _sportFilter;
  }

  List<SportsEvent> _liveEvents(DateTime now) => [
    for (final e in _events)
      if (_eventAllowed(e) && e.isLiveAt(now)) e,
  ];

  List<SportsEvent> _upcomingEvents(DateTime now) => [
    for (final e in _events)
      if (_eventAllowed(e) &&
          e.programme.start.isAfter(now) &&
          _onSelectedDay(e.programme.start, now))
        e,
  ]..sort((a, b) => a.programme.start.compareTo(b.programme.start));

  List<SportsChannelGroup> _channelGroups() {
    final base = SportsService.visibleChannels(
      _allGroups,
      _prefs,
      onlySport: _sportFilter,
    );
    if (_prefs.collapseVariants) return base;
    // Variants unfolded: every HD / FHD / 4K copy gets its own row.
    return [
      for (final g in base)
        for (final v in g.variants)
          SportsChannelGroup(key: '${g.key}|${v.channel.url}', variants: [v]),
    ];
  }

  Widget _body(
    BuildContext context,
    DateTime now,
    List<SportsEvent> live,
    List<SportsEvent> upcoming,
    List<SportsChannelGroup> channels,
  ) {
    final scan = _scan;
    if (_scanning && scan == null) {
      return const _Message(
        icon: Icons.radar_rounded,
        title: 'Finding sports channels…',
        body: 'Looking through your playlists. This only takes a moment.',
      );
    }
    if (scan != null && scan.groups.isEmpty) {
      return _Message(
        icon: Icons.sports_score_rounded,
        title: 'No sports channels found',
        body: scan.sourcesScanned == 0
            ? 'Open Live TV once so your playlist finishes loading, then '
                  'come back here.'
            : 'None of your live channels looked like sports. Check that '
                  'your playlist has sports categories.',
      );
    }
    switch (_tab) {
      case _HubTab.live:
        return _withSoonColumn(
          context,
          now,
          _eventList(context, now, live, upcomingStyle: false),
        );
      case _HubTab.upcoming:
        return _eventList(context, now, upcoming, upcomingStyle: true);
      case _HubTab.channels:
        return _channelList(context, channels);
    }
  }

  /// Wide screens: a "Starting soon" column beside the live cards.
  Widget _withSoonColumn(BuildContext context, DateTime now, Widget main) {
    final soon = [
      for (final e in _events)
        if (_eventAllowed(e) && e.programme.start.isAfter(now)) e,
    ]..sort((a, b) => a.programme.start.compareTo(b.programme.start));
    if (soon.isEmpty) return main;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 1000) return main;
        final t = IptvStyleTokens.spotlight;
        final top = soon.take(8).toList();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: main),
            Container(
              width: 320,
              margin: const EdgeInsets.fromLTRB(0, 4, 12, 12),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Text(
                      'STARTING SOON',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: t.fgFaint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: top.length,
                      itemBuilder: (context, i) {
                        final e = top[i];
                        return _SoonRow(
                          event: e,
                          day: _dayLabel(e.programme.start, now),
                          onPlay: () => _play(e.channel.best, queue: [
                            for (final x in top) x.channel,
                          ]),
                          onSources: () => _pickSource(
                            [e.channel, ...e.alsoOn],
                            e.programme.title,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _eventList(
    BuildContext context,
    DateTime now,
    List<SportsEvent> events, {
    required bool upcomingStyle,
  }) {
    if (events.isEmpty) {
      if (_loadingEvents) {
        return const _Message(
          icon: Icons.event_note_rounded,
          title: 'Reading your TV guide…',
          body: 'Matches appear here as your guide answers.',
        );
      }
      return _Message(
        icon: upcomingStyle
            ? Icons.schedule_rounded
            : Icons.sensors_off_rounded,
        title: upcomingStyle ? 'Nothing coming up' : 'Nothing live right now',
        body: _events.isEmpty
            ? 'Your playlist has no guide (EPG) data for sports channels. '
                  'The Channels tab still lists every sports channel, best '
                  'quality first.'
            : 'Try switching on more sports in settings, or check the '
                  'Channels tab.',
      );
    }
    // "My teams" first, with a star (Tivideck-style follows).
    final mine = <SportsEvent>{
      for (final e in events)
        if (sportsTitleHasTeam(e.programme.title, _prefs.myTeams)) e,
    };
    final others = mine.isEmpty
        ? events
        : [
            for (final e in events)
              if (!mine.contains(e)) e,
          ];
    // Sections: my teams first, then all matches (live) or one per day.
    final sections = <({String? header, List<SportsEvent> events})>[];
    if (mine.isNotEmpty) {
      sections.add((header: '★ My teams', events: mine.toList()));
    }
    if (upcomingStyle) {
      String? day;
      var bucket = <SportsEvent>[];
      for (final e in others) {
        final label = _dayLabel(e.programme.start, now);
        if (label != day) {
          day = label;
          bucket = <SportsEvent>[];
          sections.add((header: label, events: bucket));
        }
        bucket.add(e);
      }
    } else if (others.isNotEmpty) {
      sections.add((
        header: mine.isNotEmpty ? 'All matches' : null,
        events: others.toList(),
      ));
    }
    final queue = [for (final e in events) e.channel];
    var focusGiven = false;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1250
            ? 3
            : c.maxWidth >= 720
            ? 2
            : 1;
        return CustomScrollView(
          slivers: [
            for (final section in sections) ...[
              if (section.header != null)
                SliverToBoxAdapter(child: _DayHeader(section.header!)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisExtent: 178,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final e = section.events[i];
                    final autofocus = !focusGiven && i == 0;
                    if (autofocus) focusGiven = true;
                    return _EventTile(
                      event: e,
                      now: now,
                      mine: mine.contains(e),
                      autofocus: autofocus,
                      onPlay: () => _play(e.channel.best, queue: queue),
                      onSources: () => _pickSource(
                        [e.channel, ...e.alsoOn],
                        e.programme.title,
                      ),
                    );
                  }, childCount: section.events.length),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  Widget _channelList(BuildContext context, List<SportsChannelGroup> groups) {
    if (groups.isEmpty) {
      return const _Message(
        icon: Icons.filter_alt_off_rounded,
        title: 'No channels match your settings',
        body: 'Switch on more sports or lower the minimum quality.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return _ChannelCard(
          group: g,
          autofocus: i == 0,
          onPlay: () => _play(g.best, queue: groups),
          onSources: g.variants.length > 1
              ? () => _pickSource([g], g.displayName)
              : null,
        );
      },
    );
  }

  static String _dayLabel(DateTime d, DateTime now) {
    final a = DateTime.utc(now.year, now.month, now.day);
    final b = DateTime.utc(d.year, d.month, d.day);
    final diff = b.difference(a).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]} ${d.day}/${d.month}';
  }
}

// ── Cards ──────────────────────────────────────────────────────────────────

/// Focusable rounded card with a clear focus ring for TV remotes.
class _HubCard extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final Widget child;

  const _HubCard({
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.autofocus = false,
  });

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _focused ? const Color(0xFF173458) : cs.surfaceContainerHigh,
          borderRadius: radius,
          border: Border.all(
            color: _focused ? cs.onSurface : cs.outlineVariant,
            width: _focused ? 2.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: radius,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onSecondaryTap: widget.onLongPress,
            onFocusChange: (v) {
              setState(() => _focused = v);
              if (v) {
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.4,
                  duration: const Duration(milliseconds: 160),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? url;
  final IconData fallback;
  final double size;
  const _Logo({required this.url, required this.fallback, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Icon(fallback, color: cs.onSurfaceVariant);
    final u = url;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size > 40 ? 6 : 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: (u == null || u.isEmpty)
          ? placeholder
          : CachedNetworkImage(
              imageUrl: u,
              fit: BoxFit.contain,
              memCacheWidth: 104,
              fadeInDuration: Duration.zero,
              errorWidget: (context, url, error) => placeholder,
              placeholder: (context, url) => placeholder,
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  const _Pill(this.text, {this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? cs.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg ?? cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  final SportsChannel channel;
  const _QualityPill(this.channel);

  @override
  Widget build(BuildContext context) {
    final label = channel.qualityLabel;
    if (label.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final strong = channel.strongQuality;
    return _Pill(
      label,
      bg: strong ? cs.primary : cs.secondaryContainer,
      fg: strong ? cs.onPrimary : cs.onSecondaryContainer,
    );
  }
}

IconData _sportIcon(String id) =>
    sportDefById(id)?.icon ?? Icons.sports_rounded;

class _EventCard extends StatelessWidget {
  final SportsEvent event;
  final DateTime now;
  final bool autofocus;

  /// A match of one of the user's teams: drawn with a star.
  final bool mine;
  final VoidCallback onPlay;
  final VoidCallback onSources;

  const _EventCard({
    required this.event,
    required this.now,
    required this.autofocus,
    required this.onPlay,
    required this.onSources,
    this.mine = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = event.programme;
    final live = event.isLiveAt(now);
    final best = event.channel.best;
    final more = event.alsoOn.length;
    final timeText = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(p.start));

    return _HubCard(
      autofocus: autofocus,
      onTap: onPlay,
      onLongPress: onSources,
      child: Row(
        children: [
          _Logo(url: best.channel.logoUrl, fallback: _sportIcon(event.sportId)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (mine) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: Colors.amber.shade400,
                        semanticLabel: 'My team',
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (live && !event.isReplay)
                      _Pill('LIVE', bg: Colors.red.shade600, fg: Colors.white),
                    if (event.isReplay) const _Pill('REPLAY'),
                    if (live || event.isReplay) const SizedBox(width: 6),
                    _QualityPill(best),
                    if (!live) ...[
                      const SizedBox(width: 6),
                      Text(
                        timeText,
                        style: t.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  more > 0
                      ? '${event.channel.displayName}  ·  +$more more '
                            'channel${more == 1 ? '' : 's'}'
                      : event.channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (live) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: p.progressAt(now).clamp(0.0, 1.0).toDouble(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (more > 0 || event.channel.variants.length > 1)
            IconButton(
              tooltip: 'Choose channel / quality',
              icon: const Icon(Icons.layers_rounded),
              onPressed: onSources,
            ),
        ],
      ),
    );
  }
}

/// Live / upcoming match card (modern grid): LIVE + sport + quality on top,
/// the match title, the channel with "+N more", and the progress.
class _EventTile extends StatelessWidget {
  final SportsEvent event;
  final DateTime now;
  final bool autofocus;
  final bool mine;
  final VoidCallback onPlay;
  final VoidCallback onSources;

  const _EventTile({
    required this.event,
    required this.now,
    required this.autofocus,
    required this.onPlay,
    required this.onSources,
    this.mine = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final p = event.programme;
    final live = event.isLiveAt(now);
    final best = event.channel.best;
    final more = event.alsoOn.length + (event.channel.variants.length - 1);
    final sport = sportDefById(event.sportId)?.label ?? 'Sport';
    final start = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(p.start));
    final left = p.stop.difference(now).inMinutes;
    final progress = p.progressAt(now);
    return _HubCard(
      autofocus: autofocus,
      onTap: onPlay,
      onLongPress: onSources,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mine) ...[
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFD60A)),
                const SizedBox(width: 5),
              ],
              if (event.isReplay)
                const _Pill('REPLAY')
              else if (live)
                _Pill('LIVE', bg: t.rec, fg: Colors.white)
              else
                Text(
                  start,
                  style: TextStyle(
                    color: t.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(_sportIcon(event.sportId), size: 14, color: t.fgDim),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  sport.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: t.fgDim,
                  ),
                ),
              ),
              _QualityPill(best),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: t.fg,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _Logo(
                url: best.channel.logoUrl,
                fallback: _sportIcon(event.sportId),
                size: 30,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: t.fgMid),
                ),
              ),
              if (more > 0)
                Text(
                  '+$more more',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: t.fgDim,
                  ),
                ),
            ],
          ),
          if (live) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress),
                      color: t.live,
                      backgroundColor: t.hairline,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  left > 0 ? '$left min left' : 'ending',
                  style: TextStyle(fontSize: 11.5, color: t.fgDim),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the "Starting soon" column.
class _SoonRow extends StatelessWidget {
  final SportsEvent event;
  final String day;
  final VoidCallback onPlay;
  final VoidCallback onSources;

  const _SoonRow({
    required this.event,
    required this.day,
    required this.onPlay,
    required this.onSources,
  });

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final p = event.programme;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(p.start));
    return _HubCard(
      onTap: onPlay,
      onLongPress: onSources,
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: t.accent,
                  ),
                ),
                Text(day, style: TextStyle(fontSize: 11, color: t.fgDim)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.fg,
                  ),
                ),
                Text(
                  event.channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.fgDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What the buttons do" strip at the foot of the hub.
class _HubKeyHints extends StatelessWidget {
  const _HubKeyHints();

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    Widget hint(String key, String label) => Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.hairline2),
            ),
            child: Text(
              key,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: t.fg,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: 11.5, color: t.fgDim)),
        ],
      ),
    );
    return Container(
      height: 34,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            hint('OK / Click', 'Watch in best quality'),
            hint('Hold OK / Right-click', 'Choose stream / quality'),
            hint('▲', 'Change sport'),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final SportsChannelGroup group;
  final bool autofocus;
  final VoidCallback onPlay;
  final VoidCallback? onSources;

  const _ChannelCard({
    required this.group,
    required this.autofocus,
    required this.onPlay,
    required this.onSources,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final best = group.best;
    final firstSport = best.sports.isEmpty ? null : best.sports.first;
    final regionLabel = best.region == null
        ? null
        : kSportsRegionLabels[best.region];
    final variantCount = group.variants.length;
    final sportName = firstSport == null
        ? 'Multi-sport'
        : (sportDefById(firstSport)?.label ?? firstSport);
    final detail = <String>[
      sportName,
      if (regionLabel != null) regionLabel,
      if (variantCount > 1) '$variantCount sources',
    ].join('  ·  ');

    return _HubCard(
      autofocus: autofocus,
      onTap: onPlay,
      onLongPress: onSources,
      child: Row(
        children: [
          _Logo(
            url: best.channel.logoUrl,
            fallback: firstSport == null
                ? Icons.live_tv_rounded
                : _sportIcon(firstSport),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _QualityPill(best),
          if (onSources != null)
            IconButton(
              tooltip: 'Choose quality',
              icon: const Icon(Icons.layers_rounded),
              onPressed: onSources,
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: t.labelLarge?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sheets ─────────────────────────────────────────────────────────────────

/// Lists every stream that can show the same thing, best quality first.
class _SourceSheet extends StatelessWidget {
  final String title;
  final List<SportsChannel> options;
  const _SourceSheet({required this.title, required this.options});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final o = options[i];
                final region = o.region == null
                    ? null
                    : kSportsRegionLabels[o.region];
                final detail = <String>[
                  if (region != null) region,
                  o.sourceName,
                ].join('  ·  ');
                return ListTile(
                  autofocus: i == 0,
                  leading: _QualityPill(o),
                  title: Text(
                    o.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).pop(o),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// "Which sports do I want?" — switches apply immediately.
class _SettingsSheet extends StatefulWidget {
  final SportsPrefs initial;
  final Set<String> detectedRegions;
  final Future<void> Function(SportsPrefs) onChanged;

  const _SettingsSheet({
    required this.initial,
    required this.detectedRegions,
    required this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late SportsPrefs _p = widget.initial;
  final TextEditingController _team = TextEditingController();

  @override
  void dispose() {
    _team.dispose();
    super.dispose();
  }

  void _addTeam() {
    final name = _team.text.trim();
    if (name.isEmpty) return;
    final exists = _p.myTeams.any(
      (t) => t.toLowerCase() == name.toLowerCase(),
    );
    if (!exists) _set(_p.copyWith(myTeams: [..._p.myTeams, name]));
    _team.clear();
  }

  void _set(SportsPrefs next) {
    setState(() => _p = next);
    unawaited(widget.onChanged(next));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final regions = widget.detectedRegions.toList()..sort();
    const tiers = <(int, String)>[
      (0, 'Any'),
      (2, 'HD and up'),
      (3, 'Full HD and up'),
      (4, '4K only'),
    ];

    Widget heading(String text, [String? sub]) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (sub != null)
            Text(
              sub,
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        children: [
          heading(
            'Sports I follow',
            'Only these appear in Live now, Upcoming and Channels.',
          ),
          for (final s in kSportDefs)
            SwitchListTile(
              secondary: Icon(s.icon),
              title: Text(s.label),
              value: _p.enabledSports.contains(s.id),
              onChanged: (on) {
                final next = {..._p.enabledSports};
                if (on) {
                  next.add(s.id);
                } else {
                  next.remove(s.id);
                }
                _set(_p.copyWith(enabledSports: next));
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.live_tv_rounded),
            title: const Text('Multi-sport channels'),
            subtitle: const Text('ESPN, Sky Sports, Star Sports and similar'),
            value: _p.includeMultiSport,
            onChanged: (on) => _set(_p.copyWith(includeMultiSport: on)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality_rounded),
            title: const Text('Prefer RAW streams'),
            subtitle: const Text('RAW, then 4K, FHD, HD — LOW BIT always last'),
            value: _p.preferRaw,
            onChanged: (on) => _set(_p.copyWith(preferRaw: on)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.layers_rounded),
            title: const Text('Group quality copies'),
            subtitle: const Text(
              'One row per channel, best stream first (HD / FHD / 4K inside)',
            ),
            value: _p.collapseVariants,
            onChanged: (on) => _set(_p.copyWith(collapseVariants: on)),
          ),
          heading(
            'Minimum quality',
            'Hide streams below this. Channels without a quality tag in the '
                'name count as unknown and are hidden by any limit above Any.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (tier, label) in tiers)
                  ChoiceChip(
                    label: Text(label),
                    selected: _p.minTier == tier,
                    onSelected: (_) => _set(_p.copyWith(minTier: tier)),
                  ),
              ],
            ),
          ),
          heading(
            'My teams',
            'Matches that mention these names are pinned on top with a star.',
          ),
          if (_p.myTeams.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in _p.myTeams)
                    InputChip(
                      label: Text(team),
                      onDeleted: () => _set(
                        _p.copyWith(
                          myTeams: [
                            for (final x in _p.myTeams)
                              if (x != team) x,
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _team,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Add a team, e.g. Bayern, India, Real Madrid',
                    ),
                    onSubmitted: (_) => _addTeam(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addTeam, child: const Text('Add')),
              ],
            ),
          ),
          if (regions.isNotEmpty) ...[
            heading(
              'Preferred regions',
              'Channels from these regions are ranked first.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final r in regions)
                    FilterChip(
                      label: Text(kSportsRegionLabels[r] ?? r.toUpperCase()),
                      selected: _p.preferredRegions.contains(r),
                      onSelected: (on) {
                        final next = {..._p.preferredRegions};
                        if (on) {
                          next.add(r);
                        } else {
                          next.remove(r);
                        }
                        _set(_p.copyWith(preferredRegions: next));
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Find one match (opened by a debrify://sports link) ──────────────────────

/// The channels showing one match — the ones whose guide or name names it,
/// best stream first — then the other channels of that league or sport.
/// OK plays; holding OK lists every stream of that channel.
class SportsMatchScreen extends StatefulWidget {
  final List<IptvPlaylist> playlists;
  final SportsMatchRequest request;

  const SportsMatchScreen({
    super.key,
    required this.playlists,
    required this.request,
  });

  @override
  State<SportsMatchScreen> createState() => _SportsMatchScreenState();
}

class _SportsMatchScreenState extends State<SportsMatchScreen> {
  SportsMatchResult? _result;
  bool _searching = true;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  Future<void> _find() async {
    setState(() => _searching = true);
    final sources = SportsSource.fromPlaylists(widget.playlists);
    SportsMatchResult result;
    try {
      result = await SportsMatchFinder.find(
        sources: sources,
        request: widget.request,
        cancelled: () => !_alive,
      );
    } catch (e) {
      debugPrint('[SportsMatch] search failed: $e');
      result = const SportsMatchResult(
        match: <SportsMatchOption>[],
        more: <SportsMatchOption>[],
      );
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  List<SportsChannelGroup> get _queue => [
    for (final o in _result?.match ?? const <SportsMatchOption>[]) o.group,
    for (final o in _result?.more ?? const <SportsMatchOption>[]) o.group,
  ];

  IptvChannel _withOrigin(SportsChannel sc) {
    final c = sc.channel;
    return IptvChannel(
      channelNumber: c.channelNumber,
      name: c.name,
      url: c.url,
      logoUrl: c.logoUrl,
      group: c.group,
      duration: c.duration,
      contentType: c.contentType,
      attributes: {...c.attributes, 'source_playlist_id': sc.sourceId},
      httpHeaders: c.httpHeaders,
    );
  }

  Future<void> _play(SportsChannel target) async {
    final list = <SportsChannel>[];
    final urls = <String>{};
    for (final g in _queue.take(300)) {
      if (urls.add(g.best.channel.url)) list.add(g.best);
    }
    var index = list.indexWhere((c) => c.channel.url == target.channel.url);
    if (index < 0) {
      list.insert(0, target);
      index = 0;
    } else {
      list[index] = target;
    }
    final channels = [for (final c in list) _withOrigin(c)];
    final ch = target.channel;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: ch.url,
        title: ch.name,
        subtitle: widget.request.heading,
        channelName: ch.name,
        channelNumber: ch.channelNumber,
        showChannelName: true,
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: channels,
        iptvStartIndex: index,
        iptvContentType: 'live',
        iptvSourceId: target.sourceId,
        iptvSourceName: target.sourceName,
        httpHeaders: ch.playbackHeaders,
      ),
    );
  }

  Future<void> _pickSource(SportsChannelGroup g) async {
    if (g.variants.length < 2) {
      await _play(g.best);
      return;
    }
    final picked = await showModalBottomSheet<SportsChannel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SourceSheet(title: g.displayName, options: g.variants),
    );
    if (picked != null && mounted) await _play(picked);
  }

  String _time(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _SportsHubScreenState._hubTheme(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: IptvStyleTokens.spotlight.bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                if (_searching) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = widget.request;
    final start = r.start;
    final sub = <String>[
      if (r.league.isNotEmpty) r.league,
      if (start != null) _time(start),
      _searching ? 'Searching your channels and guide…' : 'Best stream first',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Icon(_sportIcon(r.sport), color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final result = _result;
    if (result == null) {
      return const _Message(
        icon: Icons.manage_search_rounded,
        title: 'Looking for the match…',
        body: 'Checking the guide and the channel names of your playlists.',
      );
    }
    if (result.match.isEmpty && result.more.isEmpty) {
      return const _Message(
        icon: Icons.search_off_rounded,
        title: 'No channel found',
        body:
            'Neither the guide nor the channel names of your playlists mention '
            'this match, and no channel of this sport was found.',
      );
    }
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget section(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text,
        style: t.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
    var first = true;
    Widget row(SportsMatchOption o, {required bool isMatch}) {
      final g = o.group;
      final best = g.best;
      final p = o.programme;
      final now = DateTime.now();
      final live = p != null && p.airsAt(now);
      final detail = <String>[
        if (p != null) '${_time(p.start)}  ${p.title}',
        best.sourceName,
        if (g.variants.length > 1) '${g.variants.length} streams',
      ].join('  ·  ');
      final autofocus = first;
      first = false;
      return _HubCard(
        autofocus: autofocus,
        onTap: () => _play(best),
        onLongPress: () => _pickSource(g),
        child: Row(
          children: [
            _Logo(url: best.channel.logoUrl, fallback: _sportIcon(widget.request.sport)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (live) ...[
              const _Pill('LIVE', bg: Color(0xFFE53935), fg: Colors.white),
              const SizedBox(width: 6),
            ],
            if (isMatch && o.teamHits >= 2) ...[
              _Pill('MATCH', bg: cs.primaryContainer, fg: cs.onPrimaryContainer),
              const SizedBox(width: 6),
            ],
            _QualityPill(best),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (result.match.isNotEmpty) ...[
          section('SHOWING THIS MATCH'),
          for (final o in result.match) row(o, isMatch: true),
        ] else if (!_searching)
          section('THE GUIDE DOESN\'T NAME THIS MATCH — CHANNELS OF THIS LEAGUE'),
        if (result.more.isNotEmpty) ...[
          if (result.match.isNotEmpty) section('MORE CHANNELS'),
          for (final o in result.more) row(o, isMatch: false),
        ],
      ],
    );
  }
}
