// The editing logic of "Cấu hình tính điểm" = the "bảng cấu hình" (port of the script part of
// frontend/src/components/ScoringConfigEditor.vue), kept free of widgets so it can be unit tested.
//
// One row per kiểu đánh: Kiểu đánh | Ký hiệu | Giá tiền / 1 điểm | Giá trúng / 1 điểm, per region.
// Data semantics (the same as the web editor):
//  - one map: `type` = applies to every region, `type@mb|mt|mn` = that region only (wins over `type`);
//  - a customer's map may hold `{disabled: true}` for a type the customer does not use (in every region, or just one);
//  - a row you do not change keeps following the general value; changing it in a region tab makes it a region-only value;
//  - the standard kinds (lo, dau, duoi, cang3, cang4, xien2/3/4) have a fixed matching rule; "Kiểu đánh khác" rows are
//    kind 'custom' (their own name + ký hiệu, compared with the special prize or every prize, last 2/3/4 digits).
import 'dart:convert';

import '../../core/bet_types.dart';
import '../../core/scoring_config.dart';
import '../entries/message_parser.dart' show foldText;

const regionNames = {'mb': 'Miền Bắc', 'mt': 'Miền Trung', 'mn': 'Miền Nam'};
const editorRegions = regionIds;

/// One line of the active region tab.
class EditorRow {
  EditorRow({
    required this.type,
    required this.kind,
    required this.group,
    required this.label,
    required this.symbols,
    required this.price,
    required this.payout,
    required this.tiers,
    required this.digits,
    required this.name,
    this.srcTiers = const [],
    this.srcPos = 'last',
    this.srcDigits = 2,
    this.srcPick = '',
    required this.off,
    required this.extra,
    this.editable = false,
    this.symbolsInput = '',
  });
  final String type;
  final String kind;

  /// Id of its group in [tableGroups] ('other' for the custom / older rows).
  final String group;
  final String label;
  final String symbols;
  String price;
  String payout;
  final List<String> tiers;

  final int digits;
  String name;

  /// The "lấy số" as edited ("Chỉnh lấy số"): prizes, end of the number ('last' | 'first'), digits, and the lô of each prize as
  /// text ("1, 2").
  List<String> srcTiers;
  String srcPos;
  int srcDigits;
  String srcPick;
  bool srcOpen = false;

  /// Switched off for this customer (in this region).
  final bool off;

  /// A "Kiểu đánh khác" row (not one of the standard kinds).
  final bool extra;

  /// lo / dau / duoi: the ký hiệu can be edited, as text (separated by commas / spaces).
  final bool editable;
  String symbolsInput;

  /// What the row shows as its ký hiệu: the typed list (else the built-in one) for an editable row.
  String get symbolText {
    if (!editable) return symbols;
    final list = parseSymbols(symbolsInput);
    return symbolsText(list.isNotEmpty ? list : defaultSymbols(type));
  }
}

/// Text of a number without a pointless ".0" (70.0 -> "70").
String numText(num? n) {
  if (n == null) return '';
  if (n is double && n.isFinite && n == n.roundToDouble()) return n.toInt().toString();
  return '$n';
}

num? parseNum(String s) {
  final n = num.tryParse(s.trim().replaceAll(',', '.'));
  return n != null && n.isFinite ? n : null;
}

dynamic _norm(dynamic v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _norm(v[k])};
  }
  if (v is List) return [for (final x in v) _norm(x)];
  if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
  return v;
}

/// Canonical text of a rates map, to compare "changed?" (key order, tier order and 70 vs 70.0 do not matter).
String snapshotOf(RatesMap m) {
  final copy = <String, dynamic>{};
  for (final e in m.entries) {
    final v = e.value;
    if (v is Map && v['disabled'] == true) {
      copy[e.key] = {'disabled': true};
    } else if (v is Map) {
      copy[e.key] = {...v, 'tiers': [for (final t in (v['tiers'] as List? ?? const [])) '$t']..sort()};
    }
  }
  return jsonEncode(_norm(copy));
}

