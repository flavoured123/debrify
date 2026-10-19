// Sports Hub — pure data layer.
//
// Everything here is plain Dart (no widgets besides IconData) so the matching
// rules can be unit-tested without a device: which sport a channel/programme
// belongs to, how good its stream quality looks, and which variants of the
// same channel should be collapsed together.

import 'package:flutter/material.dart' show IconData, Icons;

import '../../models/iptv_playlist.dart';
import '../../utils/iptv_name_tags.dart';

/// One sport the user can switch on or off in Sports Hub settings.
class SportDef {
  final String id;
  final String label;
  final IconData icon;

  /// Words that identify a DEDICATED channel for this sport (matched against
  /// the normalised channel name + category). e.g. "willow" → cricket.
  final List<String> channelWords;

  /// Words that identify a PROGRAMME of this sport on any channel, including
  /// multi-sport ones. e.g. "ipl" in "LIVE: IPL - CSK vs MI".
  final List<String> programmeWords;

  /// Whether the sport is switched on the first time the hub opens.
  final bool defaultOn;

  const SportDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.channelWords,
    required this.programmeWords,
    this.defaultOn = false,
  });
}

const List<SportDef> kSportDefs = [
  SportDef(
    id: 'cricket',
    label: 'Cricket',
    icon: Icons.sports_cricket_rounded,
    defaultOn: true,
    channelWords: [
      'cricket',
      'willow',
      'ipl',
      'bbl',
      'psl',
      'icc',
      't20',
      'sky sports cricket',
      'fox cricket',
    ],
    programmeWords: [
      'cricket',
      'ipl',
      't20',
      't20i',
      'odi',
      'test match',
      'bbl',
      'psl',
      'icc',
      'ashes',
      'asia cup',
      'ranji',
      'the hundred',
      'cpl',
      'sa20',
      'wpl',
    ],
  ),
  SportDef(
    id: 'football',
    label: 'Football',
    icon: Icons.sports_soccer_rounded,
    defaultOn: true,
    channelWords: [
      'football',
      'soccer',
      'premier league',
      'epl',
      'la liga',
      'laliga',
      'bundesliga',
      'serie a',
      'ligue 1',
      'champions league',
      'uefa',
      'sky sports football',
      'sky sports premier league',
      'mls',
      'bundesliga',
      'liga',
    ],
    programmeWords: [
      'football',
      'soccer',
      'premier league',
      'epl',
      'la liga',
      'laliga',
      'bundesliga',
      'serie a',
      'ligue 1',
      'champions league',
      'europa league',
      'conference league',
      'uefa',
      'fifa',
      'fa cup',
      'efl',
      'carabao',
      'copa',
      'mls',
      'isl',
      'world cup qualifier',
      'saudi pro league',
      'eredivisie',
      'bundesliga',
      'dfb pokal',
      'konferenz',
    ],
  ),
  SportDef(
    id: 'wwe',
    label: 'WWE / Wrestling',
    icon: Icons.sports_kabaddi_rounded,
    defaultOn: true,
    channelWords: ['wwe', 'aew', 'wrestling', 'tna', 'nxt'],
    programmeWords: [
      'wwe',
      'aew',
      'wrestling',
      'smackdown',
      'nxt',
      'raw is war',
      'wwe raw',
      'monday night raw',
      'wrestlemania',
      'royal rumble',
      'summerslam',
      'survivor series',
      'money in the bank',
      'tna',
    ],
  ),
  SportDef(
    id: 'tennis',
    label: 'Tennis',
    icon: Icons.sports_tennis_rounded,
    defaultOn: true,
    channelWords: ['tennis', 'atp', 'wta', 'sky sports tennis'],
    programmeWords: [
      'tennis',
      'atp',
      'wta',
      'wimbledon',
      'roland garros',
      'french open',
      'us open',
      'australian open',
      'davis cup',
      'masters 1000',
    ],
  ),
  SportDef(
    id: 'basketball',
    label: 'Basketball',
    icon: Icons.sports_basketball_rounded,
    defaultOn: true,
    channelWords: ['nba', 'basketball', 'euroleague', 'nba tv'],
    programmeWords: ['nba', 'basketball', 'euroleague', 'wnba', 'ncaa men'],
  ),
  SportDef(
    id: 'motorsport',
    label: 'F1 / Motorsport',
    icon: Icons.sports_motorsports_rounded,
    defaultOn: true,
    channelWords: [
      'f1',
      'formula 1',
      'formula one',
      'motogp',
      'motorsport',
      'nascar',
      'indycar',
      'sky sports f1',
    ],
    programmeWords: [
      'f1',
      'formula 1',
      'formula one',
      'grand prix',
      'motogp',
      'moto2',
      'moto3',
      'nascar',
      'indycar',
      'wrc',
      'rally',
      'qualifying',
      'practice 1',
      'practice 2',
      'practice 3',
      'sprint race',
    ],
  ),
  SportDef(
    id: 'combat',
    label: 'UFC / MMA / Boxing',
    icon: Icons.sports_mma_rounded,
    defaultOn: true,
    channelWords: ['ufc', 'mma', 'boxing', 'fight', 'bellator', 'dazn boxing'],
    programmeWords: [
      'ufc',
      'mma',
      'boxing',
      'bellator',
      'one championship',
      'pfl',
      'fight night',
      'kickboxing',
    ],
  ),
  SportDef(
    id: 'nfl',
    label: 'NFL / American Football',
    icon: Icons.sports_football_rounded,
    channelWords: ['nfl', 'redzone', 'ncaaf', 'college football'],
    programmeWords: [
      'nfl',
      'super bowl',
      'redzone',
      'ncaaf',
      'college football',
      'monday night football',
      'sunday night football',
      'thursday night football',
    ],
  ),
  SportDef(
    id: 'baseball',
    label: 'Baseball',
    icon: Icons.sports_baseball_rounded,
    channelWords: ['mlb', 'baseball'],
    programmeWords: ['mlb', 'baseball', 'world series'],
  ),
  SportDef(
    id: 'hockey',
    label: 'Ice Hockey',
    icon: Icons.sports_hockey_rounded,
    channelWords: ['nhl', 'hockey', 'khl'],
    programmeWords: ['nhl', 'ice hockey', 'khl', 'stanley cup'],
  ),
  SportDef(
    id: 'golf',
    label: 'Golf',
    icon: Icons.sports_golf_rounded,
    channelWords: ['golf', 'pga'],
    programmeWords: ['golf', 'pga', 'the masters', 'ryder cup', 'liv golf'],
  ),
  SportDef(
    id: 'rugby',
    label: 'Rugby / AFL',
    icon: Icons.sports_rugby_rounded,
    channelWords: ['rugby', 'nrl', 'afl'],
    programmeWords: [
      'rugby',
      'six nations',
      'super rugby',
      'nrl',
      'afl',
      'premiership rugby',
      'urc',
    ],
  ),
  SportDef(
    id: 'other',
    label: 'Olympics & more',
    icon: Icons.emoji_events_rounded,
    channelWords: ['olympic', 'olympics', 'kabaddi', 'athletics'],
    programmeWords: [
      'olympic',
      'olympics',
      'kabaddi',
      'athletics',
      'badminton',
      'volleyball',
      'handball',
      'tour de france',
      'cycling',
      'swimming',
      'commonwealth games',
      'asian games',
    ],
  ),
];

