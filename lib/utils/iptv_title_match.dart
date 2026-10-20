// "Is this the same movie / series?" across provider folders.
//
// Providers list one film several times — "NF: Inception (2010) 4K",
// "4K-MOVIES | Inception ᵁᴴᴰ", "DE - Inception (2010) MULTI" — once per
// folder (Netflix 4K, 4K Movies, Netflix Multi, India Hindi …). These helpers
// reduce a name to its core title + year so the copies can be offered
// together, best quality first.

import '../services/iptv_sports/sports_catalog.dart'
    show sportsNormalize, sportsQualityLabel, sportsQualityTier;
import 'iptv_name_tags.dart';

/// Core identity of a VOD / series name.
class IptvTitleKey {
  /// Lower-case letters and digits of the title only: "inception".
  final String key;

  /// Release year when the name carries one.
  final int? year;

  /// The longest word of the title — what the catalog search uses to find
  /// candidate copies before [matches] checks them properly.
  final String searchWord;

  const IptvTitleKey({
    required this.key,
    required this.year,
    required this.searchWord,
  });

  bool get isUsable => key.length >= 2 && searchWord.length >= 2;

  /// Same title, and the same year when BOTH names state one ("Dune (1984)"
  /// and "Dune (2021)" are different films).
  bool matches(IptvTitleKey other) {
    final a = year;
    final b = other.year;
    if (a != null && b != null && a != b) return false;
    if (key == other.key) return true;
    // A folder code the prefix rules did not catch ("nf", "top", "amz")
    // left in front of the title: "nfthesecretwoman" vs "thesecretwoman".
    // Only for reasonably long titles, and only a short leftover, so
    // "it" never matches "split".
    final longer = key.length >= other.key.length ? key : other.key;
    final shorter = identical(longer, key) ? other.key : key;
    return shorter.length >= 6 &&
        longer.length - shorter.length <= 6 &&
        longer.endsWith(shorter);
  }
}

final RegExp _kYear = RegExp(r'(?<![0-9])(19[2-9][0-9]|20[0-4][0-9])(?![0-9])');
final RegExp _kBrackets = RegExp(r'[\[\(\{][^\]\)\}]{0,40}[\]\)\}]');
final RegExp _kPrefixColon = RegExp(
  r'^\s*[\p{L}\p{N}+&.\- ]{1,14}?\s*[:|]\s*',
  unicode: true,
);
// "NF - ", "4K-NF - ", "4K-TOP - ": a short code (optionally two joined by
// a dash) followed by a spaced dash.
final RegExp _kPrefixDash = RegExp(
  r'^\s*[\p{L}\p{N}+&]{1,8}(?:-[\p{L}\p{N}+&]{1,8})?\s+[-–—]\s+',
  unicode: true,
);
final RegExp _kSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Release / quality / language decoration that never belongs to a title.
const Set<String> _kTitleNoise = {
  '4k', '8k', 'uhd', 'fhd', 'hd', 'sd', 'hq', 'lq', 'hdr', 'hdr10', 'dv',
  'sdr', 'hevc', 'h264', 'h265', 'x264', 'x265', 'av1', '2160p', '1080p',
  '1080i', '720p', '576p', '480p', '3840p', 'raw', 'multi', 'multisub',
  'multiaudio', 'dual', 'dl', 'web', 'webdl', 'webrip', 'bluray', 'bdrip',
  'remux', 'atmos', 'dolby', 'vision', 'imax', 'extended', 'uncut',
  'remastered', 'directors', 'cut', 'vip', 'backup',
};

IptvTitleKey iptvTitleKeyOf(String name) {
  var s = iptvStripTags(name);
  int? year;
  for (final m in _kYear.allMatches(s)) {
    year = int.tryParse(m.group(1)!);
  }
  s = s.replaceAll(_kBrackets, ' ');
  for (var i = 0; i < 2; i++) {
    final next = s
        .replaceFirst(_kPrefixColon, '')
        .replaceFirst(_kPrefixDash, '');
    if (next == s || next.trim().isEmpty) break;
    s = next;
  }
  final words = <String>[];
  for (final raw in s.toLowerCase().split(_kSplit)) {
    if (raw.isEmpty || _kTitleNoise.contains(raw)) continue;
    if (year != null && raw == '$year') continue;
    words.add(raw);
  }
  var search = '';
  for (final w in words) {
    if (w.length > search.length) search = w;
  }
  return IptvTitleKey(key: words.join(), year: year, searchWord: search);
}

/// Ranking for one copy: higher is better. 4K > FHD > HD > SD, RAW slightly
/// above its tier, LOW BIT / backup copies last.
int iptvCopyQualityScore(String name) {
  final padded = sportsNormalize(name);
  var score = sportsQualityTier(padded) * 100;
  if (padded.contains(' raw ')) score += 40;
  if (padded.contains(' hdr ') || padded.contains(' dv ')) score += 15;
  if (padded.contains(' multi ') || padded.contains(' dual ')) score += 5;
  if (padded.contains(' lowbit ') || padded.contains(' backup ')) score -= 150;
  return score;
}

/// Short badge for a copy: "4K", "FHD", "HD", "SD", "RAW" or "".
String iptvCopyQualityLabel(String name) {
  final padded = sportsNormalize(name);
  if (padded.contains(' lowbit ')) return 'LOW';
  final tier = sportsQualityTier(padded);
  if (tier == 0 && padded.contains(' raw ')) return 'RAW';
  return sportsQualityLabel(tier);
}
