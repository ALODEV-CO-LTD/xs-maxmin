import 'dart:convert';

/// Payout configuration of the bet types (port of frontend/src/scoringConfig.js).
///
/// "Bảng cấu hình" (customer's doc): one row per kiểu đánh, per region: Kiểu đánh - Ký hiệu - Giá tiền/1 điểm -
/// Giá trúng/1 điểm. A row is `{kind, price, payout, ...}`:
///   price   = đồng the customer pays per điểm      (tiền xác = điểm × price)
///   payout  = đồng the customer wins per điểm hit  (tiền trúng = số lần trúng × điểm × payout)
/// `kind` fixes how a number is matched (lo = bao lô, dau, duoi, cang3, cang4, xien2/3/4); kind 'custom' (and the older
/// rows without a kind) match by `tiers` + `digits`. Every row also carries the older fields (rate = payout / price,
/// unit 'point', pointValue = price) so code that only knows those still gets the same single-lot money.
///
/// A rates map holds `type` (applies to every region) and `type@mb|mt|mn` (that region only, wins over `type`).
/// A customer's map may also hold `{disabled: true}` for a type that customer does not use.
typedef Cfg = Map<String, dynamic>;
typedef RatesMap = Map<String, dynamic>;

const defaultPointValue = 23000;

/// Each group is one "kiểu đánh" of the customer's doc; its rows are the "cách đánh" inside it.
class TableGroup {
  const TableGroup(this.id, this.label);
  final String id;
  final String label;
}

const tableGroups = [
  TableGroup('lo', 'Lô'),
  TableGroup('de', 'Đề'),
  TableGroup('xien', 'Xiên'),
  TableGroup('truot', 'Lô trượt'),
  TableGroup('thantai', 'Thần tài (tài/xỉu, chẵn/lẻ)'),
  TableGroup('other', 'Kiểu đánh khác'),
];

class TableKind {
  const TableKind(this.kind, this.group, this.label, this.symbols, {this.editable = false});
  final String kind;
  final String group;
  final String label;
  final String symbols;

  /// lo / dau / duoi: the customer may change the ký hiệu (the other kinds are written with a number pattern).
  final bool editable;
}

const tableKinds = [
  TableKind('lo', 'lo', 'Bao lô 2 số', 'L, l, lo, lô, x, X', editable: true),
  TableKind('lo3', 'lo', 'Bao lô 3 số', ''),
  TableKind('lo4', 'lo', 'Bao lô 4 số', ''),
  TableKind('dau', 'de', 'Đầu', 'Đ, D, đ, dau, đầu', editable: true),
  TableKind('duoi', 'de', 'Đuôi', 'C, c, cuoi, cuối', editable: true),
  TableKind('cang3', 'de', '3 càng', '3 số + x / lo + điểm, vd 123x10'),
  TableKind('cang4', 'de', '4 càng', '4 số + x / lo + điểm, vd 5000x100'),
  TableKind('xien2', 'xien', 'Xiên 2', 'vd 20.02x10, 20x02lo10'),
  TableKind('xien3', 'xien', 'Xiên 3', 'như xiên 2, 3 cặp số'),
  TableKind('xien4', 'xien', 'Xiên 4', 'như xiên 2, 4 cặp số'),
  TableKind('truot4', 'truot', 'Trượt xiên 4', '4 cặp số'),
  TableKind('truot8', 'truot', 'Trượt xiên 8', '8 cặp số'),
  TableKind('truot10', 'truot', 'Trượt xiên 10', '10 cặp số'),
  TableKind('tai_xiu', 'thantai', 'Tài / Xỉu', 'nhập "tai" hoặc "xiu"'),
  TableKind('chan_le', 'thantai', 'Chẵn / Lẻ', 'nhập "chan" hoặc "le"'),
];
final List<String> tableKindKeys = [for (final k in tableKinds) k.kind];
bool isTableKind(Object? k) => k is String && tableKindKeys.contains(k);
/// Ký hiệu as typed ("L, l, lo"): a list, unique, at most 12.
List<String> parseSymbols(String? text) {
  final seen = <String>{};
  for (final x in (text ?? '').split(RegExp(r'[,;\s]+'))) {
    final t = x.trim();
    if (t.isNotEmpty) seen.add(t);
  }
  return seen.take(12).toList();
}

