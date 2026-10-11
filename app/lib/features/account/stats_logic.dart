/// Pure logic of the Thống kê tab (port of frontend AccountStats.vue); no Flutter imports so it is unit-testable.
enum StatUnit { day, month, year }

enum StatMetric { profit, vao, ra }

const statUnitLabels = {StatUnit.day: 'Ngày', StatUnit.month: 'Tháng', StatUnit.year: 'Năm'};
const statMetricLabels = {StatMetric.profit: 'Lợi nhuận', StatMetric.vao: 'Điểm vào', StatMetric.ra: 'Điểm ra'};
const _span = {StatUnit.day: 30, StatUnit.month: 12, StatUnit.year: 5};

class StatEntry {
  const StatEntry({required this.customerName, required this.entryDate, required this.score, required this.result});
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
  final m = _prefix.firstMatch(s.replaceAll(_junk, ''));
  if (m == null) return 0;
  return double.tryParse(m.group(0)!) ?? 0;
}

String _p(int n) => n.toString().padLeft(2, '0');

/// Continuous list of period keys ending at the period of [now] (30 days / 12 months / 5 years).
List<String> periodKeys(StatUnit u, DateTime now) {
  final out = <String>[];
  for (var i = _span[u]! - 1; i >= 0; i--) {
    switch (u) {
      case StatUnit.day:
        final d = DateTime.utc(now.year, now.month, now.day - i);
        out.add('${d.year}-${_p(d.month)}-${_p(d.day)}');
      case StatUnit.month:
        final d = DateTime.utc(now.year, now.month - i, 1);
        out.add('${d.year}-${_p(d.month)}');
      case StatUnit.year:
        out.add('${now.year - i}');
    }
  }
  return out;
}

String keyOf(String entryDate, StatUnit u) {
  final d = entryDate.length >= 10 ? entryDate.substring(0, 10) : entryDate;
  switch (u) {
    case StatUnit.day:
      return d;
    case StatUnit.month:
      return d.length >= 7 ? d.substring(0, 7) : d;
    case StatUnit.year:
      return d.length >= 4 ? d.substring(0, 4) : d;
  }
}

String labelOf(String k, StatUnit u) {
  switch (u) {
    case StatUnit.day:
      return '${k.substring(8, 10)}/${k.substring(5, 7)}';
    case StatUnit.month:
      return '${k.substring(5, 7)}/${k.substring(0, 4)}';
    case StatUnit.year:
      return k;
  }
}

String fullLabelOf(String k, StatUnit u) => u == StatUnit.day ? '${k.substring(8, 10)}/${k.substring(5, 7)}/${k.substring(0, 4)}' : labelOf(k, u);

class StatPoint {
  const StatPoint(this.key, this.label, this.full, this.value);
  final String key, label, full;
  final double value;
}

List<StatPoint> buildSeries(List<StatEntry> entries, StatUnit unit, StatMetric metric, DateTime now) {
  final keys = periodKeys(unit, now);
  final acc = {for (final k in keys) k: [0.0, 0.0]};
  for (final e in entries) {
    final b = acc[keyOf(e.entryDate, unit)];
    if (b == null) continue;
    b[0] += toNumber(e.score);
    b[1] += toNumber(e.result);
  }
  return [
    for (final k in keys)
      StatPoint(k, labelOf(k, unit), fullLabelOf(k, unit), switch (metric) { StatMetric.profit => acc[k]![0] - acc[k]![1], StatMetric.vao => acc[k]![0], StatMetric.ra => acc[k]![1] }),
  ];
}

class AccountTotals {
  const AccountTotals(this.customers, this.plays, this.vao, this.ra);
  final int customers, plays;
  final double vao, ra;
  double get profit => vao - ra;
}

/// Customers = roster names plus any name used by an entry; plays = number of entries.
AccountTotals computeTotals(Iterable<String> rosterNames, List<StatEntry> entries) {
  final names = {...rosterNames};
  var vao = 0.0, ra = 0.0;
  for (final e in entries) {
    names.add(e.customerName.isEmpty ? '(Không tên)' : e.customerName);
    vao += toNumber(e.score);
    ra += toNumber(e.result);
  }
  return AccountTotals(names.length, entries.length, vao, ra);
}

/// 1_234_000 -> "1.2M" (axis labels).
String shortNum(double n) {
  final a = n.abs();
  String t(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  if (a >= 1e9) return '${t(n / 1e9)}B';
  if (a >= 1e6) return '${t(n / 1e6)}M';
  if (a >= 1e3) return '${t(n / 1e3)}K';
  return n.round().toString();
}
