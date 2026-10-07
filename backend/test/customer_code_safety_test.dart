import 'package:server/src/customer_codes.dart';
import 'package:server/src/rate_gate.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('CREATE TABLE customer_codes (id TEXT PRIMARY KEY, user_id TEXT, code TEXT UNIQUE, created_at TEXT, label TEXT)');
  db.execute('CREATE TABLE retired_codes (code TEXT PRIMARY KEY, user_id TEXT, retired_at TEXT)');
  return db;
}

void main() {
  test('guessable codes are rejected, ordinary ones pass', () {
    for (final bad in ['100000', '123321', '112112', '111111', '111112', '120000', '543210', '121212', '455554']) {
      expect(validateCustomCode(bad), isNotNull, reason: bad);
    }
    for (final ok in ['482915', '324097', '907318']) {
      expect(validateCustomCode(ok), isNull, reason: ok);
    }
  });

  test('auto-generated codes always pass the filter', () {
    final db = _db();
    for (var i = 0; i < 3000; i++) {
      expect(validateCustomCode(generateUniqueCustomerCode(db)), isNull);
    }
  });

  test('retired code is quarantined for everyone except the old owner', () {
    final db = _db();
    retireCode(db, '324097', 'alice');
    expect(retiredCodeConflict(db, '324097', 'carol'), contains('90 ngày'));
    expect(retiredCodeConflict(db, '324097', 'alice'), isNull);
    expect(retiredCodeConflict(db, '555123', 'carol'), isNull);
    // after 90 days it is free again
    db.execute('UPDATE retired_codes SET retired_at = ?',
        [DateTime.now().toUtc().subtract(const Duration(days: 91)).toIso8601String()]);
    expect(retiredCodeConflict(db, '324097', 'carol'), isNull);
  });

  test('generator skips quarantined codes', () {
    final db = _db();
    retireCode(db, '482915', 'alice');
    for (var i = 0; i < 2000; i++) {
      expect(generateUniqueCustomerCode(db), isNot('482915'));
    }
  });

  test('sliding window gate: 30/min then wait, recovers', () {
    var t = DateTime(2026, 1, 1);
    final g = SlidingWindowGate(limit: 30, window: const Duration(minutes: 1), now: () => t);
    for (var i = 0; i < 30; i++) {
      expect(g.hit('u'), 0);
    }
    expect(g.hit('u'), inInclusiveRange(1, 61));
    expect(g.hit('other'), 0);
    t = t.add(const Duration(seconds: 61));
    expect(g.hit('u'), 0);
  });

  test('failure gate: 10 free failures, then escalating lock, then forgotten', () {
    var t = DateTime(2026, 1, 1);
    final g = FailureGate(now: () => t);
    for (var i = 0; i < 9; i++) {
      expect(g.recordFailure('u'), 0);
    }
    expect(g.lockedSecondsLeft('u'), 0);
    expect(g.recordFailure('u'), 30);
    expect(g.lockedSecondsLeft('u'), inInclusiveRange(1, 31));
    t = t.add(const Duration(seconds: 31));
    expect(g.lockedSecondsLeft('u'), 0);
    expect(g.recordFailure('u'), 60);
    t = t.add(const Duration(minutes: 40));
    expect(g.recordFailure('u'), 0); // old failures forgotten
  });

  test('gates clean up memory', () {
    var t = DateTime(2026, 1, 1);
    final g = SlidingWindowGate(limit: 5, window: const Duration(minutes: 1), now: () => t);
    for (var i = 0; i < 150; i++) {
      g.hit('k$i');
    }
    t = t.add(const Duration(minutes: 5));
    for (var i = 0; i < 250; i++) {
      g.hit('same');
    }
    expect(g.trackedKeys, lessThan(10));
  });
}