String symbolsText(List? list) => (list ?? const []).join(', ');

/// The built-in ký hiệu of lo / dau / duoi.
List<String> defaultSymbols(String kind) {
  for (final k in tableKinds) {
    if (k.kind == kind) return parseSymbols(k.symbols);
  }
  return const [];
}

const regionIds = ['mb', 'mt', 'mn'];

const _allTiers = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'];

/// A number out of a JSON value (num or numeric text); [fallback] when it is neither.
num numOf(Object? v, [num fallback = 0]) => v is num ? v : (num.tryParse('${v ?? ''}') ?? fallback);

/// Kinds that look at every prize of the day (the rest look at the special prize, or the eighth / first / seventh).
bool _isAllPrizeKind(String kind) => const ['lo', 'lo3', 'lo4'].contains(kind) || kind.startsWith('xien') || kind.startsWith('truot');

/// A full row from its essentials.
Cfg makeRow({required String kind, required num price, required num payout, List<String>? tiers, int? digits, String? name, List<String>? symbols, String? group, Map<String, dynamic>? source}) {
  final row = <String, dynamic>{
    'kind': kind,
    'price': price,
    'payout': payout,
    'rate': price > 0 ? payout / price : 0,
    'tiers': tiers != null ? [...tiers] : (_isAllPrizeKind(kind) ? [..._allTiers] : ['dacBiet']),
    'digits': (digits == null || digits == 0) ? (const {'cang3': 3, 'lo3': 3, 'cang4': 4, 'lo4': 4}[kind] ?? 2) : digits,
    'unit': 'point',
    'pointValue': price,
  };
  if (name != null && name.isNotEmpty) row['name'] = name;
  if (source != null) {
    // Lấy số set by the customer: giải nào, vị trí (đầu / cuối), bao nhiêu số, lô thứ mấy. tiers / digits mirror it for older code.
    final src = normalizeSource(source);
    row['source'] = src;
    row['tiers'] = [...(src['tiers'] as List)];
    row['digits'] = src['digits'];
  }
  if (symbols != null && symbols.isNotEmpty) row['symbols'] = [...symbols];
  if (group != null && group.isNotEmpty) row['group'] = group;
  return row;
}

/// Defaults from the doc: Nam/Trung bao lô 12.600 / 70.000, đầu và đuôi 1.000 / 70.000, 3 càng 12.600 / 500.000; Bắc bao lô
/// 21.600. 4 càng, bao lô 3/4 số, xiên, trượt xiên, tài/xỉu and chẵn/lẻ are NOT in the doc: their payouts are DEMO
/// placeholders (xiên 2/3/4 ≈ 10/40/100 × the stake, trượt xiên ≈ fair odds less the house edge, tài-xỉu / chẵn-lẻ 1.900 on
/// 1.000); the customer sets the real ones. Keep in step with
/// backend/lib/src/scoring_rates.dart (defaultTableRates) and frontend/src/scoringConfig.js.
Cfg defaultRow(String kind, [String region = 'mb']) {
  final mb = region == 'mb';
  final num loPrice = mb ? 21600 : 12600;
  // Bao lô 3 / 4 số: the price follows the number of lô it covers (700đ a lô Nam/Trung, 800đ Bắc). Only a starting point.
  final prices = <String, num>{'lo': loPrice, 'lo3': mb ? 18400 : 11900, 'lo4': mb ? 16000 : 11200, 'dau': 1000, 'duoi': 1000, 'cang3': 12600, 'cang4': 12600, 'tai_xiu': 1000, 'chan_le': 1000};
  final payouts = <String, num>{
    'lo': 70000, 'dau': 70000, 'duoi': 70000, 'cang3': 500000, 'cang4': 5000000,
    // demo placeholders (see above)
    'lo3': 500000, 'lo4': 5000000,
    'xien2': mb ? 430000 : 250000, 'xien3': mb ? 2590000 : 1500000, 'xien4': mb ? 8640000 : 5000000,
    'truot4': mb ? 225000 : 90000, 'truot8': mb ? 1350000 : 350000, 'truot10': mb ? 2800000 : 630000,
    'tai_xiu': 1900, 'chan_le': 1900,
  };
  final tiers = kind == 'dau' ? [mb ? 'giaiNhat' : 'giaiTam'] : null;
  return makeRow(kind: kind, price: prices[kind] ?? loPrice, payout: payouts[kind] ?? 0, tiers: tiers);
}

