import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/app_version.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// App version management (A17), permission `settings.manage`.
/// `GET` -> `{latestVersion, minVersion, downloadUrl, notes}`; `PUT {any subset}` saves (validated, logged to the
/// security log; an empty string clears a field). The app reads the public `GET /api/app-version`.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'settings.manage');
  if (denied != null) return denied;
  final db = context.read<Database>();

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: loadAppVersion(db).toJson());
    case HttpMethod.put:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      final before = loadAppVersion(db);
      final error = validateAppVersionInput(body, before);
      if (error != null) return Response.json(statusCode: 400, body: {'error': error});
      saveAppVersion(db, body);
      final after = loadAppVersion(db);
      final b = before.toJson();
      final a = after.toJson();
      final changed = [for (final k in a.keys) if (k != 'notes' && b[k] != a[k]) '$k: ${b[k]} -> ${a[k]}'];
      if (changed.isNotEmpty) {
        logSecurityEvent(db, 'app_version_changed', userId: auth.userId, ip: clientIp(context), detail: changed.join('; '));
      }
      return Response.json(body: a);
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
