import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

/// Chat retention choices a user may pick (seconds), shared with the API.
const allowedChatTtlSeconds = [3600, 86400, 604800, 2592000];

Timer? _timer;

/// Starts the periodic background job that executes `deletion_schedules`
/// (K35/K36/S05). Idempotent - a second call (e.g. dev hot reload) keeps the
/// existing timer. Runs once immediately so schedules that came due while the
/// server was down are carried out on boot.
void startDeletionScheduler(Database db, {Duration every = const Duration(minutes: 1)}) {
  if (_timer != null) return;
  runDueDeletions(db);
  _timer = Timer.periodic(every, (_) => runDueDeletions(db));
}

/// Executes every pending schedule whose time has come. Never throws - a
/// failure in one schedule must not stop the timer or the other schedules.
void runDueDeletions(Database db, {DateTime? now}) {
  final nowUtc = (now ?? DateTime.now()).toUtc();
  final nowIso = nowUtc.toIso8601String();
  try {
    final due = db.select(
      "SELECT * FROM deletion_schedules WHERE status = 'pending' AND run_at <= ?",
      [nowIso],
    );
    for (final s in due) {
      try {
        if (s['kind'] == 'data') {
          final n = deleteScheduledData(db, s);
          db.execute(
            "UPDATE deletion_schedules SET status = 'done', deleted_count = ?, executed_at = ? WHERE id = ?",
            [n, nowIso, s['id']],
          );
        } else {
          final ttl = s['ttl_seconds'] as int;
          final cutoff = nowUtc.subtract(Duration(seconds: ttl)).toIso8601String();
          final n = deleteChatBefore(db, s['user_id'] as String, s['friend_id'] as String, s['chat_scope'] as String, cutoff);
          // Standing rule: stays pending, only the running tally/time move.
          db.execute(
            'UPDATE deletion_schedules SET deleted_count = deleted_count + ?, executed_at = ? WHERE id = ?',
            [n, nowIso, s['id']],
          );
        }
      } catch (_) {
        /* leave the schedule as it is; it is retried on the next tick */
      }
    }
  } catch (_) {
    /* database busy/closed - try again next tick */
  }
}

/// WHERE clause (+ params) selecting the user's data_entries a 'data'
/// schedule covers. Shared by the preview, the creation warning and the run.
(String, List<Object?>) dataEntriesFilter(String userId, String? customer, String? from, String? to) {
  final where = StringBuffer('user_id = ?');
  final params = <Object?>[userId];
  if (customer != null && customer.isNotEmpty) {
    where.write(' AND customer_name = ?');
    params.add(customer);
  }
  if (from != null && from.isNotEmpty) {
    where.write(' AND entry_date >= ?');
    params.add(from);
  }
  if (to != null && to.isNotEmpty) {
    where.write(' AND entry_date <= ?');
    params.add(to);
  }
  return (where.toString(), params);
}

int countScheduledData(Database db, String userId, String? customer, String? from, String? to) {
  final (where, params) = dataEntriesFilter(userId, customer, from, to);
  return db.select('SELECT COUNT(*) AS n FROM data_entries WHERE $where', params).first['n'] as int;
}

int deleteScheduledData(Database db, Row schedule) {
  final (where, params) = dataEntriesFilter(
    schedule['user_id'] as String,
    schedule['customer_name'] as String?,
    schedule['date_from'] as String?,
    schedule['date_to'] as String?,
  );
  final n = db.select('SELECT COUNT(*) AS n FROM data_entries WHERE $where', params).first['n'] as int;
  db.execute('DELETE FROM data_entries WHERE $where', params);
  return n;
}

const _pairWhere =
    '((from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)) AND created_at < ?';

/// Messages in the [a]/[b] conversation older than [cutoffIso] that a chat
/// rule of [scope] ('all' or 'images') would remove.
int countChatBefore(Database db, String a, String b, String scope, String cutoffIso) {
  final extra = scope == 'images' ? " AND attachment_type LIKE 'image/%'" : '';
  return db.select(
    'SELECT COUNT(*) AS n FROM direct_messages WHERE $_pairWhere$extra',
    [a, b, b, a, cutoffIso],
  ).first['n'] as int;
}

/// Applies a chat rule. 'all' deletes whole messages; 'images' deletes only
/// the image attachment (the message row goes too when it has no text).
int deleteChatBefore(Database db, String a, String b, String scope, String cutoffIso) {
  final n = countChatBefore(db, a, b, scope, cutoffIso);
  if (n == 0) return 0;
  final args = [a, b, b, a, cutoffIso];
  if (scope == 'images') {
    db.execute(
      "DELETE FROM direct_messages WHERE $_pairWhere AND attachment_type LIKE 'image/%' AND content = ''",
      args,
    );
    db.execute(
      'UPDATE direct_messages SET attachment_name = NULL, attachment_type = NULL, '
      "attachment_size = NULL, attachment_data = NULL WHERE $_pairWhere AND attachment_type LIKE 'image/%'",
      args,
    );
  } else {
    db.execute('DELETE FROM direct_messages WHERE $_pairWhere', args);
  }
  return n;
}