/// The symbol of a "Kiểu đánh khác": a-z / 0-9, at most 12 characters.
final _symbolPattern = RegExp(r'^[a-z0-9]{1,12}$');

final _symbolLetters = RegExp(r'^[\p{L}×]{1,12}$', unicode: true);

const _everyPrize = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'];

class ScoringEditorModel {
  /// [isCustomer]: a customer's own overrides (falling back to [accountRates]); otherwise the account-wide default.
  ScoringEditorModel({required this.isCustomer, RatesMap? accountRates}) : accountRates = accountRates ?? <String, dynamic>{};

  final bool isCustomer;

  /// Customer scope: the account-wide map (the fallback). Account scope: unused.
  RatesMap accountRates;

  final RatesMap work = {};
  String region = 'mb';
  final List<EditorRow> rows = [];

  /// Bumped whenever the rows are rebuilt, so the UI re-creates its text fields.
  int version = 0;
  String _initial = '';

  RatesMap get _base => isCustomer ? accountRates : const <String, dynamic>{};

  static bool _disabled(dynamic v) => v is Map && v['disabled'] == true;
  static Map? _cfg(dynamic v) => v is Map && v['disabled'] != true ? v : null;

  /// [setInitial] false = just replace what is on screen (reset): the saved state stays the baseline for "changed?".
  void load(RatesMap? map, {bool setInitial = true}) {
    work.clear();
    for (final e in (map ?? const {}).entries) {
      final v = e.value;
      if (v is! Map) continue;
      work[e.key] = _disabled(v) ? {'disabled': true} : Map<String, dynamic>.from(jsonDecode(jsonEncode(v)) as Map);
    }
    if (setInitial) _initial = snapshotOf(work);
  }

  // ---- rows of the active region ------------------------------------------------------------------------------------

  /// What a row follows when it has no region-only value of its own.
  Cfg? _inheritedRow(String type) {
    if (!isCustomer) return toTableRow(type, _cfg(work[type]));
    final own = _cfg(work[type]);
    if (own != null) return toTableRow(type, own);
    return toTableRow(type, _cfg(_base[regionKey(type, region)] ?? _base[type]));
  }

  /// The row as shown: the region's own value, else what it inherits, else the built-in default of a standard kind.
  Cfg? _shownRow(String type) {
    final regional = _cfg(work[regionKey(type, region)]);
    if (regional != null) return toTableRow(type, regional);
    return _inheritedRow(type) ?? (isTableKind(type) ? defaultRow(type, region) : null);
  }

  /// Types of this region that are not a standard kind (the "Kiểu đánh khác").
  List<String> get extraTypes {
    final keys = <String>{...typesIn(work, region)};
    if (isCustomer) keys.addAll(typesIn(_base, region));
    return keys.where((k) => !isTableKind(k) && !legacyTypeAlias.containsKey(k)).toList();
  }

  /// The rows by group (empty groups left out): one group = one kiểu đánh, its rows = the cách đánh.
  /// [all]: also the empty ones (while editing, so a cách đánh can be added to any group).
  List<({TableGroup group, List<EditorRow> rows})> groupsOf({bool all = false}) => [
        for (final g in tableGroups)
          if (all || rows.any((r) => r.group == g.id)) (group: g, rows: [for (final r in rows) if (r.group == g.id) r]),
      ];

  List<({TableGroup group, List<EditorRow> rows})> get groups => groupsOf();

  /// Every type shown in this region (standard kinds first).
  List<String> get typeKeys => [...tableKindKeys, ...extraTypes];

  /// The stored config an extra type shows: the first usable of the region's own, the shared, the account's.
  Map? _extraCfg(String type) {
    for (final src in [work[regionKey(type, region)], work[type], _base[regionKey(type, region)], _base[type]]) {
      final c = _cfg(src);
      if (c != null) return c;
    }
    return null;
  }

  /// A standard row removed from the table: by the account (default scope), or by the account for every customer.
  bool removed(String kind) {
    final rk = regionKey(kind, region);
    return (!isCustomer && _disabled(work[rk])) || _disabled(_base[rk]);
  }

