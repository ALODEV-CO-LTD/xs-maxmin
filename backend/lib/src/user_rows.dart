import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Row-level copying of one account's data: used by the Admin trash (the rows of a deleted account are kept as JSON for 7 days)
/// and by "restore one customer from a backup" (rows are read from the backup file and written to the live database).

/// Every table that holds rows of an account, with the columns that point at users. A row is copied only when ALL users it points
/// at still exist (a friendship with an account that has been deleted since cannot be restored).
const userTables = <(String, List<String>)>[
  ('customers', ['user_id']),
  ('data_entries', ['user_id']),
  ('lottery_results', ['user_id']),
  ('customer_syntax_templates', ['user_id']),
  ('deletion_schedules', ['user_id', 'friend_id']),
  ('transactions', ['user_id']),
  ('payment_requests', ['user_id']),
  ('messages', ['user_id']),
  ('direct_messages', ['from_user_id', 'to_user_id']),
  ('friendships', ['user_id', 'friend_id']),
  ('friend_requests', ['from_user_id', 'to_user_id']),
  ('customer_codes', ['user_id']),
  ('retired_codes', ['user_id']),
  ('message_reads', ['user_id']),
  ('e2ee_devices', ['user_id']),
  ('recovery_requests', ['user_id']),
  ('call_logs', ['caller_id', 'callee_id']),
];

/// What "the customer's data" means for restoring from a backup: the numbers, customers, results, syntax templates and deletion
/// schedules - not the account, payments, messages or friends.
const dataTables = <String>['customers', 'data_entries', 'lottery_results', 'customer_syntax_templates', 'deletion_schedules'];

bool tableExists(Database db, String table) =>
    db.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table]).isNotEmpty;

List<String> columnsOf(Database db, String table) => [for (final r in db.select('PRAGMA table_info($table)')) r['name'] as String];

/// A value that survives JSON: BLOBs go through base64.
Object? toJsonValue(Object? v) => v is List<int> ? {'__b64': base64Encode(v)} : v;
Object? fromJsonValue(Object? v) => v is Map && v['__b64'] is String ? base64Decode(v['__b64'] as String) : v;

Map<String, Object?> rowToJson(Row r) => {for (final k in r.keys) k: toJsonValue(r[k])};

/// The rows of [userId] in [table] (all columns), or [] when the table is missing.
List<Map<String, Object?>> rowsOfUser(Database db, String table, List<String> cols, String userId) {
  if (!tableExists(db, table)) return const [];
  final have = columnsOf(db, table);
  final use = cols.where(have.contains).toList();
  if (use.isEmpty) return const [];
  final where = use.map((c) => '$c = ?').join(' OR ');
  return [for (final r in db.select('SELECT * FROM $table WHERE $where', [for (final _ in use) userId])) rowToJson(r)];
}

bool userExists(Database db, String id) => db.select('SELECT 1 FROM users WHERE id = ?', [id]).isNotEmpty;

/// Writes [rows] (JSON form) into [table]: only the columns both sides have, and only rows whose user columns ([userCols]) point at
/// accounts that exist. [replace] overwrites a row with the same key, else an existing row is kept. Returns how many were written.
int insertRows(Database db, String table, List<String> userCols, List<Map<String, Object?>> rows, {bool replace = false}) {
  if (rows.isEmpty || !tableExists(db, table)) return 0;
  final have = columnsOf(db, table).toSet();
  var n = 0;
  for (final row in rows) {
    var ok = true;
    for (final c in userCols) {
      final v = row[c];
      if (v is String && !userExists(db, v)) ok = false;
    }
    if (!ok) continue;
    final cols = [for (final k in row.keys) if (have.contains(k)) k];
    if (cols.isEmpty) continue;
    final sql = 'INSERT OR ${replace ? 'REPLACE' : 'IGNORE'} INTO $table (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})';
    db.execute(sql, [for (final c in cols) fromJsonValue(row[c])]);
    n += db.updatedRows;
  }
  return n;
}
