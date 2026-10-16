import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import 'entry_model.dart';
import 'scoring_data.dart';
import 'scoring_days.dart';
import 'scoring_logic.dart';

/// Where the "Điểm ra" of one entry stands.
enum CalcState { computing, noLottery, saved, error }

class EntryStatus {
  const EntryStatus(this.state, {this.value, this.error});
  final CalcState state;
  final double? value;
  final String? error;
}

/// One day on screen with its lottery state.
class DayView {
  const DayView(this.date, this.entries, this.lottery);
  final String date;
  final List<Entry> entries;
  final String? lottery; // 'yes' | 'partial' | 'no' | null (checking)
}

/// State and logic of Tính điểm (frontend/src/views/ScoringView.vue).
class ScoringController extends ChangeNotifier {
  ScoringController(this.api, this.stations, {String? today}) : _today = today ?? todayIso();

  static const pageDays = 10;

  final ApiClient api;
  final LotteryStations stations;
  final String _today;

  List<Entry> entries = [];
  List<CustomerRec> customers = [];
  RatesMap rates = Map<String, dynamic>.from(defaultRates);
  bool loading = true;
  String? loadError;

  String selectedCustomer = '';
  String regionFilter = 'all';
  String preset = 'all';
  String dateFrom = '';
  String dateTo = '';
  bool onlyMissing = false;
  int shownDays = pageDays;

  final Map<String, LotteryResult?> lotteryCache = {};
  final Map<String, EntryStatus> status = {};
  final Map<String, bool> _open = {};
  final Set<String> _calculated = {};
  int calcVersion = 0;
  int autoCalcRunning = 0;
  String? autoCalcError;
  String? notice;

