// Port of frontend/src/scoringSummary.js: one entry against one day's lottery result ("điểm ra") and the money summary
// ("Tổng kết tiền") of a customer over several days.
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../entries/message_parser.dart' show foldText;
import 'entry_model.dart';

/// A saved lottery result: prize tier -> String (dacBiet, giaiNhat) or List of String.
typedef LotteryResult = Map<String, dynamic>;

/// parseFloat of the digits, dots and minus signs of [v]; 0 when there is nothing numeric.
double toNumber(Object? v) {
  final cleaned = '${v ?? ''}'.replaceAll(RegExp(r'[^\d.\-]'), '');
  final m = RegExp(r'^-?(\d+\.?\d*|\.\d+)').firstMatch(cleaned);
  if (m == null) return 0;
  final n = double.tryParse(m.group(0)!);
  return n != null && n.isFinite ? n : 0;
}

/// A number as JavaScript's `String(n)` would write it ("805000", not "805000.0"): the form stored in `entry.result`.
String numToString(num n) {
  if (n is int) return '$n';
  if (n == n.truncateToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return n.toString();
}

/// The last [count] digits of [str], zero padded; '' when it has no digits.
String normDigits(Object? str, int count) {
  final d = '${str ?? ''}'.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  final tail = d.length > count ? d.substring(d.length - count) : d;
  return tail.padLeft(count, '0');
}

const baseTiers = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'];
const tierFields = [...baseTiers, 'giaiTam'];

List<String> _asList(Object? v) {
  if (v == null) return const [];
  if (v is List) return [for (final x in v) '$x'];
  return ['$v'];
}

/// The numbers of the prize groups a bet type checks. A config that ticks all eight classic groups means "every prize",
/// so on a Miền Nam / Miền Trung result it includes the eighth prize (giaiTam) too.
List<String> numbersForTiers(LotteryResult r, List<String> tiers) {
  final out = <String>[];
  final all = baseTiers.every(tiers.contains);
  for (final t in tiers) {
    if (tierFields.contains(t)) out.addAll(_asList(r[t]));
  }
  if (all && !tiers.contains('giaiTam')) out.addAll(_asList(r['giaiTam']));
  return out;
}

class NumberHits {
  const NumberHits(this.number, this.hits);
  final String number;
  final int hits;
}

class EntryDetail {
  const EntryDetail({required this.bets, required this.lots, required this.perNumber, required this.score, required this.out, this.stakeFactor = 1, this.totalHits = 0});
  final List<String> bets;
  final int lots;
  final List<NumberHits> perNumber;
  final double score; // điểm vào (or đồng for a money type) of EACH number
  final double out; // điểm ra: score x rate x hits (in the type's own unit)

  /// Multiplier of the stake: 4 for "Đầu" of a Nam/Trung customer on a Miền Bắc result (4 giải bảy), else 1.
  final int stakeFactor;
  final int totalHits;
}

/// Where an entry is scored: [region] of the đài ('mb' | 'mt' | 'mn') and the customer's own region ('mb' | 'mn' | null).
class ScoreCtx {
  const ScoreCtx({this.region = 'mb', this.customerRegion});
  final String region;
  final String? customerRegion;
}

int _digitsOf(Cfg config) {
  final d = config['digits'];
  return d is num && d != 0 ? d.toInt() : 2;
}

num _rateOf(Cfg config) {
  final r = config['rate'];
  return r is num ? r : 0;
}

List<String> _tiersOf(Cfg config) => [for (final t in (config['tiers'] as List? ?? const [])) '$t'];

/// The numbers a "lấy số" reads from a day's result: the selected prizes, only the lô thứ [pick] of each when set.
List<String> sourceNumbers(LotteryResult? lr, Map src) {
  if (lr == null) return const [];
  final out = <String>[];
  for (final t in (src['tiers'] as List)) {
    var list = _asList(lr['$t']);
    final pick = src['pick'] as List?;
    if (pick != null && pick.isNotEmpty) {
      list = [for (final i in pick) if ((i as int) - 1 < list.length) list[i - 1]];
    }
    out.addAll(list);
  }
  return out;
}

String _piece(String n, Map src, [int? d]) {
  final k = d ?? src['digits'] as int;
  if (n.length <= k) return n;
  return src['position'] == 'first' ? n.substring(0, k) : n.substring(n.length - k);
}

/// The hit count of "bảng cấu hình" rows. [ctx] = the đài's region and the customer's region.
/// Every kind reads the numbers of its "lấy số" (`effectiveSource`: giải nào, vị trí đầu / cuối, bao nhiêu số, lô thứ mấy);
/// what each kind does with them:
///   lo / lo3 / lo4 / dau / duoi / cang3 / cang4 / custom   each number the customer wrote is compared with those numbers;
///                  every match is a hit (it comes up in several lô = several hits)
///   dau on a Miền Bắc result with the built-in "lấy số": a Bắc customer = the first prize; a Nam/Trung customer = the four
///          seventh prizes with the stake ×4 ("1 điểm đầu = 4.000đ")
///   xienN  true xiên: every one of the N numbers must be among them; it wins ONCE per entry
///   truotN lô trượt: none of the N numbers may be among them; it wins once, stake = điểm × N × giá
///   tai_xiu / chan_le  the first number read: 00-49 xỉu, 50-99 tài (last 2 digits); even / odd last digit
EntryDetail _tableDetail(Entry entry, LotteryResult? lr, Cfg config, ScoreCtx ctx) {
  final kind = config['kind'] as String;
  final score = toNumber(entry.score);
  final toks = entry.value.split(RegExp(r'[,;\s]+')).where((t) => t.isNotEmpty).toList();
  var src = effectiveSource(config, kind, ctx.region);
  var stakeFactor = 1;
  if (kind == 'dau' && ctx.region == 'mb' && ctx.customerRegion == 'mn' && config['source'] == null) {
    src = {'tiers': ['giaiBay'], 'position': 'last', 'digits': 2};
    stakeFactor = 4;
  }
  final nums = sourceNumbers(lr, src);
  final d = src['digits'] as int;
  int sumHits(List<NumberHits> per) => per.fold<int>(0, (a, b) => a + b.hits);

  if (kind.startsWith('xien') || kind.startsWith('truot')) {
    // xiên: every number must be among the day's numbers; trượt: none of them may be. Either way it is one bet that pays once.
    final truot = kind.startsWith('truot');
    final n = int.parse(kind.substring(truot ? 5 : 4));
    final bets = toks.map((t) => normDigits(t, d)).where((t) => t.isNotEmpty).toList();
    final day = {for (final x in nums) if (x.length >= d) _piece(x, src)};
    final ok = lr != null && bets.length == n && bets.toSet().length == n;
    final hit = ok && (truot ? bets.every((x) => !day.contains(x)) : bets.every(day.contains)) ? 1 : 0;
    return EntryDetail(bets: bets, lots: bets.isEmpty ? 1 : bets.length, stakeFactor: 1, perNumber: [NumberHits(bets.join('.'), hit)], totalHits: hit, score: score, out: 0);
  }
  if (kind == 'tai_xiu' || kind == 'chan_le') {
    // Thần tài: a property of the number read (2 last digits: 00-49 xỉu / 50-99 tài; last digit: chẵn / lẻ).
    final first = nums.isNotEmpty ? nums.first : '';
    final tail = first.length > 2 ? first.substring(first.length - 2) : first;
    final lastDigit = first.isEmpty ? null : int.tryParse(first.substring(first.length - 1));
    final props = kind == 'tai_xiu'
        ? {'tai': tail.isNotEmpty && tail.compareTo('50') >= 0, 'xiu': tail.isNotEmpty && tail.compareTo('50') < 0}
        : {'chan': lastDigit != null && lastDigit % 2 == 0, 'le': lastDigit != null && lastDigit % 2 == 1};
    const alias = {'t': 'tai', 'tai': 'tai', 'x': 'xiu', 'xiu': 'xiu', 'c': 'chan', 'chan': 'chan', 'l': 'le', 'le': 'le'};
    final bets = <String>[];
    for (final t in toks) {
      final w = alias[foldText(t).replaceAll(RegExp(r'[^a-z]'), '')];
      if (w != null && props.containsKey(w)) bets.add(w);
    }
    final per = [for (final b in bets) NumberHits(b, lr != null && props[b]! ? 1 : 0)];
    return EntryDetail(bets: bets, lots: bets.isEmpty ? 1 : bets.length, perNumber: per, totalHits: sumHits(per), score: score, out: 0);
  }
  final bets = toks.map((t) => normDigits(t, d)).where((t) => t.isNotEmpty).toList();
  final long = [for (final x in nums) if (x.length >= d) _piece(x, src)];
  final per = [for (final number in bets) NumberHits(number, long.where((x) => x == number).length)];
  return EntryDetail(bets: bets, lots: bets.isEmpty ? 1 : bets.length, stakeFactor: stakeFactor, perNumber: per, totalHits: sumHits(per), score: score, out: 0);
}

/// One entry against one day's result: its numbers, hits per number and the points/money out.
EntryDetail entryDetail(Entry entry, LotteryResult? lr, Cfg config, [ScoreCtx ctx = const ScoreCtx()]) {
  if (isTableKind(config['kind']) || (config['kind'] == 'custom' && config['source'] is Map)) {
    final d = _tableDetail(entry, lr, config, ctx);
    return EntryDetail(
      bets: d.bets,
      lots: d.lots,
      perNumber: d.perNumber,
      score: d.score,
      stakeFactor: d.stakeFactor,
      totalHits: d.totalHits,
      out: d.totalHits > 0 ? d.score * _rateOf(config) * d.totalHits : 0,
    );
  }
  final digits = _digitsOf(config);
  final bets = entry.value.split(RegExp(r'[,;\s]+')).map((v) => normDigits(v, digits)).where((v) => v.isNotEmpty).toList();
  final trailing = lr == null
      ? <String>[]
      : [for (final n in numbersForTiers(lr, _tiersOf(config))) n.length > digits ? n.substring(n.length - digits) : n];
  final score = toNumber(entry.score);
  final perNumber = [for (final number in bets) NumberHits(number, trailing.where((x) => x == number).length)];
  final totalHits = perNumber.fold<int>(0, (a, b) => a + b.hits);
  return EntryDetail(
    bets: bets,
    lots: bets.isEmpty ? 1 : bets.length,
    perNumber: perNumber,
    score: score,
    totalHits: totalHits,
    out: totalHits > 0 ? score * _rateOf(config) * totalHits : 0,
  );
}

/// Money of a stake / a win, in đồng. A row with the money model (price + payout) is exact; an older row goes through
/// unit / pointValue / rate as before.
double stakeMoney(String key, Cfg cfg, double stake) => (hasMoneyModel(cfg) ? stake * numOf(cfg['price']) : toMoney(key, cfg, stake)).toDouble();
double winMoney(String key, Cfg cfg, double score, int hits) =>
    (hasMoneyModel(cfg) ? score * hits * numOf(cfg['payout']) : toMoney(key, cfg, score * _rateOf(cfg) * hits)).toDouble();

/// "Điểm ra" of an entry: the sum over every station it counts for that day, each scored with the config of its own
/// region; null when none of those stations has a result yet.
double? entryOutTotal({
  required Entry entry,
  required LotteryStations stations,
  required RatesMap accountRates,
  required RatesMap? customerRates,
  required LotteryResult? Function(String station) resultOf,
  String? customerRegion,
}) {
  final done = <String, LotteryResult>{};
  for (final st in stations.entryStations(entry.station, entry.entryDate)) {
    final r = resultOf(st);
    if (r != null) done[st] = r;
  }
  if (done.isEmpty) return null;
  var sum = 0.0;
  done.forEach((st, r) {
    final region = stations.regionOf(st).id;
    final cfg = effectiveConfig(accountRates, customerRates, entry.betType, region);
    sum += entryDetail(entry, r, cfg, ScoreCtx(region: region, customerRegion: customerRegion)).out;
  });
  return sum;
}

class DayEntries {
  const DayEntries(this.date, this.entries);
  final String date;
  final List<Entry> entries;
}

class WonItem {
  const WonItem({required this.date, required this.type, required this.station, required this.number, required this.hits, required this.money});
  final String date;
  final String type;
  final String station;
  final String number;
  final int hits;
  final double money;
}

class TypeTotal {
  TypeTotal(this.key, this.unit, this.pointValue);
  final String key;
  final String unit;
  final num pointValue;
  int lots = 0;
  double amount = 0;
  double money = 0;
}

class ScoreSummary {
  ScoreSummary({
    required this.sentLots,
    required this.sentPoints,
    required this.sentMoney,
    required this.byType,
    required this.settledLots,
    required this.settledMoney,
    required this.pendingLots,
    required this.pendingMoney,
    required this.won,
    required this.wonHits,
    required this.wonMoney,
  });
  final int sentLots;
  final double sentPoints;
  final double sentMoney;
  final List<TypeTotal> byType;
  final int settledLots; // sent on days that have a result
  final double settledMoney;
  final int pendingLots; // sent on days without a result yet
  final double pendingMoney;
  final List<WonItem> won;
  final int wonHits;
  final double wonMoney;

  int get wonLots => won.length;

  /// tiền gửi − tiền trúng, over the days that have a result.
  double get remaining => settledMoney - wonMoney;
}

/// Money summary of [days]; [getResult] answers (date, station) with the saved result or null (none / not known yet).
/// An entry on a region ('mn' / 'mt') counts once for EVERY station of that region drawing that day.
ScoreSummary summarize(
  List<DayEntries> days,
  RatesMap accountRates,
  RatesMap? customerRates,
  LotteryResult? Function(String date, String station) getResult,
  LotteryStations stations, {
  String? customerRegion,
}) {
  final byType = <String, TypeTotal>{};
  final won = <WonItem>[];
  var sentLots = 0, settledLots = 0, pendingLots = 0, wonHits = 0;
  var sentPoints = 0.0, sentMoney = 0.0, settledMoney = 0.0, pendingMoney = 0.0, wonMoney = 0.0;

  for (final day in days) {
    for (final entry in day.entries) {
      final key = (entry.betType == null || entry.betType!.isEmpty) ? 'de' : entry.betType!;
      final dated = entry.entryDate.isEmpty ? Entry(id: entry.id, customerName: entry.customerName, entryDate: day.date, value: entry.value, score: entry.score, result: entry.result, betType: entry.betType, station: entry.station) : entry;
      var sts = stations.entryStations(entry.station, dated.entryDate);
      if (sts.isEmpty) sts = const ['mb'];
      for (final station in sts) {
        final region = stations.regionOf(station).id;
        final cfg = effectiveConfig(accountRates, customerRates, key, region);
        final unit = unitOf(key, cfg);
        final lr = getResult(day.date, station);
        final d = entryDetail(entry, lr, cfg, ScoreCtx(region: region, customerRegion: customerRegion));
        final stake = d.score * d.lots * d.stakeFactor; // each number carries the entry's score
        final stakeValue = stakeMoney(key, cfg, stake);

        final t = byType.putIfAbsent(key, () => TypeTotal(key, unit, hasMoneyModel(cfg) ? numOf(cfg['price']) : pointValueOf(cfg)));
        t.lots += d.lots;
        t.amount += stake;
        t.money += stakeValue;
        sentLots += d.lots;
        sentMoney += stakeValue;
        if (unit == 'point') sentPoints += stake;

        if (lr == null) {
          pendingLots += d.lots;
          pendingMoney += stakeValue;
          continue;
        }
        settledLots += d.lots;
        settledMoney += stakeValue;
        for (final n in d.perNumber) {
          if (n.hits == 0) continue;
          final money = winMoney(key, cfg, d.score, n.hits);
          won.add(WonItem(date: day.date, type: key, station: station, number: n.number, hits: n.hits, money: money));
          wonMoney += money;
          wonHits += n.hits;
        }
      }
    }
  }
  won.sort((a, b) {
    if (a.date != b.date) return a.date.compareTo(b.date) < 0 ? 1 : -1;
    return b.money.compareTo(a.money);
  });
  return ScoreSummary(
    sentLots: sentLots,
    sentPoints: sentPoints,
    sentMoney: sentMoney,
    byType: byType.values.toList(),
    settledLots: settledLots,
    settledMoney: settledMoney,
    pendingLots: pendingLots,
    pendingMoney: pendingMoney,
    won: won,
    wonHits: wonHits,
    wonMoney: wonMoney,
  );
}
