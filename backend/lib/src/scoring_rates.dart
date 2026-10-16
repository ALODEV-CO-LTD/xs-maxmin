/// Payout configuration shared by the account-wide settings (routes/api/me/scoring-settings)
/// and the per-customer overrides (customers.scoring_rates, routes/api/me/customers/[id]).
/// Each bet type maps to `{rate, tiers, digits}`: payout multiple, which prize groups count
/// as a match and how many trailing digits are compared.

const validTiers = [
  'dacBiet',
  'giaiNhat',
  'giaiNhi',
  'giaiBa',
  'giaiTu',
  'giaiNam',
  'giaiSau',
  'giaiBay',
  'giaiTam', // Miền Nam / Miền Trung only (eighth prize); ignored for a Miền Bắc result
];

const minDigits = 1;
const maxDigits = 5;


/// Kinds of the "bảng cấu hình" (Kiểu đánh - Ký hiệu - Giá tiền/1 điểm - Giá trúng/1 điểm). A kinded entry carries
/// `price` (đồng per điểm staked) and `payout` (đồng per điểm won, per hit); the matching rule of the kind is built in
/// (lo = bao lô, dau, duoi, cang3, cang4, xien2/3/4); `custom` = the legacy rule (`tiers` + `digits`) with the same prices.
const validKinds = ['lo', 'lo3', 'lo4', 'dau', 'duoi', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4', 'truot4', 'truot8', 'truot10', 'tai_xiu', 'chan_le', 'custom'];
const maxPrice = 1000000000;

/// Normalizes one stored/submitted rate entry into `{rate, tiers}`.
/// Accepts a bare number too (the shape this endpoint used before "tiers"
/// existed) and fills in every tier, matching that version's behavior
/// (it always compared against all 27 numbers) so old saved settings keep
/// working exactly as before instead of silently changing what they mean.
/// Upper bound for "đồng per điểm" (sanity limit).
const maxPointValue = 100000000;

Map<String, dynamic>? normalizeRateEntry(dynamic value) {
  if (value is num) {
    if (value <= 0) return null;
    return {'rate': value, 'tiers': List<String>.from(validTiers), 'digits': 2};
  }
  if (value is Map && value['kind'] != null) return _normalizeKinded(value);
  if (value is Map) {
    final rate = value['rate'];
    final numericRate = rate is num ? rate : num.tryParse('$rate');
    final tiersRaw = value['tiers'];
    if (numericRate == null || numericRate <= 0 || tiersRaw is! List) return null;
    final tiers = tiersRaw.map((t) => t.toString()).where(validTiers.contains).toSet().toList();
    if (tiers.isEmpty) return null;
    final digitsRaw = value['digits'];
    final numericDigits = digitsRaw is num ? digitsRaw.toInt() : int.tryParse('$digitsRaw');
    final digits = (numericDigits == null || numericDigits < minDigits || numericDigits > maxDigits)
        ? 2
        : numericDigits;
    final out = <String, dynamic>{'rate': numericRate, 'tiers': tiers, 'digits': digits};
    // Money view (Tính điểm summary): `unit` is how the customer's stake is written - 'point'
    // (điểm, converted to đồng with `pointValue` = đồng per điểm) or 'money' (already đồng).
    // Both are optional; the client falls back to lô = point, everything else = money.
    final unit = value['unit'];
    if (unit == 'point' || unit == 'money') out['unit'] = unit;
    final pv = value['pointValue'];
    final pointValue = pv is num ? pv : num.tryParse('$pv');
    if (pointValue != null && pointValue >= 0 && pointValue <= maxPointValue) out['pointValue'] = pointValue.round();
    return out;
  }
  return null;
}


/// A "bảng cấu hình" row. `rate`/`tiers`/`digits`/`unit`/`pointValue` are filled in too (rate = payout / price, unit
/// point, pointValue = price) so a client that only knows the older shape still computes the same single-lot money.
Map<String, dynamic>? _normalizeKinded(Map<dynamic, dynamic> value) {
  final kind = value['kind'];
  if (kind is! String || !validKinds.contains(kind)) return null;
  num? numOf(Object? v) => v is num ? v : num.tryParse('$v');
  final price = numOf(value['price']);
  final payout = numOf(value['payout']);
  if (price == null || price <= 0 || price > maxPrice) return null;
  if (payout == null || payout < 0 || payout > maxPrice * 10) return null;
  final tiersRaw = value['tiers'];
  var tiers = tiersRaw is List ? tiersRaw.map((t) => t.toString()).where(validTiers.contains).toSet().toList() : <String>[];
  if (tiers.isEmpty) tiers = ['lo', 'lo3', 'lo4'].contains(kind) || kind.startsWith('xien') || kind.startsWith('truot') ? List<String>.from(validTiers) : ['dacBiet'];
  final digitsRaw = numOf(value['digits'])?.toInt();
  final digits = (digitsRaw == null || digitsRaw < minDigits || digitsRaw > maxDigits)
      ? (kind == 'cang3' || kind == 'lo3' ? 3 : kind == 'cang4' || kind == 'lo4' ? 4 : 2)
      : digitsRaw;
  final out = <String, dynamic>{
    'kind': kind,
    'price': price is int ? price : price.round(),
    'payout': payout is int ? payout : payout.round(),
    'rate': payout / price,
    'tiers': tiers,
    'digits': digits,
    'unit': 'point',
    'pointValue': price.round(),
  };
  // Ký hiệu typed by the customer for lo / dau / duoi (max 12, each short, no spaces); the parser reads them.
  final symbolsRaw = value['symbols'];
  if (symbolsRaw is List) {
    final symbols = symbolsRaw.map((x) => '$x'.trim()).where((x) => x.isNotEmpty && x.length <= 12 && !x.contains(RegExp(r'\s'))).toSet().take(12).toList();
    if (symbols.isNotEmpty) out['symbols'] = symbols;
  }
  // "Lấy số" set by the customer: which prizes, which end of the number, how many digits, which lô of the prize.
  final sourceRaw = value['source'];
  if (sourceRaw is Map) {
    final st = sourceRaw['tiers'];
    final stiers = st is List ? st.map((t) => t.toString()).where(validTiers.contains).toSet().toList() : <String>[];
    if (stiers.isEmpty) return null;
    final sd = numOf(sourceRaw['digits'])?.toInt();
    final sdigits = (sd == null || sd < 1 || sd > 6) ? 2 : sd;
    final pr = sourceRaw['pick'];
    final pick = pr is List ? (pr.map((x) => numOf(x)?.toInt()).whereType<int>().where((x) => x >= 1 && x <= 30).toSet().toList()..sort()) : <int>[];
    out['source'] = {
      'tiers': stiers,
      'position': sourceRaw['position'] == 'first' ? 'first' : 'last',
      'digits': sdigits,
      if (pick.isNotEmpty) 'pick': pick,
    };
    out['tiers'] = stiers;
    out['digits'] = sdigits;
  }
  // The group a custom row is shown in (Lô, Đề, Xiên, Lô trượt, Thần tài, other).
  final group = value['group'];
  if (group is String && const ['lo', 'de', 'xien', 'truot', 'thantai', 'other'].contains(group)) out['group'] = group;
  final name = value['name'];
  if (name is String && name.trim().isNotEmpty) out['name'] = name.trim().length > 30 ? name.trim().substring(0, 30) : name.trim();
  return out;
}

final _keyPattern = RegExp(r'^[^@\s]+(@(mb|mt|mn))?$');

/// Validates a whole `{typeKey: entry}` map; returns `(normalized, null)` or `(null, error)`.
/// With [allowDisabled] (per-customer overrides only) an entry may be `{disabled: true}`: the
/// customer does not use that bet type (it is hidden from their type list).
(Map<String, dynamic>?, String?) normalizeRatesMap(Object? rates, {bool allowEmpty = false, bool allowDisabled = false}) {
  if (rates is! Map || (rates.isEmpty && !allowEmpty)) return (null, 'Cần ít nhất một loại đánh');
  final out = <String, dynamic>{};
  for (final entry in rates.entries) {
    final key = entry.key;
    // `type` applies to every region; `type@mb|mt|mn` is the value for that region only (it wins over `type`).
    if (key is! String || !_keyPattern.hasMatch(key.trim())) return (null, 'Mã loại đánh không hợp lệ');
    final v = entry.value;
    if (allowDisabled && v is Map && v['disabled'] == true) {
      out[key] = {'disabled': true};
      continue;
    }
    final n = normalizeRateEntry(v);
    if (n == null) return (null, 'Cấu hình của "$key" không hợp lệ (cần tỉ lệ > 0 và ít nhất 1 giải)');
    out[key] = n;
  }
  return (out, null);
}

/// Default "bảng cấu hình" of a new account: [price, payout] per kind and region. From the customer's doc
/// (Nam/Trung bao lô 12.600 / 70.000, đầu và đuôi 1.000 / 70.000, 3 càng 12.600 / 500.000; Bắc bao lô 21.600).
/// 4 càng and xiên are NOT given in the doc: 4 càng is a placeholder, xiên payout 0 = "chưa nhập" (the customer sets it).
Map<String, dynamic> defaultTableRates() {
  const kinds = ['lo', 'lo3', 'lo4', 'dau', 'duoi', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4', 'truot4', 'truot8', 'truot10', 'tai_xiu', 'chan_le'];
  final out = <String, dynamic>{};
  for (final region in const ['mb', 'mt', 'mn']) {
    final mb = region == 'mb';
    final loPrice = mb ? 21600 : 12600;
    // Bao lô 3 / 4 số: the bao lô price scaled to the lô it covers (700đ a lô Nam/Trung, 800đ Bắc); a starting point only.
    final price = <String, num>{'lo': loPrice, 'lo3': mb ? 18400 : 11900, 'lo4': mb ? 16000 : 11200, 'dau': 1000, 'duoi': 1000, 'cang3': 12600, 'cang4': 12600};
    const payout = <String, num>{'lo': 70000, 'dau': 70000, 'duoi': 70000, 'cang3': 500000, 'cang4': 5000000};
    for (final kind in kinds) {
      final tiers = ['lo', 'lo3', 'lo4'].contains(kind) || kind.startsWith('xien') || kind.startsWith('truot')
          ? List<String>.from(validTiers)
          : kind == 'dau'
              ? [mb ? 'giaiNhat' : 'giaiTam']
              : ['dacBiet'];
      out['$kind@$region'] = normalizeRateEntry({'kind': kind, 'price': price[kind] ?? loPrice, 'payout': payout[kind] ?? 0, 'tiers': tiers});
    }
  }
  return out;
}
