import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Admin-only: publish and list notices (A16).
/// GET  -> { announcements: [...] } (all, newest first, including inactive)
/// POST { kind: info|maintenance|policy, title, body? } -> creates an active one
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'announcements.manage');
  if (denied != null) return denied;

  final db = context.read<Database>();
  switch (context.request.method) {
    case HttpMethod.get:
      final rows = db.select('SELECT * FROM announcements ORDER BY created_at DESC LIMIT 100');
      return Response.json(body: {'announcements': [for (final r in rows) announcementJson(r)]});
    case HttpMethod.post:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      final title = (body['title'] as String?)?.trim() ?? '';
      final text = (body['body'] as String?)?.trim() ?? '';
      final kind = (body['kind'] as String?)?.trim() ?? 'info';
      if (title.isEmpty) {
        return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tiêu đề thông báo'});
      }
      if (title.length > 200 || text.length > 2000) {
        return Response.json(statusCode: 400, body: {'error': 'Thông báo quá dài'});
      }
      if (!const {'info', 'maintenance', 'policy'}.contains(kind)) {
        return Response.json(statusCode: 400, body: {'error': 'Loại thông báo không hợp lệ'});
      }
      final id = newId();
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        'INSERT INTO announcements (id, kind, title, body, active, created_at, created_by) VALUES (?, ?, ?, ?, 1, ?, ?)',
        [id, kind, title, text, now, auth.userId],
      );
      return Response.json(
        statusCode: 201,
        body: announcementJson(db.select('SELECT * FROM announcements WHERE id = ?', [id]).first),
      );
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}

Map<String, Object?> announcementJson(Row r) => {
      'id': r['id'],
      'kind': r['kind'],
      'title': r['title'],
      'body': r['body'],
      'active': (r['active'] as int) == 1,
      'createdAt': r['created_at'],
    };
