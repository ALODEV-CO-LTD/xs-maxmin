import 'dart:io';

import 'package:server/src/deletion_scheduler.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  for (final u in ['a', 'b']) {
    db.execute(
      'INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) '
      "VALUES (?, ?, ?, 'x', 'user', 100, '2026-01-01')",
      [u, 'user$u', 'U $u'],
    );
  }
  return db;
}

void _entry(Database db, String id, String user, String date, {String customer = 'k1'}) {
  db.execute(
    'INSERT INTO data_entries (id, user_id, customer_name, entry_date, value, created_at) '
    "VALUES (?, ?, ?, ?, '12', '2026-01-01')",
    [id, user, customer, date],
  );
}

void _sched(Database db, String id, {String kind = 'data', String runAt = '2026-03-10T00:00:00.000Z',
    int? every, String? unit, int keep = 0, String? customer, String user = 'a'}) {
  db.execute(
    'INSERT INTO deletion_schedules (id, user_id, kind, customer_name, run_at, status, created_at, '
    "repeat_every, repeat_unit, keep_days, first_run_at, ttl_seconds, friend_id, chat_scope) VALUES (?, ?, ?, ?, ?, 'pending', '2026-01-01', ?, ?, ?, ?, ?, ?, ?)",
    [id, user, kind, customer, runAt, every, unit, keep, runAt, kind == 'chat' ? 3600 : null, kind == 'chat' ? 'b' : null, kind == 'chat' ? 'all' : null],
  );
}

int _n(Database db, [String where = '1=1']) =>
    db.select('SELECT COUNT(*) AS n FROM data_entries WHERE $where').first['n'] as int;

Row _row(Database db, String id) => db.select('SELECT * FROM deletion_schedules WHERE id = ?', [id]).first;

