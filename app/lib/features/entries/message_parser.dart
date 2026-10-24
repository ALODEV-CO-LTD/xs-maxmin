// Parses a pasted chat message ("Nhập từ tin nhắn") into candidate entry rows. Port of frontend/src/messageParser.js.
// Pure functions: nothing is saved here, the UI shows the result as a preview and the user confirms.
//
// Layout understood (one or more per line, case/diacritic-insensitive):
//   [hạng mục]  số số số  [dấu điểm]  điểm
//   de 12 34 56 x 10   -> three "Đề" rows, 10 điểm each
//   12=50              -> one row (type = sticky/default type, flagged if unknown)
//   de: / lo           -> a line holding only a hạng mục sets the type for the lines below
// Per-customer template: {defaultType, typeAliases: {dd: 'de'}, stakeMarkers: ['x', 'con']}

const defaultStakeMarkers = ['x', '×', '*', 'con', '=', 'diem'];

const _builtinAliases = {'de': 'de', 'dde': 'de', 'lo': 'lo'};

const _from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

final Map<int, String> _foldMap = () {
  assert(_from.runes.length == _to.length);
  final m = <int, String>{};
  final f = _from.runes.toList();
  for (var i = 0; i < f.length; i++) {
    m[f[i]] = _to[i];
  }
  return m;
}();

/// Lower case + strip Vietnamese diacritics (đ -> d). Same idea as fold() in the web app.
String foldText(String? s) {
  if (s == null || s.isEmpty) return '';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r >= 0x300 && r <= 0x36F) continue; // combining accent of a decomposed letter
    b.write(_foldMap[r] ?? String.fromCharCode(r));
  }
  return b.toString();
}

String _escapeRe(String s) => s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

/// Per-customer syntax template, stored with `POST /me/syntax-templates`.
class SyntaxTemplate {
  SyntaxTemplate({this.defaultType = '', Map<String, String>? typeAliases, List<String>? stakeMarkers})
      : typeAliases = typeAliases ?? {},
        stakeMarkers = stakeMarkers ?? [...defaultStakeMarkers];

  String defaultType;
  Map<String, String> typeAliases;
  List<String> stakeMarkers;

  factory SyntaxTemplate.fromJson(Object? j) {
    if (j is! Map) return SyntaxTemplate();
    final aliases = <String, String>{};
    final raw = j['typeAliases'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is String) aliases['${e.key}'] = e.value as String;
      }
    }
    final markers = j['stakeMarkers'] is List ? [for (final m in j['stakeMarkers'] as List) '$m'] : <String>[];
    return SyntaxTemplate(
      defaultType: (j['defaultType'] as String?) ?? '',
      typeAliases: aliases,
      stakeMarkers: markers.isEmpty ? null : markers,
    );
  }

  Map<String, dynamic> toJson() => {'defaultType': defaultType, 'typeAliases': typeAliases, 'stakeMarkers': stakeMarkers};
}

/// "dd=de, l=lo" <-> {dd: 'de', l: 'lo'} (the template editor).
String aliasesToText(Map<String, String>? aliases) => (aliases ?? const {}).entries.map((e) => '${e.key}=${e.value}').join(', ');

Map<String, String> textToAliases(String? text, [List<String>? validTypes]) {
  final out = <String, String>{};
  for (final part in (text ?? '').split(RegExp(r'[,;\n]'))) {
    final kv = part.split('=').map((x) => x.trim()).toList();
    if (kv.length < 2) continue;
    final a = kv[0], t = kv[1];
    if (a.isNotEmpty && t.isNotEmpty && (validTypes == null || validTypes.contains(t))) out[foldText(a)] = t;
  }
  return out;
}

/// "x, con =" -> ['x', 'con', '=']
List<String> textToMarkers(String? text) => (text ?? '').split(RegExp(r'[,;\s]+')).map((m) => m.trim()).where((m) => m.isNotEmpty).toList();

class ParsedRow {
  ParsedRow({required this.type, required this.value, required this.score, required this.raw, required this.reasons});
  String type;
  String value;
  String score;
  final String raw;
  final List<String> reasons;
  bool get uncertain => reasons.isNotEmpty;
  @override
  String toString() => '$type:$value:$score${uncertain ? '?' : ''}';
}

class ParseResult {
  ParseResult(this.rows, this.ignored);
  final List<ParsedRow> rows;
  final List<String> ignored;
}

