// Port of frontend/src/lotteryColumns.js: rebuilds a Miền Nam / Miền Trung result table from OCR words with positions.
// One column per station, prizes in table order. Pure functions; the result is only ever a SUGGESTION the user reviews
// before saving.
//
// Table layout (top to bottom): G.8 (2 digits x1), G.7 (3 x1), G.6 (4 x3), G.5 (4 x1), G.4 (5 x7), G.3 (5 x2), G.2 (5 x1),
// G.1 (5 x1), G.ĐB (6 x1). So per column: the 2-digit number is G8, the 3-digit G7, the four 4-digit numbers are G6 x3 then
// G5, the eleven 5-digit numbers are G4 x7, G3 x2, G2, G1 (reading order), the 6-digit number is the special prize.
import 'dart:math' as math;

import '../../core/lottery_stations.dart';

/// One recognised word with its bounding box (pixels of the photo).
class OcrWord {
  const OcrWord(this.text, this.x0, this.y0, this.x1, this.y1);
  final String text;
  final double x0, y0, x1, y1;
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
}

const _viGroups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};
final Map<String, String> _viMap = {
  for (final e in _viGroups.entries)
    for (final ch in e.value.split('')) ch: e.key,
};
final _combining = RegExp('[̀-ͯ]');

/// Lower case, accents removed (đ -> d), everything that is not a-z/0-9 collapsed to single spaces.
String foldText(String? s) {
  final lower = (s ?? '').toLowerCase().replaceAll(_combining, '');
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_viMap[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

// Extra spellings seen in headers (folded). The catalog names themselves are matched too.
const _aliases = <String, List<String>>{
  'mn-tphcm': ['tp hcm', 'tphcm', 'hcm', 'ho chi minh', 'tp ho chi minh'],
  'mt-hue': ['hue', 'thua thien hue', 'tt hue'],
  'mn-vungtau': ['vung tau', 'ba ria vung tau', 'brvt'],
  'mt-daklak': ['dak lak', 'daklak', 'dac lac'],
  'mt-daknong': ['dak nong', 'daknong', 'dac nong'],
  'mn-dalat': ['da lat', 'lam dong'],
};

class _Spec {
  const _Spec(this.len, this.take);
  final int len;
  final List<(String, int)> take;
}

const _spec = [
  _Spec(2, [('giaiTam', 1)]),
  _Spec(3, [('giaiBay', 1)]),
  _Spec(4, [('giaiSau', 3), ('giaiNam', 1)]),
  _Spec(5, [('giaiTu', 7), ('giaiBa', 2), ('giaiNhi', 1), ('giaiNhat', 1)]),
  _Spec(6, [('dacBiet', 1)]),
];

int _expectedFor(_Spec s) => s.take.fold(0, (n, t) => n + t.$2);

/// One recognised station column.
class OcrColumn {
  OcrColumn(this.x);
  final double x;
  String headerText = '';
  String? station;
  String source = '';
  final Map<String, List<String>> values = {}; // tier -> numbers ('' = not read)
  final List<String> issues = [];
  bool complete = false;
}

class ParsedColumns {
  const ParsedColumns(this.columns, this.date);
  final List<OcrColumn> columns;
  final String? date; // ISO
}

/// Station id from header text, or null.
String? matchStation(String text, LotteryStations stations) {
  final t = foldText(text);
  if (t.isEmpty) return null;
  for (final r in stations.regionList) {
    for (final e in r.stations.entries) {
      if (e.key == 'mb') continue;
      final names = [foldText(e.value), ...(_aliases[e.key] ?? const [])];
      if (names.any((n) => n.isNotEmpty && (t == n || t.contains(n) || (n.length > 4 && n.contains(t) && t.length > 3)))) return e.key;
    }
  }
  return null;
}

int _levenshtein(String a, String b) {
  final dp = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0)..[0] = i);
  for (var j = 1; j <= b.length; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      dp[i][j] = math.min(math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1), dp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
  }
  return dp[a.length][b.length];
}

