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

/// The digits of one OCR word, or null when it is not a number. The reader often takes a digit of a bold printed number for a
/// letter of similar shape (0 -> O, 1 -> I / l, 5 -> S, 8 -> B, 2 -> Z): such a word is accepted when most of it is real digits.
String? _digitsOf(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(t)) return t;
  if (!RegExp(r'^[0-9OoDQIl|SsBZz]+$').hasMatch(t)) return null;
  final real = RegExp(r'\d').allMatches(t).length;
  if (real * 2 < t.length) return null;
  const map = {'O': '0', 'o': '0', 'D': '0', 'Q': '0', 'I': '1', 'l': '1', '|': '1', 'S': '5', 's': '5', 'B': '8', 'Z': '2', 'z': '2'};
  return [for (final ch in t.split('')) map[ch] ?? ch].join();
}

/// The words with look-alike letters inside numbers repaired (see [_digitsOf]); other words are kept as they are.
List<OcrWord> repairDigitWords(List<OcrWord> words) => [
      for (final w in words)
        if (_digitsOf(w.text) case final d? when d != w.text.trim()) OcrWord(d, w.x0, w.y0, w.x1, w.y1) else w,
    ];

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
///
/// [others] = the rest of the region's stations (not drawing that day): a column whose header clearly names one of them
/// (a photo of another day, or a day the schedule has wrong) takes it too, but needs a stronger match than a scheduled one.
List<OcrColumn> assignStations(List<OcrColumn> columns, List<String> candidates, LotteryStations stations, {List<String> others = const []}) {
  final pool = [...candidates, ...others.where((id) => !candidates.contains(id))];
  final pairs = <({int ci, String id, double score})>[];
  for (var ci = 0; ci < columns.length; ci++) {
    for (final id in pool) {
      final s = columns[ci].station == id ? 1.0 : headerScore(columns[ci].headerText, id, stations);
      // off-schedule stations only count on a clear match, and lose a tie against a scheduled one
      final onSchedule = candidates.contains(id);
      pairs.add((ci: ci, id: id, score: onSchedule ? s : (s >= 0.8 ? s - 0.01 : 0.0)));
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
  final left = candidates.where((id) => !usedSt.contains(id)).toList();
  for (var ci = 0; ci < columns.length; ci++) {
    if (usedCol.contains(ci)) continue;
    columns[ci].station = left.isEmpty ? null : left.removeAt(0);
    columns[ci].source = columns[ci].station != null ? 'theo thứ tự' : '';
  }
  return columns;
}

/// The same 18 numbers in table order, top to bottom: tier, how many, digits each.
const _positions = <(String, int, int)>[
  ('giaiTam', 1, 2),
  ('giaiBay', 1, 3),
  ('giaiSau', 3, 4),
  ('giaiNam', 1, 4),
  ('giaiTu', 7, 5),
  ('giaiBa', 2, 5),
  ('giaiNhi', 1, 5),
  ('giaiNhat', 1, 5),
  ('dacBiet', 1, 6),
];

ParsedColumns parseColumns(List<OcrWord> words, LotteryStations stations) {
  // The title line of the page ("XSMN Thứ 4 » XSMN 07/10/2026") holds a date whose digits must not count as prizes:
  // everything down to the date word is ignored. Only the FIRST real date in the top third of the picture counts: a stray
  // "/" read from a table line further down must never raise the cut (that swallowed the first prize rows).
  final allY = [for (final w in words) w.cy];
  final top = allY.isEmpty ? 0.0 : allY.reduce(math.min);
  final span = allY.isEmpty ? 0.0 : allY.reduce(math.max) - top;
  final dateRe = RegExp(r'^\d{1,2}\s*[/.-]\s*\d{1,2}\s*[/.-]\s*(20)?\d{2}$');
  OcrWord? dateTop;
  for (final w in words) {
    final t = w.text.trim();
    if ((dateRe.hasMatch(t) || RegExp(r'^20\d\d$').hasMatch(t)) && w.cy <= top + span * 0.35 && (dateTop == null || w.cy < dateTop.cy)) dateTop = w;
  }
  final cut = dateTop == null ? double.negativeInfinity : dateTop.cy + (dateTop.y1 - dateTop.y0) * 0.9;
  var nums = <OcrWord>[
    for (final w in words)
      if (w.cy > cut)
        if (_digitsOf(w.text) case final d? when d.length >= 2 && d.length <= 6) OcrWord(d, w.x0, w.y0, w.x1, w.y1),
  ];
  final specials = nums.where((w) => w.text.length == 6).toList()..sort((a, b) => a.cx.compareTo(b.cx));
  if (specials.isEmpty) return const ParsedColumns([], null);

  // Only numbers inside the band of the station columns are prizes. The printed table also has a label column on its left
  // ("100N", "3TR", "2Tỷ" - read as "100", "3"...) and a header cell with the date ("19/10" "2026"): read as 3 and 4 digit
  // numbers they used to land in the first column and push its real prizes one place down.
  final cxs = [for (final w in specials) w.cx];
  final gap = cxs.length > 1
      ? (cxs.last - cxs.first) / (cxs.length - 1)
      : (specials.first.x1 - specials.first.x0) * 2.2;
  final bandL = cxs.first - gap * 0.5, bandR = cxs.last + gap * 0.5;
  nums = [for (final w in nums) if (w.cx >= bandL && w.cx <= bandR) w];

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
  // a longer number ABOVE the first prize row is part of the header (a date, a draw code), never a prize
  if (firstRowY.isFinite) nums = [for (final w in nums) if (w.text.length == 2 || w.cy >= firstRowY - 6) w];
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
    // Exactly the 18 numbers of a column were seen: take them by their place in the table (top to bottom) even when one
    // has a wrong length, so a lost or added digit flags that cell instead of shifting every row after it.
    if (tokens[ci].length == 18) {
      final sorted = [...tokens[ci]]..sort((a, b) => a.cy.compareTo(b.cy));
      var n = 0;
      for (final (tier, count, digits) in _positions) {
        final vals = <String>[];
        for (var k = 0; k < count; k++) {
          final t = sorted[n++].text;
          vals.add(t);
          if (t.length != digits) col.issues.add('$tier: số "$t" có ${t.length} chữ số, cần $digits');
        }
        col.values[tier] = vals;
      }
      col.complete = col.issues.isEmpty;
      continue;
    }
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
  String? date;
  for (final m in RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})').allMatches(words.map((w) => w.text).join(' '))) {
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    final real = DateTime.utc(y, mo, d); // 31/02 would roll over to March: only a date that exists counts
    if (mo >= 1 && mo <= 12 && d >= 1 && real.month == mo && real.day == d) {
      date = '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      break;
    }
  }
  return ParsedColumns(columns, date);
}