// ---- Compact ("liền") notation: number + symbol + điểm, no spaces ------------------------------
const _pointsRe = r'(\d+(?:\.\d+|,\d{1,2})?)'; // a decimal comma has 1-2 digits; "1,500" is not a decimal
final _commaSeparator = RegExp(r'(?<=[^\d.,]\d+),(?=\d{2,4}[^\d.,\s])');
const _bareX =['x', '×']; // as a symbol = bao lô; the legacy parser reads it as "× điểm" with the customer's type
const _typeLabel = {'lo': 'Lô', 'dau': 'Đầu', 'duoi': 'Đuôi', 'cang3': '3 càng', 'cang4': '4 càng', 'xien2': 'Xiên 2', 'xien3': 'Xiên 3', 'xien4': 'Xiên 4'};
const _canonSymbol = {'lo': 'lô', 'dau': 'đầu', 'duoi': 'đuôi', 'cang': 'càng', 'xien': 'xiên'};
String typeLabel(String t) => _typeLabel[t] ?? t;

class _Sym {
  const _Sym(this.kind, [this.type]);
  final String kind;
  final String? type;
}

class _Compact {
  _Compact(this.rows, this.canon);
  final List<ParsedRow> rows;
  final String canon;
}

/// folded symbol -> kind. Built-ins first, then the customer's ký hiệu from the bảng cấu hình, then spelled bet types, then
/// the customer's own aliases (they win, like everywhere else in this file).
Map<String, _Sym> _compactSymbols(Map<String, String> aliasMap, SyntaxTemplate cfg, Map<String, List<String>>? kindSymbols) {
  final m = <String, _Sym>{};
  for (final s in const ['lo', 'l', 'x', '×']) {
    m[s] = const _Sym('lo');
  }
  for (final s in const ['d', 'dau']) {
    m[s] = const _Sym('dau');
  }
  for (final s in const ['c', 'cuoi', 'duoi']) {
    m[s] = const _Sym('duoi');
  }
  final plain = RegExp(r'^[a-z×]+$');
  for (final e in (kindSymbols ?? const <String, List<String>>{}).entries) {
    for (final sym in e.value) {
      final k = foldText(sym);
      if (plain.hasMatch(k)) m[k] = _Sym(e.key);
    }
  }
  m['cang'] = const _Sym('cang');
  m['xien'] = const _Sym('xien');
  final az = RegExp(r'^[a-z]+$');
  for (final e in aliasMap.entries) {
    if (az.hasMatch(e.key) && !m.containsKey(e.key)) m[e.key] = _Sym('custom', e.value);
  }
  for (final e in cfg.typeAliases.entries) {
    final k = foldText(e.key);
    if (plain.hasMatch(k)) m[k] = e.value == 'lo' ? const _Sym('lo') : _Sym('custom', e.value);
  }
  return m;
}

