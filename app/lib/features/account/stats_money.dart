import '../../core/api_client.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_data.dart';
import '../scoring/scoring_days.dart';
import '../scoring/scoring_logic.dart';
import 'stats_logic.dart';

// Tổng quan in MONEY, worked out exactly like Tính điểm (same `summarize`, same payout rows, per customer): money the
// customers sent, money they won, and the profit on the days that already have a lottery result. Days without a result
// are shown apart ("chưa tính") and never counted as profit.

/// One day's money (đồng).
class DayMoney {
  double sent = 0; // tiền khách gửi (every day)
  double settled = 0; // tiền gửi of the days that have a result
  double won = 0; // tiền khách trúng
  double pending = 0; // tiền gửi of the days with no result yet
  int pendingLots = 0;
  int lots = 0;
  double get profit => settled - won;
}

class MoneyStats {
  MoneyStats(this.byDate, this.customerNames, this.plays);
  final Map<String, DayMoney> byDate;
  final Set<String> customerNames;
  final int plays;

  double get sent => byDate.values.fold(0.0, (a, d) => a + d.sent);
  double get won => byDate.values.fold(0.0, (a, d) => a + d.won);
  double get settled => byDate.values.fold(0.0, (a, d) => a + d.settled);
  double get pending => byDate.values.fold(0.0, (a, d) => a + d.pending);
  int get pendingLots => byDate.values.fold(0, (a, d) => a + d.pendingLots);
  double get profit => settled - won;
}

/// Pure: money per day for [entries], each customer scored with their own rates / region.
MoneyStats computeMoneyStats({
  required List<Entry> entries,
  required Iterable<CustomerRec> customers,
  required RatesMap accountRates,
  required LotteryStations stations,
  required LotteryResult? Function(String date, String station) getResult,
}) {
  final byName = {for (final c in customers) c.name: c};
  final names = {for (final c in customers) c.name};
  final groups = <String, Map<String, List<Entry>>>{}; // customer -> date -> entries
  for (final e in entries) {
    final name = e.customerName.isEmpty ? noCustomerName : e.customerName;
    names.add(name);
    groups.putIfAbsent(name, () => {}).putIfAbsent(e.entryDate, () => []).add(e);
  }
  final out = <String, DayMoney>{};
  groups.forEach((name, days) {
    final c = byName[name];
    days.forEach((date, list) {
      final s = summarize([DayEntries(date, list)], accountRates, c?.scoringRates, getResult, stations, customerRegion: c?.homeRegion);
      final d = out.putIfAbsent(date, DayMoney.new);
      d.sent += s.sentMoney;
      d.settled += s.settledMoney;
      d.won += s.wonMoney;
      d.pending += s.pendingMoney;
      d.pendingLots += s.pendingLots;
      d.lots += s.sentLots;
    });
  });
  return MoneyStats(out, names, entries.length);
}

/// Series for the window of periods ending at [now], oldest first (same shape as the points version).
List<StatPoint> buildMoneySeries(Map<String, DayMoney> byDate, StatUnit unit, StatMetric metric, DateTime now, {int? count}) {
  final keys = periodKeys(unit, now, count: count);
  final acc = {for (final k in keys) k: DayMoney()};
  byDate.forEach((date, m) {
    final b = acc[keyOf(date, unit)];
    if (b == null) return;
    b.sent += m.sent;
    b.settled += m.settled;
    b.won += m.won;
    b.pending += m.pending;
  });
  return [
    for (final k in keys)
      StatPoint(k, labelOf(k, unit), fullLabelOf(k, unit), switch (metric) {
        StatMetric.vao => acc[k]!.sent,
        StatMetric.ra => acc[k]!.won,
        StatMetric.profit => acc[k]!.profit,
      }),
  ];
}

/// What both loaders need, fetched the same way Tính điểm does (saved copy when offline).
typedef _MoneyInputs = ({List<Entry> entries, List<CustomerRec> customers, RatesMap rates, LotteryResult? Function(String, String) getResult});

Future<_MoneyInputs> _loadMoneyInputs(ApiClient api, LotteryStations stations) async {
  final r = await Future.wait([
    fetchAllEntries(api, overlay: true),
    fetchCustomers(api).catchError((_) => <CustomerRec>[]),
    fetchAccountRates(api),
    stations.load(api),
  ]);
  final entries = r[0] as List<Entry>;
  final customers = r[1] as List<CustomerRec>;
  final rates = r[2] as RatesMap;
  // every (date, station) the entries count for, looked up 4 at a time
  final need = <(String, String)>{};
  for (final e in entries) {
    for (final st in stations.entryStations(e.station, e.entryDate)) {
      need.add((e.entryDate, st));
    }
    if (stations.entryStations(e.station, e.entryDate).isEmpty) need.add((e.entryDate, 'mb'));
  }
  final cache = <String, LotteryResult?>{};
  final queue = need.toList();
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final (date, st) = queue.removeLast();
      try {
        cache[lotteryKey(date, st)] = await fetchLotteryResult(api, date, st);
      } on ApiError catch (e) {
        if (e.status != 0) cache[lotteryKey(date, st)] = null; // offline and never saved: unknown, counted as "chưa tính"
      } catch (_) {
        cache[lotteryKey(date, st)] = null;
      }
    }
  }

  await Future.wait([worker(), worker(), worker(), worker()]);
  return (entries: entries, customers: customers, rates: rates, getResult: (String d, String s) => cache[lotteryKey(d, s)]);
}

Future<MoneyStats> loadMoneyStats(ApiClient api, LotteryStations stations) async {
  final i = await _loadMoneyInputs(api, stations);
  return computeMoneyStats(entries: i.entries, customers: i.customers, accountRates: i.rates, stations: stations, getResult: i.getResult);
}

/// One customer's money over all their days (đồng): sent, won, and the profit on the days that already have a result.
class CustomerMoney {
  double sent = 0;
  double settled = 0;
  double won = 0;
  double pending = 0;
  double get profit => settled - won;
}

/// Pure: money per customer name, each scored with their own rates / region (same `summarize` as Tính điểm).
Map<String, CustomerMoney> computeMoneyByCustomer({
  required List<Entry> entries,
  required Iterable<CustomerRec> customers,
  required RatesMap accountRates,
  required LotteryStations stations,
  required LotteryResult? Function(String date, String station) getResult,
}) {
  final byName = {for (final c in customers) c.name: c};
  final groups = <String, Map<String, List<Entry>>>{};
  for (final e in entries) {
    final name = e.customerName.isEmpty ? noCustomerName : e.customerName;
    groups.putIfAbsent(name, () => {}).putIfAbsent(e.entryDate, () => []).add(e);
  }
  final out = <String, CustomerMoney>{};
  groups.forEach((name, days) {
    final c = byName[name];
    final m = out.putIfAbsent(name, CustomerMoney.new);
    days.forEach((date, list) {
      final s = summarize([DayEntries(date, list)], accountRates, c?.scoringRates, getResult, stations, customerRegion: c?.homeRegion);
      m.sent += s.sentMoney;
      m.settled += s.settledMoney;
      m.won += s.wonMoney;
      m.pending += s.pendingMoney;
    });
  });
  return out;
}

Future<Map<String, CustomerMoney>> loadCustomerMoney(ApiClient api, LotteryStations stations) async {
  final i = await _loadMoneyInputs(api, stations);
  return computeMoneyByCustomer(entries: i.entries, customers: i.customers, accountRates: i.rates, stations: stations, getResult: i.getResult);
}
