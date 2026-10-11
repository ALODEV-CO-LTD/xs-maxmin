// Date and grouping helpers of Tính điểm / Nhập kết quả (no UI, unit tested).
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import 'entry_model.dart';
import 'scoring_logic.dart';

/// ISO date moved by [delta] days (calendar arithmetic in UTC, so time zones never shift the day).
String shiftIso(String iso, int delta) {
  final p = iso.split('-').map(int.parse).toList();
  return isoOf(DateTime.utc(p[0], p[1], p[2] + delta));
}

bool isIsoDate(String? s) => s != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

const weekdayNames = ['Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy', 'Chủ nhật'];

/// "2026-10-11" -> (date: "11/10/2026", weekday: "Chủ nhật")
({String date, String weekday}) dayLabel(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return (date: viDate(iso), weekday: weekdayNames[DateTime.utc(p[0], p[1], p[2]).weekday - 1]);
}

class TimePreset {
  const TimePreset(this.key, this.label);
  final String key;
  final String label;
}

const timePresets = [
  TimePreset('today', 'Hôm nay'),
  TimePreset('7', '7 ngày'),
  TimePreset('30', '30 ngày'),
  TimePreset('all', 'Tất cả'),
  TimePreset('custom', 'Tuỳ chọn'),
];

/// The date range of a quick filter; null for "Tuỳ chọn" (the dates stay as they are). '' = no limit.
({String from, String to})? rangeForPreset(String key, String today) {
  switch (key) {
    case 'today':
      return (from: today, to: today);
    case '7':
      return (from: shiftIso(today, -6), to: today);
    case '30':
      return (from: shiftIso(today, -29), to: today);
    case 'all':
      return (from: '', to: '');
    default:
      return null;
  }
}

class DayGroup {
  DayGroup(this.date, this.entries);
  final String date;
  final List<Entry> entries;
}

/// Entries of one customer within the filters, grouped by day, newest day first.
List<DayGroup> groupDays(
  Iterable<Entry> entries, {
  required String customer,
  required LotteryStations stations,
  String region = 'all',
  String from = '',
  String to = '',
}) {
  final map = <String, List<Entry>>{};
  for (final e in entries) {
    if (e.customerName != customer) continue;
    if (region != 'all' && stations.regionOf(e.station).id != region) continue;
    if (from.isNotEmpty && e.entryDate.compareTo(from) < 0) continue;
    if (to.isNotEmpty && e.entryDate.compareTo(to) > 0) continue;
    map.putIfAbsent(e.entryDate, () => []).add(e);
  }
  final dates = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in dates) DayGroup(d, map[d]!)];
}

String lotteryKey(String date, String station) => '$date|$station';

/// For one day: 'yes' = every station its entries are on has a result, 'partial' = only some, 'no' = none,
/// null = not looked up yet. [cache] maps `date|station` to the result (or null when there is none).
String? lotteryState(String date, List<Entry> list, LotteryStations stations, Map<String, LotteryResult?> cache) {
  final keys = <String>{};
  for (final e in list) {
    for (final st in stations.entryStations(e.station, e.entryDate)) {
      keys.add(lotteryKey(date, st));
    }
  }
  if (keys.isEmpty) return null;
  var have = 0;
  for (final k in keys) {
    if (!cache.containsKey(k)) return null;
    if (cache[k] != null) have++;
  }
  return have == keys.length ? 'yes' : (have > 0 ? 'partial' : 'no');
}
