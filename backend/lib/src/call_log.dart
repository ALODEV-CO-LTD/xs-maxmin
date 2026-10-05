import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Creates the history row for an invite and returns its id. [status] is
/// 'ringing' when the invite reached the callee; for a callee who was offline
/// or busy the call is born already finished ('missed' / 'busy').
String startCallLog(Database db, String callerId, String calleeId, {String status = 'ringing'}) {
  final id = _uuid.v4();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    'INSERT INTO call_logs (id, caller_id, callee_id, status, created_at, ended_at) VALUES (?, ?, ?, ?, ?, ?)',
    [id, callerId, calleeId, status, now, status == 'ringing' ? null : now],
  );
  return id;
}

/// Moves a call through its life cycle from a signaling event. Safe to call
/// repeatedly: a finished call is never changed again.
///   accept            ringing -> in_progress
///   reject            ringing -> rejected (or busy)
///   end               ringing -> missed, in_progress -> completed
///   fail              in_progress -> failed (media never worked)
void applyCallEvent(Database db, String? logId, String event, {String? reason}) {
  if (logId == null) return;
  final rows = db.select('SELECT status, answered_at FROM call_logs WHERE id = ?', [logId]);
  if (rows.isEmpty) return;
  final status = rows.first['status'] as String;
  final now = DateTime.now().toUtc();
  final nowIso = now.toIso8601String();

  void finish(String newStatus, {int duration = 0}) {
    db.execute(
      'UPDATE call_logs SET status = ?, ended_at = ?, duration_seconds = ? WHERE id = ?',
      [newStatus, nowIso, duration, logId],
    );
  }

  switch (event) {
    case 'accept':
      if (status == 'ringing') {
        db.execute("UPDATE call_logs SET status = 'in_progress', answered_at = ? WHERE id = ?", [nowIso, logId]);
      }
    case 'reject':
      if (status == 'ringing') finish(reason == 'busy' ? 'busy' : 'rejected');
    case 'end':
      if (status == 'ringing') {
        finish('missed');
      } else if (status == 'in_progress') {
        final answeredAt = DateTime.tryParse(rows.first['answered_at'] as String? ?? '');
        final secs = answeredAt == null ? 0 : now.difference(answeredAt).inSeconds;
        finish(reason == 'failed' ? 'failed' : 'completed', duration: secs < 0 ? 0 : secs);
      }
  }
}