/// Multi-sport channels (ESPN, Sky Sports Main Event, Star Sports 1 …). They
/// are not tied to one sport, so what they air decides.
const List<String> kGeneralSportsWords = [
  'sport',
  'sports',
  'espn',
  'bein',
  'sky sports',
  'star sports',
  'sony ten',
  'sony sports',
  'ten sports',
  'tnt sports',
  'bt sport',
  'dazn',
  'eurosport',
  'supersport',
  'fox sports',
  'nbc sports',
  'cbs sports',
  'sportsnet',
  'tsn',
  'sporttv',
  'canal sport',
  'arena sport',
  'eleven',
  'ssc',
  'ptv sports',
  'a sports',
  't sports',
  'dd sports',
  'viaplay',
  'optus sport',
  'stan sport',
  'kayo',
  'dyn',
  'staige',
  'magenta sport',
];

/// Words that make a CATEGORY (folder) worth scanning for sports channels.
const List<String> kSportsCategoryWords = [
  'sport',
  'sports',
  'cricket',
  'football',
  'soccer',
  'wwe',
  'wrestling',
  'tennis',
  'nba',
  'nfl',
  'ufc',
  'f1',
  'racing',
  'golf',
  'boxing',
  'dazn',
  'espn',
  'bein',
  'sky sports',
  'eurosport',
  'supersport',
  'ppv',
  'event',
  'events',
  'bundesliga',
  'liga',
  'dyn',
  'staige',
];