/// Where a kind takes its numbers from, in each region (shown under the row so the customer can check it).
String kindSource(String kind, [String region = 'mb']) {
  final mb = region == 'mb';
  final n = mb ? 27 : 18;
  final x = kind.startsWith('xien') ? kind.substring(4) : kind.startsWith('truot') ? kind.substring(5) : '';
  switch (kind) {
    case 'lo':
      return '2 số cuối của cả $n lô';
    case 'lo3':
      return '3 số cuối của ${mb ? 23 : 17} lô có từ 3 chữ số';
    case 'lo4':
      return '4 số cuối của ${mb ? 20 : 16} lô có từ 4 chữ số';
    case 'dau':
      return mb ? 'Khách Bắc: 2 số cuối giải nhất. Khách Nam/Trung: 4 giải bảy, tiền xác ×4' : 'Giải tám (2 số)';
    case 'duoi':
      return '2 số cuối giải đặc biệt';
    case 'cang3':
      return '3 số cuối giải đặc biệt';
    case 'cang4':
      return '4 số cuối giải đặc biệt';
    case 'tai_xiu':
      return 'Đuôi giải đặc biệt: 00-49 Xỉu, 50-99 Tài';
    case 'chan_le':
      return 'Số cuối giải đặc biệt: chẵn hoặc lẻ';
    default:
      if (kind.startsWith('xien')) return 'Cả $x cặp số cùng về trong $n lô (2 số cuối), tiền xác × $x';
      if (kind.startsWith('truot')) return 'Cả $x cặp số đều không về trong $n lô, tiền xác × $x';
      return '';
  }
}

RatesMap _buildDefaults() {
  final out = <String, dynamic>{};
  for (final region in regionIds) {
    for (final kind in tableKindKeys) {
      out['$kind@$region'] = defaultRow(kind, region);
    }
  }
  return out;
}

/// The built-in "bảng cấu hình" (every kind in every region).
final RatesMap defaultRates = _buildDefaults();

/// The last resort for an entry whose type has no config at all (older data typed as "de").
const Cfg fallbackDe = {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2};

/// How a stored config reads in the table: price / payout in đồng per điểm. Older rows (no `kind`) are converted: a
/// point-unit row has price = pointValue and payout = rate × pointValue; a money-unit row (the stake is already đồng)
/// has price 1 and payout = rate.
Cfg? toTableRow(String key, Map? cfg) {
  if (cfg == null) return null;
  final c = Map<String, dynamic>.from(cfg);
  if (c['kind'] != null) return c;
  final price = unitOf(key, c) == 'point' ? pointValueOf(c) : 1;
  return {...c, 'kind': key == 'lo' ? 'lo' : 'custom', 'price': price, 'payout': numOf(c['rate']) * price};
}

// ---- Lấy số: which numbers of the day a kind looks at ---------------------------------------------------------------
// `{tiers: [giải...], position: 'last' | 'first', digits: n, pick?: [lô thứ...]}`
//   tiers     the prizes (dãy giải) the numbers come from
//   position  the last n digits (đuôi) or the first n digits (đầu) of each number
//   digits    how many digits are compared
//   pick      only the 1st, 2nd... number of each selected prize (empty = every number of the prize)

/// A prize of a region with how many numbers it has and how long they are.
class PrizeInfo {
  const PrizeInfo(this.tier, this.label, this.count, this.digits);
  final String tier;
  final String label;
  final int count;
  final int digits;
}

