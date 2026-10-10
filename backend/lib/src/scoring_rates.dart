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
];

const minDigits = 1;
const maxDigits = 5;


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


/// Validates a whole `{typeKey: entry}` map; returns `(normalized, null)` or `(null, error)`.
/// With [allowDisabled] (per-customer overrides only) an entry may be `{disabled: true}`: the
/// customer does not use that bet type (it is hidden from their type list).
(Map<String, dynamic>?, String?) normalizeRatesMap(Object? rates, {bool allowEmpty = false, bool allowDisabled = false}) {
  if (rates is! Map || (rates.isEmpty && !allowEmpty)) return (null, 'Cần ít nhất một loại đánh');
  final out = <String, dynamic>{};
  for (final entry in rates.entries) {
    final key = entry.key;
    if (key is! String || key.trim().isEmpty) return (null, 'Mã loại đánh không hợp lệ');
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
