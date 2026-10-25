import 'dart:convert';

import 'package:server/src/user_rows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

/// Admin trash: whatever an Admin deletes (a customer account with all its data, a staff account, an announcement, a package, bank
/// settings) is kept here for [trashDays] days before it is gone for good, so a wrong click can be undone. Only the Admin side has it:
/// what a customer deletes in the app is NOT put here (a customer asks Admin, who restores it from a backup), and neither is the
/// account wipe with the wipe password (that exists to destroy data for good).
///
/// The Admin sees what was deleted and how many rows, never the content of a customer's data.
const trashDays = 7;

const adminTrashDdl = '''
  CREATE TABLE IF NOT EXISTS admin_trash (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    label TEXT NOT NULL,
    payload TEXT NOT NULL,
    counts TEXT NOT NULL DEFAULT '{}',
    deleted_by TEXT,
    deleted_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
  )
''';

/// Kinds of things in the trash.
const trashKinds = {'user', 'staff', 'announcement', 'package', 'setting'};

void ensureAdminTrashTable(Database db) {
  db.execute(adminTrashDdl);
  db.execute('CREATE INDEX IF NOT EXISTS idx_admin_trash_expires ON admin_trash(expires_at)');
}

String _now([DateTime? t]) => (t ?? DateTime.now()).toUtc().toIso8601String();

String _add(String kind, String label, Map<String, Object?> payload, Map<String, int> counts, String? deletedBy, DateTime? now, Database db) {
  final id = const Uuid().v4();
  final t = (now ?? DateTime.now()).toUtc();
  db.execute(
    'INSERT INTO admin_trash (id, kind, label, payload, counts, deleted_by, deleted_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [id, kind, label, jsonEncode(payload), jsonEncode(counts), deletedBy, t.toIso8601String(), t.add(const Duration(days: trashDays)).toIso8601String()],
  );
  return id;
}

/// Keeps a copy of an account (customer: with every row it owns; staff: the account only) BEFORE it is deleted. Returns the trash id,
/// or null when there is no such account.
String? trashAccount(Database db, String userId, {required bool staff, String? deletedBy, DateTime? now}) {
  final u = db.select('SELECT * FROM users WHERE id = ?', [userId]);
  if (u.isEmpty) return null;
  final payload = <String, Object?>{
    'users': [rowToJson(u.first)],
  };
  final counts = <String, int>{};
  if (!staff) {
    for (final (table, cols) in userTables) {
      final rows = rowsOfUser(db, table, cols, userId);
      if (rows.isEmpty) continue;
      payload[table] = rows;
      counts[table] = rows.length;
    }
  }
  final name = (u.first['name'] as String?) ?? '';
  final label = '${u.first['username']}${name.isEmpty ? '' : ' ($name)'}';
  return _add(staff ? 'staff' : 'user', label, payload, counts, deletedBy, now, db);
}

String trashAnnouncement(Database db, Row row, {String? deletedBy, DateTime? now}) {
  final text = '${row['title'] ?? row['content'] ?? row['message'] ?? 'Thông báo'}';
  return _add('announcement', text.length > 60 ? '${text.substring(0, 60)}…' : text, {'announcements': [rowToJson(row)]}, {'announcements': 1}, deletedBy, now, db);
}

String trashPackage(Database db, Row row, {String? deletedBy, DateTime? now}) =>
    _add('package', '${row['label'] ?? row['code']}', {'packages': [rowToJson(row)]}, {'packages': 1}, deletedBy, now, db);

/// Settings keys an Admin resets (a package price override, the bank account...): the rows as they were.
String? trashSettings(Database db, List<String> keys, {String? deletedBy, DateTime? now}) {
  final rows = <Map<String, Object?>>[];
  for (final k in keys) {
    for (final r in db.select('SELECT * FROM settings WHERE key = ?', [k])) {
      rows.add(rowToJson(r));
    }
  }
  if (rows.isEmpty) return null;
  return _add('setting', keys.join(', '), {'settings': rows}, {'settings': rows.length}, deletedBy, now, db);
}

/// Removes what is past its 7 days. Returns how many items went.
int purgeExpiredTrash(Database db, {DateTime? now}) {
  db.execute('DELETE FROM admin_trash WHERE expires_at <= ?', [_now(now)]);
  return db.updatedRows;
}

/// The list the Admin sees: kind, label, when, how long is left, how many rows (never the rows themselves).
List<Map<String, Object?>> listTrash(Database db, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  return [
    for (final r in db.select('SELECT id, kind, label, counts, deleted_by, deleted_at, expires_at FROM admin_trash ORDER BY deleted_at DESC'))
      {
        'id': r['id'],
        'kind': r['kind'],
        'label': r['label'],
        'counts': jsonDecode(r['counts'] as String),
        'deletedAt': r['deleted_at'],
        'expiresAt': r['expires_at'],
        'daysLeft': (DateTime.parse(r['expires_at'] as String).difference(t).inHours / 24).ceil().clamp(0, trashDays),
        'deletedByName': _nameOf(db, r['deleted_by'] as String?),
      },
  ];
}

String? _nameOf(Database db, String? id) {
  if (id == null) return null;
  final r = db.select('SELECT username FROM users WHERE id = ?', [id]);
  return r.isEmpty ? null : r.first['username'] as String;
}

/// Puts an item back. Returns null on success, else the reason (Vietnamese) it cannot be restored.
String? restoreTrash(Database db, String trashId) {
  final rows = db.select('SELECT * FROM admin_trash WHERE id = ?', [trashId]);
  if (rows.isEmpty) return 'Không tìm thấy mục trong thùng rác';
  final item = rows.first;
  final kind = item['kind'] as String;
  final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
  List<Map<String, Object?>> of(String t) => [for (final r in (payload[t] as List? ?? const [])) Map<String, Object?>.from(r as Map)];

  db.execute('BEGIN');
  try {
    switch (kind) {
      case 'user' || 'staff':
        final u = of('users').first;
        if (userExists(db, u['id'] as String)) {
          db.execute('ROLLBACK');
          return 'Tài khoản này đã có lại trong hệ thống';
        }
        if (db.select('SELECT 1 FROM users WHERE username = ? COLLATE NOCASE', [u['username']]).isNotEmpty) {
          db.execute('ROLLBACK');
          return 'Tên đăng nhập "${u['username']}" đã có người khác dùng, chưa thể khôi phục';
        }
        insertRows(db, 'users', const [], [u]);
        if (kind == 'user') {
          for (final (table, cols) in userTables) {
            insertRows(db, table, cols, of(table));
          }
        }
      case 'announcement':
        insertRows(db, 'announcements', const [], [
          for (final r in of('announcements')) {...r, if (r['created_by'] is String && !userExists(db, r['created_by'] as String)) 'created_by': null},
        ]);
      case 'package':
        insertRows(db, 'packages', const [], of('packages'));
      case 'setting':
        insertRows(db, 'settings', const [], of('settings'), replace: true);
      default:
        db.execute('ROLLBACK');
        return 'Loại mục không hỗ trợ khôi phục';
    }
    db.execute('DELETE FROM admin_trash WHERE id = ?', [trashId]);
    db.execute('COMMIT');
    return null;
  } catch (_) {
    try {
      db.execute('ROLLBACK');
    } catch (_) {}
    return 'Không khôi phục được (dữ liệu liên quan bị trùng hoặc thiếu)';
  }
}

bool purgeTrashItem(Database db, String trashId) {
  db.execute('DELETE FROM admin_trash WHERE id = ?', [trashId]);
  return db.updatedRows > 0;
}