/// Cheap probes used to catch sports channels filed under a non-sports
/// category. Each runs one indexed-LIKE query per catalog.
const List<String> kSportsProbeWords = [
  'sport',
  'cricket',
  'wwe',
  'tennis',
  'espn',
  'bein',
  'nba',
  'nfl',
  'ufc',
  'f1',
  'dazn',
  'willow',
  'eurosport',
];

/// Lower-case, strip decoration, collapse everything non-alphanumeric to one
/// space and pad with spaces so `padded.contains(' word ')` is a whole-word
/// test ("raw" never matches "draw").
String sportsNormalize(String input) {
  // Superscript tags ("ᴴᴰ", "ᴿᴬᵂ", "ᵁᴴᴰ ³⁸⁴⁰ᴾ") become plain words so the
  // quality rules below can read them.
  var s = iptvTagsToAscii(input).toLowerCase();
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  // "LOW BIT" / "LOWBIT" → one token.
  s = s.replaceAll(RegExp(r'\blow bit\b'), 'lowbit');
  return ' $s ';
}

bool sportsContainsAny(String padded, Iterable<String> words) {
  for (final w in words) {
    if (padded.contains(' $w ')) return true;
  }
  return false;
}

/// Stream quality tier parsed from the channel name. 0 = nothing stated.
///   1 SD · 2 HD · 3 FHD (1080) · 4 UHD / 4K
int sportsQualityTier(String padded) {
  if (padded.contains(' 4k ') ||
      padded.contains(' 8k ') ||
      padded.contains(' uhd ') ||
      padded.contains(' 2160p ') ||
      padded.contains(' 2160 ') ||
      padded.contains(' 3840p ') ||
      padded.contains(' 3840 ') ||
      padded.contains(' 4320p ')) {
    return 4;
  }
  if (padded.contains(' fhd ') ||
      padded.contains(' 1080p ') ||
      padded.contains(' 1080 ') ||
      padded.contains(' full hd ')) {
    return 3;
  }
  if (padded.contains(' hd ') ||
      padded.contains(' 720p ') ||
      padded.contains(' 720 ') ||
      padded.contains(' hevc ') ||
      padded.contains(' h265 ')) {
    return 2;
  }
  if (padded.contains(' sd ') ||
      padded.contains(' 480p ') ||
      padded.contains(' 360p ') ||
      padded.contains(' lq ') ||
      padded.contains(' low ')) {
    return 1;
  }
  return 0;
}

String sportsQualityLabel(int tier) {
  switch (tier) {
    case 4:
      return '4K';
    case 3:
      return 'FHD';
    case 2:
      return 'HD';
    case 1:
      return 'SD';
    default:
      return '';
  }
}

/// Two-letter-ish region prefixes providers put on channel / category names
/// ("UK| Sky Sports", "IN - Star Sports").
const Map<String, String> kSportsRegionLabels = {
  'in': 'India',
  'uk': 'UK',
  'us': 'USA',
  'ca': 'Canada',
  'au': 'Australia',
  'nz': 'New Zealand',
  'pk': 'Pakistan',
  'bd': 'Bangladesh',
  'lk': 'Sri Lanka',
  'za': 'South Africa',
  'ae': 'Middle East',
  'ar': 'Arabic',
  'de': 'Germany',
  'at': 'Austria',
  'ch': 'Switzerland',
  'asia': 'Asia',
  'fr': 'France',
  'es': 'Spain',
  'it': 'Italy',
  'pt': 'Portugal',
  'br': 'Brazil',
  'nl': 'Netherlands',
  'tr': 'Turkey',
};

/// Region code from the first words of the name or category, or null.
String? sportsRegionOf(String paddedName, String paddedGroup) {
  for (final source in [paddedName, paddedGroup]) {
    final tokens = source.trim().split(' ');
    for (var i = 0; i < tokens.length && i < 2; i++) {
      if (kSportsRegionLabels.containsKey(tokens[i])) return tokens[i];
    }
  }
  return null;
}