/// Returns compact(token, ctxType) for one FOLDED whitespace-free token; null = "not compact notation" (the caller falls back to
/// the legacy parser, so nothing that worked before changes).
_Compact? Function(String, [String]) _makeCompactParser(Map<String, _Sym> symbols, List<String> betTypes) {
  String alt(bool Function(_Sym, String) pred) {
    final keys = [for (final e in symbols.entries) if (pred(e.value, e.key)) e.key]..sort((a, b) => b.length.compareTo(a.length));
    return keys.map(_escapeRe).join('|');
  }

  final all = alt((_, _) => true);
  final allNoX = alt((_, k) => !_bareX.contains(k)); // "20.02x10" stays with the legacy reading (x = × điểm)
  final lo = alt((v, _) => v.kind == 'lo');
  final reXien = lo.isNotEmpty ? RegExp('^(\\d{2}(?:(?:[.,]|$lo)\\d{2}){1,})($lo|xien)$_pointsRe\$') : null;
  final reDouble = RegExp('^(\\d+)($all)$_pointsRe($all)$_pointsRe\$');
  // "22.67lo10" / "81.24.69lo10": several numbers of one length joined by dots (or commas), one symbol and one điểm for all.
  final reList = RegExp('^(\\d{2,4}(?:[.,]\\d{2,4})+)($allNoX)$_pointsRe\$');
  final reListDouble = RegExp('^(\\d{2,4}(?:[.,]\\d{2,4})+)($allNoX)$_pointsRe($allNoX)$_pointsRe\$');
  final reSingle = RegExp('^(\\d+)($all)$_pointsRe\$');
  bool has(String t) => betTypes.contains(t);

  ({ParsedRow row, String canon})? one(String value, String sym, String points, String ctxType) {
    final info = symbols[sym]!;
    final digits = value.length;
    String type;
    String canonSym;
    switch (info.kind) {
      case 'lo':
        if (_bareX.contains(sym) && digits == 2 && ctxType.isNotEmpty) {
          type = ctxType;
          canonSym = sym;
        } else if (digits == 3) {
          type = 'cang3';
          canonSym = _canonSymbol['cang']!;
        } else if (digits == 4) {
          type = 'cang4';
          canonSym = _canonSymbol['cang']!;
        } else {
          type = 'lo';
          canonSym = _canonSymbol['lo']!;
        }
      case 'dau':
        type = 'dau';
        canonSym = _canonSymbol['dau']!;
      case 'duoi':
        // "Đuôi" = the last two digits of the special prize, which is exactly what the account's Đề already is.
        type = has('duoi') ? 'duoi' : (has('de') ? 'de' : 'duoi');
        canonSym = _canonSymbol['duoi']!;
      case 'cang':
        type = digits == 4 ? 'cang4' : 'cang3';
        canonSym = _canonSymbol['cang']!;
      case 'xien':
        return null; // a single number cannot be a xiên
      default:
        type = info.type!;
        canonSym = sym;
    }
    final reasons = <String>[];
    if (!has(type)) reasons.add('Loại "${typeLabel(type)}" chưa có trong cấu hình');
    final want = type == 'cang3' ? 3 : (type == 'cang4' ? 4 : 2);
    if (digits != want) reasons.add('Số không phải $want chữ số');
    return (row: ParsedRow(type: type, value: value, score: points.replaceFirst(',', '.'), raw: '', reasons: reasons), canon: '$value$canonSym$points');
  }

  return (String tok, [String ctxType = '']) {
    var m = reXien?.firstMatch(tok);
    if (m != null) {
      final nums = RegExp(r'\d{2}').allMatches(m.group(1)!).map((x) => x.group(0)!).toList();
      // "22.67lo10" (numbers joined by dots, then a spelled lô symbol and điểm) is a xiên: 2 numbers = xiên 2, 3 = xiên 3, 4 = xiên 4.
      // More than 4 numbers is not a xiên the system knows: it is kept as one flagged row for the user to check.
      final dotsOnly = !RegExp(r'[a-z×]').hasMatch(m.group(1)!);
      final spelledLo = dotsOnly && !_bareX.contains(m.group(2)) && symbols[m.group(2)]?.kind == 'lo';
      final type = 'xien${nums.length}';
      // "20.02x10" is also how some customers list several plain numbers, so it only means xiên when the account has that
      // Xiên type; "20x02lo10" / "20.02xiên10" cannot mean anything else.
      if (spelledLo || !(dotsOnly && m.group(2) != 'xien' && !has(type))) {
        final reasons = [
          if (nums.length > 4) 'Xiên ${nums.length} số: hệ thống chỉ có xiên 2, 3, 4, hãy kiểm tra',
          if (!has(type)) 'Loại "${typeLabel(type)}" chưa có trong cấu hình',
        ];
        return _Compact(
          [ParsedRow(type: type, value: nums.join(' '), score: m.group(3)!.replaceFirst(',', '.'), raw: '', reasons: reasons)],
          '${nums.join('.')}${_canonSymbol['xien']}${m.group(3)}',
        );
      }
    }
    m = reListDouble.firstMatch(tok);
    if (m != null) {
      final nums = m.group(1)!.split(RegExp(r'[.,]'));
      // (a lô symbol after several 2-digit numbers is a xiên, handled above: no list of numbers with two symbols)
      if (nums.every((n) => n.length == nums.first.length) && !(nums.first.length == 2 && [m.group(2), m.group(4)].any((x) => symbols[x]?.kind == 'lo'))) {
        final made = [for (final n in nums) ...[one(n, m.group(2)!, m.group(3)!, ctxType), one(n, m.group(4)!, m.group(5)!, ctxType)]];
        if (made.every((x) => x != null)) return _Compact([for (final x in made) x!.row], made.map((x) => x!.canon).join(' '));
      }
    }
    m = reList.firstMatch(tok);
    if (m != null) {
      final nums = m.group(1)!.split(RegExp(r'[.,]'));
      if (nums.every((n) => n.length == nums.first.length)) {
        final made = [for (final n in nums) one(n, m.group(2)!, m.group(3)!, ctxType)];
        if (made.every((x) => x != null)) return _Compact([for (final x in made) x!.row], made.map((x) => x!.canon).join(' '));
      }
    }
    m = reDouble.firstMatch(tok);
    if (m != null) {
      final a = one(m.group(1)!, m.group(2)!, m.group(3)!, ctxType);
      final b = one(m.group(1)!, m.group(4)!, m.group(5)!, ctxType);
      if (a != null && b != null) return _Compact([a.row, b.row], '${a.canon} ${b.canon}');
    }
    m = reSingle.firstMatch(tok);
    if (m != null) {
      final a = one(m.group(1)!, m.group(2)!, m.group(3)!, ctxType);
      if (a != null) return _Compact([a.row], a.canon);
    }
    return null;
  };
}