  void buildRows() {
    rows.clear();
    final metas = <({String type, String group, String label, String symbols, bool extra, bool editable})>[
      for (final k in tableKinds)
        if (!removed(k.kind)) (type: k.kind, group: k.group, label: k.label, symbols: k.symbols, extra: false, editable: k.editable),
      for (final t in extraTypes)
        (
          type: t,
          group: _groupOf(_extraCfg(t)),
          label: (_extraCfg(t)?['name'] is String && (_extraCfg(t)!['name'] as String).isNotEmpty) ? _extraCfg(t)!['name'] as String : betTypeLabel(t),
          symbols: t,
          extra: true,
          editable: false,
        ),
    ];
    for (final meta in metas) {
      final cfg = _shownRow(meta.type) ?? defaultRow('lo', region);
      final off = isCustomer && (_disabled(work[meta.type]) || _disabled(work[regionKey(meta.type, region)]));
      final d = cfg['digits'];
      final src = effectiveSource(cfg, '${cfg['kind']}', region);
      rows.add(EditorRow(
        type: meta.type,
        kind: '${cfg['kind']}',
        group: meta.group,
        label: meta.label,
        symbols: meta.symbols,
        price: numText(cfg['price'] as num?),
        payout: numText(cfg['payout'] as num?),
        tiers: [for (final t in (cfg['tiers'] as List? ?? const ['dacBiet'])) '$t'],
        digits: d is num && d != 0 ? d.toInt() : 2,
        name: (cfg['name'] as String?) ?? meta.label,
        srcTiers: [for (final t in src['tiers'] as List) '$t'],
        srcPos: src['position'] as String,
        srcDigits: src['digits'] as int,
        srcPick: ((src['pick'] as List?) ?? const []).join(', '),
        off: off,
        extra: meta.extra,
        editable: meta.editable,
        symbolsInput: meta.editable ? symbolsText((cfg['symbols'] is List && (cfg['symbols'] as List).isNotEmpty) ? cfg['symbols'] as List : defaultSymbols(meta.type)) : '',
      ));
    }
    version++;
  }

  /// The ký hiệu a row stores: only when they differ from the built-in spellings.
  List<String>? _ownSymbols(EditorRow r) {
    if (!r.editable) return null;
    final list = parseSymbols(r.symbolsInput);
    return list.join(',') == defaultSymbols(r.type).join(',') ? null : list;
  }

  String _groupOf(Map? cfg) {
    final g = cfg?['group'];
    return tableGroups.any((x) => x.id == g) ? g as String : 'other';
  }

  // ---- lấy số -------------------------------------------------------------------------------------------------------

  Map<String, dynamic> srcOf(EditorRow r) => normalizeSource({
        'tiers': r.srcTiers,
        'position': r.srcPos,
        'digits': r.srcDigits,
        'pick': r.srcPick.split(RegExp(r'[,;\s]+')).where((x) => x.isNotEmpty).toList(),
      });

  /// Different from what the kind reads by default (so only then it is stored; a custom row always stores it).
  bool srcChanged(EditorRow r) => !r.extra && !sameSource(srcOf(r), defaultSource(r.type, region));

  /// The `source` a row stores: a standard row only when changed; a custom row always, except an older one (no `source`)
  /// that was not touched, which keeps following its tiers / digits.
  Map<String, dynamic>? _sourceToStore(EditorRow r) {
    if (!r.extra) return srcChanged(r) ? srcOf(r) : null;
    final stored = _extraCfg(r.type);
    if (stored != null && stored['source'] == null && sameSource(srcOf(r), effectiveSource(stored, 'custom', region))) return null;
    return srcOf(r);
  }

  String srcCaption(EditorRow r) => !r.extra && !srcChanged(r) ? kindSource(r.type, region) : describeSource(srcOf(r), region);

  SourceFields fieldsOf(EditorRow r) => sourceFields(r.extra ? 'custom' : r.type);

  void toggleTier(EditorRow r, String t) => r.srcTiers.contains(t) ? r.srcTiers.remove(t) : r.srcTiers.add(t);

