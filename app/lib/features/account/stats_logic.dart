import '../../core/number_text.dart';

// Pure logic of the Thống kê tab (port of frontend AccountStats.vue); no Flutter imports so it is unit-testable.

enum StatUnit { day, week, month, year }

enum StatMetric { vao, ra, profit }

const statUnitLabels = {
  StatUnit.day: 'Ngày',
  StatUnit.week: 'Tuần',
  StatUnit.month: 'Tháng',
  StatUnit.year: 'Năm',
};
const statMetricLabels = {
  StatMetric.vao: 'Tiền khách gửi',
  StatMetric.ra: 'Tiền khách trúng',
  StatMetric.profit: 'Lợi nhuận',
};
/// Tổng quan shows the CURRENT period of the chosen unit (today, this week, this month, this year) against the one before it.
const statCurrentLabels = {
  StatUnit.day: 'Hôm nay',
  StatUnit.week: 'Tuần này',
  StatUnit.month: 'Tháng này',
  StatUnit.year: 'Năm nay',
};
const statPreviousLabels = {
  StatUnit.day: 'hôm qua',
  StatUnit.week: 'tuần trước',
  StatUnit.month: 'tháng trước',
  StatUnit.year: 'năm trước',
};
const statSpan = {
  StatUnit.day: 30,
  StatUnit.week: 12,
  StatUnit.month: 12,
  StatUnit.year: 5,
};
const statSpanLabels = {
  StatUnit.day: '30 ngày',
  StatUnit.week: '12 tuần',
  StatUnit.month: '12 tháng',
  StatUnit.year: '5 năm',
};

class StatEntry {
  const StatEntry({
    required this.customerName,
    required this.entryDate,
    required this.score,
    required this.result,
  });
  final String customerName, entryDate;
  final String? score, result;
  factory StatEntry.fromJson(Map<String, dynamic> j) => StatEntry(
    customerName: (j['customerName'] as String?) ?? '',
    entryDate: (j['entryDate'] as String?) ?? '',
    score: j['score'] as String?,
    result: j['result'] as String?,
  );
}

final _junk = RegExp(r'[^\d.\-]');
final _prefix = RegExp(r'^-?(\d+\.?\d*|\.\d+)');

/// Same as the web's `parseFloat(String(s).replace(/[^\d.-]/g, ''))`, 0 when it is not a number.
double toNumber(String? s) {
  if (s == null || s.isEmpty) return 0;
  final m = _prefix.firstMatch(normalizeNumberText(s).replaceAll(_junk, ''));
  if (m == null) return 0;
  return double.tryParse(m.group(0)!) ?? 0;
}

String _p(int n) => n.toString().padLeft(2, '0');

DateTime _mondayOf(DateTime d) {
  final u = DateTime.utc(d.year, d.month, d.day);
  return u.subtract(Duration(days: u.weekday - 1));
}

String _dKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_p(d.month)}-${_p(d.day)}';

/// ISO-8601 week number of [d] (weeks start on Monday; week 1 holds the first Thursday).
int isoWeek(DateTime d) {
  final thu = _mondayOf(d).add(const Duration(days: 3));
  final jan1 = DateTime.utc(thu.year, 1, 1);
  return (thu.difference(jan1).inDays ~/ 7) + 1;
}

/// Continuous list of period keys ending at the period of [now]; [count] defaults to 30 days / 12 weeks / 12 months / 5 years.
/// Week keys are the date of the Monday (yyyy-MM-dd).
List<String> periodKeys(StatUnit u, DateTime now, {int? count}) {
  final n = count ?? statSpan[u]!;
  final out = <String>[];
  for (var i = n - 1; i >= 0; i--) {
    switch (u) {
      case StatUnit.day:
        out.add(_dKey(DateTime.utc(now.year, now.month, now.day - i)));
      case StatUnit.week:
        out.add(
          _dKey(_mondayOf(DateTime.utc(now.year, now.month, now.day - 7 * i))),
        );
      case StatUnit.month:
        final d = DateTime.utc(now.year, now.month - i, 1);
        out.add('${d.year}-${_p(d.month)}');
      case StatUnit.year:
        out.add('${now.year - i}');
    }
  }
  return out;
}

