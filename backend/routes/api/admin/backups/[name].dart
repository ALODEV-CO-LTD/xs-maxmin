import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';

import 'index.dart' show backupDir;

/// Admin-only download of one backup file. The name is validated against a
/// strict pattern so it can never point outside the backups folder.
Future<Response> onRequest(RequestContext context, String name) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'backups.manage');
  if (denied != null) return denied;
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  if (!RegExp(r'^xoso-[0-9TZ-]+\.db$').hasMatch(name)) {
    return Response.json(statusCode: 400, body: {'error': 'Tên tệp không hợp lệ'});
  }
  final file = File(p.join(backupDir().path, name));
  if (!file.existsSync()) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy bản sao lưu'});
  }
  return Response.bytes(
    body: await file.readAsBytes(),
    headers: {
      'content-type': 'application/octet-stream',
      'content-disposition': 'attachment; filename="$name"',
    },
  );
}
