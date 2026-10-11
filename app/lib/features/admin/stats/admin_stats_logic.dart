import 'dart:math';

/// One bucket of GET /admin/stats `series`: a day (YYYY-MM-DD) or, in the 12-month view, a month (YYYY-MM).
class SeriesPoint {
  const SeriesPoint(this.date, this.newUsers, this.revenue);
  final String date;
  final int newUsers;
  final int revenue; // 0 when the account lacks payments.manage (server omits it)
}

class StatsRange {
  const StatsRange(this.key, this.label);
  final String key, label;
}

const statsRanges = [StatsRange('7', '7 ngày'), StatsRange('30', '30 ngày'), StatsRange('90', '90 ngày'), StatsRange('12m', '12 tháng')];

class AdminStats {
  const AdminStats({required this.total, required this.active, required this.expired, required this.byPackage, required this.series, required this.canRevenue});
  final int total, active, expired;
  final Map<String, int> byPackage;
  final List<SeriesPoint> series;
  final bool canRevenue;

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final by = <String, int>{};
    final raw = j['byPackage'];
    if (raw is Map) raw.forEach((k, v) => by['$k'] = n(v));
    return AdminStats(
      total: n(j['totalSubscribers']),
      active: n(j['activeSubscribers']),
      expired: n(j['expiredSubscribers']),
      byPackage: by,
      canRevenue: j['canRevenue'] == true,
      series: [
        for (final d in (j['series'] as List? ?? const []))
          if (d is Map) SeriesPoint('${d['date']}', n(d['newUsers']), n(d['revenue'])),
      ],
    );
  }

  List<SeriesPoint> get _s => series;
  int get totalNewUsers => _s.fold(0, (a, p) => a + p.newUsers);
  int get totalRevenue => _s.fold(0, (a, p) => a + p.revenue);
}

/// Round the axis maximum up to 1/2/5 x 10^n (same as StatsChart.vue niceMax).
double niceMax(double v) {
  if (v <= 0) return 4;
  final p = pow(10, (log(v) / ln10).floor()).toDouble();
  final n = v / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
}

/// "2026-10-11" -> "11/10", "2026-10" -> "10/26".
String shortDate(String k) => k.length == 7 ? '${k.substring(5)}/${k.substring(2, 4)}' : (k.length >= 10 ? '${k.substring(8, 10)}/${k.substring(5, 7)}' : k);

/// "2026-10-11" -> "11/10/2026", "2026-10" -> "Tháng 10/2026".
String longDate(String k) => k.length == 7 ? 'Tháng ${k.substring(5)}/${k.substring(0, 4)}' : (k.length >= 10 ? '${k.substring(8, 10)}/${k.substring(5, 7)}/${k.substring(0, 4)}' : k);

/// Compact axis label: 1,5tr / 200k / 12.
String shortAxis(num v, {bool money = false}) {
  if (!money) return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  if (v >= 1e6) return '${_trim(v / 1e6)}tr';
  if (v >= 1e3) return '${(v / 1e3).round()}k';
  return '${v.round()}';
}

String _trim(double x) {
  final s = x.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s.replaceFirst('.', ',');
}

const fixedPackageLabels = {'none': 'Chưa đăng ký', 'trial': 'Dùng thử 30 ngày'};

/// Package label for a code; unknown (deleted) codes show as-is.
String packageLabelOf(String code, Map<String, String> labels) => labels[code] ?? fixedPackageLabels[code] ?? code;
