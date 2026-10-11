// The editing logic of "Cấu hình tính điểm" (port of the script part of frontend/src/components/ScoringConfigEditor.vue),
// kept free of widgets so it can be unit tested.
//
// Data semantics (the same as the web editor):
//  - one map: `type` = applies to every region, `type@mb|mt|mn` = that region only (wins over `type`);
//  - a customer's map may hold `{disabled: true}` for a type the customer does not use (in every region, or just one);
//  - a row you do not change keeps following the general value; changing it in a region tab makes it a region-only value.
import 'dart:convert';
import 'dart:math' as math;

import '../../core/bet_types.dart';
import '../../core/scoring_config.dart';

const regionNames = {'mb': 'Miền Bắc', 'mt': 'Miền Trung', 'mn': 'Miền Nam'};
const editorRegions = ['mb', 'mt', 'mn'];
const digitOptions = [1, 2, 3, 4, 5];

/// One line of the active region tab.
class EditorRow {
  EditorRow({
    required this.type,
    required this.rate,
    required this.digits,
    required this.tiers,
    required this.unit,
    required this.pointValue,
    required this.off,
    required this.custom,
    required this.regionType,
  });
  final String type;
  String rate;
  int digits;
  List<String> tiers;
  String unit; // 'point' | 'money'
  String pointValue;

  /// Switched off for this customer (in this region).
  final bool off;

  /// A type only this customer has.
  final bool custom;

  /// A type made for this region only.
  final bool regionType;

  void toggleTier(String key) {
    if (tiers.contains(key)) {
      tiers.remove(key);
    } else {
      tiers.add(key);
    }
  }
}

enum RemoveKind { regionType, everywhere, thisRegionOnly }

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

