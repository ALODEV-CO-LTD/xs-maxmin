import 'package:server/src/stats_buckets.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 10); // a Monday

  test('day: 30 days ending today', () {
    final b = statsBuckets('day', now);
    expect(b.unit, 'day');
    expect(b.keys.length, 30);
    expect(b.keys.first, '2026-09-20');
    expect(b.keys.last, '2026-10-19');
    expect(b.keyOf('2026-10-11T08:00:00Z'), '2026-10-11');
  });

  test('week: 12 Mondays, an entry falls in its own week', () {
    final b = statsBuckets('week', now);
    expect(b.unit, 'week');
    expect(b.keys.length, 12);
    expect(b.keys.last, '2026-10-19');
    expect(b.keys[10], '2026-10-12');
    expect(b.keyOf('2026-10-18T23:59:00Z'), '2026-10-12'); // Sunday belongs to the week of Monday 12/10
    expect(b.keyOf('2026-10-19T00:00:00Z'), '2026-10-19');
    expect(b.since, b.keys.first);
  });

  test('month: 12 months across the year boundary', () {
    final b = statsBuckets('month', DateTime.utc(2026, 2, 5));
    expect(b.keys.length, 12);
    expect(b.keys.first, '2025-03');
    expect(b.keys.last, '2026-02');
    expect(b.keyOf('2025-12-31T23:00:00Z'), '2025-12');
    expect(b.since, '2025-03-01');
  });

  test('year: 5 years; the old keys 7 / 90 / 12m still work', () {
    final y = statsBuckets('year', now);
    expect(y.keys, ['2022', '2023', '2024', '2025', '2026']);
    expect(y.since, '2022-01-01');
    expect(statsBuckets('7', now).keys.length, 7);
    expect(statsBuckets('90', now).keys.length, 90);
    expect(statsBuckets('12m', now).unit, 'month');
    expect(statsBuckets('nonsense', now).keys.length, 30);
    expect(statsBuckets('day', now).keyOf('not a date'), isNull);
  });
}
