import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index.dart' show announcementJson;

/// Admin-only. PATCH { active: bool } hides/shows a notice; DELETE removes it.
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final existing = db.select('SELECT * FROM announcements WHERE id = ?', [id]);
  if (existing.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy thông báo'});
  }

  switch (context.request.method) {
    case HttpMethod.delete:
      db.execute('DELETE FROM announcements WHERE id = ?', [id]);
      return Response.json(body: {'ok': true});
    case HttpMethod.patch:
      final Map<String, dynamic> body;
      try {
        body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
      } catch (_) {
        return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
      }
      if (body['active'] is! bool) {
        return Response.json(statusCode: 400, body: {'error': 'Thiếu trạng thái hiển thị'});
      }
      db.execute('UPDATE announcements SET active = ? WHERE id = ?', [(body['active'] as bool) ? 1 : 0, id]);
      return Response.json(body: announcementJson(db.select('SELECT * FROM announcements WHERE id = ?', [id]).first));
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