double _similarity(String a, String b) => a.isNotEmpty && b.isNotEmpty ? 1 - _levenshtein(a, b) / math.max(a.length, b.length) : 0;

const _noise = {'giai', 'xsmn', 'xsmt', 'xsmb', 'thu', 'thir', 'thur', 'kqxs', 'truc', 'tiep', 'ngay', 'mien', 'nam', 'trung', 'bac'};

/// How well the header text of a column fits a station name (0..1): the best match over windows of 1-3 header words.
/// The header is read by a Latin model, so accents can be garbled ("Déng Thr Nai" for "Đồng Nai") - hence fuzzy.
double headerScore(String headerText, String id, LotteryStations stations) {
  final words = foldText(headerText).split(' ').where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w) && !_noise.contains(w)).toList();
  final names = [foldText(stations.stationName(id)), ...(_aliases[id] ?? const [])];
  var best = 0.0;
  for (var i = 0; i < words.length; i++) {
    for (var n = 1; n <= 3 && i + n <= words.length; n++) {
      final win = words.sublist(i, i + n).join(' ');
      for (final name in names) {
        best = math.max(best, _similarity(win, name));
      }
    }
  }
  return best;
}

/// Gives every column a station among [candidates] (the stations drawing that day): the best header matches first, then
/// the remaining columns take the remaining stations in page order. `source` tells the user how sure it is.
List<OcrColumn> assignStations(List<OcrColumn> columns, List<String> candidates, LotteryStations stations) {
  final pool = [...candidates];
  final pairs = <({int ci, String id, double score})>[];
  for (var ci = 0; ci < columns.length; ci++) {
    for (final id in pool) {
      pairs.add((ci: ci, id: id, score: columns[ci].station == id ? 1.0 : headerScore(columns[ci].headerText, id, stations)));
    }
  }
  // stable sort by score, best first
  final idx = List<int>.generate(pairs.length, (i) => i)
    ..sort((a, b) {
      final c = pairs[b].score.compareTo(pairs[a].score);
      return c != 0 ? c : a.compareTo(b);
    });
  final usedCol = <int>{};
  final usedSt = <String>{};
  for (final i in idx) {
    final p = pairs[i];
    if (p.score < 0.6 || usedCol.contains(p.ci) || usedSt.contains(p.id)) continue;
    columns[p.ci]
      ..station = p.id
      ..source = 'tiêu đề';
    usedCol.add(p.ci);
    usedSt.add(p.id);
  }
  final left = pool.where((id) => !usedSt.contains(id)).toList();
  for (var ci = 0; ci < columns.length; ci++) {
    if (usedCol.contains(ci)) continue;
    columns[ci].station = left.isEmpty ? null : left.removeAt(0);
    columns[ci].source = columns[ci].station != null ? 'theo thứ tự' : '';
  }
  return columns;
}