const prizeInfoMb = [
  PrizeInfo('dacBiet', 'Giải đặc biệt', 1, 5),
  PrizeInfo('giaiNhat', 'Giải nhất', 1, 5),
  PrizeInfo('giaiNhi', 'Giải nhì', 2, 5),
  PrizeInfo('giaiBa', 'Giải ba', 6, 5),
  PrizeInfo('giaiTu', 'Giải tư', 4, 4),
  PrizeInfo('giaiNam', 'Giải năm', 6, 4),
  PrizeInfo('giaiSau', 'Giải sáu', 3, 3),
  PrizeInfo('giaiBay', 'Giải bảy', 4, 2),
];
const prizeInfoSouth = [
  PrizeInfo('giaiTam', 'Giải tám', 1, 2),
  PrizeInfo('giaiBay', 'Giải bảy', 1, 3),
  PrizeInfo('giaiSau', 'Giải sáu', 3, 4),
  PrizeInfo('giaiNam', 'Giải năm', 1, 4),
  PrizeInfo('giaiTu', 'Giải tư', 7, 5),
  PrizeInfo('giaiBa', 'Giải ba', 2, 5),
  PrizeInfo('giaiNhi', 'Giải nhì', 1, 5),
  PrizeInfo('giaiNhat', 'Giải nhất', 1, 5),
  PrizeInfo('dacBiet', 'Giải đặc biệt', 1, 6),
];

/// The prizes of a region (Miền Bắc 27 lô, Miền Nam / Trung 18 lô).
List<PrizeInfo> prizeInfo(String region) => region == 'mb' ? prizeInfoMb : prizeInfoSouth;

List<String> _allTiersOf(String region) => region == 'mb' ? [..._allTiers] : [..._allTiers, 'giaiTam'];

/// A source in its canonical shape: known prizes only (unique, in the order given), position, digits 1..6, pick 1..30 sorted.
Map<String, dynamic> normalizeSource(Map? src) {
  final valid = {..._allTiers, 'giaiTam'};
  final tiers = <String>[];
  for (final t in (src?['tiers'] as List? ?? const [])) {
    if (valid.contains('$t') && !tiers.contains('$t')) tiers.add('$t');
  }
  final dn = numOf(src?['digits']);
  final digits = dn == 0 ? 2 : dn.round().clamp(1, 6);
  final pick = <int>{
    for (final x in (src?['pick'] as List? ?? const []))
      if (numOf(x).round() >= 1 && numOf(x).round() <= 30) numOf(x).round(),
  }.toList()
    ..sort();
  final out = <String, dynamic>{'tiers': tiers, 'position': src?['position'] == 'first' ? 'first' : 'last', 'digits': digits};
  if (pick.isNotEmpty) out['pick'] = pick;
  return out;
}

/// What each kind reads when the customer has not changed it.
Map<String, dynamic> defaultSource(String kind, [String region = 'mb', Map? cfg]) {
  final mb = region == 'mb';
  final digits = const {'lo3': 3, 'lo4': 4, 'cang3': 3, 'cang4': 4, 'chan_le': 1}[kind] ?? 2;
  List<String> tiers;
  if (kind == 'dau') {
    tiers = [mb ? 'giaiNhat' : 'giaiTam'];
  } else if (const ['duoi', 'cang3', 'cang4', 'tai_xiu', 'chan_le'].contains(kind)) {
    tiers = ['dacBiet'];
  } else if (kind == 'custom') {
    final t = cfg?['tiers'];
    tiers = t is List && t.isNotEmpty ? [for (final x in t) '$x'] : ['dacBiet'];
  } else {
    tiers = _allTiersOf(region);
  }
  final cd = cfg?['digits'];
  return {'tiers': tiers, 'position': 'last', 'digits': kind == 'custom' ? (cd is num && cd != 0 ? cd.toInt() : 2) : digits};
}

Map<String, dynamic> effectiveSource(Map? cfg, String kind, [String region = 'mb']) =>
    cfg?['source'] is Map ? normalizeSource(cfg!['source'] as Map) : defaultSource(kind, region, cfg);

String _sourceKey(Object? s) => s is Map ? jsonEncode(normalizeSource(s)) : 'null';