  void resetSrc(EditorRow r) {
    final s = r.extra ? {'tiers': ['dacBiet'], 'position': 'last', 'digits': 2} : defaultSource(r.type, region);
    r.srcTiers = [for (final t in s['tiers'] as List) '$t'];
    r.srcPos = s['position'] as String;
    r.srcDigits = s['digits'] as int;
    r.srcPick = '';
  }

  Cfg cfgOf(EditorRow r) => makeRow(
        kind: r.extra ? 'custom' : r.type,
        price: parseNum(r.price) ?? 0,
        payout: parseNum(r.payout) ?? 0,
        tiers: [...r.tiers], // (older fields; a "lấy số" below overrides them)
        digits: r.digits,
        source: _sourceToStore(r),
        name: r.extra && r.name.trim().isNotEmpty && r.name.trim() != betTypeLabel(r.type) ? r.name.trim() : null,
        group: r.extra && r.group != 'other' ? r.group : null,
        symbols: _ownSymbols(r),
      );

  /// Writes the rows of the active region back into [work]: a row that differs from what it follows becomes a
  /// region-only value, one that equals it drops its region-only value.
  void commitRows() => _commitInto(work);

  void _commitInto(RatesMap target) {
    for (final r in rows) {
      if (r.off) continue;
      final key = regionKey(r.type, region);
      final cfg = cfgOf(r);
      final baseCfg = _inheritedRow(r.type);
      if (baseCfg != null && sameConfig(cfg, baseCfg, r.type)) {
        target.remove(key);
      } else {
        target[key] = cfg;
      }
    }
  }

  /// Returns an error text when the rows on screen are not valid (then the region is not switched).
  String switchRegion(String id) {
    final problem = validate();
    if (problem.isNotEmpty) return problem;
    commitRows();
    region = id;
    buildRows();
    return '';
  }

  bool differs(EditorRow r) {
    final baseCfg = _inheritedRow(r.type);
    return baseCfg != null && !sameConfig(cfgOf(r), baseCfg, r.type);
  }

  /// The row has a region-only value (stored or just edited).
  bool hasOwn(EditorRow r) => !r.off && (work[regionKey(r.type, region)] != null || differs(r));

  String tag(EditorRow r) {
    if (r.off) return 'Không dùng';
    if (isCustomer) return hasOwn(r) ? 'Riêng' : 'Mặc định';
    return '';
  }

  /// A standard row without a "giá trúng" yet (the doc gives none): shown as a red warning.
  bool notSet(EditorRow r) => !r.off && !r.extra && !((parseNum(r.payout) ?? 0) > 0);

  /// "Theo chung": drop this row's region-only value.
  void resetRow(EditorRow r) {
    work.remove(regionKey(r.type, region));
    buildRows();
  }

  /// The "Dùng" switch of a customer's row: off writes a disabled marker for this region, on removes it.
  void toggleOff(EditorRow r) {
    commitRows();
    if (r.off) {
      if (_disabled(work[r.type])) work.remove(r.type);
      work.remove(regionKey(r.type, region));
    } else {
      work[regionKey(r.type, region)] = {'disabled': true};
    }
    buildRows();
  }

  /// Removes a row (apply AFTER the user confirmed). A standard row is not deleted but marked removed ({disabled: true}) so it
  /// does not come back as a default; a custom row loses its keys. Nothing is saved until the user saves.
  void removeRow(EditorRow r) {
    commitRows();
    if (!r.extra) {
      work[regionKey(r.type, region)] = {'disabled': true};
    } else {
      work.removeWhere((k, _) => baseKey(k) == r.type && (k == r.type || k == regionKey(r.type, region)));
    }
    buildRows();
  }

  /// The standard rows of [group] that were removed and can be put back.
  List<TableKind> restorable(String group) =>
      [for (final k in tableKinds) if (k.group == group && removed(k.kind) && !(isCustomer && _disabled(_base[regionKey(k.kind, region)]))) k];

