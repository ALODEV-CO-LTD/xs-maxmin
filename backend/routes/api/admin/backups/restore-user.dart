import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/backup_restore.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /admin/backups/restore-user {backup, userId, mode: 'merge'|'replace'}` - restores the data of ONE customer (numbers, customers,
/// results, syntax templates, deletion schedules) from a backup; nobody else is touched. `merge` (default) puts back what is missing
/// and overwrites nothing; `replace` first removes the customer's current data. A backup of the live database is made first, and the
/// action goes to the security log.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'backups.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.post) return Response(statusCode: 405, body: 'Method not allowed');
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final userId = body['userId'];
  final mode = body['mode'] ?? 'merge';
  if (userId is! String || userId.isEmpty || (mode != 'merge' && mode != 'replace')) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu khách hàng hoặc chế độ khôi phục không hợp lệ'});
  }
  final b = resolveBackup('${body['backup'] ?? ''}');
  if (b == null) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy bản sao lưu'});

  final db = context.read<Database>();
  final safety = makeSafetyBackup(db);
  if (safety == null) return Response.json(statusCode: 500, body: {'error': 'Không tạo được bản sao lưu an toàn trước khi khôi phục, chưa làm gì cả'});
  final r = restoreUserFromBackup(db, b, userId, replace: mode == 'replace');
  if (r.error != null) return Response.json(statusCode: 409, body: {'error': r.error, 'safetyBackup': safety});
  final who = db.select('SELECT username FROM users WHERE id = ?', [userId]);
  logSecurityEvent(
    db,
    'backup_user_restored',
    userId: auth.userId,
    ip: clientIp(context),
    detail: 'Admin khôi phục dữ liệu của ${who.isEmpty ? userId : who.first['username']} từ ${b.id} (${mode == 'replace' ? 'thay thế' : 'thêm phần còn thiếu'}); bản an toàn $safety',
  );
  return Response.json(body: {'restored': true, 'mode': mode, 'written': r.written, 'removed': r.removed, 'safetyBackup': safety});
}
