import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /admin/trash` -> `{trashDays, items: [{id, kind, label, counts, deletedAt, expiresAt, daysLeft, deletedByName}]}`: what Admin
/// deleted in the last 7 days (never the content of a customer's data, only how many rows). Anything older is dropped here too.
Response onRequest(RequestContext context) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'trash.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405, body: 'Method not allowed');
  final db = context.read<Database>();
  purgeExpiredTrash(db);
  return Response.json(body: {'trashDays': trashDays, 'items': listTrash(db)});
}