  int _prefetchToken = 0;
  bool _disposed = false;
  final Map<String, ScoreSummary> _daySummaries = {};
  ScoreSummary? _totalSummary;
  List<DayView>? _allDaysMemo;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _prefetchToken++;
    super.dispose();
  }

  void _touch() {
    _daySummaries.clear();
    _totalSummary = null;
    _allDaysMemo = null;
    notifyListeners();
  }

  // ---- loading ----------------------------------------------------------------------------------------------

  Future<void> load({bool keepSelection = true}) async {
    loading = entries.isEmpty;
    loadError = null;
    notifyListeners();
    try {
      final r = await Future.wait([
        fetchAllEntries(api, overlay: true),
        fetchCustomers(api).catchError((_) => <CustomerRec>[]),
        fetchAccountRates(api),
        stations.load(api),
      ]);
      entries = r[0] as List<Entry>;
      customers = r[1] as List<CustomerRec>;
      rates = r[2] as RatesMap;
      if (!keepSelection) selectedCustomer = '';
    } on ApiError catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Không tải được số liệu';
    }
    loading = false;
    _touch();
    _refreshDerived();
  }

  // ---- filters ----------------------------------------------------------------------------------------------

  void _filtersChanged() {
    shownDays = pageDays;
    _touch();
    _refreshDerived();
  }

  void selectCustomer(String name) {
    selectedCustomer = name;
    _filtersChanged();
  }

  void setRegionFilter(String r) {
    regionFilter = r;
    _filtersChanged();
  }

  void setPreset(String key) {
    preset = key;
    final r = rangeForPreset(key, _today);
    if (r != null) {
      dateFrom = r.from;
      dateTo = r.to;
    }
    _filtersChanged();
  }

  void setFrom(String v) {
    dateFrom = v;
    preset = 'custom';
    _filtersChanged();
  }

  void setTo(String v) {
    dateTo = v;
    preset = 'custom';
    _filtersChanged();
  }

  void setOnlyMissing(bool v) {
    onlyMissing = v;
    _filtersChanged();
  }

  void showMoreDays() {
    shownDays += pageDays;
    _touch();
    _refreshDerived();
  }

  // ---- derived data -----------------------------------------------------------------------------------------

  RatesMap? get customerRates {
    for (final c in customers) {
      if (c.name == selectedCustomer) return c.scoringRates;
    }
    return null;
  }

  /// The selected customer's own region ('mb' | 'mn' | null).
  String? get customerRegion {
    for (final c in customers) {
      if (c.name == selectedCustomer) return c.homeRegion;
    }
    return null;
  }

  LotteryResult? getResult(String date, String station) => lotteryCache[lotteryKey(date, station)];

  List<DayView> get allDays => _allDaysMemo ??= selectedCustomer.isEmpty
      ? const []
      : [
          for (final g in groupDays(entries, customer: selectedCustomer, stations: stations, region: regionFilter, from: dateFrom, to: dateTo))
            DayView(g.date, g.entries, lotteryState(g.date, g.entries, stations, lotteryCache)),
        ];

  /// `onlyMissing` = only the days that have no lottery result yet.
  List<DayView> get days => onlyMissing ? allDays.where((d) => d.lottery == 'no').toList() : allDays;
  List<DayView> get visibleDays => days.take(shownDays).toList();
  int get hiddenDayCount => (days.length - shownDays).clamp(0, 1 << 30);

  bool get hasEntriesForCustomer => entries.any((e) => e.customerName == selectedCustomer);

  ScoreSummary daySummary(String date) {
    return _daySummaries.putIfAbsent(date, () {
      final d = days.firstWhere((x) => x.date == date, orElse: () => DayView(date, const [], null));
      return summarize([DayEntries(d.date, d.entries)], rates, customerRates, getResult, stations, customerRegion: customerRegion);
    });
  }

  ScoreSummary get total => _totalSummary ??= summarize([for (final d in days) DayEntries(d.date, d.entries)], rates, customerRates, getResult, stations, customerRegion: customerRegion);

  bool isOpen(String date) {
    if (_open.containsKey(date)) return _open[date]!;
    final d = days;
    return d.isNotEmpty && d.first.date == date;
  }

  void toggleDay(String date) {
    _open[date] = !isOpen(date);
    notifyListeners();
    _computeOpen();
  }

  /// Config of one bet type for the region of [station] (rates are per region).
  Cfg configFor(String? betType, String? station) => effectiveConfig(rates, customerRates, betType, stations.regionOf(station).id);

  // ---- lottery results + calculation ------------------------------------------------------------------------

  Future<LotteryResult?> _fetchLottery(String date, String station) async {
    final key = lotteryKey(date, station);
    if (lotteryCache.containsKey(key)) return lotteryCache[key];
    LotteryResult? r;
    try {
      r = await fetchLotteryResult(api, date, station);
    } on ApiError catch (e) {
      // Offline and this day was never saved: do not remember "no result" (it may exist), try again later.
      if (e.status == 0) return null;
      r = null;
    } catch (_) {
      r = null;
    }
    lotteryCache[key] = r;
    return r;
  }

  void _refreshDerived() {
    _prefetch();
    _computeOpen();
  }

  /// Looks the lottery result up for every day in range (4 requests at a time) so the badges and totals are right even
  /// on collapsed cards. Cached per date and station.
  Future<void> _prefetch() async {
    final token = ++_prefetchToken;
    final queue = <(String, String)>[];
    for (final d in allDays) {
      final sts = <String>{for (final e in d.entries) ...stations.entryStations(e.station, e.entryDate)};
      for (final st in sts) {
        if (!lotteryCache.containsKey(lotteryKey(d.date, st))) queue.add((d.date, st));
      }
    }
    Future<void> worker() async {
      while (queue.isNotEmpty && token == _prefetchToken) {
        final (date, st) = queue.removeAt(0);
        await _fetchLottery(date, st);
        if (token == _prefetchToken) _touch();
      }
    }

    await Future.wait([worker(), worker(), worker(), worker()]);
    if (token == _prefetchToken) _computeOpen();
  }

  void _computeOpen() {
    for (final d in visibleDays) {
      if (isOpen(d.date)) _computeDay(d);
    }
  }

  Future<void> _computeDay(DayView day) async {
    final key = '$selectedCustomer|${day.date}|$calcVersion';
    if (_calculated.contains(key)) return;
    _calculated.add(key);
    autoCalcRunning++;
    notifyListeners();
    try {
      for (final e in day.entries) {
        await _computeOne(e);
      }
    } catch (e) {
      autoCalcError = 'Có lỗi khi tính điểm ra';
    } finally {
      autoCalcRunning--;
      _touch();
    }
  }

  Future<void> _computeOne(Entry entry) async {
    status[entry.id] = const EntryStatus(CalcState.computing);
    notifyListeners();
    final results = <String, LotteryResult>{};
    for (final st in stations.entryStations(entry.station, entry.entryDate)) {
      final lr = await _fetchLottery(entry.entryDate, st);
      if (lr != null) results[st] = lr;
    }
    if (results.isEmpty) {
      status[entry.id] = const EntryStatus(CalcState.noLottery);
      return;
    }
    var value = 0.0;
    results.forEach((st, lr) => value += entryDetail(entry, lr, configFor(entry.betType, st), ScoreCtx(region: stations.regionOf(st).id, customerRegion: customerRegion)).out);
    // Already saved with the same figure -> nothing to write.
    final stored = entry.result;
    if (stored != null && stored.isNotEmpty && toNumber(stored) == value) {
      status[entry.id] = EntryStatus(CalcState.saved, value: value);
      return;
    }
    try {
      await api.patch('/me/entries/${entry.id}', {'result': numToString(value)});
      final i = entries.indexWhere((x) => x.id == entry.id);
      if (i != -1) entries[i] = entry.withResult(numToString(value));
      status[entry.id] = EntryStatus(CalcState.saved, value: value);
    } on ApiError catch (e) {
      status[entry.id] = EntryStatus(CalcState.error, value: value, error: e.message);
    } catch (_) {
      status[entry.id] = EntryStatus(CalcState.error, value: value, error: 'Không lưu được');
    }
  }

  /// "Tính lại": forgets every cached result and calculation.
  void recalc() {
    _calculated.clear();
    lotteryCache.clear();
    status.clear();
    calcVersion++;
    _touch();
    _refreshDerived();
  }

  /// Entries shown after data was removed.
  Future<void> afterDeleted(int n) async {
    notice = 'Đã xóa $n số liệu.';
    _calculated.clear();
    await load();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }
}