const Set<String> _kNoiseTokens = {
  '4k',
  'uhd',
  'fhd',
  'hd',
  'sd',
  'lq',
  '2160p',
  '1080p',
  '720p',
  '480p',
  '360p',
  '2160',
  '1080',
  '720',
  '480',
  '60fps',
  '50fps',
  'fps',
  'hevc',
  'h265',
  'h264',
  'raw',
  'backup',
  'multi',
  'low',
  'lowbit',
  'full',
  'p',
  '3840p',
  '3840',
  '4320p',
  '8k',
  'hdr',
  'dolby',
  'audio',
  'atmos',
  'vision',
  'gold',
  'vip',
};

/// Identity shared by all variants of "the same channel" (HD/FHD/4K copies,
/// regional prefixes, backup feeds). Digits are kept: Sky Sports 1 and Sky
/// Sports 2 are different channels.
String sportsGroupKey(String paddedName) {
  final tokens = paddedName.trim().split(' ');
  final kept = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.isEmpty) continue;
    if (i == 0 && kSportsRegionLabels.containsKey(t) && tokens.length > 1) {
      continue;
    }
    if (_kNoiseTokens.contains(t)) continue;
    kept.add(t);
  }
  return kept.join(' ');
}

/// Titles that signal a programme is not the live event itself.
const List<String> kSportsReplayWords = [
  'replay',
  'repeat',
  'highlights',
  'classic',
  'rewind',
  'encore',
  'recap',
  'rerun',
  're air',
  'catch up',
  'magazine',
  'preview',
  'review',
  'best of',
];

/// One channel row from the user's own playlist that looks like sports.
class SportsChannel {
  final IptvChannel channel;
  final String sourceId;
  final String sourceName;

  /// Specific sports this channel is dedicated to. Empty = multi-sport.
  final Set<String> sports;
  final int tier;
  final int score;
  final String? region;
  final String groupKey;

  /// "RAW" feed: the provider's untouched broadcast stream. Shown as its own
  /// badge and ranked above re-encoded copies when the user prefers it.
  final bool raw;

  /// "LOW BIT" feed: a low-bandwidth copy, always ranked last.
  final bool lowBit;

  const SportsChannel({
    required this.channel,
    required this.sourceId,
    required this.sourceName,
    required this.sports,
    required this.tier,
    required this.score,
    required this.region,
    required this.groupKey,
    this.raw = false,
    this.lowBit = false,
  });

  bool get isMultiSport => sports.isEmpty;

  /// Badge text: "RAW", "LOW", or the quality tier ("4K", "FHD", …).
  String get qualityLabel =>
      raw ? 'RAW' : (lowBit ? 'LOW' : sportsQualityLabel(tier));

  /// Whether the badge should be drawn in the strong (accent) style.
  bool get strongQuality => !lowBit && (raw || tier >= 3);
}

/// All variants of one logical channel, best stream first.
class SportsChannelGroup {
  final String key;
  final List<SportsChannel> variants;

  SportsChannelGroup({required this.key, required List<SportsChannel> variants})
    : variants = List.unmodifiable(variants);

  SportsChannel get best => variants.first;
  String get displayName => best.channel.name;
  Set<String> get sports => best.sports;
  bool get isMultiSport => best.isMultiSport;
}

/// What the user chose in Sports Hub settings.
class SportsPrefs {
  final Set<String> enabledSports;

  /// Also list multi-sport channels (ESPN, Star Sports …) in the Channels tab.
  final bool includeMultiSport;

  /// Region codes to rank first. Empty = no preference.
  final Set<String> preferredRegions;

  /// Hide streams below this tier (0 = show everything).
  final int minTier;

  /// Collapse HD/FHD/4K copies of a channel into one row (best on top).
  final bool collapseVariants;

  /// Rank "RAW" feeds above re-encoded 4K/FHD/HD copies.
  final bool preferRaw;

  /// Teams the user follows ("Bayern", "India", "Real Madrid"). Their
  /// matches are pinned on top with a star.
  final List<String> myTeams;

