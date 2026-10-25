import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /admin/trash/<id>/restore` - puts a deleted account / staff account / announcement / package / setting back. 409 with the
/// reason when it cannot (the username was taken since, the account is already back...).
Response onRequest(RequestContext context, String id) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'trash.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.post) return Response(statusCode: 405, body: 'Method not allowed');
  final db = context.read<Database>();
  purgeExpiredTrash(db);
  final item = db.select('SELECT label, kind FROM admin_trash WHERE id = ?', [id]);
  final error = restoreTrash(db, id);
  if (error != null) {
    return Response.json(statusCode: item.isEmpty ? 404 : 409, body: {'error': error});
  }
  logSecurityEvent(db, 'trash_restored', userId: auth.userId, ip: clientIp(context), detail: 'Admin khôi phục từ thùng rác: ${item.first['label']} (${item.first['kind']})');
  return Response.json(body: {'restored': true});
}