/// Period key of an entry date (ISO string, extra time part ignored); '' when the date is malformed.
String keyOf(String entryDate, StatUnit u) {
  final d = entryDate.length >= 10 ? entryDate.substring(0, 10) : entryDate;
  switch (u) {
    case StatUnit.day:
      return d;
    case StatUnit.week:
      final y = int.tryParse(d.length >= 4 ? d.substring(0, 4) : ''),
          m = int.tryParse(d.length >= 7 ? d.substring(5, 7) : ''),
          dd = int.tryParse(d.length >= 10 ? d.substring(8, 10) : '');
      if (y == null || m == null || dd == null) return '';
      return _dKey(_mondayOf(DateTime.utc(y, m, dd)));
    case StatUnit.month:
      return d.length >= 7 ? d.substring(0, 7) : d;
    case StatUnit.year:
      return d.length >= 4 ? d.substring(0, 4) : d;
  }
}

DateTime _parseKeyDay(String k) => DateTime.utc(
  int.parse(k.substring(0, 4)),
  int.parse(k.substring(5, 7)),
  int.parse(k.substring(8, 10)),
);

/// Short axis label: day "dd/MM", week "dd/MM" (Monday), month "MM/yy", year "yyyy".
String labelOf(String k, StatUnit u) {
  switch (u) {
    case StatUnit.day:
    case StatUnit.week:
      return '${k.substring(8, 10)}/${k.substring(5, 7)}';
    case StatUnit.month:
      return '${k.substring(5, 7)}/${k.substring(2, 4)}';
    case StatUnit.year:
      return k;
  }
}

/// Full label for tooltips: "02/03/2026", "Tuần 10 (23/02 – 01/03/2026)", "Tháng 03/2026", "Năm 2026".
String fullLabelOf(String k, StatUnit u) {
  switch (u) {
    case StatUnit.day:
      return '${k.substring(8, 10)}/${k.substring(5, 7)}/${k.substring(0, 4)}';
    case StatUnit.week:
      final mon = _parseKeyDay(k), sun = mon.add(const Duration(days: 6));
      return 'Tuần ${isoWeek(mon)} (${_p(mon.day)}/${_p(mon.month)} – ${_p(sun.day)}/${_p(sun.month)}/${sun.year})';
    case StatUnit.month:
      return 'Tháng ${k.substring(5, 7)}/${k.substring(0, 4)}';
    case StatUnit.year:
      return 'Năm $k';
  }
}

class StatPoint {
  const StatPoint(this.key, this.label, this.full, this.value);
  final String key, label, full;
  final double value;
}

/// Series for the window of [count] periods (default per unit) ending at [now], oldest first; empty periods are 0.
List<StatPoint> buildSeries(
  List<StatEntry> entries,
  StatUnit unit,
  StatMetric metric,
  DateTime now, {
  int? count,
}) {
  final keys = periodKeys(unit, now, count: count);
  final acc = {
    for (final k in keys) k: [0.0, 0.0],
  };
  for (final e in entries) {
    final b = acc[keyOf(e.entryDate, unit)];
    if (b == null) continue;
    b[0] += toNumber(e.score);
    b[1] += toNumber(e.result);
  }
  return [
    for (final k in keys)
      StatPoint(k, labelOf(k, unit), fullLabelOf(k, unit), switch (metric) {
        StatMetric.profit => acc[k]![0] - acc[k]![1],
        StatMetric.vao => acc[k]![0],
        StatMetric.ra => acc[k]![1],
      }),
  ];
}

