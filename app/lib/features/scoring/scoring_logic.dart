// Port of frontend/src/scoringSummary.js: one entry against one day's lottery result ("điểm ra") and the money summary
// ("Tổng kết tiền") of a customer over several days.
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
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
  const EntryDetail({required this.bets, required this.lots, required this.perNumber, required this.score, required this.out});
  final List<String> bets;
  final int lots;
  final List<NumberHits> perNumber;
  final double score; // điểm vào (or đồng for a money type) of EACH number
  final double out; // điểm ra: score x rate x hits (in the type's own unit)
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

/// One entry against one day's result: its numbers, hits per number and the points/money out.
EntryDetail entryDetail(Entry entry, LotteryResult? lr, Cfg config) {
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
    out: totalHits > 0 ? score * _rateOf(config) * totalHits : 0,
  );
}

/// "Điểm ra" of an entry: the sum over every station it counts for that day, each scored with the config of its own
/// region; null when none of those stations has a result yet.
double? entryOutTotal({
  required Entry entry,
  required LotteryStations stations,
  required RatesMap accountRates,
  required RatesMap? customerRates,
  required LotteryResult? Function(String station) resultOf,
}) {
  final done = <String, LotteryResult>{};
  for (final st in stations.entryStations(entry.station, entry.entryDate)) {
    final r = resultOf(st);
    if (r != null) done[st] = r;
  }
  if (done.isEmpty) return null;
  var sum = 0.0;
  done.forEach((st, r) {
    final cfg = effectiveConfig(accountRates, customerRates, entry.betType, stations.regionOf(st).id);
    sum += entryDetail(entry, r, cfg).out;
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
  LotteryStations stations,
) {
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
        final cfg = effectiveConfig(accountRates, customerRates, key, stations.regionOf(station).id);
        final unit = unitOf(key, cfg);
        final lr = getResult(day.date, station);
        final d = entryDetail(entry, lr, cfg);
        final stake = d.score * d.lots; // each number carries the entry's score
        final stakeMoney = toMoney(key, cfg, stake).toDouble();

        final t = byType.putIfAbsent(key, () => TypeTotal(key, unit, pointValueOf(cfg)));
        t.lots += d.lots;
        t.amount += stake;
        t.money += stakeMoney;
        sentLots += d.lots;
        sentMoney += stakeMoney;
        if (unit == 'point') sentPoints += stake;

        if (lr == null) {
          pendingLots += d.lots;
          pendingMoney += stakeMoney;
          continue;
        }
        settledLots += d.lots;
        settledMoney += stakeMoney;
        for (final n in d.perNumber) {
          if (n.hits == 0) continue;
          final money = toMoney(key, cfg, d.score * _rateOf(cfg) * n.hits).toDouble();
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