/// Loosely written compact notation -> the strict spelling the matchers read: groups divided by ; / | or " - ", numbers of one
/// group divided by spaces, dots, commas or dashes, the symbol / điểm separated by spaces or followed by "điểm".
/// "22 67 lo 10; 50-65 lô 20" -> "22.67lo10 50.65lo20". Bare x / × is left alone (the legacy parser owns "× điểm").
String Function(String) _makeNormalizer(Map<String, _Sym> symbols) {
  final keys = [for (final k in symbols.keys) if (!_bareX.contains(k)) k]..sort((a, b) => b.length.compareTo(a.length));
  if (keys.isEmpty) return (f) => f;
  final symAlt = keys.map(_escapeRe).join('|');
  final reGroup = RegExp('(?<![\\d.,])((?:\\d{2,4}[ .,\\-]+)*\\d{2,4})\\s*($symAlt)\\s*(\\d+(?:[.,]\\d+)?)(?:\\s*diem)?(?![\\d])');
  // "22.67lo10 de5" / "22.67lo10de5": the second symbol re-uses the numbers in front of the first.
  final reAttach = RegExp('((?:\\d{2,4}\\.)*\\d{2,4})($symAlt)(\\d+(?:[.,]\\d+)?)\\s*($symAlt)(\\d+(?:[.,]\\d+)?)(?![\\d.,]|\\s*[a-z])');
  return (f) => f
      .replaceAll(RegExp(r'\s*[;|/]\s*|\s+-\s+'), ' ')
      .replaceAllMapped(reGroup, (m) => '${m.group(1)!.split(RegExp(r'[ .,-]+')).join('.')}${m.group(2)}${m.group(3)}')
      .replaceAllMapped(reAttach, (m) => '${m.group(1)}${m.group(2)}${m.group(3)}${m.group(4)}${m.group(5)}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

ParsedRow _withRaw(ParsedRow r, String raw) => ParsedRow(type: r.type, value: r.value, score: r.score, raw: raw, reasons: r.reasons);

Map<String, String> _aliasMapFor(List<String> betTypes, SyntaxTemplate cfg) {
  final aliasMap = <String, String>{..._builtinAliases};
  for (final t in betTypes) {
    aliasMap[foldText(t)] = t;
  }
  for (final e in cfg.typeAliases.entries) {
    aliasMap[foldText(e.key)] = e.value;
  }
  return aliasMap;
}

class DecodedPart {
  DecodedPart(this.text, this.decoded, this.status);
  final String text;
  final String decoded;
  /// space | plain | unknown | same | changed
  final String status;
}

class DecodedLine {
  DecodedLine(this.original, this.parts);
  final String original;
  final List<DecodedPart> parts;
  String get decoded => parts.map((p) => p.decoded).join();
  bool get changed => parts.any((p) => p.status == 'changed');
  bool get unknown => parts.any((p) => p.status == 'unknown');
}

/// Side-by-side check ("Đối chiếu"): each compact token in its canonical spelling next to the original. Never changes a
/// number, never guesses: a token that is not compact notation is kept exactly as typed. Whitespace is preserved.
List<DecodedLine> decodeMessage(String? text, {List<String> betTypes = const ['de', 'lo'], SyntaxTemplate? template, Map<String, List<String>>? kindSymbols}) {
  final cfg = template ?? SyntaxTemplate();
  final aliasMap = _aliasMapFor(betTypes, cfg);
  final compact = _makeCompactParser(_compactSymbols(aliasMap, cfg, kindSymbols), betTypes);
  // The hạng mục written before a token ("de 44x20", or "de:" on the line above) is the type a bare "x" stands for, exactly like
  // parseMessage reads it: "44x20" after "de" is Đề 44 x 20 điểm, not a bao lô.
  var stickyType = '';
  return (text ?? '').split(RegExp(r'\r?\n')).map((original) {
    // split(/(\s+)/) keeps the separators; JS `\s` ~ Dart `\s` plus a few unicode spaces, close enough for chat text
    final pieces = <String>[];
    var last = 0;
    for (final m in RegExp(r'\s+').allMatches(original)) {
      if (m.start > last) pieces.add(original.substring(last, m.start));
      pieces.add(m.group(0)!);
      last = m.end;
    }
    if (last < original.length) pieces.add(original.substring(last));
    final parts = pieces.map((tok) {
      if (RegExp(r'^\s+$').hasMatch(tok)) return DecodedPart(tok, tok, 'space');
      final f = foldText(tok);
      final key = f.replaceAll(RegExp(r'[:.\-–]+$'), '');
      if (aliasMap.containsKey(key)) {
        stickyType = aliasMap[key]!; // a hạng mục keyword: remembered for the tokens after it, shown as typed
        return DecodedPart(tok, tok, 'plain');
      }
      final p = compact(f, stickyType.isNotEmpty ? stickyType : cfg.defaultType);
      if (p == null) return DecodedPart(tok, tok, RegExp(r'\d').hasMatch(tok) ? 'unknown' : 'plain');
      return DecodedPart(tok, p.canon, p.canon == tok ? 'same' : 'changed');
    }).toList();
    // "de 44 x20" is not compact notation (nothing to rewrite) but parseMessage reads it without any doubt: such a line is not
    // flagged "chưa nhận ra". Only a line the parser cannot read cleanly (unclear type, odd characters, no score...) stays flagged.
    if (parts.any((x) => x.status == 'unknown')) {
      final read = parseMessage(
        original,
        betTypes: betTypes,
        kindSymbols: kindSymbols,
        template: SyntaxTemplate(defaultType: stickyType.isNotEmpty ? stickyType : cfg.defaultType, typeAliases: cfg.typeAliases, stakeMarkers: cfg.stakeMarkers),
      );
      if (read.rows.isNotEmpty && read.ignored.isEmpty && read.rows.every((r) => !r.uncertain)) {
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].status == 'unknown') parts[i] = DecodedPart(parts[i].text, parts[i].decoded, 'plain');
        }
      }
    }
    return DecodedLine(original, parts);
  }).toList();
}