  const SportsPrefs({
    required this.enabledSports,
    this.includeMultiSport = true,
    this.preferredRegions = const <String>{},
    this.minTier = 0,
    this.collapseVariants = true,
    this.preferRaw = true,
    this.myTeams = const <String>[],
  });

  factory SportsPrefs.defaults() => SportsPrefs(
    enabledSports: {
      for (final s in kSportDefs)
        if (s.defaultOn) s.id,
    },
  );

  SportsPrefs copyWith({
    Set<String>? enabledSports,
    bool? includeMultiSport,
    Set<String>? preferredRegions,
    int? minTier,
    bool? collapseVariants,
    bool? preferRaw,
    List<String>? myTeams,
  }) => SportsPrefs(
    enabledSports: enabledSports ?? this.enabledSports,
    includeMultiSport: includeMultiSport ?? this.includeMultiSport,
    preferredRegions: preferredRegions ?? this.preferredRegions,
    minTier: minTier ?? this.minTier,
    collapseVariants: collapseVariants ?? this.collapseVariants,
    preferRaw: preferRaw ?? this.preferRaw,
    myTeams: myTeams ?? this.myTeams,
  );
}

SportDef? sportDefById(String id) {
  for (final s in kSportDefs) {
    if (s.id == id) return s;
  }
  return null;
}

/// Sports whose programme words appear in [title]. Whole-word matching.
Set<String> sportsInTitle(String title) {
  final padded = sportsNormalize(title);
  final found = <String>{};
  for (final s in kSportDefs) {
    if (sportsContainsAny(padded, s.programmeWords)) found.add(s.id);
  }
  return found;
}

/// Whether [title] mentions one of [teams] as whole words
/// ("Bayern" matches "FC Bayern München – Dortmund", not "Bayernliga").
bool sportsTitleHasTeam(String title, List<String> teams) {
  if (teams.isEmpty) return false;
  final padded = sportsNormalize(title);
  for (final team in teams) {
    final t = sportsNormalize(team).trim();
    if (t.isNotEmpty && padded.contains(' $t ')) return true;
  }
  return false;
}

bool sportsTitleLooksLikeReplay(String title) =>
    sportsContainsAny(sportsNormalize(title), kSportsReplayWords);

/// Turns one catalog row into a [SportsChannel], or null when it does not look
/// like sports at all. [fromSportsCategory] marks rows found by walking a
/// sports-looking folder, which are at least multi-sport.
SportsChannel? classifySportsChannel({
  required IptvChannel channel,
  required String sourceId,
  required String sourceName,
  required bool fromSportsCategory,
  required Set<String> preferredRegions,
  bool preferRaw = true,
}) {
  // "###### SKY SPORT AUSTRIA 4K ######" rows are block headers, not
  // channels.
  if (iptvIsSeparatorName(channel.name)) return null;
  final name = sportsNormalize(channel.name);
  final group = sportsNormalize(channel.group ?? '');
  final haystack = '$name${group.trim()} ';

  final specific = <String>{};
  for (final s in kSportDefs) {
    if (sportsContainsAny(haystack, s.channelWords)) specific.add(s.id);
  }
  final general =
      sportsContainsAny(haystack, kGeneralSportsWords) || fromSportsCategory;
  if (specific.isEmpty && !general) return null;

  final raw = name.contains(' raw ');
  final lowBit = name.contains(' lowbit ');
  var tier = sportsQualityTier(name);
  // A RAW feed carries no other quality tag but is a full broadcast stream;
  // it counts as Full HD for the minimum-quality filter.
  if (raw && tier < 3) tier = 3;
  final region = sportsRegionOf(name, group);
  var score = tier * 100;
  if (raw && preferRaw) score += 160;
  if (lowBit) score -= 250;
  if (name.contains(' 60fps ') || name.contains(' 50fps ')) score += 25;
  if (name.contains(' backup ') ||
      name.contains(' test ') ||
      name.contains(' sample ')) {
    score -= 60;
  }
  if (region != null && preferredRegions.contains(region)) score += 150;
  if (channel.channelNumber != null) score += 1;

  return SportsChannel(
    channel: channel,
    sourceId: sourceId,
    sourceName: sourceName,
    sports: specific,
    tier: tier,
    score: score,
    region: region,
    groupKey: sportsGroupKey(name),
    raw: raw,
    lowBit: lowBit,
  );
}