ParsedColumns parseColumns(List<OcrWord> words, LotteryStations stations) {
  // The title line of the page ("XSMN Thứ 4 » XSMN 07/10/2026") holds a date whose digits must not count as prizes:
  // everything on or above the lowest date word is ignored.
  final dateYs = [for (final w in words) if (RegExp(r'/|^20\d\d$').hasMatch(w.text.trim())) w.cy];
  final cut = dateYs.isEmpty ? double.negativeInfinity : dateYs.reduce(math.max) + 14;
  final nums = <OcrWord>[
    for (final w in words)
      if (RegExp(r'^\d+$').hasMatch(w.text.trim()) && w.text.trim().length >= 2 && w.text.trim().length <= 6 && w.cy > cut) OcrWord(w.text.trim(), w.x0, w.y0, w.x1, w.y1),
  ];
  final specials = nums.where((w) => w.text.length == 6).toList()..sort((a, b) => a.cx.compareTo(b.cx));
  if (specials.isEmpty) return const ParsedColumns([], null);

  // One 6-digit special prize per station: they fix the column centres.
  final centres = [for (final w in specials) w.cx];
  int nearest(double cx) {
    var best = 0;
    for (var i = 1; i < centres.length; i++) {
      if ((centres[i] - cx).abs() < (centres[best] - cx).abs()) best = i;
    }
    return best;
  }

  final twoDigitYs = [for (final w in nums) if (w.text.length == 2) w.cy];
  final firstRowY = twoDigitYs.isEmpty ? double.infinity : twoDigitYs.reduce(math.min);
  final columns = [for (final x in centres) OcrColumn(x)];
  final tokens = List.generate(columns.length, (_) => <OcrWord>[]);
  final headers = List.generate(columns.length, (_) => <({String text, double cx})>[]);
  for (final w in nums) {
    tokens[nearest(w.cx)].add(w);
  }
  // Header words (station names) sit above the first prize row.
  for (final w in words) {
    final text = w.text.trim();
    if (text.isEmpty || RegExp(r'^\d+$').hasMatch(text)) continue;
    if (firstRowY.isFinite && w.cy < firstRowY - 6) headers[nearest(w.cx)].add((text: text, cx: w.cx));
  }

  for (var ci = 0; ci < columns.length; ci++) {
    final col = columns[ci];
    final h = headers[ci]..sort((a, b) => a.cx.compareTo(b.cx));
    col.headerText = h.map((x) => x.text).join(' ');
    col.station = matchStation(col.headerText, stations);
    for (final s in _spec) {
      final list = tokens[ci].where((t) => t.text.length == s.len).toList()..sort((a, b) => a.cy.compareTo(b.cy));
      final want = _expectedFor(s);
      if (list.length != want) col.issues.add('${s.len} chữ số: đọc được ${list.length}/$want');
      var i = 0;
      for (final (tier, count) in s.take) {
        col.values[tier] = [for (var k = 0; k < count; k++) i < list.length ? list[i++].text : ''];
      }
    }
    col.complete = col.issues.isEmpty;
  }

  // dd/mm/yyyy anywhere in the text -> ISO
  final m = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})').firstMatch(words.map((w) => w.text).join(' '));
  final date = m == null ? null : '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  return ParsedColumns(columns, date);
}

/// Miền Bắc photo: sorts the all-digit words of the recognised text into the 27 boxes (port of applyLrOcrGuess).
/// [form] holds tier -> numbers ('' = empty) and only EMPTY boxes are filled. 5-digit words in reading order are
/// đặc biệt, nhất, nhì (2), ba (6); 4-digit tư (4), năm (6); 3-digit sáu (3); 2-digit bảy (4).
void guessNorthForm(String text, Map<String, List<String>> form) {
  final tokens = RegExp(r'\S+').allMatches(text).map((m) => m.group(0)!).where((w) => RegExp(r'^\d+$').hasMatch(w));
  final byLen = <int, List<String>>{5: [], 4: [], 3: [], 2: []};
  for (final t in tokens) {
    byLen[t.length]?.add(t);
  }
  void fill(List<String> src, List<(String, int)> plan) {
    var i = 0;
    for (final (tier, count) in plan) {
      final box = form[tier];
      if (box == null) {
        i += count;
        continue;
      }
      for (var k = 0; k < count && k < box.length; k++) {
        if (box[k].trim().isEmpty && i < src.length) box[k] = src[i++];
      }
    }
  }

  fill(byLen[5]!, const [('dacBiet', 1), ('giaiNhat', 1), ('giaiNhi', 2), ('giaiBa', 6)]);
  fill(byLen[4]!, const [('giaiTu', 4), ('giaiNam', 6)]);
  // 3 and 2 digits are taken by position (not consumed when a box is already filled), like the web app.
  for (var k = 0; k < 3; k++) {
    final b = form['giaiSau'];
    if (b != null && k < b.length && b[k].trim().isEmpty && k < byLen[3]!.length) b[k] = byLen[3]![k];
  }
  for (var k = 0; k < 4; k++) {
    final b = form['giaiBay'];
    if (b != null && k < b.length && b[k].trim().isEmpty && k < byLen[2]!.length) b[k] = byLen[2]![k];
  }
}
