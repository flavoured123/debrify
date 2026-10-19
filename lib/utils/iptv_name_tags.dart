// Channel-name decoration used by IPTV panels.
//
// Providers tag names with superscript letters and digits ("SKY SPORT 1 ᴴᴰ",
// "PRIME: 3SAT ᴿᴬᵂ", "RELAX ICELAND ᵁᴴᴰ ³⁸⁴⁰ᴾ"), sometimes with small-capital
// letters, and fill their lists with separator rows ("###### RELAX ######").
// Pure Dart on purpose: the XMLTV parser calls this inside a worker isolate.

/// Superscript / modifier forms → plain ASCII. A run of these is always a
/// TAG (quality, feed, codec), never part of the channel's real name.
const Map<int, String> _kSuperscript = {
  0x1D2C: 'a', 0x1D2E: 'b', 0x1D30: 'd', 0x1D31: 'e', 0x1D33: 'g',
  0x1D34: 'h', 0x1D35: 'i', 0x1D36: 'j', 0x1D37: 'k', 0x1D38: 'l',
  0x1D39: 'm', 0x1D3A: 'n', 0x1D3C: 'o', 0x1D3E: 'p', 0x1D3F: 'r',
  0x1D40: 't', 0x1D41: 'u', 0x2C7D: 'v', 0x1D42: 'w',
  0x1D43: 'a', 0x1D47: 'b', 0x1D9C: 'c', 0x1D48: 'd', 0x1D49: 'e',
  0x1DA0: 'f', 0x1D4D: 'g', 0x02B0: 'h', 0x2071: 'i', 0x02B2: 'j',
  0x1D4F: 'k', 0x02E1: 'l', 0x1D50: 'm', 0x207F: 'n', 0x1D52: 'o',
  0x1D56: 'p', 0x02B3: 'r', 0x02E2: 's', 0x1D57: 't', 0x1D58: 'u',
  0x1D5B: 'v', 0x02B7: 'w', 0x02E3: 'x', 0x02B8: 'y', 0x1DBB: 'z',
  0x2070: '0', 0x00B9: '1', 0x00B2: '2', 0x00B3: '3', 0x2074: '4',
  0x2075: '5', 0x2076: '6', 0x2077: '7', 0x2078: '8', 0x2079: '9',
  0x207A: '+',
};

/// Small-capital letters → plain ASCII. Some panels write whole words this
/// way, so these are part of the name and are kept (only converted).
const Map<int, String> _kSmallCaps = {
  0x1D00: 'a', 0x0299: 'b', 0x1D04: 'c', 0x1D05: 'd', 0x1D07: 'e',
  0xA730: 'f', 0x0262: 'g', 0x029C: 'h', 0x026A: 'i', 0x1D0A: 'j',
  0x1D0B: 'k', 0x029F: 'l', 0x1D0D: 'm', 0x0274: 'n', 0x1D0F: 'o',
  0x1D18: 'p', 0x0280: 'r', 0xA731: 's', 0x1D1B: 't', 0x1D1C: 'u',
  0x1D20: 'v', 0x1D21: 'w', 0x028F: 'y', 0x1D22: 'z',
};

/// Name with every superscript tag spelled out as its own word and small
/// capitals converted: "SKY 1 ᴴᴰ" → "SKY 1  hd ". Use this when the TAGS
/// matter (reading stream quality).
String iptvTagsToAscii(String input) => _convert(input, keepTags: true);

/// Name with every superscript tag removed and small capitals converted:
/// "PRIME: 3SAT ᴿᴬᵂ" → "PRIME: 3SAT ". Use this when only the channel's real
/// name matters (matching it to a TV guide).
String iptvStripTags(String input) => _convert(input, keepTags: false);

String _convert(String input, {required bool keepTags}) {
  final out = StringBuffer();
  var inTag = false;
  for (final rune in input.runes) {
    final sup = _kSuperscript[rune];
    if (sup != null) {
      if (!inTag) {
        out.write(' ');
        inTag = true;
      }
      if (keepTags) out.write(sup);
      continue;
    }
    if (inTag) {
      out.write(' ');
      inTag = false;
    }
    final small = _kSmallCaps[rune];
    if (small != null) {
      out.write(small);
    } else {
      out.writeCharCode(rune);
    }
  }
  if (inTag) out.write(' ');
  return out.toString();
}

/// Separator rows providers put between blocks of channels:
/// "###### SKY SPORT AUSTRIA 4K ######", "===== UK =====", "★★★ NEWS ★★★".
/// They are not playable channels.
bool iptvIsSeparatorName(String name) {
  final s = name.trim();
  if (s.length < 3) return false;
  const marks = '#=*~_-★☆•▬━─|+';
  final a = s[0];
  final b = s[1];
  return marks.contains(a) && marks.contains(b) && a == b;
}

/// The leading country/provider code of a folder name, upper-cased, or null:
/// "DE| SKY SPORT AUSTRIA" → "DE", "ASIA| HINDI" → "ASIA", "UK: Sports" → "UK".
/// Only 2–5 letters before a "|" or ":" count, so "24/7 MOVIES" or
/// "SKY SPORT" never produce a code.
String? iptvFolderCountryCode(String folder) {
  final m = _kFolderPrefix.firstMatch(iptvStripTags(folder));
  return m?.group(1)?.toUpperCase();
}

final RegExp _kFolderPrefix = RegExp(r'^\s*([A-Za-z]{2,5})\s*[|:]');
