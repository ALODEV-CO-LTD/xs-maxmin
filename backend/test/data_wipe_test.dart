import 'package:server/src/data_wipe.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('''
    CREATE TABLE users (id TEXT PRIMARY KEY, data_used INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE data_entries (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE customers (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE customer_syntax_templates (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE deletion_schedules (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE call_logs (id TEXT PRIMARY KEY, caller_id TEXT NOT NULL, callee_id TEXT NOT NULL);
    CREATE TABLE messages (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE message_reads (user_id TEXT NOT NULL, peer_key TEXT NOT NULL);
    CREATE TABLE transactions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id));
    CREATE TABLE payment_requests (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), status TEXT NOT NULL);
    CREATE TABLE friendships (id TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL);
    CREATE TABLE direct_messages (id TEXT PRIMARY KEY, sender_id TEXT NOT NULL, receiver_id TEXT NOT NULL);
    CREATE TABLE login_attempts (key TEXT PRIMARY KEY, fail_count INTEGER NOT NULL, last_fail_at TEXT NOT NULL, locked_until TEXT);
    CREATE TABLE security_events (id TEXT PRIMARY KEY, type TEXT NOT NULL, user_id TEXT, username TEXT, ip TEXT, detail TEXT, created_at TEXT NOT NULL);
  ''');
  return db;
}

int _n(Database db, String table) => db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;

void main() {
  test('wipeUserData deletes only A\'s scope; B, account, friends, DMs stay', () {
    final db = _db();
    for (final u in ['a', 'b']) {
      db.execute('INSERT INTO users (id, data_used) VALUES (?, 5)', [u]);
      for (final t in ['data_entries', 'customers', 'customer_syntax_templates', 'deletion_schedules', 'messages', 'transactions']) {
        db.execute('INSERT INTO $t (id, user_id) VALUES (?, ?)', ['$t-$u', u]);
      }
      db.execute("INSERT INTO payment_requests VALUES (?, ?, 'pending')", ['pp-$u', u]);
      db.execute("INSERT INTO payment_requests VALUES (?, ?, 'approved')", ['pa-$u', u]);
      db.execute("INSERT INTO message_reads VALUES (?, 'support')", [u]);
    }
    db.execute("INSERT INTO call_logs VALUES ('c1', 'a', 'b'), ('c2', 'b', 'a'), ('c3', 'b', 'c')");
    db.execute("INSERT INTO friendships VALUES ('f', 'a', 'b')");
    db.execute("INSERT INTO direct_messages VALUES ('d', 'a', 'b')");

    final counts = wipeUserData(db, 'a');
    expect(counts['data_entries'], 1);
    expect(counts['call_logs'], 2);
    expect(counts['payment_requests'], 1);

    for (final t in ['data_entries', 'customers', 'customer_syntax_templates', 'deletion_schedules', 'messages', 'transactions']) {
      expect(_n(db, t), 1, reason: t);
      expect(db.select('SELECT user_id FROM $t').first['user_id'], 'b', reason: t);
    }
    expect(db.select('SELECT id FROM payment_requests WHERE user_id = ?', ['a']).map((r) => r['id']), ['pa-a']);
    expect(_n(db, 'payment_requests'), 3);
    expect(db.select("SELECT id FROM call_logs").map((r) => r['id']), ['c3']);
    expect(_n(db, 'users'), 2);
    expect(_n(db, 'friendships'), 1);
    expect(_n(db, 'direct_messages'), 1);
    expect(_n(db, 'message_reads'), 1);
    expect(db.select("SELECT data_used FROM users WHERE id = 'a'").first['data_used'], 0);
    expect(db.select("SELECT data_used FROM users WHERE id = 'b'").first['data_used'], 5);
  });

  test('wipeUserData is atomic: a failure rolls everything back', () {
    final db = _db();
    db.execute("INSERT INTO users (id) VALUES ('a')");
    db.execute("INSERT INTO data_entries VALUES ('e', 'a')");
    db.execute('DROP TABLE transactions'); // makes the last-but-one step fail
    expect(() => wipeUserData(db, 'a'), throwsA(isA<SqliteException>()));
    expect(_n(db, 'data_entries'), 1);
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