void main() {
  group('addRepeat / nextRunAfter', () {
    test('day and week keep time of day', () {
      final a = DateTime.utc(2026, 3, 10, 2, 30);
      expect(addRepeat(a, 10, 'day'), DateTime.utc(2026, 3, 20, 2, 30));
      expect(addRepeat(a, 1, 'week'), DateTime.utc(2026, 3, 17, 2, 30));
    });

    test('month clamps to the last day (31/1 -> 28/2, leap 29/2) without drift', () {
      // 12:00 UTC = 19:00 VN, same calendar day in VN.
      final jan31 = DateTime.utc(2026, 1, 31, 12);
      expect(addRepeat(jan31, 1, 'month'), DateTime.utc(2026, 2, 28, 12));
      expect(addRepeat(jan31, 2, 'month'), DateTime.utc(2026, 3, 31, 12));
      expect(addRepeat(DateTime.utc(2028, 1, 31, 12), 1, 'month'), DateTime.utc(2028, 2, 29, 12));
      expect(addRepeat(DateTime.utc(2026, 12, 15, 12), 1, 'month'), DateTime.utc(2027, 1, 15, 12));
      expect(addRepeat(DateTime.utc(2026, 12, 15, 12), 12, 'month'), DateTime.utc(2027, 12, 15, 12));
    });

    test('month uses the Vietnam calendar day (UTC+7)', () {
      // 20:00 UTC on 30/1 is 03:00 on 31/1 in Vietnam -> Feb clamp 28/2 03:00 VN = 27/2 20:00 UTC.
      expect(addRepeat(DateTime.utc(2026, 1, 30, 20), 1, 'month'), DateTime.utc(2026, 2, 27, 20));
    });

    test('skips missed cycles: only the nearest future occurrence', () {
      final a = DateTime.utc(2026, 3, 1, 1);
      final next = nextRunAfter(a, 1, 'day', after: DateTime.utc(2026, 3, 20, 5));
      expect(next, DateTime.utc(2026, 3, 21, 1));
      expect(nextRunAfter(a, 1, 'day', after: DateTime.utc(2026, 3, 1, 0)), DateTime.utc(2026, 3, 2, 1));
    });
  });

  group('runDueDeletions', () {
    test('recurring schedule deletes, advances run_at, stays pending, counts', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01');
      _entry(db, 'e2', 'a', '2026-03-09');
      _sched(db, 's1', every: 1, unit: 'day', runAt: '2026-03-10T01:00:00.000Z');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 1, 0, 30));
      final s = _row(db, 's1');
      expect(_n(db), 0);
      expect(s['status'], 'pending');
      expect(s['run_at'], '2026-03-11T01:00:00.000Z');
      expect(s['run_count'], 1);
      expect(s['deleted_count'], 2);
      expect(s['executed_at'], isNotNull);
      expect(db.select("SELECT data_used FROM users WHERE id='a'").first['data_used'], 98);

      // Not due yet -> nothing happens.
      _entry(db, 'e3', 'a', '2026-03-10');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 12));
      expect(_n(db), 1);
      // Next day: runs again, totals accumulate.
      runDueDeletions(db, now: DateTime.utc(2026, 3, 11, 1, 5));
      expect(_n(db), 0);
      final s2 = _row(db, 's1');
      expect(s2['run_count'], 2);
      expect(s2['deleted_count'], 3);
      expect(s2['run_at'], '2026-03-12T01:00:00.000Z');
    });

    test('server down for many cycles: runs ONCE and jumps to the nearest future', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01');
      _sched(db, 's1', every: 1, unit: 'day', runAt: '2026-03-02T01:00:00.000Z');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 20, 5));
      final s = _row(db, 's1');
      expect(s['run_count'], 1);
      expect(s['run_at'], '2026-03-21T01:00:00.000Z');
    });

    test('monthly: 31/1 -> 28/2 -> 31/3', () {
      final db = _db();
      _sched(db, 's1', every: 1, unit: 'month', runAt: '2026-01-31T12:00:00.000Z');
      runDueDeletions(db, now: DateTime.utc(2026, 1, 31, 12, 1));
      expect(_row(db, 's1')['run_at'], '2026-02-28T12:00:00.000Z');
      runDueDeletions(db, now: DateTime.utc(2026, 2, 28, 12, 1));
      expect(_row(db, 's1')['run_at'], '2026-03-31T12:00:00.000Z');
    });

    test('keepDays keeps the newest N days (Vietnam date)', () {
      final db = _db();
      // now = 10/3 18:00 UTC = 11/3 01:00 VN; keep 2 days -> cutoff 9/3.
      for (final d in ['2026-03-08', '2026-03-09', '2026-03-10', '2026-03-11']) {
        _entry(db, 'e$d', 'a', d);
      }
      _sched(db, 's1', every: 1, unit: 'week', keep: 2, runAt: '2026-03-10T17:00:00.000Z');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 18));
      final left = db.select('SELECT entry_date FROM data_entries ORDER BY entry_date').map((r) => r['entry_date']).toList();
      expect(left, ['2026-03-10', '2026-03-11']);
    });

    test('customer scope and other users untouched', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01', customer: 'k1');
      _entry(db, 'e2', 'a', '2026-03-01', customer: 'k2');
      _entry(db, 'e3', 'b', '2026-03-01', customer: 'k1');
      _sched(db, 's1', every: 1, unit: 'day', customer: 'k1');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 1));
      expect(db.select('SELECT id FROM data_entries ORDER BY id').map((r) => r['id']).toList(), ['e2', 'e3']);
    });

    test('one-off schedule (no repeat) still runs once then done', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01');
      _sched(db, 's1');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 1));
      final s = _row(db, 's1');
      expect(s['status'], 'done');
      expect(s['deleted_count'], 1);
      expect(_n(db), 0);
      _entry(db, 'e2', 'a', '2026-03-01');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 11, 1));
      expect(_n(db), 1);
    });

    test('cancelled recurring schedule stops', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01');
      _sched(db, 's1', every: 1, unit: 'day');
      db.execute("UPDATE deletion_schedules SET status = 'cancelled' WHERE id = 's1'");
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 1));
      expect(_n(db), 1);
    });

    test('chat rules are unaffected and stay pending', () {
      final db = _db();
      db.execute("INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at) VALUES ('m1', 'a', 'b', 'hi', '2026-03-01')");
      _entry(db, 'e1', 'a', '2026-03-01');
      _sched(db, 'c1', kind: 'chat');
      runDueDeletions(db, now: DateTime.utc(2026, 3, 10, 1));
      expect(_row(db, 'c1')['status'], 'pending');
      expect(db.select('SELECT COUNT(*) AS n FROM direct_messages').first['n'], 0);
      expect(_n(db), 1);
    });
  });

  group('scope helpers', () {
    test('count and delete agree (single source of truth) and never touch others', () {
      final db = _db();
      _entry(db, 'e1', 'a', '2026-03-01');
      _entry(db, 'e2', 'a', '2026-03-05');
      _entry(db, 'e3', 'b', '2026-03-01');
      final now = DateTime.utc(2026, 3, 10, 1);
      final c = countScheduledData(db, 'a', null, '2026-03-02', null, now: now);
      expect(c, 1);
      expect(deleteDataScope(db, 'a', null, '2026-03-02', null, now: now), c);
      expect(_n(db, "user_id = 'b'"), 1);
      expect(_n(db, "user_id = 'a'"), 1);
    });

    test('validateDataScope', () {
      expect(validateDataScope('2026-03-05', '2026-03-01', 0), isNotNull);
      expect(validateDataScope('2026-13-45', null, 0), isNotNull);
      expect(validateDataScope(null, null, -1), isNotNull);
      expect(validateDataScope('2026-03-01', '2026-03-05', 3650), isNull);
    });
  });
}