Map<String, dynamic> cloneCfg(Map c) {
  final d = c['digits'];
  return {
    'rate': c['rate'],
    'tiers': [for (final t in (c['tiers'] as List? ?? const [])) '$t'],
    'digits': d is num && d != 0 ? d : 2,
    if (c['unit'] != null) 'unit': c['unit'],
    if (c['pointValue'] != null) 'pointValue': c['pointValue'],
  };
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

  RatesMap get _base => isCustomer ? accountRates : defaultRates;

  static bool _disabled(dynamic v) => v is Map && v['disabled'] == true;
  static Map? _cfg(dynamic v) => v is Map && v['disabled'] != true ? v : null;

  /// [setInitial] false = just replace what is on screen (reset): the saved state stays the baseline for "changed?".
  void load(RatesMap? map, {bool setInitial = true}) {
    work.clear();
    for (final e in (map ?? const {}).entries) {
      final v = e.value;
      if (v is! Map) continue;
      work[e.key] = _disabled(v) ? {'disabled': true} : cloneCfg(v);
    }
    if (setInitial) _initial = snapshotOf(work);
  }

  // ---- rows of the active region ------------------------------------------------------------------------------------

  /// What applies to (type, region) when NO region-only value is stored: the baseline a row is compared with.
  Map? inherited(String type) {
    if (!isCustomer) return work[type] as Map?;
    final own = _cfg(work[type]);
    if (own != null) return own;
    return (_base[regionKey(type, region)] ?? _base[type]) as Map?;
  }

  Map? stored(String type) => _cfg(work[regionKey(type, region)]) ?? inherited(type);

  /// A type made for this region only (no value that applies to every region).
  bool isRegionType(String type) => work[type] == null && !(isCustomer && _base[type] != null);

  String _writeKey(EditorRow r) => r.regionType ? regionKey(r.type, region) : r.type;

  List<String> get typeKeys {
    final keys = <String>{...typesIn(work, region)};
    if (isCustomer) keys.addAll(typesIn(_base, region));
    return keys.toList();
  }

  void buildRows() {
    rows.clear();
    for (final type in typeKeys) {
      final offHere = isCustomer && (_disabled(work[type]) || _disabled(work[regionKey(type, region)]));
      final cfg = stored(type) ?? defaultRates['de'] as Map;
      rows.add(EditorRow(
        type: type,
        rate: numText(cfg['rate'] as num?),
        digits: (cfg['digits'] is num && cfg['digits'] != 0) ? (cfg['digits'] as num).toInt() : 2,
        tiers: [for (final t in (cfg['tiers'] as List? ?? const [])) '$t'],
        unit: unitOf(type, Map<String, dynamic>.from(cfg)),
        pointValue: numText(pointValueOf(Map<String, dynamic>.from(cfg))),
        off: offHere,
        custom: isCustomer && _base[type] == null && _base[regionKey(type, region)] == null,
        regionType: isRegionType(type),
      ));
    }
    version++;
  }

  Cfg cfgOf(EditorRow r) => {
        'rate': parseNum(r.rate) ?? 0,
        'tiers': [...r.tiers],
        'digits': r.digits == 0 ? 2 : r.digits,
        'unit': r.unit,
        'pointValue': math.max(0, parseNum(r.pointValue) ?? 0),
      };

  /// Writes the rows of the active region back into [work]: a row that differs from what it would inherit becomes a
  /// region-only value, one that equals it drops its region-only value.
  void commitRows() => _apply(work);

  void _apply(RatesMap target) {
    for (final r in rows) {
      if (r.off) continue;
      final key = regionKey(r.type, region);
      final cfg = cfgOf(r);
      final baseCfg = inherited(r.type);
      if (baseCfg == null) {
        target[_writeKey(r)] = cfg; // a type without a general value gets one
      } else if (sameConfig(cfg, Map<String, dynamic>.from(baseCfg), r.type)) {
        target.remove(key);
      } else if (!(target[key] is Map && sameConfig(Map<String, dynamic>.from(target[key] as Map), cfg, r.type))) {
        target[key] = cfg; // (an unchanged stored value is kept exactly as it was)
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

  /// A row counts as region-only as soon as it differs from what it would inherit (live, before saving) or already is.
  bool differs(EditorRow r) {
    final baseCfg = inherited(r.type);
    return baseCfg != null && !sameConfig(cfgOf(r), Map<String, dynamic>.from(baseCfg), r.type);
  }

  bool isRegionOnly(EditorRow r) => !r.off && !r.regionType && (work[regionKey(r.type, region)] != null || differs(r));
  bool isInherited(EditorRow r) => !r.off && !isRegionOnly(r);

  String tag(EditorRow r) {
    if (r.off) return 'Đã bỏ';
    if (r.regionType) return isCustomer ? 'Riêng khách · chỉ miền này' : 'Chỉ miền này';
    if (isRegionOnly(r)) return isCustomer ? 'Riêng khách · miền này' : 'Riêng miền này';
    if (isCustomer) {
      if (_cfg(work[r.type]) != null) return r.custom ? 'Chỉ khách này' : 'Riêng khách';
      return _base[regionKey(r.type, region)] != null ? 'Mặc định (riêng miền)' : 'Mặc định';
    }
    return 'Chung các miền';
  }

  /// "Theo chung": drop this row's region-only value.
  void resetRow(EditorRow r) {
    work.remove(regionKey(r.type, region));
    buildRows();
  }

  RemoveKind removeKind(EditorRow r) {
    if (r.regionType) return RemoveKind.regionType;
    return (!isCustomer || r.custom) ? RemoveKind.everywhere : RemoveKind.thisRegionOnly;
  }

  /// Apply AFTER the user confirmed (see [removeKind] for the wording). Nothing is saved until [save].
  void removeRow(EditorRow r) {
    commitRows();
    switch (removeKind(r)) {
      case RemoveKind.regionType:
        work.remove(regionKey(r.type, region));
      case RemoveKind.everywhere:
        work.removeWhere((k, _) => baseKey(k) == r.type);
      case RemoveKind.thisRegionOnly:
        work[regionKey(r.type, region)] = {'disabled': true};
    }
    buildRows();
  }

  void restoreRow(EditorRow r) {
    commitRows();
    if (_disabled(work[r.type])) work.remove(r.type);
    work.remove(regionKey(r.type, region));
    buildRows();
  }

  /// A new type, valid only in the active region tab. Returns false when the key is already in use here.
  bool addType({required String key, required num rate, required List<String> tiers, required int digits, required String unit, required num pointValue}) {
    commitRows();
    if (typeKeys.contains(key)) return false;
    work[regionKey(key, region)] = {'rate': rate, 'tiers': [...tiers], 'digits': digits, 'unit': unit, 'pointValue': pointValue};
    buildRows();
    return true;
  }

  // ---- save ---------------------------------------------------------------------------------------------------------

  String validate() {
    for (final r in rows) {
      if (r.off) continue;
      final n = parseNum(r.rate);
      if (n == null || n <= 0) return 'Tỉ lệ của "${betTypeLabel(r.type)}" không hợp lệ';
      if (r.tiers.isEmpty) return '"${betTypeLabel(r.type)}" cần chọn ít nhất một giải để đối chiếu';
    }
    return '';
  }

  bool get dirty {
    final copy = _deepCopy(work);
    _apply(copy);
    return snapshotOf(copy) != _initial;
  }

  RatesMap _deepCopy(RatesMap m) => Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);

  /// Commits the rows and returns the map to send (customer: empty = follow the account again; account: not empty).
  RatesMap resultMap() {
    commitRows();
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

  int get overrideCount => work.keys.where((k) => isRegionalKey(k) || _disabled(work[k]) || (isCustomer && _base[k] == null)).length;
  bool regionHasOverride(String id) => work.keys.any((k) => k.endsWith('@$id'));
}
