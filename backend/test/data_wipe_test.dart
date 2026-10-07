import 'dart:io';

import 'package:server/src/data_wipe.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// In-memory DB built from the REAL schema (backend/schema.sql), so a wipe that
/// targets a table/column that does not exist, or the WRONG table (e.g. the
/// old `messages` instead of `direct_messages`), cannot pass unnoticed.
Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  return db;
}

void _user(Database db, String id, {String role = 'user'}) {
  db.execute(
    'INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) '
    "VALUES (?, ?, ?, 'x', ?, 5, '2026-01-01')",
    [id, 'user$id', 'U $id', role],
  );
}

void _dm(Database db, String id, String from, String to, {bool attach = false}) {
  db.execute(
    'INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at, attachment_name, attachment_data) '
    "VALUES (?, ?, ?, 'hi', '2026-01-01', ?, ?)",
    [id, from, to, attach ? 'f.png' : null, attach ? [1, 2, 3] : null],
  );
}

int _n(Database db, String table) => db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

List<Object?> _ids(Database db, String table) =>
    db.select('SELECT id FROM $table ORDER BY id').map((r) => r['id']).toList();

void main() {
  test('wipeUserData deletes only A\'s scope; B, account, friends, friend chat stay', () {
    final db = _db();
    _user(db, 'a');
    _user(db, 'b');
    _user(db, 'c');
    for (final u in ['a', 'b']) {
      db.execute("INSERT INTO data_entries (id, user_id, entry_date, value, created_at) VALUES (?, ?, '2026-01-01', '12', '2026-01-01')", ['e-$u', u]);
      db.execute("INSERT INTO customers (id, user_id, name, created_at) VALUES (?, ?, 'k', '2026-01-01')", ['c-$u', u]);
      db.execute("INSERT INTO customer_syntax_templates VALUES (?, ?, 'k', '{}', '2026-01-01')", ['t-$u', u]);
      db.execute("INSERT INTO deletion_schedules (id, user_id, kind, created_at) VALUES (?, ?, 'data', '2026-01-01')", ['s-$u', u]);
      db.execute("INSERT INTO transactions VALUES (?, ?, 'purchase', 'p', 1, '2026-01-01')", ['x-$u', u]);
      db.execute("INSERT INTO payment_requests (id, user_id, package_type, amount, status, created_at) VALUES (?, ?, 'p', 1, 'pending', '2026-01-01')", ['pp-$u', u]);
      db.execute("INSERT INTO payment_requests (id, user_id, package_type, amount, status, created_at) VALUES (?, ?, 'p', 1, 'approved', '2026-01-01')", ['pa-$u', u]);
      db.execute("INSERT INTO message_reads VALUES (?, 'support', '2026-01-01')", [u]);
      db.execute("INSERT INTO message_reads VALUES (?, 'friend-z', '2026-01-01')", [u]);
    }
    for (final u in ['a', 'b']) {
      db.execute("INSERT INTO messages VALUES (?, ?, 'user', 'old', '2026-01-01')", ['m-$u', u]);
    }
    for (final r in [['c1', 'a', 'b'], ['c2', 'b', 'a'], ['c3', 'b', 'c']]) {
      db.execute("INSERT INTO call_logs (id, caller_id, callee_id, status, created_at) VALUES (?, ?, ?, 'completed', '2026-01-01')", r);
    }
    db.execute("INSERT INTO friendships VALUES ('f', 'a', 'b', '2026-01-01')");
    _dm(db, 'd-ab', 'a', 'b');

    final counts = wipeUserData(db, 'a');
    expect(counts['data_entries'], 1);
    expect(counts['call_logs'], 2);
    expect(counts['payment_requests'], 1);

    for (final t in ['data_entries', 'customers', 'customer_syntax_templates', 'deletion_schedules', 'messages', 'transactions']) {
      expect(_n(db, t), 1, reason: t);
      expect(db.select('SELECT user_id FROM $t').first['user_id'], 'b', reason: t);
    }
    expect(_ids(db, 'payment_requests'), ['pa-a', 'pa-b', 'pp-b']);
    expect(_ids(db, 'call_logs'), ['c3']);
    expect(_n(db, 'users'), 3);
    expect(_n(db, 'friendships'), 1);
    expect(_ids(db, 'direct_messages'), ['d-ab']);
    // only A's support read-marker goes
    expect(db.select('SELECT user_id, peer_key FROM message_reads WHERE user_id = ?', ['a']).map((r) => r['peer_key']), ['friend-z']);
    expect(_n(db, 'message_reads'), 3);
    expect(db.select("SELECT data_used FROM users WHERE id = 'a'").first['data_used'], 0);
    expect(db.select("SELECT data_used FROM users WHERE id = 'b'").first['data_used'], 5);
  });

  test('wipeUserData deletes support chat with Admin (both directions, attachments), keeps friend chat and other users\' support chat', () {
    final db = _db();
    _user(db, 'admin', role: 'admin');
    _user(db, 'a');
    _user(db, 'b');
    _dm(db, 'a-to-admin', 'a', 'admin');
    _dm(db, 'admin-to-a', 'admin', 'a');
    _dm(db, 'a-to-admin-file', 'a', 'admin', attach: true);
    _dm(db, 'b-to-admin', 'b', 'admin'); // another user's support chat
    _dm(db, 'admin-to-b', 'admin', 'b');
    _dm(db, 'a-to-b', 'a', 'b'); // friend chat (both people's data)
    _dm(db, 'b-to-a', 'b', 'a', attach: true);

    final counts = wipeUserData(db, 'a');
    expect(counts['support_messages'], 3);
    expect(_ids(db, 'direct_messages'), ['a-to-b', 'admin-to-b', 'b-to-a', 'b-to-admin']);
    // the friend-chat attachment is untouched
    expect(db.select("SELECT attachment_name FROM direct_messages WHERE id = 'b-to-a'").first['attachment_name'], 'f.png');
  });

  test('wipeUserData is atomic: a failure rolls everything back', () {
    final db = _db();
    _user(db, 'a');
    _user(db, 'admin', role: 'admin');
    db.execute("INSERT INTO data_entries (id, user_id, entry_date, value, created_at) VALUES ('e', 'a', '2026-01-01', '1', '2026-01-01')");
    _dm(db, 'm', 'a', 'admin');
    db.execute('DROP TABLE transactions'); // makes a later step fail
    expect(() => wipeUserData(db, 'a'), throwsA(isA<SqliteException>()));
    expect(_n(db, 'data_entries'), 1);
    expect(_n(db, 'direct_messages'), 1);
  });

  test('reauth throttle: 5 free wrong tries, then locked; success resets', () {
    final db = _db();
    expect(reauthLockedSecondsLeft(db, 'a'), 0);
    for (var i = 1; i <= 4; i++) {
      expect(reauthRecordFailure(db, 'a', 'test'), 0, reason: 'try $i');
    }
    expect(reauthLockedSecondsLeft(db, 'a'), 0);
    expect(reauthRecordFailure(db, 'a', 'test'), 30);
    expect(reauthLockedSecondsLeft(db, 'a'), greaterThan(0));
    expect(reauthLockedSecondsLeft(db, 'b'), 0);
    expect(reauthRecordFailure(db, 'a', 'test'), 60);
    reauthClear(db, 'a');
    expect(reauthLockedSecondsLeft(db, 'a'), 0);
    // never logs the password, only the action
    final ev = db.select("SELECT detail FROM security_events WHERE type = 'reauth_failed'");
    expect(ev.length, 6);
  });
}
