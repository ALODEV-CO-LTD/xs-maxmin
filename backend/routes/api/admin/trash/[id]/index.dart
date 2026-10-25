import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `DELETE /admin/trash/<id>` - deletes the item for good before its 7 days are over.
Response onRequest(RequestContext context, String id) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'trash.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.delete) return Response(statusCode: 405, body: 'Method not allowed');
  final db = context.read<Database>();
  final label = db.select('SELECT label FROM admin_trash WHERE id = ?', [id]);
  if (!purgeTrashItem(db, id)) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy mục trong thùng rác'});
  logSecurityEvent(db, 'trash_purged', userId: auth.userId, ip: clientIp(context), detail: 'Admin xoá hẳn khỏi thùng rác: ${label.first['label']}');
  return Response.json(body: {'deleted': true});
}
