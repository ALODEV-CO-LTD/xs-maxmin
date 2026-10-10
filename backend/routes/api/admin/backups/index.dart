import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:server/src/auth_middleware.dart';
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
    HttpMethod.get => Response.json(body: {'backups': listBackups()}),
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

Response _create(RequestContext context) {
  final dir = backupDir();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final name = 'xoso-$stamp.db';
  final path = p.join(dir.path, name);
  try {
    context.read<Database>().execute('VACUUM INTO ?', [path]);
  } catch (_) {
    return Response.json(statusCode: 500, body: {'error': 'Không tạo được bản sao lưu'});
  }
  final f = File(path);
  return Response.json(
    statusCode: 201,
    body: {
      'name': name,
      'size': f.lengthSync(),
      'createdAt': f.lastModifiedSync().toUtc().toIso8601String(),
    },
  );
}
