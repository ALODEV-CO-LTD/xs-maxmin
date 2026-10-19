// Buckets of the admin stats chart (GET /admin/stats?range=day|week|month|year).

/// The buckets of one stats window.
class StatsBuckets {
  StatsBuckets(this.unit, this.keys, this._keyOf);
  final String unit; // day | week | month | year
  final List<String> keys; // oldest first
  final String Function(DateTime) _keyOf;

  /// First day (YYYY-MM-DD) that can fall in the window; rows older than that are ignored by the SQL.
  String get since => unit == 'year' ? '${keys.first}-01-01' : (unit == 'month' ? '${keys.first}-01' : keys.first);

  /// Bucket key of an ISO timestamp / date, null when it is not a date.
  String? keyOf(String iso) {
    final d = DateTime.tryParse(iso.length >= 10 ? iso.substring(0, 10) : iso);
    return d == null ? null : _keyOf(DateTime.utc(d.year, d.month, d.day));
  }
}

String _p2(int n) => n.toString().padLeft(2, '0');
String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';
DateTime _monday(DateTime d) => DateTime.utc(d.year, d.month, d.day - (d.weekday - 1));

/// [range]: day | week | month | year, or the older 7 | 30 | 90 (days) and 12m (months).
StatsBuckets statsBuckets(String range, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  String unit;
  int count;
  switch (range) {
    case 'week':
      unit = 'week';
      count = 12;
    case 'month' || '12m':
      unit = 'month';
      count = 12;
    case 'year':
      unit = 'year';
      count = 5;
    case '7' || '90':
      unit = 'day';
      count = int.parse(range);
    default:
      unit = 'day';
      count = 30;
  }
  final keys = <String>[
    for (var i = count - 1; i >= 0; i--)
      switch (unit) {
        'week' => _day(_monday(DateTime.utc(today.year, today.month, today.day - 7 * i))),
        'month' => '${DateTime.utc(today.year, today.month - i, 1).year}-${_p2(DateTime.utc(today.year, today.month - i, 1).month)}',
        'year' => '${today.year - i}',
        _ => _day(DateTime.utc(today.year, today.month, today.day - i)),
      },
  ];
  String keyOf(DateTime d) => switch (unit) {
        'week' => _day(_monday(d)),
        'month' => '${d.year}-${_p2(d.month)}',
        'year' => '${d.year}',
        _ => _day(d),
      };
  return StatsBuckets(unit, keys, keyOf);
}
