import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/backup_restore.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Admin-only database backups (A13). Files live in backend/data/backups
/// (`data/` is git-ignored, so no .db ever reaches git).
///
/// GET  -> { backups: [{ name, size, createdAt }] }, newest first
/// POST -> runs `VACUUM INTO` (a consistent snapshot, safe while the server is
///         live) and returns the new { name, size, createdAt }
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'backups.manage');
  if (denied != null) return denied;

  return switch (context.request.method) {
    // `backups`: the ones made in the app (download); `sources`: also the daily server backups, for "restore one customer"
    HttpMethod.get => Response.json(body: {'backups': listBackups(), 'sources': listRestorableBackups()}),
    HttpMethod.post => _create(context),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Directory backupDir() => Directory(p.join(Directory.current.path, 'data', 'backups'));

List<Map<String, Object?>> listBackups() {
  final dir = backupDir();
  if (!dir.existsSync()) return [];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('xoso-') && f.path.endsWith('.db'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  return [
    for (final f in files)
      {
        'name': p.basename(f.path),
        'size': f.lengthSync(),
        'createdAt': f.lastModifiedSync().toUtc().toIso8601String(),
      },
  ];
}

/// Keeps at most this many backups; the oldest beyond that are deleted after a new one is made.
const maxBackups = 20;

/// Refuse a new backup when the disk has less than this free.
const minFreeBytes = 200 * 1024 * 1024;

/// Deletes the oldest `xoso-*.db` files in [dir] beyond [keep] (names carry a UTC timestamp, so name order = age).
/// Returns how many were removed.
int pruneBackups(Directory dir, {int keep = maxBackups}) {
  if (!dir.existsSync()) return 0;
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('xoso-') && f.path.endsWith('.db'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  var removed = 0;
  for (final f in files.skip(keep)) {
    try {
      f.deleteSync();
      removed++;
    } catch (_) {}
  }
  return removed;
}

/// Free bytes on the disk holding [dir], or null when it cannot be determined (`df -k`).
int? freeDiskBytes(Directory dir) {
  try {
    final r = Process.runSync('df', ['-k', dir.path]);
    if (r.exitCode != 0) return null;
    final lines = (r.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.trim().split(RegExp(r'\s+'));
    final kb = int.tryParse(cols.length > 3 ? cols[3] : '');
    return kb == null ? null : kb * 1024;
  } catch (_) {
    return null;
  }
}

Response _create(RequestContext context) {
  final dir = backupDir();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final free = freeDiskBytes(dir);
  if (free != null && free < minFreeBytes) {
    return Response.json(statusCode: 507, body: {'error': 'Ổ đĩa còn trống quá ít (dưới 200 MB), chưa thể sao lưu'});
  }
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final name = 'xoso-$stamp.db';
  final path = p.join(dir.path, name);
  try {
    context.read<Database>().execute('VACUUM INTO ?', [path]);
  } catch (_) {
    return Response.json(statusCode: 500, body: {'error': 'Không tạo được bản sao lưu'});
  }
  final f = File(path);
  pruneBackups(dir);
  return Response.json(
    statusCode: 201,
    body: {
      'name': name,
      'size': f.lengthSync(),
      'createdAt': f.lastModifiedSync().toUtc().toIso8601String(),
    },
  );
}