bool sameSource(Map? a, Map? b) => jsonEncode(normalizeSource(a)) == jsonEncode(normalizeSource(b));

/// Which of the four settings make sense for a kind.
class SourceFields {
  const SourceFields({this.tiers = true, this.position = true, this.digits = true, this.pick = true});
  final bool tiers;
  final bool position;
  final bool digits;
  final bool pick;
}

SourceFields sourceFields(String? kind) {
  if (kind == 'tai_xiu' || kind == 'chan_le') return const SourceFields(position: false, digits: false);
  if (kind != null && (kind.startsWith('xien') || kind.startsWith('truot'))) return const SourceFields(position: false, digits: false, pick: false);
  return const SourceFields();
}

/// "2 số cuối của giải đặc biệt, giải nhất" - for the row's caption.
String describeSource(Map src, [String region = 'mb']) {
  final info = prizeInfo(region);
  final tiers = [for (final t in (src['tiers'] as List)) '$t'];
  final names = [for (final t in tiers) info.where((p) => p.tier == t).map((p) => p.label.toLowerCase()).firstOrNull ?? t];
  final every = _allTiersOf(region).every(tiers.contains);
  final where = src['position'] == 'first' ? 'đầu' : 'cuối';
  final pick = src['pick'] as List?;
  final which = pick != null && pick.isNotEmpty ? ' (lô thứ ${pick.join(', ')})' : '';
  return '${src['digits']} số $where của ${every ? 'cả ${region == 'mb' ? 27 : 18} lô' : names.join(', ')}$which';
}

/// A row with the money model (price + payout); an older row goes through unit / pointValue / rate.
bool hasMoneyModel(Cfg? cfg) => cfg?['price'] != null && cfg?['payout'] != null;

String regionKey(String type, String region) => '$type@$region';
bool isRegionalKey(String key) => key.contains('@');
String baseKey(String key) => key.split('@').first;

/// The bet types of a rates map (keys without a region suffix).
List<String> typesOf(RatesMap? rates) => (rates ?? const {}).keys.where((k) => !isRegionalKey(k) && !_isDisabled(rates![k])).toList();

bool _isDisabled(dynamic v) => v is Map && v['disabled'] == true;

/// Types seen in one region: the shared ones plus the ones made only for that region.
List<String> typesIn(RatesMap? rates, String region) {
  final map = rates ?? const <String, dynamic>{};
  final keys = map.keys.toList();
  // A row removed from the table ({disabled: true}); the region's own value wins over the shared one.
  bool off(String type) {
    final regional = map[regionKey(type, region)];
    return regional != null ? _isDisabled(regional) : _isDisabled(map[type]);
  }
  final shared = keys.where((k) => !isRegionalKey(k) && !off(k)).toList();
  final own = keys.where((k) => k.endsWith('@$region') && !_isDisabled(map[k])).map(baseKey).where((t) => !shared.contains(t) && !_isDisabled(map[t])).toList();
  return [...shared, ...own];
}

bool _usable(dynamic v) => v is Map && v['disabled'] != true;

/// Config of one bet type for one region: the customer's own region value, the customer's own value for every region,
/// the account's region value, the account's value, then the account's Đề.
Cfg effectiveConfig(RatesMap? account, RatesMap? customer, String? betType, [String region = 'mb']) {
  final key = (betType == null || betType.isEmpty) ? 'de' : betType;
  for (final k in [regionKey(key, region), key]) {
    final own = customer?[k];
    if (_usable(own)) return Map<String, dynamic>.from(own as Map);
    if (own is Map && own['disabled'] == true) break;
  }
  final direct = account?[regionKey(key, region)] ?? account?[key];
  // A row the account removed from its table still scores the entries already saved with it, with the built-in default.
  if (_isDisabled(direct)) return isTableKind(key) ? defaultRow(key, region) : Map<String, dynamic>.from(fallbackDe);
  final de = account?['de'];
  final acc = direct ?? (_usable(de) ? de : null) ?? fallbackDe;
  return Map<String, dynamic>.from(acc as Map);
}