/// Anchor date of the window right before the one ending at [now] (same length).
DateTime previousAnchor(StatUnit u, DateTime now, {int? count}) {
  final n = count ?? statSpan[u]!;
  switch (u) {
    case StatUnit.day:
      return DateTime.utc(now.year, now.month, now.day - n);
    case StatUnit.week:
      return DateTime.utc(now.year, now.month, now.day - 7 * n);
    case StatUnit.month:
      return DateTime.utc(now.year, now.month - n, 1);
    case StatUnit.year:
      return DateTime.utc(now.year - n, 1, 1);
  }
}

double sumOf(List<StatPoint> pts) => pts.fold<double>(0, (a, p) => a + p.value);

/// Percent change of [cur] vs [prev]; null when [prev] is 0 (no base to compare).
double? percentChange(double cur, double prev) =>
    prev == 0 ? null : (cur - prev) / prev.abs() * 100;

class AccountTotals {
  const AccountTotals(this.customers, this.plays, this.vao, this.ra);
  final int customers, plays;
  final double vao, ra;
  double get profit => vao - ra;
}

/// Customers = roster names plus any name used by an entry; plays = number of entries.
AccountTotals computeTotals(
  Iterable<String> rosterNames,
  List<StatEntry> entries,
) {
  final names = {...rosterNames};
  var vao = 0.0, ra = 0.0;
  for (final e in entries) {
    names.add(e.customerName.isEmpty ? '(Không tên)' : e.customerName);
    vao += toNumber(e.score);
    ra += toNumber(e.result);
  }
  return AccountTotals(names.length, entries.length, vao, ra);
}

/// Compact axis number: 1500 -> "1,5k", 2_000_000 -> "2tr", 3_200_000_000 -> "3,2 tỷ", negatives keep the sign.
String shortNum(double n) {
  final a = n.abs();
  String t(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble()
        ? r.toInt().toString()
        : r.toStringAsFixed(1).replaceAll('.', ',');
  }

  if (a >= 1e9) return '${t(n / 1e9)} tỷ';
  if (a >= 1e6) return '${t(n / 1e6)}tr';
  if (a >= 1e3) return '${t(n / 1e3)}k';
  return n.round().toString();
}

/// Every how many bars one X label fits: [labelWidth] + gap against the slot width of one bar.
int labelStep(int count, double width, double labelWidth) {
  if (count <= 1 || width <= 0) return 1;
  final slot = width / count;
  final s = ((labelWidth + 6) / slot).ceil();
  return s < 1 ? 1 : s;
}

/// Indices that get an X label: always the last, then every [step] backwards, plus the first (replacing a neighbour that would touch it).
List<int> labelIndices(int count, int step) {
  if (count <= 0) return const [];
  final out = <int>[];
  for (var i = count - 1; i >= 0; i -= step) {
    out.add(i);
  }
  if (out.last != 0) {
    if (out.length > 1 && out.last * 2 < step) out.removeLast();
    out.add(0);
  }
  return out.reversed.toList();
}

class YAxis {
  const YAxis(this.min, this.max, this.ticks);
  final double min, max;
  final List<double> ticks;
}

/// Round axis (1/2/5 x 10^k steps, about 4 intervals) that always contains 0 and the data range.
YAxis niceAxis(double dataMin, double dataMax) {
  final lo = dataMin < 0 ? dataMin : 0.0, hi = dataMax > 0 ? dataMax : 0.0;
  if (lo == 0 && hi == 0) return const YAxis(0, 1, [0, 1]);
  final raw = (hi - lo) / 4;
  var mag = 1.0;
  while (mag * 10 <= raw) {
    mag *= 10;
  }
  while (mag > raw) {
    mag /= 10;
  }
  final f = raw / mag;
  final step =
      (f <= 1
          ? 1
          : f <= 2
          ? 2
          : f <= 5
          ? 5
          : 10) *
      mag;
  final min = (lo / step).floor() * step, max = (hi / step).ceil() * step;
  final ticks = <double>[];
  for (var v = min; v <= max + step / 2; v += step) {
    ticks.add(v.abs() < step / 1e6 ? 0.0 : v);
  }
  return YAxis(min, max, ticks);
}
