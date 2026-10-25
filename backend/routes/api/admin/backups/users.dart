import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/backup_restore.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /admin/backups/users?backup=<id>` -> `{users: [{id, username, name, inBackup: {table: n}, now: {table: n} | null}]}`: the
/// customers a backup holds and how many numbers / customers / results... each had then and has now (only counts, never the data).
Response onRequest(RequestContext context) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'backups.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405, body: 'Method not allowed');
  final b = resolveBackup(context.request.uri.queryParameters['backup'] ?? '');
  if (b == null) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy bản sao lưu'});
  try {
    return Response.json(body: {'users': usersInBackup(b, context.read<Database>())});
  } catch (_) {
    return Response.json(statusCode: 500, body: {'error': 'Không đọc được bản sao lưu này'});
  }
}
