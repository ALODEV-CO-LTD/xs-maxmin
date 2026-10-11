/// Payout configuration of the bet types (port of frontend/src/scoringConfig.js).
///
/// A rates map holds `type` (applies to every region) and `type@mb|mt|mn` (that region only, wins over `type`).
/// Entries are the JSON maps the API sends: `{rate, tiers, digits, unit?, pointValue?}`; a customer's map may also hold
/// `{disabled: true}` for a type that customer does not use.
typedef Cfg = Map<String, dynamic>;
typedef RatesMap = Map<String, dynamic>;

const defaultPointValue = 23000;

final RatesMap defaultRates = {
  'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
  'lo': {
    'rate': 20,
    'tiers': ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'],
    'digits': 2,
  },
};

String regionKey(String type, String region) => '$type@$region';
bool isRegionalKey(String key) => key.contains('@');
String baseKey(String key) => key.split('@').first;

/// The bet types of a rates map (keys without a region suffix).
List<String> typesOf(RatesMap? rates) => (rates ?? const {}).keys.where((k) => !isRegionalKey(k)).toList();

/// Types seen in one region: the shared ones plus the ones made only for that region.
List<String> typesIn(RatesMap? rates, String region) {
  final keys = (rates ?? const {}).keys.toList();
  final shared = keys.where((k) => !isRegionalKey(k)).toList();
  final own = keys.where((k) => k.endsWith('@$region')).map(baseKey).where((t) => !shared.contains(t)).toList();
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
  final acc = account?[regionKey(key, region)] ?? account?[key] ?? account?['de'] ?? defaultRates['de'];
  return Map<String, dynamic>.from(acc as Map);
}

/// Bet types this customer can use in [region]: the account's types minus the ones switched off for them, plus the
/// types only they have.
List<String> customerBetTypes(RatesMap? account, RatesMap? customer, [String region = 'mb']) {
  bool off(String k) => customer?[k] is Map && customer![k]['disabled'] == true || (customer?[regionKey(k, region)] is Map && customer![regionKey(k, region)]['disabled'] == true);
  final out = typesIn(account, region).where((k) => !off(k)).toList();
  for (final k in typesIn(customer, region)) {
    if (!off(k) && !out.contains(k)) out.add(k);
  }
  return out;
}

/// 'point' (điểm × 1 điểm = pointValue đồng) or 'money'. Lô defaults to points, everything else to money.
String unitOf(String key, Cfg? cfg) => (cfg?['unit'] as String?) ?? (key == 'lo' ? 'point' : 'money');

num pointValueOf(Cfg? cfg) {
  final v = cfg?['pointValue'];
  return v is num && v >= 0 ? v : defaultPointValue;
}

/// [amount] is in the type's own unit (điểm or đồng); returns đồng.
num toMoney(String key, Cfg? cfg, num amount) => unitOf(key, cfg) == 'point' ? amount * pointValueOf(cfg) : amount;

/// Same config? (rate, digits and the SET of prize groups, unit, price per point)
bool sameConfig(Cfg? a, Cfg? b, [String key = '']) {
  if (a == null || b == null) return false;
  List<String> tiers(Cfg c) => [...((c['tiers'] as List?) ?? const []).cast<String>()]..sort();
  final ua = unitOf(key, a), ub = unitOf(key, b);
  final ma = ua == 'point' ? pointValueOf(a) : 0, mb = ub == 'point' ? pointValueOf(b) : 0;
  return (a['rate'] as num?) == (b['rate'] as num?) &&
      ((a['digits'] as num?) ?? 2) == ((b['digits'] as num?) ?? 2) &&
      tiers(a).join(',') == tiers(b).join(',') &&
      ua == ub &&
      ma == mb;
}
