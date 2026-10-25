import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/src/user_rows.dart';
import 'package:sqlite3/sqlite3.dart';

/// Restoring ONE customer's data from a backup file (the customer deleted numbers by mistake and asks Admin). Only that customer's
/// rows of [dataTables] are touched; every other account stays exactly as it is.

/// Tests point these at a temporary folder (the working directory is shared by every test running in the process).
Directory? manualBackupDirOverride;
Directory? cronBackupDirOverride;

/// Backups the Admin made in the app (`data/backups`).
Directory manualBackupDir() => manualBackupDirOverride ?? Directory(p.join(Directory.current.path, 'data', 'backups'));

/// The daily backups of the server cron job (`deploy/xs-maxmin-backup.sh`); the folder can be changed with `XOSO_CRON_BACKUP_DIR`.
Directory cronBackupDir() => cronBackupDirOverride ?? Directory(Platform.environment['XOSO_CRON_BACKUP_DIR'] ?? '/var/backups/xs-maxmin');

final _manualName = RegExp(r'^xoso-[0-9TZ-]+\.db$');
final _cronName = RegExp(r'^xoso-[0-9-]+\.db$');

class BackupFile {
  const BackupFile(this.id, this.source, this.name, this.file);

  /// `manual:<name>` or `cron:<name>` - what the API and the app use to point at it.
  final String id;
  final String source; // 'manual' | 'cron'
  final String name;
  final File file;
}

List<BackupFile> _scan(Directory dir, String source, RegExp pattern) {
  if (!dir.existsSync()) return const [];
  try {
    return [
      for (final f in dir.listSync().whereType<File>())
        if (pattern.hasMatch(p.basename(f.path))) BackupFile('$source:${p.basename(f.path)}', source, p.basename(f.path), f),
    ];
  } catch (_) {
    return const [];
  }
}

/// Every backup the Admin can restore a customer from, newest first (Admin's own and the daily cron ones).
List<Map<String, Object?>> listRestorableBackups() {
  final all = [..._scan(manualBackupDir(), 'manual', _manualName), ..._scan(cronBackupDir(), 'cron', _cronName)];
  final rows = [
    for (final b in all)
      {
        'id': b.id,
        'source': b.source,
        'name': b.name,
        'size': b.file.lengthSync(),
        'createdAt': b.file.lastModifiedSync().toUtc().toIso8601String(),
      },
  ]..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
  return rows;
}

/// The file behind a backup id, or null (unknown id, wrong shape, or the file is gone). The name is matched against a strict pattern
/// so an id can never point outside the two backup folders.
BackupFile? resolveBackup(String id) {
  final i = id.indexOf(':');
  if (i < 0) return null;
  final source = id.substring(0, i), name = id.substring(i + 1);
  final (dir, pattern) = switch (source) {
    'manual' => (manualBackupDir(), _manualName),
    'cron' => (cronBackupDir(), _cronName),
    _ => (null, _manualName),
  };
  if (dir == null || !pattern.hasMatch(name)) return null;
  final f = File(p.join(dir.path, name));
  return f.existsSync() ? BackupFile(id, source, name, f) : null;
}

Database openBackup(BackupFile b) => sqlite3.open(b.file.path, mode: OpenMode.readOnly);

Map<String, int> _counts(Database db, String userId) {
  final out = <String, int>{};
  for (final t in dataTables) {
    if (!tableExists(db, t) || !columnsOf(db, t).contains('user_id')) {
      out[t] = 0;
      continue;
    }
    out[t] = db.select('SELECT COUNT(*) AS n FROM $t WHERE user_id = ?', [userId]).first['n'] as int;
  }
  return out;
}

/// The customers a backup holds (id, username, name) with how much data each had then, and how much they have now.
List<Map<String, Object?>> usersInBackup(BackupFile b, Database live) {
  final bk = openBackup(b);
  try {
    if (!tableExists(bk, 'users')) return const [];
    return [
      for (final u in bk.select("SELECT id, username, name FROM users WHERE role = 'user' ORDER BY username COLLATE NOCASE"))
        {
          'id': u['id'],
          'username': u['username'],
          'name': u['name'],
          'inBackup': _counts(bk, u['id'] as String),
          'now': userExists(live, u['id'] as String) ? _counts(live, u['id'] as String) : null,
        },
    ];
  } finally {
    bk.dispose();
  }
}

class RestoreResult {
  const RestoreResult.ok(this.written, this.removed) : error = null;
  const RestoreResult.fail(this.error)
      : written = const {},
        removed = const {};
  final String? error;
  final Map<String, int> written; // rows written, per table
  final Map<String, int> removed; // rows deleted first (mode `replace` only), per table
}

/// Restores the data of [userId] from [b].
///  - `merge`: puts back what is missing (rows whose key already exists are kept as they are now: nothing is overwritten or doubled).
///  - `replace`: first removes the customer's current rows of the data tables, then writes the backup's (what was typed after the
///    backup is lost).
/// The account must still exist; use the Admin trash for a deleted account. One transaction: all or nothing.
RestoreResult restoreUserFromBackup(Database live, BackupFile b, String userId, {required bool replace}) {
  if (!userExists(live, userId)) return const RestoreResult.fail('Tài khoản này không còn trong hệ thống (hãy dùng Thùng rác nếu mới xoá)');
  final bk = openBackup(b);
  try {
    if (!tableExists(bk, 'users') || bk.select('SELECT 1 FROM users WHERE id = ?', [userId]).isEmpty) {
      return const RestoreResult.fail('Khách này không có trong bản sao lưu đã chọn');
    }
    final written = <String, int>{}, removed = <String, int>{};
    live.execute('BEGIN');
    try {
      if (replace) {
        for (final t in dataTables.reversed) {
          if (!tableExists(live, t) || !columnsOf(live, t).contains('user_id')) continue;
          live.execute('DELETE FROM $t WHERE user_id = ?', [userId]);
          removed[t] = live.updatedRows;
        }
      }
      for (final (table, cols) in userTables) {
        if (!dataTables.contains(table)) continue;
        written[table] = insertRows(live, table, cols, rowsOfUser(bk, table, cols, userId));
      }
      live.execute('COMMIT');
    } catch (_) {
      try {
        live.execute('ROLLBACK');
      } catch (_) {}
      return const RestoreResult.fail('Không khôi phục được (dữ liệu trong bản sao lưu không khớp)');
    }
    return RestoreResult.ok(written, removed);
  } finally {
    bk.dispose();
  }
}

/// A fresh backup of the live database right now (named like the others), made before a restore so it can itself be undone.
/// Returns its name, or null when it could not be made.
String? makeSafetyBackup(Database live) {
  try {
    final dir = manualBackupDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final name = 'xoso-$stamp.db';
    live.execute('VACUUM INTO ?', [p.join(dir.path, name)]);
    return name;
  } catch (_) {
    return null;
  }
}
