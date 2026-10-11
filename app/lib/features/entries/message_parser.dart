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

ParseResult parseMessage(String? text, {List<String> betTypes = const ['de', 'lo'], SyntaxTemplate? template}) {
  final cfg = template ?? SyntaxTemplate();
  final markers = (cfg.stakeMarkers.isNotEmpty ? cfg.stakeMarkers : defaultStakeMarkers).map(foldText).toList();

  // alias (folded) -> type key; later sources win: built-in < bet types < template
  final aliasMap = <String, String>{..._builtinAliases};
  for (final t in betTypes) {
    aliasMap[foldText(t)] = t;
  }
  for (final e in cfg.typeAliases.entries) {
    aliasMap[foldText(e.key)] = e.value;
  }
  final aliasKeys = aliasMap.keys.where((k) => k.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  final aliasRe = aliasKeys.isEmpty ? null : RegExp('(?<![a-z0-9])(${aliasKeys.map(_escapeRe).join('|')})(?![a-z0-9])');
  final stakeRe = RegExp('^(.*?)(?:${markers.map(_escapeRe).join('|')})\\s*(\\d+(?:[.,]\\d+)?)\\s*(?:diem|d)?\\s*\$');

  final rows = <ParsedRow>[];
  final ignored = <String>[];
  var stickyType = '';

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
