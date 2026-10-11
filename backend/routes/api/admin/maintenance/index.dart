import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Maintenance mode banner (A16), its own right (`maintenance.manage`) so it can be
/// handed out without the whole settings page.
/// GET -> { enabled, message };  PUT { enabled?, message? } -> the new state.
/// Stored in the `settings` store (`maintenance_enabled`, `maintenance_message`).
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'maintenance.manage');
  if (denied != null) return denied;
  final db = context.read<Database>();

  Map<String, dynamic> state() {
    String? get(String k) {
      final r = db.select('SELECT value FROM settings WHERE key = ?', [k]);
      return r.isEmpty ? null : r.first['value'] as String?;
    }

    return {'enabled': get('maintenance_enabled') == 'true', 'message': get('maintenance_message') ?? ''};
  }

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: state());
    case HttpMethod.put:
      final Map<String, dynamic> body;
      try {
        body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
      } catch (_) {
        return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
      }
      void put(String k, String v) => db.execute(
            'INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
            [k, v],
          );
      if (body['enabled'] is bool) put('maintenance_enabled', body['enabled'] == true ? 'true' : 'false');
      if (body['message'] is String) {
        final m = (body['message'] as String).trim();
        if (m.length > 500) return Response.json(statusCode: 400, body: {'error': 'Nội dung tối đa 500 ký tự'});
        put('maintenance_message', m);
      }
      return Response.json(body: state());
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
