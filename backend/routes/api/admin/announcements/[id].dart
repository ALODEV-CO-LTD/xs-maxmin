import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index.dart' show announcementJson;

/// Admin-only. PATCH { active: bool } hides/shows a notice; DELETE removes it.
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'announcements.manage');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final existing = db.select('SELECT * FROM announcements WHERE id = ?', [id]);
  if (existing.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy thông báo'});
  }

  switch (context.request.method) {
    case HttpMethod.delete:
      trashAnnouncement(db, existing.first, deletedBy: auth.userId);
      db.execute('DELETE FROM announcements WHERE id = ?', [id]);
      return Response.json(body: {'ok': true});
    case HttpMethod.patch:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      if (body['active'] is! bool) {
        return Response.json(statusCode: 400, body: {'error': 'Thiếu trạng thái hiển thị'});
      }
      db.execute('UPDATE announcements SET active = ? WHERE id = ?', [(body['active'] as bool) ? 1 : 0, id]);
      return Response.json(body: announcementJson(db.select('SELECT * FROM announcements WHERE id = ?', [id]).first));
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
