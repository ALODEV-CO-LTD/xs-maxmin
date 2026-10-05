import 'package:server/src/call_log.dart';
import 'package:server/src/call_signaling.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = OFF');
  db.execute('''
    CREATE TABLE call_logs (
      id TEXT PRIMARY KEY, caller_id TEXT NOT NULL, callee_id TEXT NOT NULL,
      status TEXT NOT NULL, created_at TEXT NOT NULL, answered_at TEXT,
      ended_at TEXT, duration_seconds INTEGER NOT NULL DEFAULT 0,
      callee_seen INTEGER NOT NULL DEFAULT 0
    )
  ''');
  return db;
}

String _status(Database db, String id) =>
    db.select('SELECT status FROM call_logs WHERE id = ?', [id]).first['status'] as String;

void main() {
  test('answered call: ringing -> in_progress -> completed with duration', () {
    final db = _db();
    final id = startCallLog(db, 'a', 'b');
    expect(_status(db, id), 'ringing');
    applyCallEvent(db, id, 'accept');
    expect(_status(db, id), 'in_progress');
    db.execute(
      'UPDATE call_logs SET answered_at = ? WHERE id = ?',
      [DateTime.now().toUtc().subtract(const Duration(seconds: 42)).toIso8601String(), id],
    );
    applyCallEvent(db, id, 'end');
    final row = db.select('SELECT * FROM call_logs WHERE id = ?', [id]).first;
    expect(row['status'], 'completed');
    expect(row['duration_seconds'], inInclusiveRange(42, 44));
  });

  test('unanswered calls become missed / rejected / busy', () {
    final db = _db();
    final missed = startCallLog(db, 'a', 'b');
    applyCallEvent(db, missed, 'end');
    expect(_status(db, missed), 'missed');

    final rejected = startCallLog(db, 'a', 'b');
    applyCallEvent(db, rejected, 'reject');
    expect(_status(db, rejected), 'rejected');

    final busy = startCallLog(db, 'a', 'b');
    applyCallEvent(db, busy, 'reject', reason: 'busy');
    expect(_status(db, busy), 'busy');
  });

  test('media failure is recorded, and a finished call never changes again', () {
    final db = _db();
    final id = startCallLog(db, 'a', 'b');
    applyCallEvent(db, id, 'accept');
    applyCallEvent(db, id, 'end', reason: 'failed');
    expect(_status(db, id), 'failed');
    applyCallEvent(db, id, 'end');
    applyCallEvent(db, id, 'reject');
    expect(_status(db, id), 'failed');
    applyCallEvent(db, null, 'end'); // no log id: ignored
  });

  test('offline callee is logged as missed straight away', () {
    final db = _db();
    final id = startCallLog(db, 'a', 'b', status: 'missed');
    expect(_status(db, id), 'missed');
  });

  test('invite rate limit: 6 per minute per caller', () {
    final reg = CallSignalingRegistry.instance;
    final results = [for (var i = 0; i < 8; i++) reg.allowInvite('rate-test-user')];
    expect(results.where((e) => e).length, 6);
    expect(reg.allowInvite('someone-else'), isTrue);
  });

  test('active peer + log are paired and cleared together', () {
    final reg = CallSignalingRegistry.instance;
    reg.setActivePeer('u1', 'u2', logId: 'log-1');
    expect(reg.activePeerOf('u2'), 'u1');
    expect(reg.activeLogOf('u1'), 'log-1');
    reg.clearActivePeer('u2');
    expect(reg.activePeerOf('u1'), isNull);
    expect(reg.activeLogOf('u1'), isNull);
  });
}