  /// Puts a removed standard row back (it follows what it inherits, or the built-in default).
  void restoreKind(String kind) {
    commitRows();
    work.remove(regionKey(kind, region));
    buildRows();
  }

  /// A new custom cách đánh in [group] for the active region. Returns an error text, or '' when added.
  String addCustom({String group = 'other', required String name, required String symbol, required bool allTiers, required int digits, required String price, required String payout}) {
    final sym = symbol.trim().toLowerCase();
    if (!_symbolPattern.hasMatch(sym)) return 'Ký hiệu chỉ gồm chữ không dấu hoặc số (tối đa 12 ký tự)';
    if (isTableKind(sym) || rows.any((r) => r.type == sym)) return 'Ký hiệu này đã có';
    final p = parseNum(price), w = parseNum(payout);
    if (p == null || p <= 0 || w == null || w < 0) return 'Giá tiền phải lớn hơn 0, giá trúng không âm';
    commitRows();
    work[regionKey(sym, region)] = makeRow(
      kind: 'custom',
      price: p,
      payout: w,
      source: {'tiers': allTiers ? _everyPrize : ['dacBiet'], 'position': 'last', 'digits': digits},
      name: name.trim().isEmpty ? null : name.trim(),
      group: group == 'other' ? null : group,
    );
    buildRows();
    return '';
  }

  // ---- save ---------------------------------------------------------------------------------------------------------

  String validate() {
    for (final r in rows) {
      if (r.off) continue;
      final price = parseNum(r.price);
      if (price == null || price <= 0) return 'Giá tiền/1 điểm của "${r.label}" không hợp lệ';
      final payout = r.payout.trim().isEmpty ? 0 : parseNum(r.payout);
      if (payout == null || payout < 0) return 'Giá trúng/1 điểm của "${r.label}" không hợp lệ';
    }
    for (final r in rows) {
      if (r.off) continue;
      if (r.extra || srcChanged(r)) {
        if (r.srcTiers.isEmpty) return '"${r.label}": chọn ít nhất một giải để lấy số';
        if (r.srcDigits < 1 || r.srcDigits > 6) return '"${r.label}": số chữ số từ 1 đến 6';
      }
    }
    final seen = <String, String>{}; // folded symbol -> type
    for (final r in rows) {
      if (!r.editable || r.off) continue;
      for (final sym in parseSymbols(r.symbolsInput)) {
        if (!_symbolLetters.hasMatch(sym)) return 'Ký hiệu "$sym" của "${r.label}" chỉ được gồm chữ cái (tối đa 12 ký tự)';
        final k = foldText(sym);
        final other = seen[k];
        if (other != null && other != r.type) {
          return 'Ký hiệu "$sym" đang dùng cho cả "${rows.firstWhere((x) => x.type == other).label}" và "${r.label}"';
        }
        seen[k] = r.type;
      }
    }
    return '';
  }

  /// Default scope: every standard kind of every region gets a value (a legacy account only had Đề / Lô), so an entry of
  /// any kind is always scored with a real row.
  void _fillMissing(RatesMap target) {
    for (final r in regionIds) {
      for (final kind in tableKindKeys) {
        if (target[regionKey(kind, r)] == null && target[kind] == null) target[regionKey(kind, r)] = defaultRow(kind, r);
      }
    }
  }

  bool get dirty {
    final copy = _deepCopy(work);
    _commitInto(copy);
    return snapshotOf(copy) != _initial;
  }

  RatesMap _deepCopy(RatesMap m) => Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);

  /// Commits the rows and returns the map to send (customer: empty = follow the account again; account: not empty,
  /// every standard kind filled in).
  RatesMap resultMap() {
    commitRows();
    if (!isCustomer) _fillMissing(work);
    return _deepCopy(work);
  }

  void resetAll() {
    if (isCustomer) {
      load(const {}, setInitial: false);
    } else {
      load(defaultRates, setInitial: false);
    }
    buildRows();
  }

  int get overrideCount => work.keys.where((k) => isRegionalKey(k) || _disabled(work[k])).length;
  bool regionHasOverride(String id) => work.keys.any((k) => k.endsWith('@$id'));
}
