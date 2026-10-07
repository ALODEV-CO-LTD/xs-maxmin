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
          final n = deleteScheduledData(db, s, now: nowUtc);
          final every = s['repeat_every'] as int?;
          final unit = s['repeat_unit'] as String?;
          if (every != null && every >= 1 && unit != null) {
            // Recurring: stay 'pending', jump to the next FUTURE occurrence
            // (cycles missed while the server was off are skipped, not replayed).
            final current = DateTime.parse(s['run_at'] as String).toUtc();
            final anchor = DateTime.tryParse((s['first_run_at'] ?? s['run_at']) as String)?.toUtc() ?? current;
            final next = nextRunAfter(anchor, every, unit, after: nowUtc.isAfter(current) ? nowUtc : current);
            db.execute(
              'UPDATE deletion_schedules SET run_at = ?, deleted_count = deleted_count + ?, '
              'run_count = run_count + 1, executed_at = ? WHERE id = ?',
              [next.toIso8601String(), n, nowIso, s['id']],
            );
          } else {
            db.execute(
              "UPDATE deletion_schedules SET status = 'done', deleted_count = ?, run_count = run_count + 1, executed_at = ? WHERE id = ?",
              [n, nowIso, s['id']],
            );
          }
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

/// Vietnam has no DST: local time is always UTC+7.
const vietnamOffset = Duration(hours: 7);

/// Calendar date (YYYY-MM-DD) in Vietnam time of the instant [t].
String vnDate(DateTime t) {
  final v = t.toUtc().add(vietnamOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${v.year.toString().padLeft(4, '0')}-${two(v.month)}-${two(v.day)}';
}

/// [anchor] + [count] units in Vietnam local time, keeping the time of day.
/// Months are calendar months, clamped to the last day (31/1 + 1 month = 28/2
/// or 29/2). Always computed from the anchor, so a clamp never drifts later
/// occurrences (31/1 -> 28/2 -> 31/3, not 28/3).
DateTime addRepeat(DateTime anchor, int count, String unit) {
  final v = anchor.toUtc().add(vietnamOffset);
  final DateTime local;
  switch (unit) {
    case 'week':
      local = v.add(Duration(days: 7 * count));
    case 'month':
      final idx = v.year * 12 + (v.month - 1) + count;
      final y = idx ~/ 12;
      final m = idx % 12 + 1;
      final last = DateTime.utc(y, m + 1, 0).day;
      local = DateTime.utc(y, m, v.day > last ? last : v.day, v.hour, v.minute, v.second, v.millisecond);
    default:
      local = v.add(Duration(days: count));
  }
  return local.subtract(vietnamOffset);
}

/// First occurrence (anchor + k*every units, k >= 1) strictly after [after].
DateTime nextRunAfter(DateTime anchor, int every, String unit, {required DateTime after}) {
  var k = 1;
  var t = addRepeat(anchor, every, unit);
  while (!t.isAfter(after) && k < 200000) {
    k++;
    t = addRepeat(anchor, k * every, unit);
  }
  return t;
}

bool _isRealDate(String d) {
  final y = int.parse(d.substring(0, 4)), m = int.parse(d.substring(5, 7)), day = int.parse(d.substring(8, 10));
  final t = DateTime.utc(y, m, day);
  return t.year == y && t.month == m && t.day == day;
}

final _scopeDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Vietnamese error for a bad date range / keepDays, or null when valid.
/// Shared by the schedule route and bulk-delete.
String? validateDataScope(String? from, String? to, int keepDays) {
  for (final d in [from, to]) {
    if (d != null && (!_scopeDatePattern.hasMatch(d) || !_isRealDate(d))) {
      return 'Ngày không hợp lệ (định dạng YYYY-MM-DD)';
    }
  }
  if (from != null && to != null && from.compareTo(to) > 0) {
    return 'Ngày bắt đầu phải trước ngày kết thúc';
  }
  if (keepDays < 0 || keepDays > 3650) return 'Số ngày giữ lại phải từ 0 đến 3650';
  return null;
}

/// WHERE clause (+ params) selecting the user's data_entries a 'data'
/// schedule / manual bulk delete covers. THE single source of truth: preview,
/// dry run, creation warning, scheduled run and bulk-delete all use it.
/// [keepDays] keeps the newest N days: only entries dated on or before
/// (Vietnam date of [now]) - keepDays match.
(String, List<Object?>) dataEntriesFilter(
  String userId,
  String? customer,
  String? from,
  String? to, {
  int keepDays = 0,
  DateTime? now,
}) {
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
  if (keepDays > 0) {
    where.write(' AND entry_date <= ?');
    params.add(vnDate((now ?? DateTime.now()).toUtc().subtract(Duration(days: keepDays))));
  }
  return (where.toString(), params);
}

int countScheduledData(Database db, String userId, String? customer, String? from, String? to,
    {int keepDays = 0, DateTime? now}) {
  final (where, params) = dataEntriesFilter(userId, customer, from, to, keepDays: keepDays, now: now);
  return db.select('SELECT COUNT(*) AS n FROM data_entries WHERE $where', params).first['n'] as int;
}

/// Deletes the user's entries in scope and releases the same quota a single
/// entry delete does (data_used - n, never below 0). Returns the count.
int deleteDataScope(Database db, String userId, String? customer, String? from, String? to,
    {int keepDays = 0, DateTime? now}) {
  final (where, params) = dataEntriesFilter(userId, customer, from, to, keepDays: keepDays, now: now);
  db.execute('DELETE FROM data_entries WHERE $where', params);
  final n = db.updatedRows;
  if (n > 0) {
    db.execute('UPDATE users SET data_used = MAX(data_used - ?, 0) WHERE id = ?', [n, userId]);
  }
  return n;
}

int deleteScheduledData(Database db, Row schedule, {DateTime? now}) => deleteDataScope(
      db,
      schedule['user_id'] as String,
      schedule['customer_name'] as String?,
      schedule['date_from'] as String?,
      schedule['date_to'] as String?,
      keepDays: schedule['keep_days'] as int? ?? 0,
      now: now,
    );

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
