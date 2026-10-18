import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/lottery_stations.dart';
import 'package:test/test.dart';

import '../routes/api/admin/backups/index.dart' as backups;
import '../routes/api/lottery-results/index.dart' as lottery;
import 'support.dart';

Map<String, dynamic> _mb(Object? date) => {
      'drawDate': date,
      'station': 'mb',
      for (final prize in regionOf('mb')!.structure)
        prize.tier: prize.tier == 'dacBiet' || prize.tier == 'giaiNhat'
            ? '1' * prize.digits
            : List.filled(prize.count, '1' * prize.digits),
    };

void main() {
  test('isValidDrawDate is strict YYYY-MM-DD', () {
    for (final ok in ['2026-10-18', '2024-02-29']) {
      expect(lottery.isValidDrawDate(ok), isTrue, reason: ok);
    }
    for (final bad in ['2026-10-18 00:00', '2026-10-18T00:00:00', '2026-1-8', '2026-02-30', '2025-02-29', '20261018', '', '2026-13-01', ' 2026-10-18']) {
      expect(lottery.isValidDrawDate(bad), isFalse, reason: bad);
    }
  });

  test('POST lottery-results rejects non-canonical or non-string dates with 400', () async {
    final db = testDb();
    for (final d in ['2026-10-18 00:00', '2026-10-18T00:00:00Z', 20261018, '18/10/2026', '2026-02-30']) {
      final r = await callRoute(lottery.onRequest, db, body: _mb(d));
      expect(r.statusCode, 400, reason: '$d');
    }
    expect(db.select('SELECT 1 FROM lottery_results'), isEmpty);
    final good = await callRoute(lottery.onRequest, db, body: _mb('2026-10-18'));
    expect(good.statusCode, 200);
    expect(db.select('SELECT draw_date FROM lottery_results').single['draw_date'], '2026-10-18');
  });

  test('pruneBackups keeps the newest N and only touches xoso-*.db', () {
    final dir = Directory.systemTemp.createTempSync('bk');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (var i = 0; i < 25; i++) {
      File('${dir.path}/xoso-2026-10-${(i + 1).toString().padLeft(2, '0')}.db').writeAsStringSync('x');
    }
    File('${dir.path}/other.txt').writeAsStringSync('keep');
    expect(backups.pruneBackups(dir), 5);
    final left = dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();
    expect(left.where((n) => n.startsWith('xoso-')).length, 20);
    expect(left, isNot(contains('xoso-2026-10-01.db')));
    expect(left, contains('xoso-2026-10-25.db'));
    expect(left, contains('other.txt'));
    expect(backups.pruneBackups(dir), 0);
  });

  test('freeDiskBytes returns a plausible number or null', () {
    final free = backups.freeDiskBytes(Directory.systemTemp);
    expect(free == null || free > 0, isTrue);
  });
}