/// 'mt' / 'mn' / 'mb' when the TITLE area (top quarter of the picture) holds that region's word as a whole token
/// ("XSMT", "XSMN", "XSMB"); null otherwise. A word elsewhere in the picture (a station name, a footer) does not count.
String? regionFromTitle(List<OcrWord> words) {
  final r = _regionFromTitleWords(words);
  if (r != null) return r;
  if (words.isEmpty) return null;
  // "KQXS Miền Nam" / "Xổ số miền Trung": the two words in a row, in the top quarter
  final top = words.map((w) => w.y0).reduce(math.min), bottom = words.map((w) => w.y1).reduce(math.max);
  final limit = top + (bottom - top) * 0.25;
  final head = [for (final w in words) if (w.cy <= limit) w]..sort((a, b) => (a.cy - b.cy).abs() > (a.y1 - a.y0) / 2 ? a.cy.compareTo(b.cy) : a.cx.compareTo(b.cx));
  for (var i = 0; i + 1 < head.length; i++) {
    if (foldText(head[i].text) != 'mien') continue;
    switch (foldText(head[i + 1].text)) {
      case 'nam':
        return 'mn';
      case 'trung':
        return 'mt';
      case 'bac':
        return 'mb';
    }
  }
  return null;
}

/// The region the recognised headers belong to: the one most columns name a station of (null when none does).
String? regionFromColumns(List<OcrColumn> columns, LotteryStations stations) {
  final votes = <String, int>{};
  for (final c in columns) {
    final st = c.station;
    if (st == null) continue;
    final r = stations.regionOf(st).id;
    if (r != 'mb') votes[r] = (votes[r] ?? 0) + 1;
  }
  if (votes.isEmpty) return null;
  return (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/// The photo has no readable date: the latest day, today or up to 6 days before [fromIso], on which every station in [ids]
/// draws (so the right stations come up for the table). Null when there is none or fewer than 2 stations are known.
String? inferDateFromStations(String regionId, Iterable<String> ids, String fromIso, LotteryStations stations) {
  final want = ids.toSet();
  if (want.length < 2) return null;
  final base = DateTime.tryParse(fromIso);
  if (base == null) return null;
  final start = DateTime.utc(base.year, base.month, base.day);
  for (var back = 0; back <= 6; back++) {
    final d = start.subtract(Duration(days: back));
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (stations.stationsOn(regionId, iso).toSet().containsAll(want)) return iso;
  }
  return null;
}

String? _regionFromTitleWords(List<OcrWord> words) {
  if (words.isEmpty) return null;
  final top = words.map((w) => w.y0).reduce(math.min), bottom = words.map((w) => w.y1).reduce(math.max);
  final limit = top + (bottom - top) * 0.25;
  for (final w in words) {
    if (w.cy > limit) continue;
    switch (w.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
      case 'xsmt':
        return 'mt';
      case 'xsmn':
        return 'mn';
      case 'xsmb':
        return 'mb';
    }
  }
  return null;
}

/// Miền Bắc photo: sorts the all-digit words of the recognised text into the 27 boxes (port of applyLrOcrGuess).
/// [form] holds tier -> numbers ('' = empty) and only EMPTY boxes are filled. 5-digit words in reading order are
/// đặc biệt, nhất, nhì (2), ba (6); 4-digit tư (4), năm (6); 3-digit sáu (3); 2-digit bảy (4).
/// Digit-only words grouped into table ROWS (top to bottom), each row left to right.
List<List<OcrWord>> _digitRows(List<OcrWord> words) {
  final digits = words.where((w) => RegExp(r'^\d+$').hasMatch(w.text.trim())).toList();
  if (digits.isEmpty) return [];
  final heights = digits.map((w) => w.y1 - w.y0).toList()..sort();
  final tol = math.max(4.0, heights[heights.length ~/ 2] * 0.6);
  digits.sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<OcrWord>>[];
  var rowCy = 0.0;
  for (final w in digits) {
    if (rows.isEmpty || w.cy - rowCy > tol) {
      rows.add([w]);
      rowCy = w.cy;
    } else {
      rows.last.add(w);
      rowCy = rows.last.map((x) => x.cy).reduce((a, b) => a + b) / rows.last.length;
    }
  }
  for (final r in rows) {
    r.sort((a, b) => a.cx.compareTo(b.cx));
  }
  return rows;
}

/// The digit-only words of a photo in TABLE reading order: top to bottom by row, left to right inside a row. ML Kit's own
/// text order follows its text blocks (often column by column), which scatters one prize over several; using the positions
/// keeps every row together, so "Giải nhì 21143 52941" and the two lines of "Giải ba" come out in the printed order.
///
/// Rows ABOVE the first row holding a 5-digit number (the đặc biệt) are dropped: they are the title / date ("18 10 2026"),
/// whose digits would otherwise take the first slots of giải tư / giải bảy.
String orderedDigitText(List<OcrWord> words) {
  final rows = _digitRows(words);
  final first = rows.indexWhere((r) => r.any((w) => w.text.trim().length == 5));
  return [for (final r in (first > 0 ? rows.sublist(first) : rows)) ...r.map((w) => w.text.trim())].join(' ');
}

/// A photo can reach the reader turned (a phone held sideways or upside down): then "top to bottom" runs the other way,
/// which shows up as the table being read right to left / bottom to top. This tries the four turns of the picture and keeps
/// the one where the table looks like a result table: the numbers get SHORTER going down in Miền Bắc (đặc biệt 5 digits
/// ... giải bảy 2 digits) and LONGER going down in Miền Nam / Miền Trung (giải tám 2 digits ... đặc biệt 6 digits).
/// Returns the words with their positions turned upright (the same words when the photo is already upright).
List<OcrWord> uprightWords(List<OcrWord> words, {required bool lengthsDecreaseDownward}) {
  OcrWord t(OcrWord w, int k) {
    // k quarter turns: 0 = as is, 1 = (x, y) -> (-y, x), 2 = (-x, -y), 3 = (y, -x). Boxes are re-made around the new centre.
    final hw = (w.x1 - w.x0) / 2, hh = (w.y1 - w.y0) / 2;
    final cx = w.cx, cy = w.cy;
    final (nx, ny, nhw, nhh) = switch (k) {
      1 => (-cy, cx, hh, hw),
      2 => (-cx, -cy, hw, hh),
      3 => (cy, -cx, hh, hw),
      _ => (cx, cy, hw, hh),
    };
    return OcrWord(w.text, nx - nhw, ny - nhh, nx + nhw, ny + nhh);
  }

  double score(List<OcrWord> ws) {
    // correlation between the row number and the length of the numbers in it (2-6 digit prizes only)
    final rows = _digitRows(ws);
    final xs = <double>[], ys = <double>[];
    for (var r = 0; r < rows.length; r++) {
      for (final w in rows[r]) {
        final n = w.text.trim().length;
        if (n >= 2 && n <= 6) {
          xs.add(r.toDouble());
          ys.add(n.toDouble());
        }
      }
    }
    if (rows.length < 4 || xs.length < 8) return 0;
    final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < xs.length; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
      syy += (ys[i] - my) * (ys[i] - my);
    }
    if (sxx == 0 || syy == 0) return 0;
    final corr = sxy / math.sqrt(sxx * syy);
    return lengthsDecreaseDownward ? -corr : corr;
  }

  var best = 0;
  var bestScore = score(words);
  for (var k = 1; k < 4; k++) {
    final sc = score([for (final w in words) t(w, k)]);
    // a turn must be clearly better than the picture as it is, so a normal photo is never turned by noise
    if (sc > bestScore + 0.25) {
      best = k;
      bestScore = sc;
    }
  }
  return best == 0 ? words : [for (final w in words) t(w, best)];
}

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