ParseResult parseMessage(String? text, {List<String> betTypes = const ['de', 'lo'], SyntaxTemplate? template, Map<String, List<String>>? kindSymbols}) {
  final cfg = template ?? SyntaxTemplate();
  final markers = (cfg.stakeMarkers.isNotEmpty ? cfg.stakeMarkers : defaultStakeMarkers).map(foldText).toList();

  // alias (folded) -> type key; later sources win: built-in < bet types < template
  final aliasMap = _aliasMapFor(betTypes, cfg);
  final aliasKeys = aliasMap.keys.where((k) => k.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  final aliasRe = aliasKeys.isEmpty ? null : RegExp('(?<![a-z0-9])(${aliasKeys.map(_escapeRe).join('|')})(?![a-z0-9])');
  final groupRe = RegExp('(\\d[\\d\\s,.;\\-/]*?)\\s*(?:${markers.map(_escapeRe).join('|')})\\s*(\\d+(?:[.,]\\d+)?)(?:\\s*(?:diem|d)(?![a-z0-9]))?');
  final stakeRe = RegExp('^(.*?)(?:${markers.map(_escapeRe).join('|')})\\s*(\\d+(?:[.,]\\d+)?)\\s*(?:diem|d)?\\s*\$');

  final rows = <ParsedRow>[];
  final ignored = <String>[];
  var stickyType = '';
  final symbols = _compactSymbols(aliasMap, cfg, kindSymbols);
  final compact = _makeCompactParser(symbols, betTypes);
  final normalize = _makeNormalizer(symbols);

  void push(String type, bool assumed, String value, String score, String raw, [List<String> extra = const []]) {
    final reasons = [...extra];
    if (assumed) reasons.add('Chưa rõ hạng mục, tạm dùng mặc định');
    if (score.isEmpty) reasons.add('Chưa có điểm');
    if (!RegExp(r'^\d{2}$').hasMatch(value)) reasons.add('Số không phải 2 chữ số');
    rows.add(ParsedRow(type: type, value: value, score: score, raw: raw, reasons: reasons));
  }

  for (final rawLine in (text ?? '').split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final f = foldText(line);

    // Compact notation: only when EVERY space-separated token of the line is one ("20lo100 70lo500 54lo300").
    // A line that mixes in anything else goes through the legacy path below, exactly as before.
    // "20lo100,70lo500": a comma between a điểm and the next number group is a separator, not a decimal point.
    var toks = [for (final t in f.split(RegExp(r'\s+'))) ...t.split(_commaSeparator)].where((t) => t.isNotEmpty).toList();
    final ctxType = stickyType.isNotEmpty ? stickyType : cfg.defaultType;
    var parsed = [for (final t in toks) compact(t, ctxType)];
    if (!parsed.every((p) => p != null)) {
      // The same line written loosely ("22 67 lo 10", "22-67 lô10; 50.65 lo20"): tidy it and try again.
      final tidy = normalize(f).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      final again = [for (final t in tidy) compact(t, ctxType)];
      if (tidy.isNotEmpty && again.every((p) => p != null)) {
        toks = tidy;
        parsed = again;
      }
    }
    if (toks.isNotEmpty && parsed.every((p) => p != null)) {
      for (final p in parsed) {
        for (final r in p!.rows) {
          rows.add(_withRaw(r, line));
        }
      }
      continue;
    }

    // split the line into [type, text] segments at every hạng mục keyword
    final segments = <({String? type, String text})>[];
    var last = 0;
    String? curType;
    if (aliasRe != null) {
      for (final m in aliasRe.allMatches(f)) {
        final before = f.substring(last, m.start);
        if (before.trim().isNotEmpty || curType != null) segments.add((type: curType, text: before));
        curType = aliasMap[m.group(1)!];
        last = m.end;
      }
    }
    segments.add((type: curType, text: f.substring(last)));

    var produced = false;
    for (final seg in segments) {
      final body = seg.text.replaceAll(RegExp(r'^[\s:.\-–]+|[\s:.\-–]+$'), '');
      if (!RegExp(r'\d').hasMatch(body)) {
        // keyword only ("de:", "lo") -> remember it for the following lines
        if (seg.type != null && body.isEmpty) {
          stickyType = seg.type!;
          produced = true;
        }
        continue;
      }
      if (seg.type != null) stickyType = seg.type!;
      final type = seg.type ?? (stickyType.isNotEmpty ? stickyType : (cfg.defaultType.isNotEmpty ? cfg.defaultType : (betTypes.isNotEmpty ? betTypes.first : 'de')));
      final assumed = seg.type == null && stickyType.isEmpty && cfg.defaultType.isEmpty;

      final groups = groupRe.allMatches(body).toList();
      if (groups.length > 1 && body.replaceAll(groupRe, '').replaceAll(RegExp(r'[\s,;.\-/]'), '').isEmpty) {
        for (final g in groups) {
          for (final n in RegExp(r'\d+').allMatches(g.group(1)!)) {
            push(type, assumed, n.group(0)!, g.group(2)!.replaceFirst(',', '.'), line);
          }
        }
        produced = true;
        continue;
      }

      var left = body;
      var score = '';
      final m = stakeRe.firstMatch(body);
      if (m != null) {
        left = m.group(1)!;
        score = m.group(2)!.replaceFirst(',', '.');
      }
      final extra = <String>[];
      if (RegExp(r'[^\d\s,.;\-/]').hasMatch(left)) extra.add('Có ký tự lạ trong phần số');
      final numbers = RegExp(r'\d+').allMatches(left).map((x) => x.group(0)!).toList();
      if (numbers.isEmpty) {
        push(type, assumed, '', score, line, ['Không đọc được số']);
      } else {
        for (final n in numbers) {
          push(type, assumed, n, score, line, extra);
        }
      }
      produced = true;
    }
    if (!produced) ignored.add(line);
  }
  return ParseResult(rows, ignored);
}
