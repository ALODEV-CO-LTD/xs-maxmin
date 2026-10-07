/// Lower-cases [s] and strips Vietnamese diacritics ("Đỗ Ngọc Mai" -> "do ngoc mai"),
/// so searching "do ngoc" finds names written with accents. SQLite's LIKE cannot do this
/// for non-ASCII letters, hence the matching is done here. The frontend has the same
/// function (`fold` in src/messageParser.js); keep them in step.
String foldVi(String s) {
  final buf = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    // combining marks left over from decomposed (NFD) input
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    buf.write(_map[rune] ?? String.fromCharCode(rune));
  }
  return buf.toString();
}

final Map<int, String> _map = () {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  final m = <int, String>{};
  groups.forEach((plain, accented) {
    for (final r in accented.runes) {
      m[r] = plain;
    }
  });
  return m;
}();