/// Old account-made types that mean the same as a standard kind ("Đề" = 2 số cuối giải đặc biệt = Đuôi, "3-càng" = 3 càng).
/// Shown once: the standard row; the old key stays in the data so entries already saved with it are scored as before.
const legacyTypeAlias = {'de': 'duoi', '3-càng': 'cang3'};

/// [types] without the old types whose standard kind is there too.
List<String> withoutLegacyDuplicates(List<String> types) => [for (final t in types) if (!(legacyTypeAlias.containsKey(t) && types.contains(legacyTypeAlias[t]))) t];

/// Bet types this customer can use in [region]: the account's types minus the ones switched off for them, plus the
/// types only they have.
List<String> customerBetTypes(RatesMap? account, RatesMap? customer, [String region = 'mb']) {
  bool off(String k) => customer?[k] is Map && customer![k]['disabled'] == true || (customer?[regionKey(k, region)] is Map && customer![regionKey(k, region)]['disabled'] == true);
  final out = typesIn(account, region).where((k) => !off(k)).toList();
  for (final k in typesIn(customer, region)) {
    if (!off(k) && !out.contains(k)) out.add(k);
  }
  return withoutLegacyDuplicates(out);
}

/// 'point' (điểm × 1 điểm = pointValue đồng) or 'money'. Lô defaults to points, everything else to money.
String unitOf(String key, Cfg? cfg) => (cfg?['unit'] as String?) ?? (key == 'lo' ? 'point' : 'money');

num pointValueOf(Cfg? cfg) {
  final v = cfg?['pointValue'];
  return v is num && v >= 0 ? v : defaultPointValue;
}

/// [amount] is in the type's own unit (điểm or đồng); returns đồng.
num toMoney(String key, Cfg? cfg, num amount) => unitOf(key, cfg) == 'point' ? amount * pointValueOf(cfg) : amount;

/// Same config? (kinded rows: kind, price, payout, and for 'custom' also digits + the SET of prize groups; older rows:
/// rate, digits, the SET of prize groups, unit, price per point)
bool sameConfig(Cfg? a, Cfg? b, [String key = '']) {
  if (a == null || b == null) return false;
  List<String> tiers(Cfg c) => [...((c['tiers'] as List?) ?? const []).cast<String>()]..sort();
  final ta = tiers(a).join(','), tb = tiers(b).join(',');
  final da = numOf(a['digits'], 2), db = numOf(b['digits'], 2);
  if (a['kind'] != null || b['kind'] != null) {
    return a['kind'] == b['kind'] &&
        numOf(a['price'], double.nan) == numOf(b['price'], double.nan) &&
        numOf(a['payout'], double.nan) == numOf(b['payout'], double.nan) &&
        symbolsText(a['symbols'] as List?) == symbolsText(b['symbols'] as List?) &&
        '${a['name'] ?? ''}' == '${b['name'] ?? ''}' &&
        '${a['group'] ?? ''}' == '${b['group'] ?? ''}' &&
        _sourceKey(a['source']) == _sourceKey(b['source']) &&
        (a['kind'] != 'custom' || (da == db && ta == tb));
  }
  final ua = unitOf(key, a), ub = unitOf(key, b);
  final ma = ua == 'point' ? pointValueOf(a) : 0, mb = ub == 'point' ? pointValueOf(b) : 0;
  return (a['rate'] as num?) == (b['rate'] as num?) && da == db && ta == tb && ua == ub && ma == mb;
}

/// The ký hiệu the customer set for lo / dau / duoi, for the message reader: `{lo: [...], dau: [...], duoi: [...]}` (a kind
/// without its own list is left out and keeps the built-in spellings).
Map<String, List<String>> kindSymbolsFor(RatesMap? accountRates, RatesMap? customerRates, [String region = 'mb']) {
  final out = <String, List<String>>{};
  for (final kind in const ['lo', 'dau', 'duoi']) {
    final list = effectiveConfig(accountRates, customerRates, kind, region)['symbols'];
    if (list is List && list.isNotEmpty) out[kind] = [for (final x in list) '$x'];
  }
  return out;
}
